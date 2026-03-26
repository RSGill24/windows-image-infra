# ===============================
# DoD Certificates Import Script
# ===============================
# Paths
$MainP7B = "C:\Users\packer_user\hardening\Certificates_PKCS7_v5_14_DoD.der.p7b"
$ExternalFolder = "C:\Users\packer_user\hardening\DoD._Approval_External"

# Function to import certificates to a store
function Import-CertsToStore {
    param (
        [Parameter(Mandatory)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]$Certificates,

        [Parameter(Mandatory)]
        [string]$StoreName
    )

    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($StoreName, "LocalMachine")
    $store.Open("ReadWrite")

    foreach ($cert in $Certificates) {
        if (-not $store.Certificates.Find("FindByThumbprint", $cert.Thumbprint, $false)) {
            $store.Add($cert)
        }
    }

    $store.Close()
}

# Import main P7B
Write-Host "`nProcessing main P7B file: $MainP7B"
$collection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
$collection.Import($MainP7B)

$rootCerts = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
$intermediateCerts = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection

foreach ($cert in $collection) {
    if ($cert.Subject -eq $cert.Issuer) {
        $rootCerts.Add($cert)
    } else {
        $intermediateCerts.Add($cert)
    }
}

Import-CertsToStore -Certificates $rootCerts -StoreName "Root"
Import-CertsToStore -Certificates $intermediateCerts -StoreName "CA"

# Import external approval certificates if folder exists
if (Test-Path $ExternalFolder) {
    Write-Host "`nProcessing external approval certificates from: $ExternalFolder"
    $externalFiles = Get-ChildItem -Path $ExternalFolder -Filter *.cer -File
    $externalCerts = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection

    foreach ($file in $externalFiles) {
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($file.FullName)
        $externalCerts.Add($cert)
    }

    Import-CertsToStore -Certificates $externalCerts -StoreName "Root"
    Import-CertsToStore -Certificates $externalCerts -StoreName "CA"
}

# ===============================
# Verification
# ===============================
$rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root","LocalMachine")
$rootStore.Open("ReadOnly")
$caStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("CA","LocalMachine")
$caStore.Open("ReadOnly")
$disallowedStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("Disallowed","LocalMachine")
$disallowedStore.Open("ReadOnly")

Write-Host "`n--- Verification ---"
Write-Host "Total Root Certs: $($rootStore.Certificates.Count)"
Write-Host "Total Intermediate Certs: $($caStore.Certificates.Count)"
Write-Host "Total Disallowed Certs: $($disallowedStore.Certificates.Count)"

if ($disallowedStore.Certificates.Count -eq 0) {
    Write-Host "`nDisallowed store is clean ✅"
} else {
    Write-Host "`nWarning: Disallowed store has certs!"
}

$rootStore.Close()
$caStore.Close()
$disallowedStore.Close()

Write-Host "`nScript completed successfully."
