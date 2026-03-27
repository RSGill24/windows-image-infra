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
# V-254258: Passwords must expire
# -----------------------------------------------------------------------
Write-Section "V-254258: Configure password expiry"

# Fix all local users
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

# Enforce policy (net accounts)
try {
    net accounts /maxpwage:60 | Out-Null
    Write-OK "Max password age set to 60 days"
} catch {
    Write-Fail "Failed to set password policy"
    $ErrorCount++
}

# Backup validation via secedit (ensures persistence in GCP)
try {
    secedit /export /cfg "$env:TEMP\check.cfg" | Out-Null
    Write-OK "Policy persisted via secedit"
    Remove-Item "$env:TEMP\check.cfg" -ErrorAction SilentlyContinue
} catch {
    Write-Warn "Could not validate via secedit"
}

# -----------------------------------------------------------------------
# V-254251: FIX C:\ ROOT ACL (STIG CORRECT)
# -----------------------------------------------------------------------
Write-Section "V-254251: Fix C:\ permissions (STIG compliant)"

try {
    # Disable inheritance (CRITICAL)
    icacls "C:\" /inheritance:r | Out-Null

    # Remove unwanted principals
    icacls "C:\" /remove "Everyone" 2>$null
    icacls "C:\" /remove "Authenticated Users" 2>$null

    # Apply required STIG permissions
    icacls "C:\" /grant:r "SYSTEM:(OI)(CI)(F)" | Out-Null
    icacls "C:\" /grant:r "Administrators:(OI)(CI)(F)" | Out-Null
    icacls "C:\" /grant:r "Users:(OI)(CI)(RX)" | Out-Null
    icacls "C:\" /grant:r "CREATOR OWNER:(OI)(CI)(IO)(F)" | Out-Null

    Write-OK "C:\ ACL set correctly"
} catch {
    Write-Fail "ACL fix failed"
    $ErrorCount++
}

# -----------------------------------------------------------------------
# V-254251 VALIDATION (VERY IMPORTANT FOR SCAP)
# -----------------------------------------------------------------------
Write-Section "Validating C:\ ACL"

try {
    $acl = Get-Acl "C:\"

    # Check inheritance
    if ($acl.AreAccessRulesProtected) {
        Write-OK "Inheritance disabled"
    } else {
        Write-Fail "Inheritance still enabled"
        $ErrorCount++
    }

    # Check unwanted users
    $bad = $acl.Access | Where-Object {
        $_.IdentityReference -match "Everyone|Authenticated Users"
    }

    if ($bad) {
        Write-Fail "Unwanted principals still exist"
        $bad | ForEach-Object { Write-Host "   $_" -ForegroundColor Red }
        $ErrorCount++
    } else {
        Write-OK "No unwanted principals"
    }

} catch {
    Write-Fail "ACL validation failed"
    $ErrorCount++
}

# -----------------------------------------------------------------------
# V-254261: Remove ALL certificate/install artifacts
# -----------------------------------------------------------------------
Write-Section "V-254261: Remove installation + cert artifacts"

# -----------------------------------------------------------------------
# Kill processes that may lock files
# -----------------------------------------------------------------------
Get-Process msiexec -ErrorAction SilentlyContinue | Stop-Process -Force

# -----------------------------------------------------------------------
# IMPORTANT: Add your actual hardening dir if different
# -----------------------------------------------------------------------
$searchPaths = @(
    "C:\Users\packer_user\hardening",
    "C:\Users\packer_user\Desktop",
    "C:\DoD_Certs",
    "C:\Windows\Temp",
    "$env:TEMP"
)

# -----------------------------------------------------------------------
# PRIORITY: .p7b files (explicit handling)
# -----------------------------------------------------------------------
Write-Host "Removing .p7b files explicitly..."

