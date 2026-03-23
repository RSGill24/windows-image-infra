# install_dod_certs.ps1
# Fixes:
#   V-254442 -- DoD Root CA certificates must be in Trusted Root Store
#   V-254443 -- DoD Interoperability Root CA 2 cross-cert in Untrusted Store
#   V-254444 -- US DoD CCEB Interoperability Root CA 2 cross-cert in Untrusted Store
#
# Downloads the official DoD PKI bundles from public.cyber.mil and installs them.
# Requires outbound HTTPS access from the Packer build VM.

Write-Host "=== Installing DoD PKI Certificates ==="

# -----------------------------------------------------------------------
# Helper: download with retry
# -----------------------------------------------------------------------
function Invoke-DownloadWithRetry {
    param(
        [string]$Url,
        [string]$OutFile,
        [int]$Retries = 3
    )
    for ($i = 1; $i -le $Retries; $i++) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 60
            return $true
        } catch {
            Write-Warning "  Attempt $i failed: $_"
            Start-Sleep -Seconds 5
        }
    }
    return $false
}

# -----------------------------------------------------------------------
# Helper: import cert into a named store
# -----------------------------------------------------------------------
function Import-CertToStore {
    param(
        [string]$CertPath,
        [string]$StoreName,       # e.g. "Root", "Disallowed"
        [string]$StoreLocation    # e.g. "LocalMachine"
    )
    try {
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
            $StoreName,
            [System.Security.Cryptography.X509Certificates.StoreLocation]::$StoreLocation
        )
        $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)

        # Handle both .cer (single) and .p7b (bundle) files
        if ($CertPath -match "\.p7b$") {
            $cms = New-Object System.Security.Cryptography.Pkcs.SignedCms
            $cms.Decode([System.IO.File]::ReadAllBytes($CertPath))
            foreach ($cert in $cms.Certificates) {
                $store.Add($cert)
                Write-Host "    Imported: $($cert.Subject)"
            }
        } else {
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertPath)
            $store.Add($cert)
            Write-Host "    Imported: $($cert.Subject)"
        }
        $store.Close()
        return $true
    } catch {
        Write-Error "  Failed to import $CertPath into $StoreName : $_"
        return $false
    }
}

$tempDir = Join-Path $env:TEMP "dod_certs"
New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

# -----------------------------------------------------------------------
# V-254442: DoD Root CA certificates -- Trusted Root Store
# Bundle source: public.cyber.mil (official DoD PKI)
# -----------------------------------------------------------------------
Write-Host "--- V-254442: Installing DoD Root CA certificates..."

$dodRootUrl  = "https://public.cyber.mil/pki-pke/pkipke-document-library/"
# The trust anchor bundle (.p7b) contains DoD Root CA 3, 4, 5, 6
$dodRootFile = Join-Path $tempDir "dod_root_cas.p7b"

# DoD PKI trust bundle -- always fetch the latest from cyber.mil
$downloaded = Invoke-DownloadWithRetry `
    -Url "https://dl.dod.cyber.mil/wp-content/uploads/pki-pke/zip/unclass-certificates_pkcs7_DoD.zip" `
    -OutFile (Join-Path $tempDir "dod_pki.zip")

if ($downloaded) {
    Expand-Archive -Path (Join-Path $tempDir "dod_pki.zip") -DestinationPath $tempDir -Force
    # Find the Roots p7b inside the extracted bundle
    $rootBundle = Get-ChildItem -Path $tempDir -Filter "*DoD_PKE_CA_chain*" -Recurse |
                  Select-Object -First 1
    if ($rootBundle) {
        Import-CertToStore -CertPath $rootBundle.FullName -StoreName "Root" -StoreLocation "LocalMachine"
        Write-Host "  DoD Root CA bundle installed."
    } else {
        Write-Warning "  Root CA bundle file not found in zip -- manual install may be required."
    }
} else {
    Write-Warning "  Could not download DoD PKI bundle -- skipping V-254442."
    Write-Warning "  Manual installation required: https://public.cyber.mil/pki-pke/"
}

# -----------------------------------------------------------------------
# V-254443 / V-254444: Cross-certs in Untrusted (Disallowed) store
# These cross-certs prevent misuse of DoD interoperability roots on
# unclassified systems by placing them in the Untrusted Certificates store.
# -----------------------------------------------------------------------
Write-Host "--- V-254443 / V-254444: Installing cross-certificates into Untrusted store..."

$crossCertSources = @(
    @{
        # V-254443: DoD Interoperability Root CA 2
        Url  = "https://dl.dod.cyber.mil/wp-content/uploads/pki-pke/zip/unclass-dod_interoperability_root_ca2_cross_certs.zip"
        File = "dod_interop_root_ca2.zip"
        STIG = "V-254443"
    },
    @{
        # V-254444: US DoD CCEB Interoperability Root CA 2
        Url  = "https://dl.dod.cyber.mil/wp-content/uploads/pki-pke/zip/unclass-us_dod_cceb_interoperability_root_ca2_cross_certs.zip"
        File = "us_dod_cceb_root_ca2.zip"
        STIG = "V-254444"
    }
)

foreach ($src in $crossCertSources) {
    Write-Host "  Processing $($src.STIG)..."
    $zipPath = Join-Path $tempDir $src.File
    $ok = Invoke-DownloadWithRetry -Url $src.Url -OutFile $zipPath

    if ($ok) {
        $extractDir = Join-Path $tempDir ($src.STIG)
        Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
        Get-ChildItem -Path $extractDir -Include "*.cer","*.p7b" -Recurse |
            ForEach-Object {
                Import-CertToStore -CertPath $_.FullName -StoreName "Disallowed" -StoreLocation "LocalMachine"
            }
        Write-Host "  $($src.STIG): cross-cert installed in Untrusted store."
    } else {
        Write-Warning "  Could not download cross-cert for $($src.STIG) -- manual install required."
    }
}

# -----------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "=== DoD certificate installation complete. ==="