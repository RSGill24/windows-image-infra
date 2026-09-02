#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies STIG-required account and password policies.
    Uses BOTH net accounts AND secedit to ensure policies survive
    the DSC SCE (Security Configuration Engine) database lock issue
    that occurs during Packer image builds on GCP.

    FIX: Verification regex rewritten to match actual net accounts output
         which uses variable whitespace and different label wording.
         Previously all checks reported "Could not parse" even when values
         were correctly applied.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

function Write-Section ($msg) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " $msg" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}
function Write-OK    ($msg) { Write-Host "  [OK]    $msg" -ForegroundColor Green   }
function Write-Fixed ($msg) { Write-Host "  [FIX]   $msg" -ForegroundColor Yellow  }
function Write-Warn  ($msg) { Write-Host "  [WARN]  $msg" -ForegroundColor Magenta }

$ErrorCount = 0

# -----------------------------------------------------------------------
# PASS 1: net accounts
# -----------------------------------------------------------------------
Write-Section "Pass 1: Account Policy via net accounts"

$netCmds = @(
    @{ Args = '/minpwlen:15';        Label = 'MinimumPasswordLength = 15'         },
    @{ Args = '/maxpwage:60';        Label = 'MaximumPasswordAge = 60 days'       },
    @{ Args = '/minpwage:1';         Label = 'MinimumPasswordAge = 1 day'         },
    @{ Args = '/uniquepw:24';        Label = 'PasswordHistory = 24'               },
    @{ Args = '/lockoutthreshold:3'; Label = 'LockoutThreshold = 3'              },
    @{ Args = '/lockoutduration:15'; Label = 'LockoutDuration = 15 min'          },
    @{ Args = '/lockoutwindow:15';   Label = 'LockoutObservationWindow = 15 min'  }
)

foreach ($cmd in $netCmds) {
    try {
        $output = net accounts $cmd.Args 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Fixed "$($cmd.Label)"
        } else {
            Write-Warn "net accounts $($cmd.Args) returned exit code $LASTEXITCODE"
            Write-Warn "  Output: $output"
        }
    } catch {
        Write-Warn "Exception running net accounts $($cmd.Args): $_"
        $ErrorCount++
    }
}

# -----------------------------------------------------------------------
# PASS 2: secedit — reliable fallback that bypasses the SCE lock
# -----------------------------------------------------------------------
Write-Section "Pass 2: Account Policy via secedit (SCE lock bypass)"

$seceditCfg = "$env:TEMP\stig_acct_policy.cfg"
$seceditDb  = "$env:TEMP\stig_acct_policy.sdb"

Remove-Item $seceditCfg -ErrorAction SilentlyContinue
Remove-Item $seceditDb  -ErrorAction SilentlyContinue

try {
    Write-Host "  Exporting current security policy..."
    secedit /export /areas SECURITYPOLICY /cfg $seceditCfg /quiet

    if (-not (Test-Path $seceditCfg)) {
        Write-Warn "secedit export failed — cannot apply account policy via secedit"
        $ErrorCount++
    } else {
        Write-OK "Policy exported to: $seceditCfg"

        $cfg = Get-Content $seceditCfg -Raw

        $cfg = $cfg -replace 'MinimumPasswordLength\s*=\s*\d+',  'MinimumPasswordLength = 15'
        $cfg = $cfg -replace 'MaximumPasswordAge\s*=\s*\d+',     'MaximumPasswordAge = 60'
        $cfg = $cfg -replace 'MinimumPasswordAge\s*=\s*\d+',     'MinimumPasswordAge = 1'
        $cfg = $cfg -replace 'PasswordHistorySize\s*=\s*\d+',    'PasswordHistorySize = 24'
        $cfg = $cfg -replace 'PasswordComplexity\s*=\s*\d+',     'PasswordComplexity = 1'
        $cfg = $cfg -replace 'LockoutBadCount\s*=\s*\d+',        'LockoutBadCount = 3'
        $cfg = $cfg -replace 'ResetLockoutCount\s*=\s*\d+',      'ResetLockoutCount = 15'
        $cfg = $cfg -replace 'LockoutDuration\s*=\s*-?\d+',      'LockoutDuration = 15'

        $cfg | Set-Content $seceditCfg -Encoding Unicode

        Write-Host "  Applying patched policy via secedit..."
        secedit /configure /db $seceditDb /cfg $seceditCfg /areas SECURITYPOLICY /quiet

        if ($LASTEXITCODE -eq 0) {
            Write-OK "secedit /configure succeeded"
        } else {
            Write-Warn "secedit /configure returned exit code $LASTEXITCODE"
            Write-Warn "Check: $env:windir\security\logs\scesrv.log for details"
            $ErrorCount++
        }
    }
} catch {
    Write-Warn "Exception in secedit process: $_"
    $ErrorCount++
} finally {
    Remove-Item $seceditCfg -ErrorAction SilentlyContinue
    Remove-Item $seceditDb  -ErrorAction SilentlyContinue
}