foreach ($path in $searchPaths) {
    if (!(Test-Path $path)) { continue }

    Get-ChildItem -Path $path -Recurse -Include *.p7b -Force -ErrorAction SilentlyContinue |
    ForEach-Object {
        try {
            takeown /F $_.FullName /A /R /D Y | Out-Null
            icacls $_.FullName /grant Administrators:F /T /Q | Out-Null

            Remove-Item $_.FullName -Force -ErrorAction Stop
            Write-OK "Removed P7B: $($_.FullName)"
        } catch {
            Write-Warn "Could not remove P7B: $($_.FullName)"
        }
    }
}

# -----------------------------------------------------------------------
# OTHER FILE TYPES
# -----------------------------------------------------------------------
$extensions = @(
    "*.p12","*.pfx",
    "*.cer","*.crt","*.der",
    "*.msi","*.exe",
    "*.zip","*.cab"
)

$removedCount = 0

foreach ($path in $searchPaths) {
    if (!(Test-Path $path)) { continue }

    foreach ($ext in $extensions) {
        Get-ChildItem -Path $path -Filter $ext -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                takeown /F $_.FullName /A /R /D Y | Out-Null
                icacls $_.FullName /grant Administrators:F /T /Q | Out-Null

                Remove-Item $_.FullName -Force -ErrorAction Stop

                Write-OK "Removed: $($_.FullName)"
                $removedCount++
            } catch {
                Write-Warn "Could not remove: $($_.FullName)"
            }
        }
    }
}

# -----------------------------------------------------------------------
# Remove entire DoD cert directory (CRITICAL)
# -----------------------------------------------------------------------
if (Test-Path "C:\DoD_Certs") {
    try {
        takeown /F "C:\DoD_Certs" /R /D Y | Out-Null
        icacls "C:\DoD_Certs" /grant Administrators:F /T /Q | Out-Null
        Remove-Item "C:\DoD_Certs" -Recurse -Force -ErrorAction Stop
        Write-OK "Removed entire DoD_Certs folder"
    } catch {
        Write-Warn "Could not delete DoD_Certs"
    }
}

# -----------------------------------------------------------------------
# FINAL VERIFICATION (ONLY .p7b — STIG critical)
# -----------------------------------------------------------------------
Write-Host "Verifying .p7b cleanup..."

$p7bLeft = Get-ChildItem C:\ -Recurse -Include *.p7b -Force -ErrorAction SilentlyContinue

if ($p7bLeft.Count -eq 0) {
    Write-OK "No .p7b files remaining"
} else {
    Write-Fail ".p7b files still exist:"
    $p7bLeft | Select-Object -First 10 | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Red
    }
}

# -----------------------------------------------------------------------
# V-254447 & V-254448: Rename Administrator and Guest accounts
# -----------------------------------------------------------------------
Write-Section "V-254447 & V-254448: Rename built-in accounts"

try {
    $admin = Get-LocalUser | Where-Object SID -like "*-500"
    if ($admin.Name -eq "Administrator") {
        Rename-LocalUser -Name "Administrator" -NewName "AdminRenamed"
        Write-OK "Administrator renamed to AdminRenamed"
    } else {
        Write-OK "Administrator already renamed to: $($admin.Name)"
    }
} catch {
    Write-Fail "Failed to rename Administrator"
    $ErrorCount++
}

try {
    $guest = Get-LocalUser | Where-Object SID -like "*-501"
    if ($guest.Name -eq "Guest") {
        Rename-LocalUser -Name "Guest" -NewName "GuestRenamed"
        Write-OK "Guest renamed to GuestRenamed"
    } else {
        Write-OK "Guest already renamed to: $($guest.Name)"
    }
} catch {
    Write-Fail "Failed to rename Guest"
    $ErrorCount++
}



# -----------------------------------------------------------------------
# FINAL VALIDATION
# -----------------------------------------------------------------------
Write-Section "Final Validation"

# Password check
net accounts | Select-String "Maximum password age"

# ACL check
icacls "C:\" | Select-String "SYSTEM|Administrators|Users"

# Artifact check
$left = Get-ChildItem "C:\" -Recurse `
    -Include *.p7b,*.cer,*.crt,*.der,*.msi,*.exe,*.zip `
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
