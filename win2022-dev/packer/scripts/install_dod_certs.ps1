# ===============================================================
# Import and Verify DoD PKCS7 Certificates
# ===============================================================

$P7BPath = "C:\Users\packer_user\hardening\Certificates_PKCS7_v5_14_DoD.der.p7b"

Function Import-CertsToStore {
    param (
        [Parameter(Mandatory=$true)][System.Security.Cryptography.X509Certificates.X509Certificate2Collection]$Certificates,
        [Parameter(Mandatory=$true)][string]$StoreName
    )

    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store $StoreName, "LocalMachine"
    $store.Open("ReadWrite")
    foreach ($cert in $Certificates) {
        if (-not ($store.Certificates | Where-Object { $_.Thumbprint -eq $cert.Thumbprint })) {
            $store.Add($cert)
        }
    }
    $store.Close()
}

# Load certificates from P7B
$collection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
try {
    $collection.Import($P7BPath)
} catch {
    Write-Error "Failed to load P7B file: $_"
    exit 1
}

# Separate Root and Intermediate certs
$roots = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
$intermediates = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection

foreach ($cert in $collection) {
    if ($cert.Subject -eq $cert.Issuer) {
        $roots.Add($cert)
    } else {
        $intermediates.Add($cert)
    }
}

# Import certs
Import-CertsToStore -Certificates $roots -StoreName "Root"
Import-CertsToStore -Certificates $intermediates -StoreName "CA"

# Verification
$rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store "Root","LocalMachine"
$rootStore.Open("ReadOnly")
$caStore = New-Object System.Security.Cryptography.X509Certificates.X509Store "CA","LocalMachine"
$caStore.Open("ReadOnly")
$disallowedStore = New-Object System.Security.Cryptography.X509Certificates.X509Store "Disallowed","LocalMachine"
$disallowedStore.Open("ReadOnly")

Write-Host "`n--- Verification ---"
Write-Host "Total Root Certs: $($rootStore.Certificates.Count)"
Write-Host "Total Intermediate Certs: $($caStore.Certificates.Count)"
Write-Host "Total Disallowed Certs: $($disallowedStore.Certificates.Count)"

if ($disallowedStore.Certificates.Count -eq 0) {
    Write-Host "`nDisallowed store is clean ✅"
} else {
    Write-Host "`nDisallowed store contains certificates ⚠️"
}

$rootStore.Close()
$caStore.Close()
$disallowedStore.Close()

Write-Host "`nScript completed successfully."
