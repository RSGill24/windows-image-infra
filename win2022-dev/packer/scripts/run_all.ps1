#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Main STIG hardening entry point for Packer/GCP builds.
    Orchestrates all hardening scripts in the correct order.

.NOTES
    Script execution order matters:
    1. PowerSTIG + dependencies must be installed before DSC MOF creation
    2. DoD certs must be installed before DSC MOF (so DSC cert checks pass)
    3. DSC MOF must be created before it is applied
    4. account_policy.ps1 runs AFTER apply_mof.ps1 (DSC cannot undo secedit writes)
    5. stig_remediation_fixes.ps1 runs AFTER apply_mof.ps1 (same reason)
    6. audit.ps1 runs AFTER apply_mof.ps1 (V-278942 to V-278947)
    7. apply_remaining_fixes.ps1 runs AFTER apply_mof.ps1 (V-254251/258/261)
    8. install_nessus.ps1 runs AFTER all STIG fixes, BEFORE WinRM repair
    9. repair_winrm_for_packer.ps1 runs LAST (must not be undone by any STIG script)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Write-Host "========== START STIG HARDENING ==========" -ForegroundColor Cyan
Write-Host "  Start time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan

$scriptDir   = $PSScriptRoot
$globalFails = 0

# -----------------------------------------------------------------------
# Helper: Run a script step and abort pipeline on failure
# -----------------------------------------------------------------------
function Invoke-Step {
    param(
        [string]$ScriptPath,
        [string]$Label,
        [switch]$AllowFailure
    )

    Write-Host "`n--- $Label ---" -ForegroundColor Yellow
    Write-Host "    Script: $ScriptPath" -ForegroundColor Gray
    Write-Host "    Time:   $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray

    if (-not (Test-Path $ScriptPath)) {
        Write-Warning "Script not found, skipping: $ScriptPath"
        return
    }

    $global:LASTEXITCODE = 0
    $stepFailed = $false

    try {
        & $ScriptPath
        if ($global:LASTEXITCODE -ne 0) { $stepFailed = $true }
    } catch {
        Write-Warning "Unhandled exception in $Label : $_"
        $stepFailed = $true
        $global:LASTEXITCODE = 1
    }

    $exitCode = $global:LASTEXITCODE

    if ($stepFailed -and -not $AllowFailure) {
        Write-Error "$Label FAILED with exit code $exitCode -- aborting hardening pipeline"
        exit $exitCode
    } elseif ($stepFailed -and $AllowFailure) {
        Write-Warning "$Label completed with warnings (exit code: $exitCode) -- continuing"
        $script:globalFails++
    } else {
        Write-Host "    $Label completed OK" -ForegroundColor Green
    }
}

# -----------------------------------------------------------------------
# PRE-FLIGHT: Verify critical scripts are not truncated
# -----------------------------------------------------------------------
Write-Host "`n--- Pre-flight: Script integrity checks ---" -ForegroundColor Yellow

$integrityChecks = @(
    @{ Path = "$scriptDir\install_dod_certs.ps1";      MinLines = 50;  Label = "install_dod_certs.ps1"     }
    @{ Path = "$scriptDir\stig_remediation_fixes.ps1"; MinLines = 100; Label = "stig_remediation_fixes.ps1" }
    @{ Path = "$scriptDir\install_dsc_deps.ps1";       MinLines = 50;  Label = "install_dsc_deps.ps1"      }
    @{ Path = "$scriptDir\create_mof.ps1";             MinLines = 50;  Label = "create_mof.ps1"            }
    @{ Path = "$scriptDir\audit.ps1";                  MinLines = 30;  Label = "audit.ps1"                 }
    @{ Path = "$scriptDir\apply_remaining_fixes.ps1";  MinLines = 30;  Label = "apply_remaining_fixes.ps1" }
    @{ Path = "$scriptDir\install_nessus.ps1";         MinLines = 30;  Label = "install_nessus.ps1"        }
)

$integrityFail = $false

foreach ($check in $integrityChecks) {
    if (Test-Path $check.Path) {
        $lineCount = (Get-Content $check.Path).Count
        $hash      = (Get-FileHash $check.Path -Algorithm SHA256).Hash

        Write-Host "  $($check.Label): $lineCount lines | SHA256: $($hash.Substring(0,16))..." -ForegroundColor Gray

        if ($lineCount -lt $check.MinLines) {
            Write-Host "  [FAIL] $($check.Label) appears TRUNCATED ($lineCount lines, expected >= $($check.MinLines))" -ForegroundColor Red
            $integrityFail = $true
        } else {
            Write-Host "  [OK]  $($check.Label)" -ForegroundColor Green
        }
    } else {
        Write-Warning "  Script not found (will be caught later): $($check.Path)"
    }
}

if ($integrityFail) {
    Write-Error "One or more scripts appear truncated. Fix the Packer file provisioner and retry."
    exit 1
}

