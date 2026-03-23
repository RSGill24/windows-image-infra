# run_all.ps1
# Master orchestration script.
# Executes the full STIG hardening workflow in the correct order.

param (
    [string]$HardeningDir = $PSScriptRoot
)

Set-Location $HardeningDir
$ErrorActionPreference = "Stop"

function Invoke-Step {
    param([string]$Name, [string]$Script)
    Write-Host ""
    Write-Host "================================================================"
    Write-Host " STEP: $Name"
    Write-Host "================================================================"
    $scriptPath = Join-Path $HardeningDir $Script
    if (!(Test-Path $scriptPath)) {
        Write-Error "Script not found: $scriptPath"
        exit 1
    }
    & $scriptPath -HardeningDir $HardeningDir
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Write-Error "$Name failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
    Write-Host " STEP COMPLETE: $Name"
}

Invoke-Step "Install PowerSTIG"          "install_PowerSTIG.ps1"
Invoke-Step "Install DSC Dependencies"   "install_dsc_deps.ps1"
Invoke-Step "Install DoD Certificates"   "install_dod_certs.ps1"      # V-254442/443/444
Invoke-Step "Generate MOF"               "create_mof.ps1"
Invoke-Step "Apply MOF (STIG DSC)"       "apply_mof.ps1"
Invoke-Step "Apply Audit Policy"         "apply_audit_policy.ps1"     # V-278942 to V-278947
Invoke-Step "Apply Account Hardening"    "apply_account_hardening.ps1" # V-254446/447/448/258/501/251/261
Invoke-Step "Run Audit Validation"       "audit.ps1"

Write-Host ""
Write-Host "================================================================"
Write-Host " ALL HARDENING STEPS COMPLETE"
Write-Host "================================================================"