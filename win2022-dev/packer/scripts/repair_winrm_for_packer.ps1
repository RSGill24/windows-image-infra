#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Repairs WinRM connectivity after STIG hardening for Packer GCP builds.
    Must be the LAST script Packer runs before image capture.
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

# -----------------------------------------------------------------------
# 1. Remove GPO registry overrides FIRST
# -----------------------------------------------------------------------
Write-Section "Remove GPO WinRM policy registry overrides"

$policyServicePath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service"
$policyClientPath  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client"

$serviceKeys = @("AllowBasic", "AllowUnencrypted", "DisableRunAs", "AllowCredSSP", "AllowKerberos", "AllowNegotiate")
$clientKeys  = @("AllowBasic", "AllowUnencrypted", "AllowCredSSP", "AllowKerberos", "AllowNegotiate")

if (Test-Path $policyServicePath) {
    foreach ($key in $serviceKeys) {
        Remove-ItemProperty -Path $policyServicePath -Name $key -ErrorAction SilentlyContinue
        Write-Fixed "Removed GPO policy key: WinRM\Service\$key"
    }
} else {
    Write-Info "No GPO WinRM\Service policy path found — skipping"
}

if (Test-Path $policyClientPath) {
    foreach ($key in $clientKeys) {
        Remove-ItemProperty -Path $policyClientPath -Name $key -ErrorAction SilentlyContinue
        Write-Fixed "Removed GPO policy key: WinRM\Client\$key"
    }
} else {
    Write-Info "No GPO WinRM\Client policy path found — skipping"
}

# -----------------------------------------------------------------------
# 2. Restore WinRM auth via WSMan provider
# -----------------------------------------------------------------------
Write-Section "Restore WinRM authentication settings"

try { Set-Item -Path "WSMan:\localhost\Service\Auth\Basic"      -Value $true -Force; Write-Fixed "WinRM Basic auth re-enabled" } catch { Write-Info "WSMan Basic auth: $_" }
try { Set-Item -Path "WSMan:\localhost\Service\Auth\Negotiate"  -Value $true -Force; Write-Fixed "WinRM Negotiate auth re-enabled" } catch { Write-Info "WSMan Negotiate auth: $_" }
try { Set-Item -Path "WSMan:\localhost\Service\AllowUnencrypted" -Value $true -Force; Write-Fixed "WinRM AllowUnencrypted = true" } catch { Write-Info "AllowUnencrypted: $_" }
try { Set-Item -Path "WSMan:\localhost\Client\Auth\Basic"       -Value $true -Force; Write-Fixed "WinRM Client Basic auth re-enabled" } catch { Write-Info "WSMan Client Basic auth: $_" }
try { Set-Item -Path "WSMan:\localhost\Client\AllowUnencrypted" -Value $true -Force; Write-Fixed "WinRM Client AllowUnencrypted = true" } catch { Write-Info "WSMan Client AllowUnencrypted: $_" }

# -----------------------------------------------------------------------
# 3. Ensure packer_user account password does not expire
# -----------------------------------------------------------------------
Write-Section "Protect packer_user account from STIG account policy changes"

$packerAccounts = @('packer_user', 'packer', 'WinRMUser')

foreach ($acct in $packerAccounts) {
    $user = Get-LocalUser -Name $acct -ErrorAction SilentlyContinue
    if (-not $user) { continue }

    try {
        $adsiUser = [ADSI]"WinNT://./$acct,user"
        $adsiUser.UserFlags.Value = $adsiUser.UserFlags.Value -bor 65536  # ADS_UF_DONT_EXPIRE_PASSWD
        $adsiUser.SetInfo()
        Write-Fixed "Password expiry disabled for build account: $acct"
    } catch {
        Write-Info "Could not update $acct (non-fatal): $_"
    }
}

# -----------------------------------------------------------------------
# 4. Verify WinRM listener and auth config (Restart-Service removed)
# -----------------------------------------------------------------------
Write-Section "Verify WinRM listener and auth"

try {
    $listeners = Get-WSManInstance -ResourceURI winrm/config/listener -SelectorSet @{} -Enumerate
    foreach ($l in $listeners) {
        Write-OK "WinRM listener: $($l.Transport) on port $($l.Port)"
    }
} catch {
    $netstat = netstat -an | Select-String ":5985|:5986"
    if ($netstat) {
        Write-OK "WinRM port confirmed open: $netstat"
    } else {
        Write-Info "Could not confirm WinRM listener"
    }
}

try {
    $auth = Get-Item "WSMan:\localhost\Service\Auth"
    $auth | Get-ChildItem | ForEach-Object {
        Write-Info "WinRM Auth\$($_.Name) = $($_.Value)"
    }
} catch {
    Write-Info "Could not read WSMan auth state (non-fatal)"
}

Write-Host "`n=== WinRM repair complete — Packer should reconnect successfully ===" -ForegroundColor Green

