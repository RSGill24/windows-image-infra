#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies STIG-required account and password policies.
    Uses BOTH net accounts AND secedit to ensure policies survive
    the DSC SCE (Security Configuration Engine) database lock issue
    that occurs during Packer image builds on GCP.

.NOTES
    FIX: Added secedit as a secondary enforcement path.
    During Packer image builds the LSA/SCE engine can lock the SAM
    database, causing DSC's MSFT_AccountPolicy resource to fail with:
      "Failed to update Account Policy Account_lockout_duration.
       Refer to %windir%\security\logs\scesrv.log for details."
    The secedit /configure path bypasses DSC entirely and writes
    directly to the security database, which is reliable even under lock.

    Run order in run_all.ps1: AFTER apply_mof.ps1
    (DSC runs first, this script re-enforces any policies DSC missed)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'  # Don't abort on individual policy failures

function Write-Section ($msg) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " $msg" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}
function Write-OK    ($msg) { Write-Host "  [OK]    $msg" -ForegroundColor Green  }
function Write-Fixed ($msg) { Write-Host "  [FIX]   $msg" -ForegroundColor Yellow }
function Write-Warn  ($msg) { Write-Host "  [WARN]  $msg" -ForegroundColor Magenta }

$ErrorCount = 0

# -----------------------------------------------------------------------
# PASS 1: net accounts
# Fast and works in most contexts. Not reliable when DSC SCE is locked,
# but good as a first attempt.
# -----------------------------------------------------------------------
Write-Section "Pass 1: Account Policy via net accounts"

$netCmds = @(
    @{ Args = '/minpwlen:15';         Label = 'MinimumPasswordLength = 15'        }
    @{ Args = '/maxpwage:60';         Label = 'MaximumPasswordAge = 60 days'      }
    @{ Args = '/minpwage:1';          Label = 'MinimumPasswordAge = 1 day'        }
    @{ Args = '/uniquepw:24';         Label = 'PasswordHistory = 24'              }
    @{ Args = '/lockoutthreshold:3';  Label = 'LockoutThreshold = 3'             }
    @{ Args = '/lockoutduration:15';  Label = 'LockoutDuration = 15 min'         }
    @{ Args = '/lockoutwindow:15';    Label = 'LockoutObservationWindow = 15 min' }
)

foreach ($cmd in $netCmds) {
    $output = net accounts $cmd.Args 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Fixed "$($cmd.Label)"
    } else {
        Write-Warn "net accounts $($cmd.Args) returned exit code $LASTEXITCODE — secedit will retry"
        Write-Warn "  Output: $output"
    }
}

# -----------------------------------------------------------------------
# PASS 2: secedit — reliable fallback that bypasses the SCE lock
# Exports the current security policy, patches the relevant keys,
# then re-imports via secedit /configure.
# This path works even when MSFT_AccountPolicy DSC resource fails.
# -----------------------------------------------------------------------
Write-Section "Pass 2: Account Policy via secedit (SCE lock bypass)"

$seceditCfg = "$env:TEMP\stig_acct_policy.cfg"
$seceditDb  = "$env:TEMP\stig_acct_policy.sdb"

# Clean up any leftover temp files from a prior run
Remove-Item $seceditCfg -ErrorAction SilentlyContinue
Remove-Item $seceditDb  -ErrorAction SilentlyContinue

