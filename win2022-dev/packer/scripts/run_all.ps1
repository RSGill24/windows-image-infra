# run_all.ps1
# Master orchestration script — correct execution order.

param (
    [string]$HardeningDir = $PSScriptRoot
)

Set-Location $HardeningDir
$ErrorActionPreference = "Stop"

function Invoke-Step {
    param([string]$Name, [string]$Script)
    Write-Host ""
    Write-Host "============================================================"
    Write-Host " STEP: $Name"
    Write-Host "============================================================"
    $scriptPath = Join-Path $HardeningDir $Script
    if (!(Test-Path $scriptPath)) {
        Write-Error "Script not found: $scriptPath"
        exit 1
    }
    & $scriptPath
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Write-Error "$Name failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
    Write-Host " COMPLETE: $Name"
}

# Correct order: install modules first, then deps (which generates org XML),
# then compile MOF, then apply, then audit hardening on top.
Invoke-Step "1. Install PowerSTIG"           "install_PowerSTIG.ps1"
Invoke-Step "2. Install DSC Dependencies"    "install_dsc_deps.ps1"
Invoke-Step "3. Install DoD Certificates"    "install_dod_certs.ps1"
Invoke-Step "4. Generate MOF"                "create_mof.ps1"
Invoke-Step "5. Apply MOF (STIG DSC)"        "apply_mof.ps1"
Invoke-Step "6. Apply Audit Policy"          "apply_audit_policy.ps1"
Invoke-Step "7. Apply Account Hardening"     "apply_account_hardening.ps1"
Invoke-Step "8. Create Audit Task"           "create_audit_task.ps1"
Invoke-Step "9. Run Audit Validation"        "audit.ps1"

Write-Host ""
Write-Host "============================================================"
Write-Host " ALL HARDENING STEPS COMPLETE"
Write-Host "============================================================"
