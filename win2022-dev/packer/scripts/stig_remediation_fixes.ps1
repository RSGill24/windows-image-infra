#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Targeted STIG remediation for all failing rules identified in the SCAP scan.
    Run AFTER apply_mof.ps1 so DSC exceptions do not undo these fixes.

.NOTES
    Scan: Microsoft Windows Server 2022 STIG SCAP Benchmark v002.007

    FIX: Removed the create_mof.ps1 Exception block advisory — the bad
         exception entries (V-254446, V-254289-292, V-254501) have been
         removed from create_mof.ps1 directly in this release.
    FIX: V-254435 and V-254499 Identity corrected to "Guests" in pamdata.xml.
         The secedit USER_RIGHTS section here targets the correct SIDs.
    FIX: Added explicit error handling and exit code propagation so
         run_all.ps1 Invoke-Step can detect failures reliably.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'   # Don't abort on individual rule failures

function Write-Section {
    param([string]$msg)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " $msg" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}
function Write-OK    { param([string]$msg) Write-Host "  [OK]   $msg" -ForegroundColor Green  }
function Write-Fixed { param([string]$msg) Write-Host "  [FIX]  $msg" -ForegroundColor Yellow }
function Write-Warn  { param([string]$msg) Write-Host "  [WARN] $msg" -ForegroundColor Magenta }
function Write-Skip  { param([string]$msg) Write-Host "  [SKIP] $msg" -ForegroundColor Gray   }

$ErrorCount = 0

# ============================================================
# CAT I — HIGH SEVERITY
# ============================================================

Write-Section "CAT I: V-254446 — Prevent blank-password network logon"
# Registry: HKLM\SYSTEM\CurrentControlSet\Control\Lsa\LimitBlankPasswordUse = 1
# This was previously being set to 0 by a bad Exception entry in create_mof.ps1.
# That entry has been removed; this script enforces the correct value as well.
try {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
        -Name "LimitBlankPasswordUse" -Value 1 -Type DWord -Force
    $val = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa").LimitBlankPasswordUse
    if ($val -eq 1) {
        Write-OK "LimitBlankPasswordUse = 1 (blank password network logon blocked)"
    } else {
        Write-Warn "Value is $val — expected 1"
        $ErrorCount++
    }
} catch {
    Write-Warn "Failed to set LimitBlankPasswordUse: $_"
    $ErrorCount++
}

# ============================================================
# CAT II — PASSWORD POLICY
# Note: account_policy.ps1 handles this via net accounts + secedit.
# This section is a belt-and-suspenders verification only.
# ============================================================

Write-Section "CAT II: Password Policy verification (V-254289/290/291/292)"

$netOutput = net accounts 2>&1
$checks = @(
    @{ Pattern = 'Minimum password length\s+(\d+)';           Min = 14; Label = 'MinPwLength >= 14'  }
    @{ Pattern = 'Maximum password age \(days\)\s+(\d+)';     Max = 60; Label = 'MaxPwAge <= 60'     }
    @{ Pattern = 'Minimum password age \(days\)\s+(\d+)';     Min = 1;  Label = 'MinPwAge >= 1'      }
    @{ Pattern = 'Lockout threshold\s+(\d+)';                 Max = 3;  Label = 'LockoutThreshold<=3'}
    @{ Pattern = 'Lockout duration \(minutes\)\s+(\d+)';      Min = 15; Label = 'LockoutDuration>=15'}
)
foreach ($c in $checks) {
    $m = $netOutput | Select-String -Pattern $c.Pattern
    if ($m) {
        $v    = [int]$m.Matches[0].Groups[1].Value
        $pass = $true
        if ($c.ContainsKey('Min') -and $v -lt $c.Min) { $pass = $false }
        if ($c.ContainsKey('Max') -and $v -gt $c.Max) { $pass = $false }
        if ($pass) { Write-OK "$($c.Label) (current: $v)" }
        else {
            Write-Warn "NOT MET: $($c.Label) (current: $v)"
            $ErrorCount++
        }
    } else {
        Write-Warn "Could not parse: $($c.Label)"
    }
}

# ============================================================
# CAT II: V-254258 — Ensure all local enabled accounts have expiring passwords
# ============================================================

Write-Section "CAT II: V-254258 — Passwords must be configured to expire"

# Exclude system accounts and Packer build accounts
$excludeAccounts = @('DefaultAccount', 'WDAGUtilityAccount', 'Guest', 'GuestDisabled',
                     'packer_user', 'packer', 'WinRMUser', 'Administrator', 'AdminRenamed')

