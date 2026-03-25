#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs all required DoD PKI certificates for STIG compliance.
    Fixes: V-254442 (DoD Root CAs), V-254443 (DoD Interop cross-certs),
           V-254444 (US DOD CCEB Interop cross-certs)

.NOTES
    FIX: Rewrote script to eliminate the PowerShell parse error
         (MissingEndCurlyBrace at lines 206, 237, 255, 273, 303, 321, 392)
         that caused the script to fail entirely during Packer image builds.
         The previous version was being truncated by Packer's WinRM file
         upload when the destination was specified as a directory path only.

    Certificate source: https://crl.gds.disa.mil / https://cyber.mil/pki-pke
    This script downloads the DoD PKI bundle ZIP, extracts it, and installs
    each required certificate into the correct Windows certificate store.
    Safe to re-run — existing certs are skipped.

    IMPORTANT FOR PACKER USERS:
    In your Packer HCL file provisioner, always specify the FULL destination
    path including the filename — not just the directory. Example:
      destination = "C:/Users/packer_user/hardening/install_dod_certs.ps1"
    Specifying only the directory (e.g. "C:/Users/packer_user/hardening/")
    causes WinRM to silently truncate large scripts.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------
function Write-Section {
    param([string]$msg)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " $msg" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$msg)
    Write-Host "  [OK]     $msg" -ForegroundColor Green
}

function Write-Fixed {
    param([string]$msg)
    Write-Host "  [ADDED]  $msg" -ForegroundColor Yellow
}

function Write-Warn {
    param([string]$msg)
    Write-Host "  [WARN]   $msg" -ForegroundColor Magenta
}

function Write-Info {
    param([string]$msg)
    Write-Host "  [INFO]   $msg" -ForegroundColor Gray
}

# -----------------------------------------------------------------------
# Enforce TLS 1.2 for all web requests
# Required on older .NET defaults (Windows Server 2022 defaults to TLS 1.2
# but this makes the requirement explicit)
# -----------------------------------------------------------------------
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# -----------------------------------------------------------------------
# Working directory for downloaded files
# -----------------------------------------------------------------------
$workDir = Join-Path $env:TEMP "dod_certs_install"
if (Test-Path $workDir) {
    Remove-Item $workDir -Recurse -Force
}
New-Item -Path $workDir -ItemType Directory -Force | Out-Null

$ErrorCount  = 0
$bundleP7b   = Join-Path $workDir "DODRoots.p7b"
$bundleZip   = Join-Path $workDir "dod_certs_bundle.zip"

# -----------------------------------------------------------------------
# REQUIRED CERTIFICATES — defined as structured data
# V-254442: DoD Root CAs -> Trusted Root Certification Authorities store
# -----------------------------------------------------------------------
$dodRootCAs = @(
    @{
        Name       = "DoD Root CA 3"
        Thumbprint = "D73CA91102A2204A36459ED32213B467D7CE97FB"
        Store      = "Cert:\LocalMachine\Root"
        StoreName  = "Root"
        NotAfter   = "2029-12-30"
    },
    @{
        Name       = "DoD Root CA 4"
        Thumbprint = "B8269F25DBD937ECAFD4C35A9838571723F2D026"
        Store      = "Cert:\LocalMachine\Root"
        StoreName  = "Root"
        NotAfter   = "2032-07-25"
    },
    @{
        Name       = "DoD Root CA 5"
        Thumbprint = "4ECB5CC3095670454DA1CBD410FC921F46B8564B"
        Store      = "Cert:\LocalMachine\Root"
        StoreName  = "Root"
        NotAfter   = "2041-06-14"
    },
    @{
        Name       = "DoD Root CA 6"
        Thumbprint = "D37ECF61C0B4ED88681EF3630C4E2FC787B37AEF"
        Store      = "Cert:\LocalMachine\Root"
        StoreName  = "Root"
        NotAfter   = "2053-01-24"
    }
)

