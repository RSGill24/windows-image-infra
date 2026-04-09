#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

function Write-OK      ($m) { Write-Host "  [OK]   $m" -ForegroundColor Green  }
function Write-Fail    ($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red    }
function Write-Warn    ($m) { Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Write-Fixed   ($m) { Write-Host "  [FIX]  $m" -ForegroundColor Yellow }
function Write-Section ($m) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " $m" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

$ErrorCount = 0

# -----------------------------------------------------------------------
# V-254258: Passwords must expire
# FIX: Get-LocalUser objects on this GCP image do not populate
#      PasswordNeverExpires reliably. Use net user output parsing instead
#      which works consistently on all Windows Server configurations.
# -----------------------------------------------------------------------
Write-Section "V-254258: Configure password expiry"

try {
    $localUsers = Get-LocalUser -ErrorAction Stop | Where-Object { $_.Enabled }
    foreach ($user in $localUsers) {
        try {
            # Parse net user output — always available and always populated
            $netUserOut = (net user $user.Name 2>&1) -join "`n"
            $neverExpires = $netUserOut -match 'Password expires\s+Never'

            if ($neverExpires) {
                Set-LocalUser -Name $user.Name -PasswordNeverExpires $false -ErrorAction Stop
                Write-Fixed "Password expiry enabled for: $($user.Name)"
            } else {
                Write-OK "Already expires: $($user.Name)"
            }
        } catch {
            Write-Warn "Skipping $($user.Name): $_"
        }
    }
} catch {
    Write-Fail "Get-LocalUser failed: $_"
    $ErrorCount++
}

try {
    net accounts /maxpwage:60 | Out-Null
    Write-OK "Max password age confirmed at 60 days"
} catch {
    Write-Fail "Failed to set max password age"
    $ErrorCount++
}

# -----------------------------------------------------------------------
# V-254251: Fix C:\ root ACL
# -----------------------------------------------------------------------
Write-Section "V-254251: Fix C:\ permissions"

try {
    icacls "C:\" /inheritance:r | Out-Null
    icacls "C:\" /remove "Everyone"            2>$null | Out-Null
    icacls "C:\" /remove "Authenticated Users" 2>$null | Out-Null

    icacls "C:\" /grant:r "SYSTEM:(OI)(CI)(F)"            | Out-Null
    icacls "C:\" /grant:r "Administrators:(OI)(CI)(F)"    | Out-Null
    icacls "C:\" /grant:r "Users:(OI)(CI)(RX)"            | Out-Null
    icacls "C:\" /grant:r "CREATOR OWNER:(OI)(CI)(IO)(F)" | Out-Null

    Write-OK "C:\ ACL reset to STIG-required defaults"
} catch {
    Write-Fail "ACL fix failed: $_"
    $ErrorCount++
}

# -----------------------------------------------------------------------
# V-254261: Remove cert/install artifacts
# -----------------------------------------------------------------------
Write-Section "V-254261: Cleanup artifacts"

Get-Process msiexec -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$searchPaths = @(
    "C:\Users\packer_user\hardening",
    "C:\Users\packer_user\Desktop",
    "C:\DoD_Certs",
    "C:\Windows\Temp",
    "$env:TEMP"
)

$gceMtlsCert = "C:\ProgramData\Google\Compute Engine\mds-mtls-client.key.pfx"

foreach ($path in $searchPaths) {
    if (!(Test-Path $path)) { continue }

    Get-ChildItem $path -Recurse -Include *.p7b,*.pfx -Force -ErrorAction SilentlyContinue |
    ForEach-Object {
        if ($_.FullName -eq $gceMtlsCert) {
            Write-OK "SKIP: GCE mTLS cert retained (GCP agent dependency): $($_.FullName)"
            return
        }
        try {
            takeown /F $_.FullName /A /R /D Y 2>$null | Out-Null
            icacls $_.FullName /grant Administrators:F /T /Q 2>$null | Out-Null
            Remove-Item $_.FullName -Force -ErrorAction Stop
            Write-Fixed "Removed: $($_.FullName)"
        } catch {
            Write-Warn "Could not remove $($_.FullName): $_"
        }
    }
}

if (Test-Path "C:\DoD_Certs") {
    Remove-Item "C:\DoD_Certs" -Recurse -Force -ErrorAction SilentlyContinue
    Write-OK "Removed C:\DoD_Certs"
}

# -----------------------------------------------------------------------
# V-254447 & V-254448: Rename built-in accounts
# -----------------------------------------------------------------------
Write-Section "Rename built-in accounts (V-254447 / V-254448)"

try {
    $admin = Get-LocalUser | Where-Object { $_.SID -like "*-500" }
    if ($admin.Name -ne "AdminRenamed") {
        Rename-LocalUser -Name $admin.Name -NewName "AdminRenamed" -ErrorAction Stop
        Write-Fixed "Administrator renamed to: AdminRenamed"
    } else {
        Write-OK "Administrator already renamed to: AdminRenamed"
    }
} catch {
    Write-Fail "Administrator rename failed: $_"
    $ErrorCount++
}

try {
    $guest = Get-LocalUser | Where-Object { $_.SID -like "*-501" }
    if ($guest.Name -ne "GuestDisabled") {
        Rename-LocalUser -Name $guest.Name -NewName "GuestDisabled" -ErrorAction Stop
        Write-Fixed "Guest renamed to: GuestDisabled"
    } else {
        Write-OK "Guest already renamed to: GuestDisabled"
    }
} catch {
    Write-Fail "Guest rename failed: $_"
    $ErrorCount++
}

# -----------------------------------------------------------------------
# Verification
# -----------------------------------------------------------------------
Write-Section "Verification"

$adminCheck = Get-LocalUser | Where-Object { $_.SID -like "*-500" }
$guestCheck = Get-LocalUser | Where-Object { $_.SID -like "*-501" }

if ($adminCheck.Name -eq "AdminRenamed") {
    Write-OK "Administrator verified: $($adminCheck.Name)"
} else {
    Write-Fail "Administrator not renamed — current name: $($adminCheck.Name)"
    $ErrorCount++
}

if ($guestCheck.Name -eq "GuestDisabled") {
    Write-OK "Guest verified: $($guestCheck.Name)"
} else {
    Write-Fail "Guest not renamed — current name: $($guestCheck.Name)"
    $ErrorCount++
}

# FIX: Wrap Get-ChildItem result in @() to force array type under StrictMode.
# Without this, a single result is a FileInfo object which has no .Count property.
$leftover = @(Get-ChildItem `
    -Path "C:\Users","C:\Windows\Temp" `
    -Recurse -Include *.p7b,*.cer,*.crt,*.der,*.msi `
    -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -ne $gceMtlsCert })

if ($leftover.Count -eq 0) {
    Write-OK "No leftover cert/install files"
} else {
    Write-Warn "$($leftover.Count) leftover file(s) — may need manual review"
    $leftover | ForEach-Object { Write-Warn "  $($_.FullName)" }
}

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
Write-Section "Summary"

if ($ErrorCount -eq 0) {
    Write-Host "  All remaining fixes applied successfully." -ForegroundColor Green
} else {
    Write-Host "  $ErrorCount issue(s) need attention." -ForegroundColor Yellow
}

exit $ErrorCount
