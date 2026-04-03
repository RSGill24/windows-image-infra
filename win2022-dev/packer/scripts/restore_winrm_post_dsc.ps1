#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Restores WinRM HTTPS immediately after DSC/secedit breaks it.
    Called by run_all.ps1 right after apply_mof.ps1 exits.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

function Write-Section ($msg) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " $msg" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}
function Write-OK    ($msg) { Write-Host "  [OK]    $msg" -ForegroundColor Green  }
function Write-Fixed ($msg) { Write-Host "  [FIX]   $msg" -ForegroundColor Yellow }
function Write-Info  ($msg) { Write-Host "  [INFO]  $msg" -ForegroundColor Gray   }

Write-Host "=== Restoring WinRM HTTPS after DSC/secedit ===" -ForegroundColor Cyan

# -----------------------------------------------------------------------
# 1. Remove GPO policy overrides written by secedit
# -----------------------------------------------------------------------
Write-Section "Remove GPO WinRM policy overrides"

foreach ($path in @(
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service",
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client"
)) {
    if (Test-Path $path) {
        foreach ($key in @("AllowBasic","AllowUnencrypted","DisableRunAs","AllowCredSSP","AllowKerberos","AllowNegotiate")) {
            Remove-ItemProperty -Path $path -Name $key -ErrorAction SilentlyContinue
        }
        Write-Fixed "Removed GPO overrides: $path"
    } else {
        Write-Info "Not present (OK): $path"
    }
}

# -----------------------------------------------------------------------
# 2. Restore WSMan auth settings 
#    (Listener rebuild removed to prevent dropping active session)
# -----------------------------------------------------------------------
Write-Section "Restore WSMan auth settings"

foreach ($s in @(
    @{ Path = "WSMan:\localhost\Service\Auth\Basic";       Value = $true    },
    @{ Path = "WSMan:\localhost\Service\Auth\Negotiate";   Value = $true    },
    @{ Path = "WSMan:\localhost\Service\Auth\Certificate"; Value = $true    },
    @{ Path = "WSMan:\localhost\Service\AllowUnencrypted"; Value = $false   },
    @{ Path = "WSMan:\localhost\Client\Auth\Basic";        Value = $true    },
    @{ Path = "WSMan:\localhost\Client\AllowUnencrypted";  Value = $false   },
    @{ Path = "WSMan:\localhost\MaxTimeoutms";             Value = 1800000  }
)) {
    try {
        Set-Item -Path $s.Path -Value $s.Value -Force
        Write-Fixed "$($s.Path) = $($s.Value)"
    } catch {
        Write-Info "$($s.Path) (non-fatal): $_"
    }
}

# -----------------------------------------------------------------------
# 3. Ensure WinRM firewall rules exist
# -----------------------------------------------------------------------
Write-Section "Ensure WinRM firewall rules"

foreach ($rule in @(
    @{ Name = "WinRM-HTTPS"; Port = 5986 },
    @{ Name = "WinRM-HTTP";  Port = 5985 }
)) {
    Remove-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
    New-NetFirewallRule `
        -DisplayName $rule.Name `
        -Direction   Inbound `
        -Action      Allow `
        -Protocol    TCP `
        -LocalPort   $rule.Port `
        -Profile     Any `
        -ErrorAction SilentlyContinue | Out-Null
    Write-Fixed "Firewall rule: $($rule.Name) port $($rule.Port)"
}

# -----------------------------------------------------------------------
# 4. Protect packer_user from STIG password expiry
# -----------------------------------------------------------------------
Write-Section "Protect packer_user account"

foreach ($acct in @('packer_user', 'packer', 'WinRMUser')) {
    $user = Get-LocalUser -Name $acct -ErrorAction SilentlyContinue
    if (-not $user) { continue }
    try {
        $adsiUser = [ADSI]"WinNT://./$acct,user"
        $adsiUser.UserFlags.Value = $adsiUser.UserFlags.Value -bor 65536
        $adsiUser.SetInfo()
        Write-Fixed "Password expiry disabled: $acct"
    } catch {
        Write-Info "Could not update $acct: $_"
    }
}

# -----------------------------------------------------------------------
# 5. Verify port 5986 (Restart-Service removed to preserve connection)
# -----------------------------------------------------------------------
Write-Section "Verify WinRM Port"

$port = netstat -an | Select-String ":5986"
if ($port) {
    Write-OK "Port 5986 listening — WinRM HTTPS restored" -ForegroundColor Green
} else {
    Write-Warning "Port 5986 not detected"
}

Write-Host "`n=== WinRM restore complete ===" -ForegroundColor Green
exit 0
