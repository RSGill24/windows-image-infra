# ===============================
# DoD Certificates Import Script
# ===============================

# Paths
$MainP7B      = "C:\Users\packer_user\hardening\Certificates_PKCS7_v5_14_DoD.der.p7b"
$ExternalFolder = "C:\Users\packer_user\hardening\DoD_Approved_External_PKIs_Trust_Chains_v11.5_20250303"

# ===============================
# Function: Import certificates to a store
# ===============================
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
        try {
            $found = $store.Certificates.Find("FindByThumbprint", $cert.Thumbprint, $false)
            if ($found.Count -eq 0) {
                $store.Add($cert)
                Write-Host "✅ Imported $($cert.Subject) -> $StoreName"
            } else {
                Write-Host "Already exists: $($cert.Subject) -> $StoreName"
            }
        } catch {
            Write-Warning ("Failed to import " + $cert.Subject + " to " + $StoreName + ": " + $_.Exception.Message)
        }
    }

    $store.Close()
}

# ===============================
# Import main P7B
# ===============================
if (Test-Path $MainP7B) {
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
} else {
    Write-Warning "Main P7B file not found: $MainP7B"
}

# ===============================
# Import external approval certificates
# ===============================
if (Test-Path $ExternalFolder) {
    Write-Host "`nProcessing external approval certificates from: $ExternalFolder"
    $externalFiles = Get-ChildItem -Path $ExternalFolder -Filter *.cer -File
    $externalCerts = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection

    foreach ($file in $externalFiles) {
        try {
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($file.FullName)
            $externalCerts.Add($cert)
        } catch {
            Write-Warning ("Failed to load external cert: " + $file.FullName + " - " + $_.Exception.Message)
        }
    }

    if ($externalCerts.Count -gt 0) {
        Import-CertsToStore -Certificates $externalCerts -StoreName "Root"
        Import-CertsToStore -Certificates $externalCerts -StoreName "CA"
    } else {
        Write-Warning "No valid external certificates found in $ExternalFolder"
    }
} else {
    Write-Warning "External folder not found: $ExternalFolder"
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