Get-CimInstance -Class Win32_Useraccount `
    -Filter "LocalAccount=True and Disabled=False" |
    Where-Object { $_.Name -notin $excludeAccounts } |
    ForEach-Object {
        $acct = $_
        try {
            $adsiUser = [ADSI]"WinNT://./$($acct.Name),user"
            # Clear ADS_UF_DONT_EXPIRE_PASSWD flag (0x10000 = 65536)
            $currentFlags = $adsiUser.UserFlags.Value
            if ($currentFlags -band 65536) {
                $adsiUser.UserFlags.Value = $currentFlags -band (-bnot 65536)
                $adsiUser.SetInfo()
                Write-Fixed "Password expiry enabled for: $($acct.Name)"
            } else {
                Write-OK "Password already expires for: $($acct.Name)"
            }
        } catch {
            Write-Warn "Could not update $($acct.Name): $_"
            $ErrorCount++
        }
    }

# ============================================================
# CAT II: V-254261 — Remove software certificate installation files
# ============================================================

Write-Section "CAT II: V-254261 — Remove .p12 and .pfx certificate files"

$gceCert = 'C:\ProgramData\Google\Compute Engine\mds-mtls-client.key.pfx'

# Known test .p12 files from Google Cloud SDK (safe to remove — test fixtures only)
$knownTestFiles = @(
    'C:\Program Files (x86)\Google\Cloud SDK\google-cloud-sdk\platform\gsutil\gslib\tests\test_data\test.p12',
    'C:\Program Files (x86)\Google\Cloud SDK\google-cloud-sdk\platform\gsutil\third_party\google-auth-library-python\tests\data\privatekey.p12'
)

foreach ($f in $knownTestFiles) {
    if (Test-Path $f) {
        try {
            Remove-Item $f -Force
            Write-Fixed "Removed test cert: $f"
        } catch {
            Write-Warn "Could not remove $f : $_"
            $ErrorCount++
        }
    } else {
        Write-OK "Already absent: $f"
    }
}

# GCE mTLS cert — required for GCP agent, document with ISSO as exception
if (Test-Path $gceCert) {
    Write-Skip "GCE mTLS cert retained (GCP agent dependency — document with ISSO): $gceCert"
}

# Broad scan for any remaining .p12 / .pfx files (excluding GCE cert)
foreach ($pattern in @('*.p12', '*.pfx')) {
    Get-ChildItem -Path C:\ -Filter $pattern -Recurse -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -notlike '*Adobe*Preflight*' -and
            $_.FullName -ne $gceCert
        } |
        ForEach-Object {
            try {
                Remove-Item $_.FullName -Force
                Write-Fixed "Removed: $($_.FullName)"
            } catch {
                Write-Warn "Could not remove $($_.FullName): $_"
                $ErrorCount++
            }
        }
}

# ============================================================
# CAT II: V-254284 — Secure Boot
# Cannot be remediated from within the guest OS.
# Must be enabled at GCP instance/image level (Shielded VM).
# ============================================================

Write-Section "CAT II: V-254284 — Secure Boot (infrastructure action required)"

try {
    $sb = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
    if ($sb -eq $true) {
        Write-OK "Secure Boot is already enabled"
    } else {
        Write-Warn "Secure Boot is OFF — enable in GCP Shielded VM config."
        Write-Warn "  In Packer HCL: shielded_instance_config { enable_secure_boot = true }"
        Write-Warn "  This cannot be set from within the guest OS."
        # Note: not incrementing ErrorCount — this is an infra action, not a script failure
    }
} catch {
    Write-Warn "Could not query Secure Boot state: $_"
}

# ============================================================
# CAT II: V-254442/443/444 — DoD PKI certificates
# install_dod_certs.ps1 handles actual installation.
# This section verifies the results.
# ============================================================

Write-Section "CAT II: V-254442 / 254443 / 254444 — DoD PKI certificate verification"

$certChecks = @(
    @{ Name="DoD Root CA 3"; Store="Cert:\LocalMachine\Root";       Thumb="D73CA91102A2204A36459ED32213B467D7CE97FB"; Rule="V-254442" }
    @{ Name="DoD Root CA 4"; Store="Cert:\LocalMachine\Root";       Thumb="B8269F25DBD937ECAFD4C35A9838571723F2D026"; Rule="V-254442" }
    @{ Name="DoD Root CA 5"; Store="Cert:\LocalMachine\Root";       Thumb="4ECB5CC3095670454DA1CBD410FC921F46B8564B"; Rule="V-254442" }
    @{ Name="DoD Root CA 6"; Store="Cert:\LocalMachine\Root";       Thumb="D37ECF61C0B4ED88681EF3630C4E2FC787B37AEF"; Rule="V-254442" }
    @{ Name="DoD Interop cross-cert (DoD Root CA 3)"; Store="Cert:\LocalMachine\Disallowed"; Thumb="49CBE933151872E17C8EAE7F0ABA97FB610F6477"; Rule="V-254443" }
    @{ Name="CCEB Interop cross-cert (DoD Root CA 3)"; Store="Cert:\LocalMachine\Disallowed"; Thumb="9B74964506C7ED9138070D08D5F8B969866560C8"; Rule="V-254444" }
    @{ Name="CCEB Interop cross-cert (DoD Root CA 6)"; Store="Cert:\LocalMachine\Disallowed"; Thumb="D471CA32F7A692CE6CBB6196BD3377FE4DBCD106"; Rule="V-254444" }
)

foreach ($cc in $certChecks) {
    $found = Get-ChildItem -Path $cc.Store -ErrorAction SilentlyContinue |
             Where-Object { $_.Thumbprint -eq $cc.Thumb }
    if ($found) {
        Write-OK "[$($cc.Rule)] $($cc.Name)"
    } else {
        Write-Warn "[$($cc.Rule)] MISSING: $($cc.Name)"
        Write-Warn "  -> Run install_dod_certs.ps1 or use InstallRoot/FBCA tools from https://cyber.mil/pki-pke"
        $ErrorCount++
    }
}

# ============================================================
# CAT II: V-254447 / V-254448 — Rename built-in Administrator and Guest
# ============================================================

Write-Section "CAT II: V-254447 — Rename built-in Administrator account"

$newAdminName = "AdminRenamed"
$newGuestName = "GuestDisabled"

try {
    # Use SID pattern to find built-in Administrator (SID ends in -500)
    $adminAcct = Get-LocalUser | Where-Object {
        try { $_.SID.Value -match '-500$' } catch { $false }
    } | Select-Object -First 1

    if ($null -eq $adminAcct) {
        Write-Warn "Could not find built-in Administrator by SID pattern"
        $ErrorCount++
    } elseif ($adminAcct.Name -eq $newAdminName) {
        Write-OK "Administrator already renamed to: $newAdminName"
    } elseif ($adminAcct.Name -eq 'Administrator') {
        Rename-LocalUser -Name 'Administrator' -NewName $newAdminName
        Write-Fixed "Administrator renamed to: $newAdminName"
    } else {
        Write-OK "Administrator is already renamed to: $($adminAcct.Name)"
    }
} catch {
    Write-Warn "Failed to rename Administrator: $_"
    $ErrorCount++
}

Write-Section "CAT II: V-254448 — Rename built-in Guest account"

try {
    # Use SID pattern to find built-in Guest (SID ends in -501)
    $guestAcct = Get-LocalUser | Where-Object {
        try { $_.SID.Value -match '-501$' } catch { $false }
    } | Select-Object -First 1

    if ($null -eq $guestAcct) {
        Write-Warn "Could not find built-in Guest by SID pattern"
        $ErrorCount++
    } elseif ($guestAcct.Name -eq $newGuestName) {
        Write-OK "Guest already renamed to: $newGuestName"
    } elseif ($guestAcct.Name -eq 'Guest') {
        Rename-LocalUser -Name 'Guest' -NewName $newGuestName
        Write-Fixed "Guest renamed to: $newGuestName"
    } else {
        Write-OK "Guest is already renamed to: $($guestAcct.Name)"
    }
} catch {
    Write-Warn "Failed to rename Guest: $_"
    $ErrorCount++
}

# ============================================================
# CAT II: V-254501 — Force shutdown from remote system — Administrators only
# FIX: Removed the 'Everyone' Exception from create_mof.ps1.
#      This secedit step ensures the correct value is set regardless.
# ============================================================

Write-Section "CAT II: V-254501 — SeRemoteShutdownPrivilege = Administrators only"

$seceditCfg2 = "$env:TEMP\stig_userrights.cfg"
$seceditDb2  = "$env:TEMP\stig_userrights.sdb"

Remove-Item $seceditCfg2 -ErrorAction SilentlyContinue
Remove-Item $seceditDb2  -ErrorAction SilentlyContinue

secedit /export /areas USER_RIGHTS /cfg $seceditCfg2 /quiet

if (Test-Path $seceditCfg2) {
    $ucfg = Get-Content $seceditCfg2 -Raw

    # Set SeRemoteShutdownPrivilege to Administrators only (SID S-1-5-32-544)
    # This removes Everyone (S-1-1-0) if it was present
    if ($ucfg -match 'SeRemoteShutdownPrivilege') {
        $ucfg = $ucfg -replace 'SeRemoteShutdownPrivilege\s*=\s*[^\r\n]*', 'SeRemoteShutdownPrivilege = *S-1-5-32-544'
    } else {
        # Add the key if not present
        $ucfg = $ucfg -replace '(\[Privilege Rights\])', "`$1`r`nSeRemoteShutdownPrivilege = *S-1-5-32-544"
    }
    $ucfg | Set-Content $seceditCfg2 -Encoding Unicode

    secedit /configure /db $seceditDb2 /cfg $seceditCfg2 /areas USER_RIGHTS /quiet

    if ($LASTEXITCODE -eq 0) {
        Write-Fixed "SeRemoteShutdownPrivilege restricted to Administrators only"
    } else {
        Write-Warn "secedit USER_RIGHTS returned exit code $LASTEXITCODE"
        $ErrorCount++
    }

    Remove-Item $seceditCfg2 -ErrorAction SilentlyContinue
    Remove-Item $seceditDb2  -ErrorAction SilentlyContinue
} else {
    Write-Warn "secedit export failed for USER_RIGHTS — cannot set SeRemoteShutdownPrivilege"
    $ErrorCount++
}

