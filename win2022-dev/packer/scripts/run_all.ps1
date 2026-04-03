#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Main STIG hardening entry point for Packer/GCP builds.

.NOTES
    Script execution order:
    1.  install_PowerSTIG.ps1         — install PowerSTIG module
    2.  install_dsc_deps.ps1          — remove CIM duplicates
    3.  install_dod_certs.ps1         — DoD PKI certs (V-254442/443/444)
    4.  create_mof.ps1                — compile DSC MOF
    5.  apply_mof.ps1                 — apply DSC MOF (breaks WinRM via secedit)
    *** Packer reconnects here via separate provisioner block ***
    6.  restore_winrm_post_dsc.ps1    — rebuild HTTPS listener, restore auth
    7.  registry_stig.ps1             — registry fixes
    8.  services_stig.ps1             — services fixes (adds WinRM rules before firewall)
    9.  account_policy.ps1            — password/lockout policy
    10. audit.ps1                     — audit subcategory policy
    11. install_nessus.ps1            — Nessus agent (unlinked)
    12. apply_remaining_fixes.ps1     — V-254251/258/261
    13. stig_remediation_fixes.ps1    — targeted STIG remediation
    14. repair_winrm_for_packer.ps1   — final WinRM repair (LAST)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Write-Host "========== START STIG HARDENING ==========" -ForegroundColor Cyan
Write-Host "  Start time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan

$scriptDir   = $PSScriptRoot
$globalFails = 0

# -----------------------------------------------------------------------
# Helper: Run a script step
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
        Write-Error "$Label FAILED with exit code $exitCode -- aborting pipeline"
        exit $exitCode
    } elseif ($stepFailed -and $AllowFailure) {
        Write-Warning "$Label completed with warnings (exit code: $exitCode) -- continuing"
        $script:globalFails++
    } else {
        Write-Host "    $Label completed OK" -ForegroundColor Green
    }
}

# -----------------------------------------------------------------------
# PRE-FLIGHT: Script integrity checks
# -----------------------------------------------------------------------
Write-Host "`n--- Pre-flight: Script integrity checks ---" -ForegroundColor Yellow

$integrityChecks = @(
    @{ Path = "$scriptDir\install_dod_certs.ps1";         MinLines = 50;  Label = "install_dod_certs.ps1"         }
    @{ Path = "$scriptDir\stig_remediation_fixes.ps1";    MinLines = 100; Label = "stig_remediation_fixes.ps1"    }
    @{ Path = "$scriptDir\install_dsc_deps.ps1";          MinLines = 50;  Label = "install_dsc_deps.ps1"          }
    @{ Path = "$scriptDir\create_mof.ps1";                MinLines = 50;  Label = "create_mof.ps1"                }
    @{ Path = "$scriptDir\audit.ps1";                     MinLines = 30;  Label = "audit.ps1"                     }
    @{ Path = "$scriptDir\apply_remaining_fixes.ps1";     MinLines = 30;  Label = "apply_remaining_fixes.ps1"     }
    @{ Path = "$scriptDir\install_nessus.ps1";            MinLines = 30;  Label = "install_nessus.ps1"            }
    @{ Path = "$scriptDir\restore_winrm_post_dsc.ps1";    MinLines = 30;  Label = "restore_winrm_post_dsc.ps1"   }
)

$integrityFail = $false

foreach ($check in $integrityChecks) {
    if (Test-Path $check.Path) {
        $lineCount = (Get-Content $check.Path).Count
        $hash      = (Get-FileHash $check.Path -Algorithm SHA256).Hash

        Write-Host "  $($check.Label): $lineCount lines | SHA256: $($hash.Substring(0,16))..." -ForegroundColor Gray

        if ($lineCount -lt $check.MinLines) {
            Write-Host "  [FAIL] $($check.Label) TRUNCATED ($lineCount lines, expected >= $($check.MinLines))" -ForegroundColor Red
            $integrityFail = $true
        } else {
            Write-Host "  [OK]  $($check.Label)" -ForegroundColor Green
        }
    } else {
        Write-Warning "  Script not found: $($check.Path)"
    }
}

