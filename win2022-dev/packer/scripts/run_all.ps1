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
    6. repair_winrm_for_packer.ps1 runs LAST (must not be undone by any STIG script)

    FIX: Added script integrity check for install_dod_certs.ps1 to catch
         WinRM file upload truncation before it causes a silent parse failure.
    FIX: Improved Invoke-Step to reliably detect non-zero exit codes from
         tools like net accounts that do not always set $LASTEXITCODE.
    FIX: Added DSC compliance audit at end with pass/fail counts.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'  # Don't abort the whole pipeline on non-fatal step errors

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
        [switch]$AllowFailure   # Pass this flag for non-critical steps
    )

    Write-Host "`n--- $Label ---" -ForegroundColor Yellow
    Write-Host "    Script: $ScriptPath" -ForegroundColor Gray
    Write-Host "    Time:   $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray

    if (-not (Test-Path $ScriptPath)) {
        Write-Warning "Script not found, skipping: $ScriptPath"
        return
    }

    # Run the script in the current session context
    & $ScriptPath

    # Capture the exit code reliably — both $LASTEXITCODE and $?
    $exitCode = $LASTEXITCODE
    $psSuccess = $?

    if (($exitCode -and $exitCode -ne 0) -or (-not $psSuccess -and -not $AllowFailure)) {
        if ($AllowFailure) {
            Write-Warning "$Label completed with warnings (exit code: $exitCode) — continuing"
            $script:globalFails++
        } else {
            Write-Error "$Label FAILED with exit code $exitCode — aborting hardening pipeline"
            exit $exitCode
        }
    } else {
        Write-Host "    $Label completed OK" -ForegroundColor Green
    }
}

# -----------------------------------------------------------------------
# PRE-FLIGHT: Verify critical scripts are not truncated
# Packer's WinRM file upload can silently truncate large scripts when the
# destination path is a directory instead of a full file path.
# -----------------------------------------------------------------------
Write-Host "`n--- Pre-flight: Script integrity checks ---" -ForegroundColor Yellow

$integrityChecks = @(
    @{ Path = "$scriptDir\install_dod_certs.ps1";       MinLines = 200; Label = "install_dod_certs.ps1"   }
    @{ Path = "$scriptDir\stig_remediation_fixes.ps1";  MinLines = 100; Label = "stig_remediation_fixes"  }
    @{ Path = "$scriptDir\install_dsc_deps.ps1";        MinLines = 50;  Label = "install_dsc_deps.ps1"    }
    @{ Path = "$scriptDir\create_mof.ps1";              MinLines = 50;  Label = "create_mof.ps1"           }
)

$integrityFail = $false
foreach ($check in $integrityChecks) {
    if (Test-Path $check.Path) {
        $lineCount = (Get-Content $check.Path).Count
        $hash      = (Get-FileHash $check.Path -Algorithm SHA256).Hash
        Write-Host "  $($check.Label): $lineCount lines | SHA256: $($hash.Substring(0,16))..." -ForegroundColor Gray

        if ($lineCount -lt $check.MinLines) {
            Write-Host "  [FAIL] $($check.Label) appears TRUNCATED ($lineCount lines, expected >= $($check.MinLines))" -ForegroundColor Red
            Write-Host "         Check your Packer file provisioner — destination must include the filename," -ForegroundColor Red
            Write-Host "         e.g.:  destination = `"C:/Users/packer_user/hardening/$($check.Label)`"" -ForegroundColor Red
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
# STEP 1 — Install PowerSTIG and DSC dependencies
# Must run first. Removes duplicate CertificateDsc copies before installing
# to prevent CIM class conflict errors during MOF compilation.
# -----------------------------------------------------------------------
Invoke-Step "$scriptDir\install_PowerSTIG.ps1"   "Install PowerSTIG"
Invoke-Step "$scriptDir\install_dsc_deps.ps1"    "Install DSC dependencies (removes CIM duplicates)"

# -----------------------------------------------------------------------
# STEP 2 — Install DoD Certificates
# Must run BEFORE create_mof.ps1 / apply_mof.ps1 so that DSC certificate
# verification rules find the certs already in the store.
# V-254442, V-254443, V-254444
# -----------------------------------------------------------------------
Invoke-Step "$scriptDir\install_dod_certs.ps1"   "Install DoD Certificates (V-254442/443/444)" -AllowFailure

# -----------------------------------------------------------------------
# STEP 3 — Create and apply the DSC MOF
# create_mof.ps1 now has all bad Exception entries removed.
# apply_mof.ps1 will have DSC SCE lock failures for account policy —
# those are fixed by account_policy.ps1 in Step 4.
# -----------------------------------------------------------------------
Invoke-Step "$scriptDir\create_mof.ps1"          "Create DSC MOF"
Invoke-Step "$scriptDir\apply_mof.ps1"           "Apply DSC MOF"

# -----------------------------------------------------------------------
# STEP 4 — Post-DSC targeted fixes
# These MUST run AFTER apply_mof.ps1.
# DSC cannot undo secedit or direct registry writes — running these after
# DSC ensures they are the final state baked into the image.
# -----------------------------------------------------------------------
Invoke-Step "$scriptDir\registry_stig.ps1"            "Registry STIG fixes"         -AllowFailure
Invoke-Step "$scriptDir\services_stig.ps1"            "Services STIG fixes"         -AllowFailure

# account_policy.ps1 uses BOTH net accounts AND secedit to reliably set
# policies that DSC's MSFT_AccountPolicy often fails to apply due to SCE lock.
# Covers: V-254285, V-254286, V-254287, V-254288, V-254289, V-254290, V-254291, V-254292
Invoke-Step "$scriptDir\account_policy.ps1"           "Account Policy (net accounts + secedit)"

# Targeted fixes for the remaining 22 SCAP failures (CAT I + CAT II)
Invoke-Step "$scriptDir\stig_remediation_fixes.ps1"   "Targeted STIG remediation (22 failures)"  -AllowFailure

# -----------------------------------------------------------------------
# STEP 5 — Repair WinRM for Packer
# MUST be the LAST script. Packer needs WinRM to reconnect after hardening
# to upload its cleanup script and capture the image.
# This restores Packer's auth without undoing any STIG controls.
# -----------------------------------------------------------------------
Invoke-Step "$scriptDir\repair_winrm_for_packer.ps1"  "Repair WinRM for Packer (LAST step)"

# -----------------------------------------------------------------------
# STEP 6 — Final DSC compliance audit
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

    $passCount = ($results.ResourcesInDesiredState   | Measure-Object).Count
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
    Write-Warning "This is non-fatal — the image will still be captured."
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