# -----------------------------------------------------------------------
# STEP 1 -- Install PowerSTIG and DSC dependencies
# -----------------------------------------------------------------------
Invoke-Step "$scriptDir\install_PowerSTIG.ps1"   "Install PowerSTIG"
Invoke-Step "$scriptDir\install_dsc_deps.ps1"    "Install DSC dependencies (removes CIM duplicates)"

# -----------------------------------------------------------------------
# STEP 2 -- Install DoD Certificates (V-254442, V-254443, V-254444)
# -----------------------------------------------------------------------
Invoke-Step "$scriptDir\install_dod_certs.ps1"   "Install DoD Certificates (V-254442/443/444)" -AllowFailure

# -----------------------------------------------------------------------
# STEP 3 -- Create and apply the DSC MOF
# -----------------------------------------------------------------------
Invoke-Step "$scriptDir\create_mof.ps1"          "Create DSC MOF"
Invoke-Step "$scriptDir\apply_mof.ps1"           "Apply DSC MOF"

# -----------------------------------------------------------------------
# STEP 4 -- Post-DSC targeted fixes (must all run AFTER apply_mof.ps1)
# -----------------------------------------------------------------------
Invoke-Step "$scriptDir\registry_stig.ps1"           "Registry STIG fixes"                             -AllowFailure
Invoke-Step "$scriptDir\services_stig.ps1"           "Services STIG fixes"                             -AllowFailure
Invoke-Step "$scriptDir\account_policy.ps1"          "Account Policy (net accounts + secedit)"
Invoke-Step "$scriptDir\audit.ps1"                   "Audit Subcategory Policy (V-278942 to V-278947)" -AllowFailure
Invoke-Step "$scriptDir\apply_remaining_fixes.ps1"   "Remaining STIG fixes (V-254251/258/261)"         -AllowFailure
Invoke-Step "$scriptDir\stig_remediation_fixes.ps1"  "Targeted STIG remediation"                       -AllowFailure

# -----------------------------------------------------------------------
# STEP 4b -- Install Nessus Agent (after all STIG fixes are final)
# Agent is installed unlinked. Client activates on first boot.
# -----------------------------------------------------------------------
Invoke-Step "$scriptDir\install_nessus.ps1"          "Install Nessus Agent (unlinked)"                 -AllowFailure

# -----------------------------------------------------------------------
# STEP 5 -- Repair WinRM for Packer (MUST be absolute last step)
# Removes GPO registry overrides written by STIG, then restores WinRM auth.
# -----------------------------------------------------------------------
Invoke-Step "$scriptDir\repair_winrm_for_packer.ps1" "Repair WinRM for Packer (LAST step)"

# -----------------------------------------------------------------------
# STEP 6 -- Final DSC compliance audit
# -----------------------------------------------------------------------
Write-Host "`n--- Final DSC Compliance Audit ---" -ForegroundColor Yellow

try {
    $results    = Test-DscConfiguration -Detailed -ErrorAction Stop
    $reportPath = Join-Path $scriptDir "DSC_Audit_Results.csv"

    $final = @()
    foreach ($r in $results.ResourcesInDesiredState) {
        $r | Add-Member -NotePropertyName Compliance -NotePropertyValue "PASS" -Force
        $final += $r
    }
    foreach ($r in $results.ResourcesNotInDesiredState) {
        $r | Add-Member -NotePropertyName Compliance -NotePropertyValue "FAIL" -Force
        $final += $r
    }
    $final | Export-Csv -Path $reportPath -NoTypeInformation

    $passCount = ($results.ResourcesInDesiredState    | Measure-Object).Count
    $failCount = ($results.ResourcesNotInDesiredState | Measure-Object).Count

    Write-Host "  DSC Compliance: $passCount PASS  /  $failCount FAIL" -ForegroundColor Cyan
    Write-Host "  Report saved:   $reportPath" -ForegroundColor Cyan

    if ($failCount -gt 0) {
        Write-Host "`n  DSC resources NOT in desired state:" -ForegroundColor Yellow
        $results.ResourcesNotInDesiredState | ForEach-Object {
            Write-Host "    FAIL: $($_.ResourceId)" -ForegroundColor Yellow
        }
        $globalFails += $failCount
    }
} catch {
    Write-Warning "DSC compliance audit failed: $_"
    Write-Warning "This is non-fatal -- the image will still be captured."
}

# -----------------------------------------------------------------------
# Final summary
# -----------------------------------------------------------------------
Write-Host "`n========== STIG HARDENING COMPLETE ==========" -ForegroundColor Cyan
Write-Host "  End time:        $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "  Pipeline issues: $globalFails" -ForegroundColor $(if ($globalFails -eq 0) { 'Green' } else { 'Yellow' })

if ($globalFails -gt 0) {
    Write-Host "  Review WARN messages above and the DSC audit CSV for details." -ForegroundColor Yellow
}

Write-Host "==========================================" -ForegroundColor Cyan
exit 0