# -----------------------------------------------------------------------
# V-254443: DoD Interoperability Root CA cross-certs -> Disallowed store
# -----------------------------------------------------------------------
$dodInteropCerts = @(
    @{
        Name       = "DoD Root CA 3 (issued by DoD Interoperability Root CA 2)"
        Thumbprint = "49CBE933151872E17C8EAE7F0ABA97FB610F6477"
        Store      = "Cert:\LocalMachine\Disallowed"
        StoreName  = "Disallowed"
        NotAfter   = "2024-11-16"
    }
)

# -----------------------------------------------------------------------
# V-254444: US DOD CCEB Interoperability Root CA cross-certs -> Disallowed store
# -----------------------------------------------------------------------
$dodCCEBCerts = @(
    @{
        Name       = "DOD Root CA 3 (issued by US DOD CCEB Interoperability Root CA 2)"
        Thumbprint = "9B74964506C7ED9138070D08D5F8B969866560C8"
        Store      = "Cert:\LocalMachine\Disallowed"
        StoreName  = "Disallowed"
        NotAfter   = "2025-07-18"
    },
    @{
        Name       = "DOD Root CA 6 (issued by US DOD CCEB Interoperability Root CA 2)"
        Thumbprint = "D471CA32F7A692CE6CBB6196BD3377FE4DBCD106"
        Store      = "Cert:\LocalMachine\Disallowed"
        StoreName  = "Disallowed"
        NotAfter   = "2026-07-18"
    }
)

# -----------------------------------------------------------------------
# Helper: Install a single certificate from a p7b bundle by thumbprint
# Returns $true if installed (or already present), $false if not found in bundle
# -----------------------------------------------------------------------
function Install-CertFromP7bBundle {
    param(
        [string]$BundlePath,
        [string]$Thumbprint,
        [string]$StoreName,
        [string]$CertName
    )

    if (-not (Test-Path $BundlePath)) {
        return $false
    }

    $store = $null
    try {
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
            $StoreName,
            [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
        )
        $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)

        # Check if already present
        $existing = $store.Certificates | Where-Object { $_.Thumbprint -eq $Thumbprint }
        if ($existing) {
            return $true
        }

        # Try to parse the p7b and find the cert by thumbprint
        $p7b   = New-Object System.Security.Cryptography.Pkcs.SignedCms
        $bytes = [System.IO.File]::ReadAllBytes($BundlePath)
        $p7b.Decode($bytes)

        $match = $p7b.Certificates | Where-Object { $_.Thumbprint -eq $Thumbprint }
        if ($match) {
            $store.Add($match)
            return $true
        }

        return $false
    } catch {
        Write-Info "Could not parse p7b bundle for $CertName : $_"
        return $false
    } finally {
        if ($store) {
            $store.Close()
        }
    }
}

# -----------------------------------------------------------------------
# Helper: Download and install a single cert by thumbprint from DISA CRL
# Returns $true on success, $false on failure
# -----------------------------------------------------------------------
function Install-CertFromDisa {
    param(
        [string]$Thumbprint,
        [string]$StoreName,
        [string]$CertName,
        [string]$WorkDir
    )

    $certUrl  = "https://crl.gds.disa.mil/get/$Thumbprint.cer"
    $certFile = Join-Path $WorkDir "$Thumbprint.cer"

    try {
        Invoke-WebRequest -Uri $certUrl `
            -OutFile $certFile `
            -UseBasicParsing `
            -TimeoutSec 30 `
            -ErrorAction Stop

        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certFile)

        if ($cert.Thumbprint -ne $Thumbprint) {
            Write-Warn "Thumbprint mismatch for $CertName — NOT installing (possible tampering)"
            return $false
        }

        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
            $StoreName,
            [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
        )
        $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
        $store.Add($cert)
        $store.Close()
        return $true

    } catch {
        Write-Warn "Could not download $CertName from DISA: $_"
        return $false
    }
}

