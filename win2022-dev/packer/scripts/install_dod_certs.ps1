#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs all required DoD PKI certificates for STIG compliance.
    Fixes: V-254442 (DoD Root CAs), V-254443 (DoD Interop cross-certs),
           V-254444 (US DOD CCEB Interop cross-certs)

.NOTES
    Certificate source: https://crl.gds.disa.mil / https://cyber.mil/pki-pke
    This script downloads the DoD PKI bundle ZIP, extracts it, and installs
    each required certificate into the correct Windows certificate store.
    Safe to re-run — existing certs are skipped.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Section ($msg) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " $msg" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}
function Write-OK    ($msg) { Write-Host "  [OK]     $msg" -ForegroundColor Green   }
function Write-Fixed ($msg) { Write-Host "  [ADDED]  $msg" -ForegroundColor Yellow  }
function Write-Warn  ($msg) { Write-Host "  [WARN]   $msg" -ForegroundColor Magenta }
function Write-Info  ($msg) { Write-Host "  [INFO]   $msg" -ForegroundColor Gray    }

# -----------------------------------------------------------------------
# Enforce TLS 1.2 for all web requests (required on older .NET defaults)
# -----------------------------------------------------------------------
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$workDir = Join-Path $env:TEMP "dod_certs_install"
if (Test-Path $workDir) { Remove-Item $workDir -Recurse -Force }
New-Item -Path $workDir -ItemType Directory -Force | Out-Null

$ErrorCount = 0

# -----------------------------------------------------------------------
# REQUIRED CERTIFICATES — defined as structured data
# -----------------------------------------------------------------------

# V-254442: DoD Root CAs -> Trusted Root Certification Authorities store
$dodRootCAs = @(
    @{
        Name       = "DoD Root CA 3"
        Thumbprint = "D73CA91102A2204A36459ED32213B467D7CE97FB"
        Store      = "Cert:\LocalMachine\Root"
        StoreName  = "Root"
        NotAfter   = "2029-12-30"
    }
    @{
        Name       = "DoD Root CA 4"
        Thumbprint = "B8269F25DBD937ECAFD4C35A9838571723F2D026"
        Store      = "Cert:\LocalMachine\Root"
        StoreName  = "Root"
        NotAfter   = "2032-07-25"
    }
    @{
        Name       = "DoD Root CA 5"
        Thumbprint = "4ECB5CC3095670454DA1CBD410FC921F46B8564B"
        Store      = "Cert:\LocalMachine\Root"
        StoreName  = "Root"
        NotAfter   = "2041-06-14"
    }
    @{
        Name       = "DoD Root CA 6"
        Thumbprint = "D37ECF61C0B4ED88681EF3630C4E2FC787B37AEF"
        Store      = "Cert:\LocalMachine\Root"
        StoreName  = "Root"
        NotAfter   = "2053-01-24"
    }
)

# V-254443: DoD Interoperability Root CA cross-certs -> Untrusted/Disallowed store
$dodInteropCerts = @(
    @{
        Name       = "DoD Root CA 3 (issued by DoD Interoperability Root CA 2)"
        Thumbprint = "49CBE933151872E17C8EAE7F0ABA97FB610F6477"
        Store      = "Cert:\LocalMachine\Disallowed"
        StoreName  = "Disallowed"
        NotAfter   = "2024-11-16"
    }
)

# V-254444: US DOD CCEB Interoperability Root CA cross-certs -> Untrusted/Disallowed store
$dodCCEBCerts = @(
    @{
        Name       = "DOD Root CA 3 (issued by US DOD CCEB Interoperability Root CA 2)"
        Thumbprint = "9B74964506C7ED9138070D08D5F8B969866560C8"
        Store      = "Cert:\LocalMachine\Disallowed"
        StoreName  = "Disallowed"
        NotAfter   = "2025-07-18"
    }
    @{
        Name       = "DOD Root CA 6 (issued by US DOD CCEB Interoperability Root CA 2)"
        Thumbprint = "D471CA32F7A692CE6CBB6196BD3377FE4DBCD106"
        Store      = "Cert:\LocalMachine\Disallowed"
        StoreName  = "Disallowed"
        NotAfter   = "2026-07-18"
    }
)

