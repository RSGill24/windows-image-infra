#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Fixes remaining STIG failures:
      V-254251 - C:\ root directory permissions
      V-254258 - Passwords must be configured to expire
      V-254261 - Software certificate installation files removed
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

function Write-OK   ($m) { Write-Host "  [OK]   $m" -ForegroundColor Green  }
function Write-Fail ($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red    }
function Write-Warn ($m) { Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Write-Section ($m) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " $m" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

$ErrorCount = 0

# -----------------------------------------------------------------------
# V-254258: All enabled local accounts must have password expiry enabled
# -----------------------------------------------------------------------
Write-Section "V-254258: Configure passwords to expire"

Get-LocalUser | Where-Object { $_.Enabled -eq $true } | ForEach-Object {
    if ($_.PasswordNeverExpires) {
        try {
            Set-LocalUser -Name $_.Name -PasswordNeverExpires $false
            Write-OK "Password expiry enabled for: $($_.Name)"
        } catch {
            Write-Fail "Could not set expiry for $($_.Name): $_"
            $ErrorCount++
        }
    } else {
        Write-OK "$($_.Name): already set to expire"
    }
}

# -----------------------------------------------------------------------
# V-254251: C:\ root directory permissions must conform to STIG minimum
# Required ACL:
#   SYSTEM          - Full Control (OI)(CI)
#   Administrators  - Full Control (OI)(CI)
#   Users           - Read & Execute (OI)(CI)
#   CREATOR OWNER   - Full Control (OI)(CI)(IO) -- subfolders/files only
# -----------------------------------------------------------------------
Write-Section "V-254251: Reset C:\ root directory permissions"

try {
    # Remove non-standard ACEs (Authenticated Users, Everyone, etc.)
    Write-Host "  Removing non-standard ACEs..."
    icacls "C:\" /remove:g "Authenticated Users" /c /q 2>&1 | Out-Null
    icacls "C:\" /remove:g "Everyone" /c /q 2>&1 | Out-Null

    # Grant required ACEs -- use /grant:r to replace (not add) existing entries
    Write-Host "  Applying required ACEs..."
    icacls "C:\" /grant:r "SYSTEM:(OI)(CI)F"          /c /q 2>&1 | Out-Null
    icacls "C:\" /grant:r "Administrators:(OI)(CI)F"   /c /q 2>&1 | Out-Null
    icacls "C:\" /grant:r "Users:(OI)(CI)(RX)"         /c /q 2>&1 | Out-Null
    icacls "C:\" /grant:r "CREATOR OWNER:(OI)(CI)(IO)F" /c /q 2>&1 | Out-Null

    # Verify
    $aclOutput = icacls "C:\" 2>&1
    Write-Host "  Current C:\ ACL:" -ForegroundColor Gray
    $aclOutput | Select-String "(SYSTEM|Administrators|Users|CREATOR)" |
        ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }

    Write-OK "C:\ permissions applied"
} catch {
    Write-Fail "Failed to set C:\ permissions: $_"
    $ErrorCount++
}

# -----------------------------------------------------------------------
# V-254261: Remove software certificate installation files (.p12, .pfx)
# Scan common locations where these may exist
# -----------------------------------------------------------------------
Write-Section "V-254261: Remove software certificate files (.p12, .pfx)"

$searchPaths = @(
    "C:\",
    "C:\Users",
    "C:\Temp",
    "C:\Windows\Temp",
    "$env:TEMP"
)
$extensions = @("*.p12", "*.pfx")
$removedCount = 0

foreach ($path in $searchPaths) {
    if (!(Test-Path $path)) { continue }
    foreach ($ext in $extensions) {
        Get-ChildItem -Path $path -Filter $ext -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object {
                try {
                    Remove-Item -Path $_.FullName -Force -ErrorAction Stop
                    Write-OK "Removed: $($_.FullName)"
                    $removedCount++
                } catch {
                    Write-Warn "Could not remove $($_.FullName): $_"
                }
            }
    }
}

if ($removedCount -eq 0) {
    Write-OK "No .p12 or .pfx files found -- already clean"
} else {
    Write-OK "Removed $removedCount certificate file(s)"
}

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
Write-Section "Remaining Fixes Summary"
if ($ErrorCount -eq 0) {
    Write-Host "  All remaining fixes applied successfully." -ForegroundColor Green
} else {
    Write-Host "  $ErrorCount fix(es) need manual attention." -ForegroundColor Yellow
}

exit $ErrorCount