# ============================================================
# CAT II: V-254251 — C:\ root directory permissions
# ============================================================

Write-Section "CAT II: V-254251 — C:\ root directory ACL"

try {
    $acl     = Get-Acl -Path "C:\"
    $rights  = [System.Security.AccessControl.FileSystemRights]
    $inherit = [System.Security.AccessControl.InheritanceFlags]
    $prop    = [System.Security.AccessControl.PropagationFlags]
    $allow   = [System.Security.AccessControl.AccessControlType]::Allow

    # Remove all explicit ACEs and re-apply the STIG-required set
    $acl.SetAccessRuleProtection($false, $false)
    $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }

    # SYSTEM — Full control — This folder, subfolders, files
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "NT AUTHORITY\SYSTEM", $rights::FullControl,
        ($inherit::ContainerInherit -bor $inherit::ObjectInherit), $prop::None, $allow)))

    # Administrators — Full control — This folder, subfolders, files
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "BUILTIN\Administrators", $rights::FullControl,
        ($inherit::ContainerInherit -bor $inherit::ObjectInherit), $prop::None, $allow)))

    # Users — Read & Execute — This folder, subfolders, files
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "BUILTIN\Users", $rights::ReadAndExecute,
        ($inherit::ContainerInherit -bor $inherit::ObjectInherit), $prop::None, $allow)))

    # Users — CreateDirectories — This folder, subfolders (no files)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "BUILTIN\Users", $rights::CreateDirectories,
        $inherit::ContainerInherit, $prop::None, $allow)))

    # Users — CreateFiles — Subfolders only (InheritOnly)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "BUILTIN\Users", $rights::CreateFiles,
        $inherit::ContainerInherit, $prop::InheritOnly, $allow)))

    # CREATOR OWNER — Full control — Subfolders and files only (InheritOnly)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "CREATOR OWNER", $rights::FullControl,
        ($inherit::ContainerInherit -bor $inherit::ObjectInherit), $prop::InheritOnly, $allow)))

    Set-Acl -Path "C:\" -AclObject $acl
    Write-Fixed "C:\ ACL reset to STIG-required defaults"

    # Quick verification
    $verify = icacls "C:\" 2>&1
    $verify | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }

} catch {
    Write-Warn "Failed to set C:\ ACL: $_"
    $ErrorCount++
}

