# run_all.ps1  (UPDATED — correct execution order to prevent DSC overriding fixes)
Write-Host "========== START STIG HARDENING =========="

# ---------------------------------------------------------
# 1. Install PowerSTIG + DSC dependencies
# ---------------------------------------------------------
& "$PSScriptRoot\install_PowerSTIG.ps1"
& "$PSScriptRoot\install_dsc_deps.ps1"

# ---------------------------------------------------------
# 2. Install DoD Certificates (V-254442 / 443 / 444)
#    Requires InstallRoot tool from https://cyber.mil/pki-pke/tools-configuration-files
#    Must run BEFORE DSC so cert presence is picked up in audit
# ---------------------------------------------------------
if (Test-Path "$PSScriptRoot\install_dod_certs.ps1") {
    & "$PSScriptRoot\install_dod_certs.ps1"
} else {
    Write-Warning "install_dod_certs.ps1 not found — V-254442/443/444 will remain FAIL"
}

# ---------------------------------------------------------
# 3. Apply PowerSTIG via DSC MOF
#    Use the CORRECTED create_mof.ps1 (bad Exception entries removed)
# ---------------------------------------------------------
& "$PSScriptRoot\create_mof.ps1"
& "$PSScriptRoot\apply_mof.ps1"

# ---------------------------------------------------------
# 4. Apply targeted STIG fixes AFTER DSC
#    This order is critical — DSC runs first, then we override
#    the few things DSC gets wrong or doesn't cover.
# ---------------------------------------------------------
Write-Host "=== Applying Custom STIG Fixes (post-DSC) ==="
& "$PSScriptRoot\registry_stig.ps1"
& "$PSScriptRoot\services_stig.ps1"
& "$PSScriptRoot\account_policy.ps1"

# This is the new consolidated fix script — replaces ad-hoc fixes
& "$PSScriptRoot\stig_remediation_fixes.ps1"

# ---------------------------------------------------------
# 5. Final audit
# ---------------------------------------------------------
Write-Host "=== Running Final DSC Compliance Audit ==="
$results = Test-DscConfiguration -Detailed
$reportPath = Join-Path $PSScriptRoot "DSC_Audit_Results.csv"

$final = @()
foreach ($r in $results.ResourcesInDesiredState) {
    $r | Add-Member -NotePropertyName Compliance -NotePropertyValue "TRUE" -Force
    $final += $r
}
foreach ($r in $results.ResourcesNotInDesiredState) {
    $r | Add-Member -NotePropertyName Compliance -NotePropertyValue "FALSE" -Force
    $final += $r
}
$final | Export-Csv -Path $reportPath -NoTypeInformation

$passCount = ($results.ResourcesInDesiredState | Measure-Object).Count
$failCount = ($results.ResourcesNotInDesiredState | Measure-Object).Count
Write-Host "DSC Compliance: $passCount PASS / $failCount FAIL"
Write-Host "Report saved at: $reportPath"
Write-Host "========== STIG HARDENING COMPLETE =========="
