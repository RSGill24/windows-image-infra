#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Restores WinRM HTTPS after DSC breaks it.
    Must run in a SEPARATE Packer provisioner block after apply_mof.ps1.

.NOTES
    DSC AccountPolicy resource calls secedit internally which resets the
    security policy database and wipes WinRM auth settings + HTTPS listener.
    Packer auto-retries the WinRM connection (winrm_timeout = 90m), so by
    the time this script runs in the next provisioner block, we just need
    to ensure WinRM is fully restored before the rest of the pipeline runs.
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

Write-Host "=== Restoring WinRM HTTPS after DSC ===" -ForegroundColor Cyan

# -----------------------------------------------------------------------
# 1. Remove GPO policy overrides written by DSC/secedit
# -----------------------------------------------------------------------
Write-Section "Remove GPO WinRM policy overrides"

$policyPaths = @(
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service",
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client"
)
foreach ($path in $policyPaths) {
    if (Test-Path $path) {
        foreach ($key in @("AllowBasic","AllowUnencrypted","DisableRunAs","AllowCredSSP","AllowKerberos","AllowNegotiate")) {
            Remove-ItemProperty -Path $path -Name $key -ErrorAction SilentlyContinue
        }
        Write-Fixed "Removed GPO overrides: $path"
    } else {
        Write-Info "Not present: $path"
    }
}

# -----------------------------------------------------------------------
# 2. Rebuild WinRM HTTPS listener on port 5986
# -----------------------------------------------------------------------
Write-Section "Rebuild WinRM HTTPS listener (port 5986)"

try {
    Get-ChildItem WSMan:\localhost\Listener |
        Where-Object { $_.Keys -contains "Transport=HTTPS" } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    $cert  = New-SelfSignedCertificate -DnsName "packer" -CertStoreLocation "Cert:\LocalMachine\My"
    $thumb = $cert.Thumbprint

    New-Item -Path WSMan:\localhost\Listener `
             -Transport HTTPS `
             -Address * `
             -CertificateThumbPrint $thumb `
             -Force | Out-Null

    Write-OK "HTTPS listener rebuilt on port 5986 (cert: $thumb)"
} catch {
    Write-Warning "HTTPS listener rebuild failed: $_"
}

# -----------------------------------------------------------------------
# 3. Restore WSMan auth settings
# -----------------------------------------------------------------------
Write-Section "Restore WSMan auth settings"

$settings = @(
    @{ Path = "WSMan:\localhost\Service\Auth\Basic";       Value = $true    },
    @{ Path = "WSMan:\localhost\Service\Auth\Negotiate";   Value = $true    },
    @{ Path = "WSMan:\localhost\Service\Auth\Certificate"; Value = $true    },
    @{ Path = "WSMan:\localhost\Service\AllowUnencrypted"; Value = $false   },
    @{ Path = "WSMan:\localhost\Client\Auth\Basic";        Value = $true    },
    @{ Path = "WSMan:\localhost\Client\AllowUnencrypted";  Value = $false   },
    @{ Path = "WSMan:\localhost\MaxTimeoutms";             Value = 1800000  }
)
foreach ($s in $settings) {
    try {
        Set-Item -Path $s.Path -Value $s.Value -Force
        Write-Fixed "$($s.Path) = $($s.Value)"
    } catch {
        Write-Info "$($s.Path) (non-fatal): $_"
    }
}

# -----------------------------------------------------------------------
# 4. Ensure WinRM HTTPS firewall rule exists
# -----------------------------------------------------------------------
Write-Section "Ensure WinRM firewall rules"

foreach ($rule in @(@{Name="WinRM-HTTPS";Port=5986}, @{Name="WinRM-HTTP";Port=5985})) {
    $existing = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
    if (-not $existing) {
        netsh advfirewall firewall add rule name="$($rule.Name)" dir=in action=allow protocol=TCP localport=$($rule.Port)
        Write-Fixed "Firewall rule added: $($rule.Name) port $($rule.Port)"
    } else {
        Write-OK "Firewall rule exists: $($rule.Name)"
    }
}

# -----------------------------------------------------------------------
# 5. Protect packer_user from STIG password expiry
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
        Write-Info "Could not update $acct (non-fatal): $_"
    }
}

# -----------------------------------------------------------------------
# 6. Restart WinRM and verify port 5986
# -----------------------------------------------------------------------
Write-Section "Restart WinRM and verify"

try {
    Restart-Service -Name WinRM -Force
    Start-Sleep -Seconds 5
    Write-OK "WinRM service: $((Get-Service WinRM).Status)"
} catch {
    Write-Warning "WinRM restart failed: $_"
}

$port = netstat -an | Select-String ":5986"
if ($port) {
    Write-OK "Port 5986 listening — WinRM HTTPS restored" -ForegroundColor Green
} else {
    Write-Warning "Port 5986 not detected"
}

Write-Host "`n=== WinRM restore complete — pipeline can continue ===" -ForegroundColor Green
exit 0