# -----------------------------------------------------------------------
# STEP 1 — Download the DoD PKI bundle from DISA
# -----------------------------------------------------------------------
Write-Section "Step 1: Download DoD PKI certificate bundle"

$downloaded = $false

# Attempt 1: PKCS#7 bundle from DISA CRL server (single file, most reliable)
Write-Info "Attempting p7b download from DISA CRL server..."
try {
    Invoke-WebRequest -Uri "https://crl.gds.disa.mil/get/DODRoots.p7b" `
        -OutFile $bundleP7b `
        -UseBasicParsing `
        -TimeoutSec 60 `
        -ErrorAction Stop
    Write-OK "Downloaded DoD PKI bundle (p7b): $bundleP7b"
    $downloaded = $true
} catch {
    Write-Warn "Primary p7b download failed: $_"
}

# Attempt 2: ZIP bundle from cyber.mil
if (-not $downloaded) {
    Write-Info "Attempting ZIP download from cyber.mil..."
    try {
        Invoke-WebRequest -Uri "https://dl.dod.cyber.mil/wp-content/uploads/pki-pke/zip/unclass-certificates_pkcs7_DoD.zip" `
            -OutFile $bundleZip `
            -UseBasicParsing `
            -TimeoutSec 120 `
            -ErrorAction Stop

        Expand-Archive -Path $bundleZip -DestinationPath $workDir -Force

        # Look for a p7b inside the extracted ZIP
        $extractedP7b = Get-ChildItem -Path $workDir -Filter "*.p7b" -Recurse | Select-Object -First 1
        if ($extractedP7b) {
            Copy-Item $extractedP7b.FullName $bundleP7b -Force
            Write-OK "Extracted p7b from ZIP: $($extractedP7b.FullName)"
            $downloaded = $true
        } else {
            Write-Warn "ZIP extracted but no .p7b found inside"
        }
    } catch {
        Write-Warn "ZIP fallback also failed: $_"
    }
}

if (-not $downloaded) {
    Write-Warn "Bundle download failed — will attempt individual cert downloads per thumbprint"
}

# -----------------------------------------------------------------------
# STEP 2 — Install DoD Root CA certificates (V-254442)
# -----------------------------------------------------------------------
Write-Section "Step 2: Install DoD Root CA certificates (V-254442)"

foreach ($ca in $dodRootCAs) {
    Write-Info "Processing: $($ca.Name) [$($ca.Thumbprint.Substring(0,8))...]"

    # Check if already present
    $existing = Get-ChildItem -Path $ca.Store -ErrorAction SilentlyContinue |
                Where-Object { $_.Thumbprint -eq $ca.Thumbprint }

    if ($existing) {
        Write-OK "Already installed: $($ca.Name)"
        continue
    }

    # Try bundle install
    $installed = Install-CertFromP7bBundle `
        -BundlePath $bundleP7b `
        -Thumbprint $ca.Thumbprint `
        -StoreName  $ca.StoreName `
        -CertName   $ca.Name

    if ($installed) {
        Write-Fixed "Installed from bundle: $($ca.Name)"
        continue
    }

    # Try individual DISA download
    $installed = Install-CertFromDisa `
        -Thumbprint $ca.Thumbprint `
        -StoreName  $ca.StoreName `
        -CertName   $ca.Name `
        -WorkDir    $workDir

    if ($installed) {
        Write-Fixed "Installed from individual DISA download: $($ca.Name)"
    } else {
        Write-Warn "FAILED to install: $($ca.Name)"
        Write-Warn "  Manual action: Run InstallRoot from https://cyber.mil/pki-pke/tools-configuration-files"
        $ErrorCount++
    }
}

# -----------------------------------------------------------------------
# STEP 3 — Install Interop cross-certs into Disallowed store (V-254443 / V-254444)
# -----------------------------------------------------------------------
Write-Section "Step 3: Install DoD Interop cross-certs into Disallowed store (V-254443 / V-254444)"