# -----------------------------------------------------------------------
# STEP 1 — Download the official DoD PKI certificate bundle from DISA
# -----------------------------------------------------------------------
Write-Section "Step 1: Download DoD PKI certificate bundle"

# Primary source: DISA CRL/PKI bundle (unclassified)
# This ZIP contains all DoD Root CA and Interop cross-cert .cer files
$bundleUrls = @(
    "https://crl.gds.disa.mil/get/DODRoots.p7b",
    "https://dl.dod.cyber.mil/wp-content/uploads/pki-pke/zip/unclass-certificates_pkcs7_DoD.zip"
)

$bundleZip = Join-Path $workDir "dod_certs_bundle.zip"
$bundleP7b = Join-Path $workDir "DODRoots.p7b"
$downloaded = $false

# Try downloading the PKCS#7 bundle first (most reliable single file)
Write-Info "Attempting download from DISA CRL server..."
try {
    Invoke-WebRequest -Uri $bundleUrls[0] `
        -OutFile $bundleP7b `
        -UseBasicParsing `
        -TimeoutSec 60 `
        -ErrorAction Stop
    Write-OK "Downloaded DoD PKI bundle (p7b): $bundleP7b"
    $downloaded = $true
} catch {
    Write-Warn "Primary download failed: $_"
}

# Try the ZIP bundle if p7b failed
if (-not $downloaded) {
    Write-Info "Attempting fallback download from cyber.mil..."
    try {
        Invoke-WebRequest -Uri $bundleUrls[1] `
            -OutFile $bundleZip `
            -UseBasicParsing `
            -TimeoutSec 120 `
            -ErrorAction Stop
        Write-OK "Downloaded DoD cert bundle ZIP: $bundleZip"
        $downloaded = $true
        # Extract ZIP
        Expand-Archive -Path $bundleZip -DestinationPath $workDir -Force
        Write-OK "Extracted bundle to: $workDir"
    } catch {
        Write-Warn "Fallback download also failed: $_"
    }
}

# -----------------------------------------------------------------------
# STEP 2 — Install certificates from the downloaded bundle (if available)
# -----------------------------------------------------------------------
Write-Section "Step 2: Install certificates from bundle"

function Install-CertFromBundle {
    param(
        [string]$BundlePath,
        [string]$Thumbprint,
        [string]$StoreName,
        [string]$CertName
    )

    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
        $StoreName,
        [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
    )
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)

    # Check if already installed
    $existing = $store.Certificates | Where-Object { $_.Thumbprint -eq $Thumbprint }
    if ($existing) {
        $store.Close()
        return $true  # already present
    }

    # Try to load from p7b bundle
    if ($BundlePath -and (Test-Path $BundlePath) -and $BundlePath.EndsWith('.p7b')) {
        try {
            $p7b = New-Object System.Security.Cryptography.Pkcs.SignedCms
            $p7b.Decode([System.IO.File]::ReadAllBytes($BundlePath))
            $match = $p7b.Certificates | Where-Object {
                $_.Thumbprint -eq $Thumbprint
            }
            if ($match) {
                $store.Add($match)
                $store.Close()
                return $true
            }
        } catch {
            Write-Info "  Could not parse p7b for $CertName`: $_"
        }
    }

    $store.Close()
    return $false
}

# -----------------------------------------------------------------------
# STEP 3 — Install each required cert (bundle first, then embedded fallback)
# -----------------------------------------------------------------------
Write-Section "Step 3: Install DoD Root CA certificates (V-254442)"