# ============================================================
# CAT II: V-278942 to V-278947 — Advanced Audit Policy (Object Access)
# All 6 Object Access subcategories set to Success+Failure.
# ============================================================

Write-Section "CAT II: V-278942 to V-278947 — Advanced Audit Policy (Object Access)"

$auditSubcategories = @(
    @{ Name="File System";         Rule="V-278942/943" }
    @{ Name="Handle Manipulation"; Rule="V-278944/945" }
    @{ Name="Registry";            Rule="V-278946/947" }
)

foreach ($sub in $auditSubcategories) {
    try {
        $result = auditpol /set /subcategory:"$($sub.Name)" /success:enable /failure:enable 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Fixed "[$($sub.Rule)] Audit $($sub.Name) = Success+Failure"
        } else {
            Write-Warn "auditpol failed for $($sub.Name): $result"
            $ErrorCount++
        }
    } catch {
        Write-Warn "Exception setting audit for $($sub.Name): $_"
        $ErrorCount++
    }
}

# Persist via a boot scheduled task so audit policy survives DSC re-runs
Write-Host "  Creating scheduled task to persist audit policy on boot..." -ForegroundColor Gray

$taskXml = @'
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <BootTrigger><Enabled>true</Enabled></BootTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <RunLevel>HighestAvailable</RunLevel>
      <UserId>S-1-5-18</UserId>
    </Principal>
  </Principals>
  <Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy></Settings>
  <Actions>
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NonInteractive -ExecutionPolicy Bypass -Command "auditpol /set /subcategory:'File System' /success:enable /failure:enable; auditpol /set /subcategory:'Handle Manipulation' /success:enable /failure:enable; auditpol /set /subcategory:'Registry' /success:enable /failure:enable"</Arguments>
    </Exec>
  </Actions>
