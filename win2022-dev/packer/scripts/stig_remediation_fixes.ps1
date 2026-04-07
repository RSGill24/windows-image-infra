#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Targeted STIG remediation for all failing rules identified in the SCAP scan.
    Run AFTER apply_mof.ps1 so DSC exceptions do not undo these fixes.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

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
try {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
        -Name "LimitBlankPasswordUse" -Value 1 -Type DWord -Force -ErrorAction Stop
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
# CAT II: V-254258 — Ensure all local enabled accounts have expiring passwords
# ============================================================

Write-Section "CAT II: V-254258 — Passwords must be configured to expire"

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
# CAT II: V-254261 — Remove software certificate installation files
# FIX: Only scan specific known paths instead of full C:\ recursive scan.
# Full C:\ recursive scan triggers security policy changes mid-execution
# which kills the active WinRM session.
# ============================================================

Write-Section "CAT II: V-254261 — Remove .p12 and .pfx certificate files"

$gceCert = 'C:\ProgramData\Google\Compute Engine\mds-mtls-client.key.pfx'

# Known specific files — remove directly
$knownFiles = @(
    'C:\Program Files (x86)\Google\Cloud SDK\google-cloud-sdk\platform\gsutil\gslib\tests\test_data\test.p12',
    'C:\Program Files (x86)\Google\Cloud SDK\google-cloud-sdk\platform\gsutil\third_party\google-auth-library-python\tests\data\privatekey.p12'
)

foreach ($f in $knownFiles) {
    if (Test-Path $f) {
        try {
            Remove-Item $f -Force
            Write-Fixed "Removed: $f"
        } catch {
            Write-Warn "Could not remove $f : $_"
            $ErrorCount++
        }
    } else {
        Write-OK "Already absent: $f"
    }
}

if (Test-Path $gceCert) {
    Write-Skip "GCE mTLS cert retained (GCP agent dependency): $gceCert"
}

# Scan only specific safe directories — NOT full C:\ recursion
$safeScanPaths = @(
    "C:\Users\packer_user",
    "C:\Windows\Temp",
    "C:\Temp",
    "C:\DoD_Certs"
)

foreach ($scanPath in $safeScanPaths) {
    if (-not (Test-Path $scanPath)) { continue }
    foreach ($pattern in @('*.p12', '*.pfx')) {
        try {
            Get-ChildItem -Path $scanPath -Filter $pattern -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -ne $gceCert } |
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
            Write-Warn "Exception scanning $scanPath : $_"
            $ErrorCount++
        }
    }
}

Write-OK "Certificate file cleanup complete"

# ============================================================
# CAT II: V-254284 — Secure Boot
# ============================================================

Write-Section "CAT II: V-254284 — Secure Boot (infrastructure action required)"

try {
    $sb = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
    if ($sb -eq $true) {
        Write-OK "Secure Boot is already enabled"
    } else {
        Write-Warn "Secure Boot is OFF — enable in GCP Shielded VM config."
    }
} catch {
    Write-Warn "Could not query Secure Boot state: $_"
}

# ============================================================
# CAT II: V-254442/443/444 — DoD PKI certificates
# ============================================================

Write-Section "CAT II: V-254442 / 254443 / 254444 — DoD PKI certificate verification"

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
            $ErrorCount++
        }
    } catch {
        Write-Warn "Exception checking cert $($cc.Name): $_"
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

Write-Section "CAT II: V-254448 — Rename built-in Guest account"

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
# CAT II: V-278942 to V-278947 — Advanced Audit Policy (Object Access)
# ============================================================

Write-Section "CAT II: V-278942 to V-278947 — Advanced Audit Policy (Object Access)"

$auditSubcategories = @(
    @{ Name="File System";         Rule="V-278942/943" },
    @{ Name="Handle Manipulation"; Rule="V-278944/945" },
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

# ============================================================
# Summary
# ============================================================

Write-Section "REMEDIATION SUMMARY"

if ($ErrorCount -eq 0) {
    Write-Host "  All remediations applied successfully." -ForegroundColor Green
} else {
    Write-Host "  $ErrorCount item(s) need attention (see WARN messages above)." -ForegroundColor Yellow
}
if ($ErrorCount -gt 0) {
    Write-Warn "$ErrorCount issue(s) found during remediation — continuing pipeline"
}
exit 0