foreach ($ca in $dodRootCAs) {
    Write-Info "Processing: $($ca.Name) [$($ca.Thumbprint.Substring(0,8))...]"

    # Check if already installed
    $existing = Get-ChildItem -Path $ca.Store -ErrorAction SilentlyContinue |
                Where-Object { $_.Thumbprint -eq $ca.Thumbprint }

    if ($existing) {
        Write-OK "Already installed: $($ca.Name)"
        continue
    }

    # Try bundle install
    $installedFromBundle = $false
    if (Test-Path $bundleP7b) {
        $installedFromBundle = Install-CertFromBundle `
            -BundlePath $bundleP7b `
            -Thumbprint $ca.Thumbprint `
            -StoreName $ca.StoreName `
            -CertName $ca.Name
    }

    if ($installedFromBundle) {
        Write-Fixed "Installed from bundle: $($ca.Name)"
        continue
    }

    # Try downloading individual cert by thumbprint from DISA CRL
    $certUrl = "https://crl.gds.disa.mil/get/$($ca.Thumbprint).cer"
    $certFile = Join-Path $workDir "$($ca.Thumbprint).cer"

    try {
        Invoke-WebRequest -Uri $certUrl `
            -OutFile $certFile `
            -UseBasicParsing `
            -TimeoutSec 30 `
            -ErrorAction Stop

        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certFile)

        if ($cert.Thumbprint -eq $ca.Thumbprint) {
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
                $ca.StoreName,
                [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
            )
            $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
            $store.Add($cert)
            $store.Close()
            Write-Fixed "Installed from individual download: $($ca.Name)"
        } else {
            Write-Warn "Thumbprint mismatch for $($ca.Name) — NOT installing"
            $ErrorCount++
        }
    } catch {
        Write-Warn "Could not download individual cert for $($ca.Name): $_"
        Write-Warn "  Manual action: Install from InstallRoot tool at https://cyber.mil/pki-pke/tools-configuration-files"
        $ErrorCount++
    }
}

# -----------------------------------------------------------------------
# Install Interop cross-certs into Disallowed (Untrusted) store
# -----------------------------------------------------------------------
Write-Section "Step 4: Install DoD Interop cross-certs — Disallowed store (V-254443 / V-254444)"

$allCrossCerts = $dodInteropCerts + $dodCCEBCerts

foreach ($ca in $allCrossCerts) {
    Write-Info "Processing: $($ca.Name)"

    $existing = Get-ChildItem -Path $ca.Store -ErrorAction SilentlyContinue |
                Where-Object { $_.Thumbprint -eq $ca.Thumbprint }

    if ($existing) {
        Write-OK "Already installed: $($ca.Name)"
        continue
    }

    # Try bundle install
    $installedFromBundle = $false
    if (Test-Path $bundleP7b) {
        $installedFromBundle = Install-CertFromBundle `
            -BundlePath $bundleP7b `
            -Thumbprint $ca.Thumbprint `
            -StoreName $ca.StoreName `
            -CertName $ca.Name
    }

    if ($installedFromBundle) {
        Write-Fixed "Installed from bundle: $($ca.Name)"
        continue
    }

    # Try individual download
    $certUrl = "https://crl.gds.disa.mil/get/$($ca.Thumbprint).cer"
    $certFile = Join-Path $workDir "$($ca.Thumbprint).cer"

    try {
        Invoke-WebRequest -Uri $certUrl `
            -OutFile $certFile `
            -UseBasicParsing `
            -TimeoutSec 30 `
            -ErrorAction Stop

        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certFile)

        if ($cert.Thumbprint -eq $ca.Thumbprint) {
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
                $ca.StoreName,
                [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
            )
            $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
            $store.Add($cert)
            $store.Close()
            Write-Fixed "Installed: $($ca.Name) -> $($ca.StoreName)"
        } else {
            Write-Warn "Thumbprint mismatch for $($ca.Name) — NOT installing"
            $ErrorCount++
        }
    } catch {
        Write-Warn "Could not download $($ca.Name): $_"
        Write-Warn "  Manual action: Run FBCA Cross-Certificate Remover Tool from https://cyber.mil/pki-pke/tools-configuration-files"
        $ErrorCount++
    }
}

# -----------------------------------------------------------------------
# STEP 5 — Verify all required certs are now present
# -----------------------------------------------------------------------
Write-Section "Step 5: Verification"

$allRequired = $dodRootCAs + $dodInteropCerts + $dodCCEBCerts
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
# Cleanup
# -----------------------------------------------------------------------
try {
    Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue
} catch { }

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
Write-Section "DoD Certificate Installation Summary"

if ($verifyFail -eq 0) {
    Write-Host "  All DoD certificates installed and verified." -ForegroundColor Green
    Write-Host "  V-254442, V-254443, V-254444 should now PASS on next SCAP scan." -ForegroundColor Green
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