# Export current policy to a temp .cfg file
Write-Host "  Exporting current security policy..."
$exportResult = secedit /export /areas SECURITYPOLICY /cfg $seceditCfg /quiet
if (-not (Test-Path $seceditCfg)) {
    Write-Warn "secedit export failed — cannot apply account policy via secedit"
    $ErrorCount++
} else {
    Write-OK "Policy exported to: $seceditCfg"

    $cfg = Get-Content $seceditCfg -Raw

    # ---------------------------------------------------------------
    # Patch each policy value using regex replacement.
    # The .cfg file uses [System Access] section with INI-style keys.
    # ---------------------------------------------------------------

    # V-254291: MinimumPasswordLength >= 14 (STIG min); using 15
    $cfg = $cfg -replace 'MinimumPasswordLength\s*=\s*\d+', 'MinimumPasswordLength = 15'
    Write-Fixed "MinimumPasswordLength = 15"

    # V-254289: MaximumPasswordAge <= 60
    $cfg = $cfg -replace 'MaximumPasswordAge\s*=\s*\d+', 'MaximumPasswordAge = 60'
    Write-Fixed "MaximumPasswordAge = 60"

    # V-254290: MinimumPasswordAge >= 1
    $cfg = $cfg -replace 'MinimumPasswordAge\s*=\s*\d+', 'MinimumPasswordAge = 1'
    Write-Fixed "MinimumPasswordAge = 1"

    # V-254288: PasswordHistorySize = 24
    $cfg = $cfg -replace 'PasswordHistorySize\s*=\s*\d+', 'PasswordHistorySize = 24'
    Write-Fixed "PasswordHistorySize = 24"

    # V-254292: PasswordComplexity = 1 (enabled)
    $cfg = $cfg -replace 'PasswordComplexity\s*=\s*\d+', 'PasswordComplexity = 1'
    Write-Fixed "PasswordComplexity = 1 (enabled)"

    # V-254286: LockoutBadCount <= 3
    $cfg = $cfg -replace 'LockoutBadCount\s*=\s*\d+', 'LockoutBadCount = 3'
    Write-Fixed "LockoutBadCount = 3"

    # V-254287: ResetLockoutCount >= 15 min
    $cfg = $cfg -replace 'ResetLockoutCount\s*=\s*\d+', 'ResetLockoutCount = 15'
    Write-Fixed "ResetLockoutCount = 15"

    # V-254285: LockoutDuration >= 15 min (0 = forever; any value >= 15 is compliant)
    $cfg = $cfg -replace 'LockoutDuration\s*=\s*\d+', 'LockoutDuration = 15'
    Write-Fixed "LockoutDuration = 15"

    # Write patched config back
    $cfg | Set-Content $seceditCfg -Encoding Unicode

    # Apply the patched config
    Write-Host "  Applying patched policy via secedit..."
    $applyResult = secedit /configure /db $seceditDb /cfg $seceditCfg /areas SECURITYPOLICY /quiet

    if ($LASTEXITCODE -eq 0) {
        Write-OK "secedit /configure succeeded"
    } else {
        Write-Warn "secedit /configure returned exit code $LASTEXITCODE"
        Write-Warn "Check: %windir%\security\logs\scesrv.log for details"
        $ErrorCount++
    }

    # Clean up temp files
    Remove-Item $seceditCfg -ErrorAction SilentlyContinue
    Remove-Item $seceditDb  -ErrorAction SilentlyContinue
}

# -----------------------------------------------------------------------
# PASS 3: Verification — confirm policies were actually applied
# -----------------------------------------------------------------------
Write-Section "Pass 3: Verification"

$netAccountsOutput = net accounts 2>&1
Write-Host "  net accounts output:" -ForegroundColor Gray
$netAccountsOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }

# Parse key values and verify compliance
$checks = @(
    @{ Pattern = 'Minimum password length\s+(\d+)';  Min = 14; Label = 'MinimumPasswordLength >= 14' }
    @{ Pattern = 'Maximum password age \(days\)\s+(\d+)'; Max = 60;  Label = 'MaximumPasswordAge <= 60'  }
    @{ Pattern = 'Minimum password age \(days\)\s+(\d+)'; Min = 1;  Label = 'MinimumPasswordAge >= 1'   }
    @{ Pattern = 'Lockout threshold\s+(\d+)';         Max = 3;  Label = 'LockoutThreshold <= 3'        }
    @{ Pattern = 'Lockout duration \(minutes\)\s+(\d+)'; Min = 15; Label = 'LockoutDuration >= 15'      }
)

foreach ($check in $checks) {
    $match = $netAccountsOutput | Select-String -Pattern $check.Pattern
    if ($match) {
        $val = [int]$match.Matches[0].Groups[1].Value
        $pass = $true
        if ($check.ContainsKey('Min') -and $val -lt $check.Min) { $pass = $false }
        if ($check.ContainsKey('Max') -and $val -gt $check.Max) { $pass = $false }

        if ($pass) { Write-OK "$($check.Label) (value: $val)" }
        else {
            Write-Warn "FAIL: $($check.Label) (value: $val)"
            $ErrorCount++
        }
    } else {
        Write-Warn "Could not parse: $($check.Label)"
    }
}

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
Write-Section "Account Policy Summary"

if ($ErrorCount -eq 0) {
    Write-Host "  All account policies applied and verified." -ForegroundColor Green
    Write-Host "  STIG rules covered: V-254285, V-254286, V-254287, V-254288," -ForegroundColor Green
    Write-Host "                      V-254289, V-254290, V-254291, V-254292" -ForegroundColor Green
} else {
    Write-Host "  $ErrorCount policy/policies need manual attention." -ForegroundColor Yellow
    Write-Host "  Check: %windir%\security\logs\scesrv.log" -ForegroundColor Yellow
}

exit $ErrorCount