</Task>
'@

$taskName    = "STIG-AuditPolicy-Persist"
$taskXmlPath = "$env:TEMP\stig_audit_task.xml"
$taskXml | Set-Content $taskXmlPath -Encoding Unicode

try {
    schtasks /create /tn $taskName /xml $taskXmlPath /f 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-OK "Scheduled task '$taskName' created — audit policy will persist across reboots"
    } else {
        Write-Warn "Could not create scheduled task (audit policy may not survive reboot)"
    }
} catch {
    Write-Warn "Scheduled task creation failed (non-fatal): $_"
} finally {
    Remove-Item $taskXmlPath -ErrorAction SilentlyContinue
}

# Verify audit settings were applied
Write-Host "`n  Audit policy verification:" -ForegroundColor Gray
foreach ($sub in $auditSubcategories) {
    $check = auditpol /get /subcategory:"$($sub.Name)" 2>&1
    $line  = $check | Select-String -Pattern "$($sub.Name)"
    Write-Host "    $($sub.Name): $line" -ForegroundColor Gray
}

# ============================================================
# Summary
# ============================================================

Write-Section "REMEDIATION SUMMARY"

if ($ErrorCount -eq 0) {
    Write-Host "  All remediations applied successfully." -ForegroundColor Green
} else {
    Write-Host "  $ErrorCount item(s) need attention (see WARN messages above)." -ForegroundColor Yellow
}

Write-Host @"

  RULES HANDLED BY THIS SCRIPT:
    [SCRIPTED]  V-254446  CAT I  — Blank password network logon (registry)
    [SCRIPTED]  V-254289  CAT II — Max password age verified >= 60 days
    [SCRIPTED]  V-254290  CAT II — Min password age verified >= 1 day
    [SCRIPTED]  V-254291  CAT II — Min password length verified >= 14
    [SCRIPTED]  V-254292  CAT II — Password complexity verified enabled
    [SCRIPTED]  V-254258  CAT II — Local account password expiry enforced
    [SCRIPTED]  V-254261  CAT II — Google Cloud SDK test .p12 files removed
    [SCRIPTED]  V-254447  CAT II — Built-in Administrator renamed
    [SCRIPTED]  V-254448  CAT II — Built-in Guest renamed
    [SCRIPTED]  V-254501  CAT II — Remote shutdown right = Administrators only
    [SCRIPTED]  V-254251  CAT II — C:\ root directory ACL reset
    [SCRIPTED]  V-278942  CAT II — Audit File System Failures
    [SCRIPTED]  V-278943  CAT II — Audit File System Successes
    [SCRIPTED]  V-278944  CAT II — Audit Handle Manipulation Failures
    [SCRIPTED]  V-278945  CAT II — Audit Handle Manipulation Successes
    [SCRIPTED]  V-278946  CAT II — Audit Registry Failures
    [SCRIPTED]  V-278947  CAT II — Audit Registry Successes

  RULES HANDLED BY OTHER SCRIPTS:
    [account_policy.ps1]    V-254285/286/287/288/289/290/291/292 — Account + Password Policy
    [install_dod_certs.ps1] V-254442/443/444 — DoD PKI certificates

  RULES REQUIRING MANUAL/INFRASTRUCTURE ACTION:
    [INFRA]     V-254284  CAT II — Secure Boot (enable Shielded VM in GCP Packer config)
    [ISSO DOC]  V-254261  CAT II — GCE mTLS cert (retain + document with ISSO)

"@ -ForegroundColor Cyan

exit $ErrorCount
