#Requires -RunAsAdministrator
# run_all.ps1 — Main STIG hardening entry point for Packer/GCP builds
Write-Host "========== START STIG HARDENING ==========" -ForegroundColor Cyan

$scriptDir = $PSScriptRoot

# Helper: run a script and abort on failure
function Invoke-Step {
    param([string]$ScriptPath, [string]$Label)
    Write-Host "`n--- $Label ---" -ForegroundColor Yellow
    if (-not (Test-Path $ScriptPath)) {
        Write-Warning "Script not found, skipping: $ScriptPath"
        return
    }
    & $ScriptPath
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Write-Error "$Label failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
}

# 1. Install PowerSTIG + DSC dependencies
Invoke-Step "$scriptDir\install_PowerSTIG.ps1"    "Install PowerSTIG"
Invoke-Step "$scriptDir\install_dsc_deps.ps1"     "Install DSC dependencies"

# 2. Install DoD Certificates (V-254442 / 443 / 444)
Invoke-Step "$scriptDir\install_dod_certs.ps1"    "Install DoD Certificates"

# 3. Apply PowerSTIG DSC MOF (use corrected version — bad Exception entries removed)
Invoke-Step "$scriptDir\create_mof.ps1" "Create DSC MOF"
Invoke-Step "$scriptDir\apply_mof.ps1"            "Apply DSC MOF"

# 4. Post-DSC targeted fixes (must run AFTER DSC so DSC cannot undo them)
Invoke-Step "$scriptDir\registry_stig.ps1"              "Registry STIG fixes"
Invoke-Step "$scriptDir\services_stig.ps1"              "Services STIG fixes"
Invoke-Step "$scriptDir\account_policy.ps1"             "Account policy fixes"
Invoke-Step "$scriptDir\stig_remediation_fixes.ps1"     "Targeted STIG remediation (22 failures)"

# 5. Repair WinRM LAST — must run after all STIG hardening so Packer
#    can reconnect to upload its cleanup script and capture the image.
#    This does NOT undo STIG controls — it only restores Packer's auth.
Invoke-Step "$scriptDir\repair_winrm_for_packer.ps1"   "Repair WinRM for Packer (post-hardening)"

# 5. Final DSC compliance audit
Write-Host "`n--- Final DSC Compliance Audit ---" -ForegroundColor Yellow
$results    = Test-DscConfiguration -Detailed
$reportPath = Join-Path $scriptDir "DSC_Audit_Results.csv"

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

$passCount = ($results.ResourcesInDesiredState  | Measure-Object).Count
$failCount = ($results.ResourcesNotInDesiredState | Measure-Object).Count

Write-Host "DSC Compliance: $passCount PASS  /  $failCount FAIL" -ForegroundColor Cyan
Write-Host "Report: $reportPath"
Write-Host "========== STIG HARDENING COMPLETE ==========" -ForegroundColor Cyan
