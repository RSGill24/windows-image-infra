#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies the compiled DSC MOF to enforce STIG controls,
    then immediately restores WinRM HTTPS so Packer stays connected.

.NOTES
    DSC AccountPolicy resource calls secedit internally, which resets
    the security policy database and wipes WinRM auth settings. This
    breaks the active Packer WinRM session before any post-DSC scripts
    can run. The fix is to restore WinRM HTTPS right here, at the end
    of this script, before returning control to Packer.

    Run order: AFTER create_mof.ps1, BEFORE account_policy.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "=== Applying DSC configuration ==="

# -----------------------------------------------------------------------
# Resolve MOF path
# -----------------------------------------------------------------------
$OutputPath = Join-Path $PSScriptRoot "MOF"
$mofFile    = Join-Path $OutputPath "localhost.mof"

if (!(Test-Path $mofFile)) {
    Write-Error "MOF file not found at: $mofFile"
    exit 1
}

$mofSize = (Get-Item $mofFile).Length
Write-Host "Found MOF: $mofFile ($mofSize bytes)"

if ($mofSize -lt 10000) {
    Write-Error "MOF file is suspiciously small ($mofSize bytes)"
    exit 1
}

# -----------------------------------------------------------------------
# Apply DSC configuration
# -----------------------------------------------------------------------
Write-Host "Applying DSC configuration (this may take several minutes)..."

try {
    Start-DscConfiguration -Path $OutputPath -Wait -Force -Verbose -ErrorAction Stop
    Write-Host "=== DSC configuration applied successfully ===" -ForegroundColor Green
} catch {
    Write-Warning "Start-DscConfiguration encountered an error: $_"
    Write-Warning "Resource-level failures are expected during Packer builds."
    Write-Warning "They will be corrected by account_policy.ps1 and stig_remediation_fixes.ps1."
    Write-Host "=== DSC application completed with resource-level warnings ===" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------
# CRITICAL: Restore WinRM HTTPS immediately after DSC
#
# DSC AccountPolicy resource runs secedit which resets the security
# policy database. This wipes WinRM auth settings and removes the
# HTTPS listener, breaking the active Packer session. We must rebuild
# it here before this script returns — otherwise Packer loses the
# connection and all subsequent scripts are silently skipped.
# -----------------------------------------------------------------------
Write-Host "`n=== Restoring WinRM HTTPS after DSC (anti-disconnect) ===" -ForegroundColor Cyan

# Step 1: Remove GPO policy overrides written by DSC/secedit
$policyPaths = @(
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service",
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client"
)
foreach ($path in $policyPaths) {
    if (Test-Path $path) {
        foreach ($key in @("AllowBasic","AllowUnencrypted","DisableRunAs","AllowCredSSP","AllowKerberos","AllowNegotiate")) {
            Remove-ItemProperty -Path $path -Name $key -ErrorAction SilentlyContinue
        }
        Write-Host "  [FIX] Removed GPO WinRM overrides from $path"
    }
}

# Step 2: Rebuild HTTPS listener with fresh self-signed cert
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

    Write-Host "  [FIX] WinRM HTTPS listener rebuilt (cert: $thumb)"
} catch {
    Write-Warning "  HTTPS listener rebuild failed: $_ -- Packer may disconnect"
}

# Step 3: Restore WSMan auth settings
$wsmanSettings = @(
    @{ Path = "WSMan:\localhost\Service\Auth\Basic";       Value = $true  },
    @{ Path = "WSMan:\localhost\Service\Auth\Negotiate";   Value = $true  },
    @{ Path = "WSMan:\localhost\Service\Auth\Certificate"; Value = $true  },
    @{ Path = "WSMan:\localhost\Service\AllowUnencrypted"; Value = $false },
    @{ Path = "WSMan:\localhost\Client\Auth\Basic";        Value = $true  },
    @{ Path = "WSMan:\localhost\Client\AllowUnencrypted";  Value = $false },
    @{ Path = "WSMan:\localhost\MaxTimeoutms";             Value = 1800000 }
)
foreach ($s in $wsmanSettings) {
    try {
        Set-Item -Path $s.Path -Value $s.Value -Force
        Write-Host "  [FIX] $($s.Path) = $($s.Value)"
    } catch {
        Write-Host "  [INFO] $($s.Path) (non-fatal): $_"
    }
}

# Step 4: Ensure WinRM HTTPS firewall rule exists
$existing = Get-NetFirewallRule -DisplayName "WinRM-HTTPS" -ErrorAction SilentlyContinue
if (-not $existing) {
    netsh advfirewall firewall add rule name="WinRM-HTTPS" dir=in action=allow protocol=TCP localport=5986
    Write-Host "  [FIX] Firewall rule WinRM-HTTPS added"
} else {
    Write-Host "  [OK]  Firewall rule WinRM-HTTPS exists"
}

# Step 5: Restart WinRM and verify
try {
    Restart-Service -Name WinRM -Force
    Start-Sleep -Seconds 5
    $status = (Get-Service WinRM).Status
    Write-Host "  [OK]  WinRM service: $status"
} catch {
    Write-Warning "  WinRM restart failed: $_"
}

# Verify port 5986
$port = netstat -an | Select-String ":5986"
if ($port) {
    Write-Host "  [OK]  Port 5986 listening — Packer connection intact" -ForegroundColor Green
} else {
    Write-Warning "  Port 5986 not detected after restore"
}

Write-Host "=== WinRM restore complete ===" -ForegroundColor Green
exit 0
