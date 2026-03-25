# ------------------------------------------------------------
# install_dod_certs.ps1
# Applies all DoD, Interop, and CCEB certificates into Disallowed store
# Skips DoD Root certificates
# Run this script as Administrator
# ------------------------------------------------------------

# Path to your DoD cert folder
$certFolder = "C:\Users\packer_user\hardening\DoD_Approved_External_PKIs_Trust_Chains_v11.5_20250303"

Write-Host "Starting import of DoD / Interop / CCEB certificates..." -ForegroundColor Cyan

# Import certs
Get-ChildItem "$certFolder" -Recurse -Filter *.cer | ForEach-Object {
    $lines = certutil -dump $_.FullName

    foreach ($line in $lines) {
        # Match all three V-IDs: DoD, Interop, CCEB
        if ($line -match "Interop|CCEB|DoD") {
            # Skip DoD Root certs only
            if ($line -match "DoD Root") {
                Write-Host "Skipping root cert (kept trusted): $($_.FullName)" -ForegroundColor Yellow
                break
            }

            Write-Host "Importing cert into Disallowed store: $($_.FullName)" -ForegroundColor Green
            certutil -addstore -f "Disallowed" $_.FullName
            break
        }
    }
}

Write-Host "`nImport complete. Verifying applied certificates..." -ForegroundColor Cyan

# Verify applied certs
$appliedCerts = Get-ChildItem Cert:\LocalMachine\Disallowed |
    Where-Object { $_.Subject -match "DoD|Interop|CCEB" -and $_.Subject -notmatch "DoD Root" } |
    Select-Object Subject, NotAfter, Thumbprint

if ($appliedCerts.Count -eq 0) {
    Write-Host "No DoD / Interop / CCEB certificates found in Disallowed store!" -ForegroundColor Red
} else {
    Write-Host "Certificates successfully applied:" -ForegroundColor Green
    $appliedCerts | Format-Table -AutoSize
}

Write-Host "`nAll done." -ForegroundColor Cyan

# ------------------------------------------------------------
# Notes / Comments:
# 1. Cloud Run / Packer sometimes truncates long scripts; consider splitting each V-ID import into separate .ps1 files.
# 2. Ensure script is saved as UTF-8 without BOM and CRLF line endings.
# 3. Running as Admin is required to write to LocalMachine stores.
# 4. DoD Root certs are skipped by default; if needed, remove the skip check.
# 5. Verification prints the subject, expiration date, and thumbprint of applied certificates.
# ------------------------------------------------------------

# ------------------------------------------------------------
# Notes / Comments:
# 1. Cloud Run / Packer sometimes truncates long scripts; consider splitting each V-ID import into separate .ps1 files.
# 2. Ensure script is saved as UTF-8 without BOM and CRLF line endings.
# 3. Running as Admin is required to write to LocalMachine stores.
# 4. DoD Root certs are skipped by default; if needed, remove the skip check.
# 5. Verification prints the subject, expiration date, and thumbprint of applied certificates.
# ------------------------------------------------------------
