#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Write-Host "========== START STIG HARDENING ==========" -ForegroundColor Cyan
Write-Host "  Start time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan

$scriptDir   = $PSScriptRoot
$globalFails = 0

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
# PRE-FLIGHT
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
            Write-Host "  [FAIL] $($check.Label) TRUNCATED ($lineCount lines)" -ForegroundColor Red
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
Invoke-Step "$scriptDir\install_nessus.ps1"           "Install Nessus Agent (unlinked)" -AllowFailure
# -----------------------------------------------------------------------
# STEP 2 -- Install DoD Certificates
# -----------------------------------------------------------------------
Invoke-Step "$scriptDir\install_dod_certs.ps1"        "Install DoD Certificates"        -AllowFailure

# -----------------------------------------------------------------------
# STEP 3 -- Create and apply DSC MOF
# -----------------------------------------------------------------------
Invoke-Step "$scriptDir\create_mof.ps1"               "Create DSC MOF"
Invoke-Step "$scriptDir\apply_mof.ps1"                "Apply DSC MOF"

# -----------------------------------------------------------------------
# STEP 4 -- Post-DSC fixes
# -----------------------------------------------------------------------
Invoke-Step "$scriptDir\registry_stig.ps1"            "Registry STIG fixes"             -AllowFailure
Invoke-Step "$scriptDir\services_stig.ps1"            "Services STIG fixes"             -AllowFailure
Invoke-Step "$scriptDir\account_policy.ps1"           "Account Policy"
Invoke-Step "$scriptDir\audit.ps1"                    "Audit Subcategory Policy"         -AllowFailure
Invoke-Step "$scriptDir\apply_remaining_fixes.ps1"    "Remaining STIG fixes"            -AllowFailure
Invoke-Step "$scriptDir\stig_remediation_fixes.ps1"   "Targeted STIG remediation"       -AllowFailure

# # -----------------------------------------------------------------------
# # STEP 5 -- Install Nessus Agent
# # -----------------------------------------------------------------------


# # -----------------------------------------------------------------------
# # STEP 6 -- Final WinRM repair
# # -----------------------------------------------------------------------
# Invoke-Step "$scriptDir\repair_winrm_for_packer.ps1"  "Repair WinRM for Packer (LAST)"

# -----------------------------------------------------------------------
# STEP 7 -- DSC compliance audit
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
    if ($failCount -gt 0) {
        $results.ResourcesNotInDesiredState | ForEach-Object {
            Write-Host "    FAIL: $($_.ResourceId)" -ForegroundColor Yellow
        }
        $globalFails += $failCount
    }
} catch {
    Write-Warning "DSC compliance audit failed: $_"
}

Write-Host "`n========== STIG HARDENING COMPLETE ==========" -ForegroundColor Cyan
Write-Host "  End time:        $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "  Pipeline issues: $globalFails" -ForegroundColor $(if ($globalFails -eq 0) { 'Green' } else { 'Yellow' })
Write-Host "==========================================" -ForegroundColor Cyan
exit 0
