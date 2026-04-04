#Requires -RunAsAdministrator
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
    }
}

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

    Write-OK "HTTPS listener rebuilt (cert: $thumb)"
} catch {
    Write-Warning "HTTPS listener rebuild failed: $_"
}

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

Write-Section "Restart WinRM and verify"

try {
    Restart-Service -Name WinRM -Force
    Start-Sleep -Seconds 5
    Write-OK "WinRM service: $((Get-Service WinRM).Status)"
} catch {
    Write-Warning "WinRM restart: $_"
}

$port = netstat -an | Select-String ":5986"
if ($port) {
    Write-OK "Port 5986 listening" -ForegroundColor Green
} else {
    Write-Warning "Port 5986 not detected"
}

Write-Host "`n=== WinRM repair complete ===" -ForegroundColor Green
exit 0