# -----------------------------------------------------------------------
# PASS 3: Verification
# FIX: net accounts output format is:
#   "Minimum password length:                              15"
# Regex must use \s+ between label and value, and label text must
# match exactly what net accounts prints (including trailing colon).
# -----------------------------------------------------------------------
Write-Section "Pass 3: Verification"

try {
    # Capture as a single string array — one element per line
    $netOut = (net accounts 2>&1) -join "`n"

    Write-Host "  net accounts output:" -ForegroundColor Gray
    $netOut -split "`n" | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }

    # Each entry: Pattern to match, expected operator, expected value, label
    $checks = @(
        @{ Pattern = 'Minimum password length:\s+(\d+)';           Op = 'ge'; Expected = 15; Label = 'MinimumPasswordLength >= 15' },
        @{ Pattern = 'Maximum password age \(days\):\s+(\d+)';     Op = 'le'; Expected = 60; Label = 'MaximumPasswordAge <= 60'    },
        @{ Pattern = 'Minimum password age \(days\):\s+(\d+)';     Op = 'ge'; Expected = 1;  Label = 'MinimumPasswordAge >= 1'     },
        @{ Pattern = 'Lockout threshold:\s+(\d+)';                 Op = 'le'; Expected = 3;  Label = 'LockoutThreshold <= 3'       },
        @{ Pattern = 'Lockout duration \(minutes\):\s+(\d+)';      Op = 'ge'; Expected = 15; Label = 'LockoutDuration >= 15'       },
        @{ Pattern = 'Lockout observation window \(minutes\):\s+(\d+)'; Op = 'ge'; Expected = 15; Label = 'LockoutObsWindow >= 15' }
    )

    foreach ($check in $checks) {
        if ($netOut -match $check.Pattern) {
            $val = [int]$Matches[1]
            $pass = switch ($check.Op) {
                'ge' { $val -ge $check.Expected }
                'le' { $val -le $check.Expected }
            }
            if ($pass) {
                Write-OK "$($check.Label) (value: $val)"
            } else {
                Write-Warn "FAIL: $($check.Label) (value: $val, expected $($check.Op) $($check.Expected))"
                $ErrorCount++
            }
        } else {
            Write-Warn "Could not parse: $($check.Label)"
        }
    }
} catch {
    Write-Warn "Exception during verification: $_"
    $ErrorCount++
}

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
Write-Section "Account Policy Summary"

if ($ErrorCount -eq 0) {
    Write-Host "  All account policies applied and verified." -ForegroundColor Green
} else {
    Write-Host "  $ErrorCount policy issue(s) need attention." -ForegroundColor Yellow
}

# -----------------------------------------------------------------------
# SecurityOption rules skipped from DSC MOF (V-254445, V-254465)
# These were removed from DSC to prevent SCE database writes breaking
# WinRM. Applied here via registry after all uploads are complete.
# -----------------------------------------------------------------------

# V-254445 / V-278225: Network security — LAN Manager authentication level
# Must be: Send NTLMv2 response only, refuse LM and NTLM (value 5)
Write-Section "V-278225: LAN Manager authentication level"
try {
    Set-ItemProperty `
        -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
        -Name "LmCompatibilityLevel" -Value 5 -Type DWord -Force
    $val = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa").LmCompatibilityLevel
    if ($val -eq 5) {
        Write-OK "LmCompatibilityLevel = 5 (NTLMv2 only, refuse LM+NTLM)"
    } else {
        Write-Warn "LmCompatibilityLevel = $val (expected 5)"
        $ErrorCount++
    }
} catch {
    Write-Warn "Failed to set LmCompatibilityLevel: $_"
    $ErrorCount++
}

# V-254465: Network security — LDAP client signing requirements
# Must be: Negotiate signing (value 1)
Write-Section "V-254465: LDAP client signing requirements"
try {
    $ldapPath = "HKLM:\SYSTEM\CurrentControlSet\Services\ldap"
    if (!(Test-Path $ldapPath)) {
        New-Item -Path $ldapPath -Force | Out-Null
    }
    Set-ItemProperty `
        -Path $ldapPath `
        -Name "LDAPClientIntegrity" -Value 1 -Type DWord -Force
    $val = (Get-ItemProperty $ldapPath).LDAPClientIntegrity
    if ($val -eq 1) {
        Write-OK "LDAPClientIntegrity = 1 (Negotiate signing)"
    } else {
        Write-Warn "LDAPClientIntegrity = $val (expected 1)"
        $ErrorCount++
    }
} catch {
    Write-Warn "Failed to set LDAPClientIntegrity: $_"
    $ErrorCount++
}

exit $ErrorCount
