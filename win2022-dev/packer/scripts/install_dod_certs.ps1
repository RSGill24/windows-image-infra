# ===============================
# DoD Certificates Import Script (FINAL - STIG COMPLIANT)
# ===============================

# Paths (UPDATED)
$MainP7B        = "C:\Users\packer_user\hardening\Certificates_PKCS7_v5_14_DoD.der.p7b"
$ExternalFolder = "C:\DoD_Certs"   # ✅ FIXED (was wrong earlier)

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
# Function: Import to Disallowed (Untrusted) store
# ===============================
function Import-ToDisallowed {
    param (
        [Parameter(Mandatory)]
        [string]$FolderPath
    )

    Write-Host "`nProcessing Interop / CCEB certs for UNTRUSTED store..."

    if (!(Test-Path $FolderPath)) {
        Write-Warning "Folder not found: $FolderPath"
        return
    }

    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Disallowed", "LocalMachine")
    $store.Open("ReadWrite")

    Get-ChildItem -Path $FolderPath -Recurse -Include *.cer, *.crt, *.der -File | ForEach-Object {
        try {
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($_.FullName)

            # Only import Interop / CCEB related certs
            if ($cert.Subject -match "Interop|CCEB") {

                $exists = $store.Certificates.Find("FindByThumbprint", $cert.Thumbprint, $false)

                if ($exists.Count -eq 0) {
                    $store.Add($cert)
                    Write-Host "🚫 Added to DISALLOWED: $($_.Name)"
                } else {
                    Write-Host "Already in Disallowed: $($_.Name)"
                }
            }
        } catch {
            Write-Warning "Failed to import $($_.FullName): $_"
        }
    }

    $store.Close()
}

# ===============================
# Import main P7B (Root + Intermediate)
# ===============================
if (Test-Path $MainP7B) {
    Write-Host "`nProcessing main DoD P7B..."

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
# STIG FIX: V-254443 & V-254444
# Import Interop + CCEB → DISALLOWED
# ===============================
Import-ToDisallowed -FolderPath $ExternalFolder

# ===============================
# Verification
# ===============================
Write-Host "`n--- FINAL VERIFICATION ---"

$rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root","LocalMachine")
$rootStore.Open("ReadOnly")

$caStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("CA","LocalMachine")
$caStore.Open("ReadOnly")

$disallowedStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("Disallowed","LocalMachine")
$disallowedStore.Open("ReadOnly")

Write-Host "Root Certs Count: $($rootStore.Certificates.Count)"
Write-Host "Intermediate Certs Count: $($caStore.Certificates.Count)"
Write-Host "Disallowed Certs Count: $($disallowedStore.Certificates.Count)"

# Show only relevant Disallowed certs
$disallowedStore.Certificates |
Where-Object { $_.Subject -match "Interop|CCEB" } |
Select Subject, Thumbprint

$rootStore.Close()
$caStore.Close()
$disallowedStore.Close()

Write-Host "`n✅ Script completed (STIG aligned)"