if ($integrityFail) {
    Write-Error "One or more scripts appear truncated."
    exit 1
}

# -----------------------------------------------------------------------
# STEP 1 -- Install PowerSTIG and DSC dependencies
# -----------------------------------------------------------------------
Invoke-Step "$scriptDir\install_PowerSTIG.ps1"        "Install PowerSTIG"
Invoke-Step "$scriptDir\install_dsc_deps.ps1"         "Install DSC dependencies"

# -----------------------------------------------------------------------
# STEP 2 -- Install DoD Certificates
# -----------------------------------------------------------------------
Invoke-Step "$scriptDir\install_dod_certs.ps1"        "Install DoD Certificates (V-254442/443/444)"   -AllowFailure

# -----------------------------------------------------------------------
# STEP 3 -- Create DSC MOF
# -----------------------------------------------------------------------
Invoke-Step "$scriptDir\create_mof.ps1"               "Create DSC MOF"

# -----------------------------------------------------------------------
# STEP 4 -- Apply DSC MOF
# NOTE: apply_mof.ps1 will break WinRM via secedit/AccountPolicy.
# Packer will lose the connection after this step exits.
# restore_winrm_post_dsc.ps1 runs in the NEXT Packer provisioner block.
# -----------------------------------------------------------------------
Invoke-Step "$scriptDir\apply_mof.ps1"                "Apply DSC MOF"

# -----------------------------------------------------------------------
# STEP 5 -- Restore WinRM after DSC (Packer reconnects before this runs)
# -----------------------------------------------------------------------
Invoke-Step "$scriptDir\restore_winrm_post_dsc.ps1"   "Restore WinRM after DSC"

# -----------------------------------------------------------------------
# STEP 6 -- Post-DSC targeted fixes
# -----------------------------------------------------------------------
Invoke-Step "$scriptDir\registry_stig.ps1"            "Registry STIG fixes"                           -AllowFailure
Invoke-Step "$scriptDir\services_stig.ps1"            "Services STIG fixes"                           -AllowFailure
Invoke-Step "$scriptDir\account_policy.ps1"           "Account Policy (net accounts + secedit)"
Invoke-Step "$scriptDir\audit.ps1"                    "Audit Subcategory Policy (V-278942 to V-278947)"-AllowFailure
Invoke-Step "$scriptDir\apply_remaining_fixes.ps1"    "Remaining STIG fixes (V-254251/258/261)"        -AllowFailure
Invoke-Step "$scriptDir\stig_remediation_fixes.ps1"   "Targeted STIG remediation"                     -AllowFailure

# -----------------------------------------------------------------------
# STEP 7 -- Install Nessus Agent (unlinked)
# -----------------------------------------------------------------------
Invoke-Step "$scriptDir\install_nessus.ps1"           "Install Nessus Agent (unlinked)"               -AllowFailure

# -----------------------------------------------------------------------
# STEP 8 -- Final WinRM repair (MUST be last)
# -----------------------------------------------------------------------
Invoke-Step "$scriptDir\repair_winrm_for_packer.ps1"  "Repair WinRM for Packer (LAST step)"

# -----------------------------------------------------------------------
# STEP 9 -- Final DSC compliance audit
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
        $results.ResourcesNotInDesiredState | ForEach-Object {
            Write-Host "    FAIL: $($_.ResourceId)" -ForegroundColor Yellow
        }
        $globalFails += $failCount
    }
} catch {
    Write-Warning "DSC compliance audit failed: $_"
    Write-Warning "Non-fatal — image will still be captured."
}

# -----------------------------------------------------------------------
# Final summary
# -----------------------------------------------------------------------
Write-Host "`n========== STIG HARDENING COMPLETE ==========" -ForegroundColor Cyan
Write-Host "  End time:        $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "  Pipeline issues: $globalFails" -ForegroundColor $(if ($globalFails -eq 0) { 'Green' } else { 'Yellow' })

if ($globalFails -gt 0) {
    Write-Host "  Review WARN messages above and DSC audit CSV for details." -ForegroundColor Yellow
}

Write-Host "==========================================" -ForegroundColor Cyan
exit 0
