#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Targeted STIG remediation for all failing rules identified in the SCAP scan.
    Run AFTER apply_mof.ps1 so DSC exceptions do not undo these fixes.
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
# CAT I -- HIGH SEVERITY
# ============================================================

Write-Section "CAT I: V-254446 -- Prevent blank-password network logon"
try {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
        -Name "LimitBlankPasswordUse" -Value 1 -Type DWord -Force -ErrorAction Stop
    $val = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa").LimitBlankPasswordUse
    if ($val -eq 1) {
        Write-OK "LimitBlankPasswordUse = 1 (blank password network logon blocked)"
    } else {
        Write-Warn "Value is $val -- expected 1"
        $ErrorCount++
    }
} catch {
    Write-Warn "Failed to set LimitBlankPasswordUse: $_"
    $ErrorCount++
}

# ============================================================
# CAT II -- PASSWORD POLICY
# ============================================================

Write-Section "CAT II: Password Policy verification (V-254289/290/291/292)"

try {
    $netOutput = net accounts 2>&1
    $checks = @(
        @{ Pattern = 'Minimum password length\s+(\d+)';           Min = 14; Label = 'MinPwLength >= 14'  },
        @{ Pattern = 'Maximum password age \(days\)\s+(\d+)';     Max = 60; Label = 'MaxPwAge <= 60'     },
        @{ Pattern = 'Minimum password age \(days\)\s+(\d+)';     Min = 1;  Label = 'MinPwAge >= 1'      },
        @{ Pattern = 'Lockout threshold\s+(\d+)';                 Max = 3;  Label = 'LockoutThreshold<=3'},
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
} catch {
    Write-Warn "Exception during password policy verification: $_"
    $ErrorCount++
}

# ============================================================
# CAT II: V-254258 -- Ensure all local enabled accounts have expiring passwords
# ============================================================

Write-Section "CAT II: V-254258 -- Passwords must be configured to expire"

$excludeAccounts = @('DefaultAccount', 'WDAGUtilityAccount', 'Guest', 'GuestDisabled', 'packer_user', 'packer', 'WinRMUser', 'Administrator', 'AdminRenamed')

try {
    Get-CimInstance -Class Win32_Useraccount -Filter "LocalAccount=True and Disabled=False" |
        Where-Object { $_.Name -notin $excludeAccounts } |
        ForEach-Object {
            $acct = $_
            try {
                $adsiUser = [ADSI]"WinNT://./$($acct.Name),user"
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
} catch {
    Write-Warn "Exception during account password expiry check: $_"
    $ErrorCount++
}

# ============================================================
# CAT II: V-254261 -- Remove software certificate installation files
# ============================================================

Write-Section "CAT II: V-254261 -- Remove .p12 and .pfx certificate files"

$gceCert = 'C:\ProgramData\Google\Compute Engine\mds-mtls-client.key.pfx'
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

if (Test-Path $gceCert) {
    Write-Skip "GCE mTLS cert retained (GCP agent dependency -- document with ISSO): $gceCert"
}

foreach ($pattern in @('*.p12', '*.pfx')) {
    try {
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
    } catch {
        Write-Warn "Exception during cert file scan: $_"
        $ErrorCount++
    }
}

# ============================================================
# CAT II: V-254284 -- Secure Boot
# ============================================================

Write-Section "CAT II: V-254284 -- Secure Boot (infrastructure action required)"

try {
    $sb = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
    if ($sb -eq $true) {
        Write-OK "Secure Boot is already enabled"
    } else {
        Write-Warn "Secure Boot is OFF -- enable in GCP Shielded VM config."
        Write-Warn "  In Packer HCL: shielded_instance_config { enable_secure_boot = true }"
    }
} catch {
    Write-Warn "Could not query Secure Boot state: $_"
}

# ============================================================
# CAT II: V-254442/443/444 -- DoD PKI certificates
# ============================================================

Write-Section "CAT II: V-254442 / 254443 / 254444 -- DoD PKI certificate verification"

$certChecks = @(
    @{ Name="DoD Root CA 3"; Store="Cert:\LocalMachine\Root";       Thumb="D73CA91102A2204A36459ED32213B467D7CE97FB"; Rule="V-254442" },
    @{ Name="DoD Root CA 4"; Store="Cert:\LocalMachine\Root";       Thumb="B8269F25DBD937ECAFD4C35A9838571723F2D026"; Rule="V-254442" },
    @{ Name="DoD Root CA 5"; Store="Cert:\LocalMachine\Root";       Thumb="4ECB5CC3095670454DA1CBD410FC921F46B8564B"; Rule="V-254442" },
    @{ Name="DoD Root CA 6"; Store="Cert:\LocalMachine\Root";       Thumb="D37ECF61C0B4ED88681EF3630C4E2FC787B37AEF"; Rule="V-254442" },
    @{ Name="DoD Interop cross-cert (DoD Root CA 3)"; Store="Cert:\LocalMachine\Disallowed"; Thumb="49CBE933151872E17C8EAE7F0ABA97FB610F6477"; Rule="V-254443" },
    @{ Name="CCEB Interop cross-cert (DoD Root CA 3)"; Store="Cert:\LocalMachine\Disallowed"; Thumb="9B74964506C7ED9138070D08D5F8B969866560C8"; Rule="V-254444" },
    @{ Name="CCEB Interop cross-cert (DoD Root CA 6)"; Store="Cert:\LocalMachine\Disallowed"; Thumb="D471CA32F7A692CE6CBB6196BD3377FE4DBCD106"; Rule="V-254444" }
)

foreach ($cc in $certChecks) {
    try {
        $found = Get-ChildItem -Path $cc.Store -ErrorAction SilentlyContinue |
                 Where-Object { $_.Thumbprint -eq $cc.Thumb }
        if ($found) {
            Write-OK "[$($cc.Rule)] $($cc.Name)"
        } else {
            Write-Warn "[$($cc.Rule)] MISSING: $($cc.Name)"
            Write-Warn "  -> Run install_dod_certs.ps1 or use InstallRoot/FBCA tools from https://cyber.mil/pki-pke"
            $ErrorCount++
        }
    } catch {
        Write-Warn "Exception checking cert $($cc.Name): $_"
        $ErrorCount++
    }
}

# ============================================================
# CAT II: V-254447 / V-254448 -- Rename built-in Administrator and Guest
# ============================================================

Write-Section "CAT II: V-254447 -- Rename built-in Administrator account"

$newAdminName = "AdminRenamed"
$newGuestName = "GuestDisabled"

try {
    $adminAcct = Get-LocalUser | Where-Object { $_.SID.Value -match '-500$' } | Select-Object -First 1
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

Write-Section "CAT II: V-254448 -- Rename built-in Guest account"

try {
    $guestAcct = Get-LocalUser | Where-Object { $_.SID.Value -match '-501$' } | Select-Object -First 1
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
# User rights -- REMOVED from the pipeline
# ============================================================
# This block used secedit /areas USER_RIGHTS to set SeRemoteShutdownPrivilege.
# User-rights assignments are excluded from the image at the caller's direction
# and are applied by domain GPO at first boot, for two reasons:
#   1. They do not reliably survive image capture and sysprep.
#   2. The secedit write goes through the Security Configuration Engine, which
#      re-enforces GPO-derived WinRM restrictions mid-session and can drop
#      Packer's connection.
# UserRightRule is also skipped as a whole class in the DSC MOF (create_mof.ps1),
# so leaving this here would have been the one place user rights still got
# written during a build.
Write-Section "User rights -- skipped (applied by domain GPO at first boot)"
Write-Skip "SeRemoteShutdownPrivilege and all other user-rights assignments"

# ============================================================
# C:\ root directory ACL -- DISABLED (slow, and duplicated)
# ============================================================
# Rewriting the ACL on C:\ walks the whole volume and was by far the slowest
# step in the build. It was also being done TWICE -- once here and once in the
# other post-DSC script -- so the cost was paid twice for the same result.
# Disabled at the caller's direction.
#
# The Server 2025 STIG expresses system-drive permissions as a PermissionRule,
# which DSC applies from the MOF, so this hand-rolled ACL reset is redundant on
# top of that. Re-enable only if a SCC scan actually flags the system drive.
Write-Section "C:\ root ACL -- skipped (disabled: slow)"
Write-Skip "C:\ ACL reset disabled; DSC PermissionRule covers system-drive permissions"

# ============================================================
# Advanced audit policy -- REMOVED from the pipeline
# ============================================================
# This block ran auditpol /set for the Object Access subcategories. Advanced
# audit policy is excluded from the image at the caller's direction and applied
# by domain GPO at first boot; it does not persist through image capture.
# AuditPolicyRule is also skipped as a whole class in the DSC MOF.
#
# The one piece that DOES persist and that GPO audit policy depends on is the
# SCENoApplyLegacyAuditPolicy registry value, which makes subcategory settings
# override the legacy category settings. That is a registry rule, so it is
# applied by win2025_registry_fixes.ps1 from the STIG content, and audit.ps1
# sets it as a belt-and-braces guarantee.
Write-Section "Advanced audit policy -- skipped (applied by domain GPO at first boot)"
Write-Skip "Object Access subcategories (File System, Handle Manipulation, Registry)"

# ============================================================
# Summary
# ============================================================

Write-Section "REMEDIATION SUMMARY"

if ($ErrorCount -eq 0) {
    Write-Host "  All remediations applied successfully." -ForegroundColor Green
} else {
    Write-Host "  $ErrorCount item(s) need attention (see WARN messages above)." -ForegroundColor Yellow
}
$global:LASTEXITCODE = 0
exit $ErrorCount