$allCrossCerts = @($dodInteropCerts) + @($dodCCEBCerts)

foreach ($ca in $allCrossCerts) {
    Write-Info "Processing: $($ca.Name)"

    $existing = Get-ChildItem -Path $ca.Store -ErrorAction SilentlyContinue |
                Where-Object { $_.Thumbprint -eq $ca.Thumbprint }

    if ($existing) {
        Write-OK "Already installed: $($ca.Name)"
        continue
    }

    # Try bundle install
    $installed = Install-CertFromP7bBundle `
        -BundlePath $bundleP7b `
        -Thumbprint $ca.Thumbprint `
        -StoreName  $ca.StoreName `
        -CertName   $ca.Name

    if ($installed) {
        Write-Fixed "Installed from bundle: $($ca.Name) -> $($ca.StoreName)"
        continue
    }

    # Try individual DISA download
    $installed = Install-CertFromDisa `
        -Thumbprint $ca.Thumbprint `
        -StoreName  $ca.StoreName `
        -CertName   $ca.Name `
        -WorkDir    $workDir

    if ($installed) {
        Write-Fixed "Installed from individual DISA download: $($ca.Name) -> $($ca.StoreName)"
    } else {
        Write-Warn "FAILED to install: $($ca.Name)"
        Write-Warn "  Manual action: Run FBCA Cross-Certificate Remover Tool from https://cyber.mil/pki-pke/tools-configuration-files"
        $ErrorCount++
    }
}

# -----------------------------------------------------------------------
# STEP 4 — Verify all required certs are present
# -----------------------------------------------------------------------
Write-Section "Step 4: Verification"

$allRequired = @($dodRootCAs) + @($dodInteropCerts) + @($dodCCEBCerts)
$verifyFail  = 0

foreach ($ca in $allRequired) {
    $found = Get-ChildItem -Path $ca.Store -ErrorAction SilentlyContinue |
             Where-Object { $_.Thumbprint -eq $ca.Thumbprint }

    if ($found) {
        Write-OK "$($ca.Name)"
        Write-Info "    Store: $($ca.Store) | Expires: $($ca.NotAfter)"
    } else {
        Write-Warn "MISSING: $($ca.Name)"
        Write-Warn "    Store: $($ca.Store) | Thumbprint: $($ca.Thumbprint)"
        $verifyFail++
        $ErrorCount++
    }
}

# -----------------------------------------------------------------------
# Cleanup working directory
# -----------------------------------------------------------------------
try {
    Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    # Non-fatal
}

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
Write-Section "DoD Certificate Installation Summary"

if ($verifyFail -eq 0) {
    Write-Host "  All DoD certificates installed and verified." -ForegroundColor Green
    Write-Host "  V-254442, V-254443, V-254444 should PASS on next SCAP scan." -ForegroundColor Green
} else {
    Write-Host "  $verifyFail certificate(s) could not be installed automatically." -ForegroundColor Yellow
    Write-Host @"

  MANUAL FALLBACK STEPS:
  -------------------------------------------------------
  1. Download InstallRoot from: https://cyber.mil/pki-pke/tools-configuration-files
  2. Run as Administrator: InstallRoot.exe /InstallRoot /unattended
     This installs all DoD Root CAs into Trusted Root store (fixes V-254442).

  3. Download the FBCA Cross-Certificate Remover Tool from the same URL.
  4. Run it once as Administrator AND once as the current user (fixes V-254443/444).

  OR manually import the following .cer files into certlm.msc:
    Trusted Root  <- DoD Root CA 3, 4, 5, 6
    Untrusted     <- DoD Interoperability Root CA 2 cross-cert
    Untrusted     <- US DOD CCEB Interoperability Root CA 2 cross-certs (x2)
  -------------------------------------------------------

"@ -ForegroundColor Yellow
}

exit $ErrorCount
