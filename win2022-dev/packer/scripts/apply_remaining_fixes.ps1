#Requires -RunAsAdministrator

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
# V-254258: Passwords must expire (USER + POLICY LEVEL)
# -----------------------------------------------------------------------
Write-Section "V-254258: Configure password expiry"

# Fix local users
Get-LocalUser | Where-Object { $_.Enabled } | ForEach-Object {
    if ($_.PasswordNeverExpires) {
        try {
            Set-LocalUser -Name $_.Name -PasswordNeverExpires $false
            Write-OK "Password expiry enabled: $($_.Name)"
        } catch {
            Write-Fail "Failed: $($_.Name)"
            $ErrorCount++
        }
    }
}

# Fix system policy (IMPORTANT)
try {
    net accounts /maxpwage:60 | Out-Null
    Write-OK "Max password age set to 60 days"
} catch {
    Write-Fail "Failed to set password policy"
    $ErrorCount++
}

# -----------------------------------------------------------------------
# V-254251: Strict C:\ ACL FIX
# -----------------------------------------------------------------------
Write-Section "V-254251: Fix C:\ permissions (STRICT)"

try {
    # RESET FIRST (important)
    icacls "C:\" /reset /t /c /q | Out-Null

    # REMOVE unwanted
    icacls "C:\" /remove:g "Authenticated Users" "Everyone" /c /q | Out-Null

    # APPLY EXACT STIG ACL
    icacls "C:\" /inheritance:e | Out-Null
    icacls "C:\" /grant:r "SYSTEM:(OI)(CI)F" | Out-Null
    icacls "C:\" /grant:r "Administrators:(OI)(CI)F" | Out-Null
    icacls "C:\" /grant:r "Users:(OI)(CI)(RX)" | Out-Null
    icacls "C:\" /grant:r "CREATOR OWNER:(OI)(CI)(IO)F" | Out-Null

    Write-OK "C:\ ACL reset to STIG standard"
} catch {
    Write-Fail "ACL fix failed"
    $ErrorCount++
}

# -----------------------------------------------------------------------
# V-254261: Remove ALL certificate/install artifacts
# -----------------------------------------------------------------------
Write-Section "V-254261: Remove installation + cert artifacts"

$searchPaths = @(
    "C:\Users\packer_user\hardening",
    "C:\DoD_Certs",        
    "C:\Windows\Temp",
    "$env:TEMP"
)

# EXTENDED list (IMPORTANT FIX)
$extensions = @(
    "*.p12","*.pfx",
    "*.p7b","*.cer","*.crt","*.der",
    "*.msi","*.exe"
)

$removedCount = 0

foreach ($path in $searchPaths) {
    if (!(Test-Path $path)) { continue }

    foreach ($ext in $extensions) {
        Get-ChildItem -Path $path -Filter $ext -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                Remove-Item $_.FullName -Force -ErrorAction Stop
                Write-OK "Removed: $($_.FullName)"
                $removedCount++
            } catch {
                Write-Warn "Could not remove: $($_.FullName)"
            }
        }
    }
}

if ($removedCount -eq 0) {
    Write-OK "No leftover files found"
} else {
    Write-OK "Total removed files: $removedCount"
}

# -----------------------------------------------------------------------
# FINAL VALIDATION (VERY IMPORTANT)
# -----------------------------------------------------------------------
Write-Section "Validation Check"

# Check password policy
net accounts | Select-String "Maximum password age"

# Check ACL
icacls "C:\" | Select-String "Users|SYSTEM|Administrators"

# Check leftover files
$left = Get-ChildItem "C:\Users\packer_user\hardening" -Recurse `
    -Include *.p7b,*.cer,*.crt,*.der,*.msi,*.exe `
    -ErrorAction SilentlyContinue

if ($left.Count -eq 0) {
    Write-OK "No leftover cert/install files"
} else {
    Write-Fail "Still found leftover files"
    $ErrorCount++
}

# -----------------------------------------------------------------------
# SUMMARY
# -----------------------------------------------------------------------
Write-Section "SUMMARY"

if ($ErrorCount -eq 0) {
    Write-Host "ALL STIG FIXES APPLIED ✅" -ForegroundColor Green
} else {
    Write-Host "$ErrorCount issues remain ⚠️" -ForegroundColor Yellow
}

exit $ErrorCount
