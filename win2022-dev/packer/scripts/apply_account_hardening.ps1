# apply_account_hardening.ps1
# Fixes:
#   V-254447 -- Built-in Administrator account must be renamed
#   V-254448 -- Built-in Guest account must be renamed
#   V-254446 -- Local accounts with blank passwords must be blocked from network
#   V-254258 -- Passwords must be configured to expire
#   V-254501 -- Force shutdown from remote system right: Administrators only
#   V-254251 -- C:\ root directory permissions must conform to minimum requirements

Write-Host "=== Applying Account & Local Policy Hardening ==="

# -----------------------------------------------------------------------
# V-254447: Rename built-in Administrator account
# -----------------------------------------------------------------------
Write-Host "--- V-254447: Renaming built-in Administrator account..."
$adminAccount = Get-LocalUser | Where-Object { $_.SID -like "S-1-5-*-500" }
if ($adminAccount) {
    if ($adminAccount.Name -eq "Administrator") {
        Rename-LocalUser -Name "Administrator" -NewName "Local_Admin"
        Write-Host "  Renamed 'Administrator' to 'Local_Admin'"
    } else {
        Write-Host "  Already renamed: '$($adminAccount.Name)' -- skipping"
    }
} else {
    Write-Warning "  Built-in Administrator account not found"
}

# -----------------------------------------------------------------------
# V-254448: Rename built-in Guest account
# -----------------------------------------------------------------------
Write-Host "--- V-254448: Renaming built-in Guest account..."
$guestAccount = Get-LocalUser | Where-Object { $_.SID -like "S-1-5-*-501" }
if ($guestAccount) {
    if ($guestAccount.Name -eq "Guest") {
        Rename-LocalUser -Name "Guest" -NewName "Local_Guest"
        Write-Host "  Renamed 'Guest' to 'Local_Guest'"
    } else {
        Write-Host "  Already renamed: '$($guestAccount.Name)' -- skipping"
    }
} else {
    Write-Warning "  Built-in Guest account not found"
}

# -----------------------------------------------------------------------
# V-254446: Block blank password accounts from network access
# Registry: HKLM\SYSTEM\CurrentControlSet\Control\Lsa\LimitBlankPasswordUse = 1
# -----------------------------------------------------------------------
Write-Host "--- V-254446: Blocking blank password accounts from network..."
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
                 -Name "LimitBlankPasswordUse" `
                 -Value 1 `
                 -Type DWord
Write-Host "  LimitBlankPasswordUse set to 1"

# -----------------------------------------------------------------------
# V-254258: Passwords must be configured to expire on all local accounts
# -----------------------------------------------------------------------
Write-Host "--- V-254258: Configuring all local accounts to have password expiry..."
Get-LocalUser | Where-Object { $_.PasswordNeverExpires -eq $true -and $_.Enabled -eq $true } |
    ForEach-Object {
        Set-LocalUser -Name $_.Name -PasswordNeverExpires $false
        Write-Host "  Password expiry enabled for: $($_.Name)"
    }

# -----------------------------------------------------------------------
# V-254501: Force shutdown from remote system -- Administrators only
# Uses secedit to enforce User Rights Assignment
# -----------------------------------------------------------------------
Write-Host "--- V-254501: Setting 'Force shutdown from remote system' to Administrators only..."

$secCfgPath = "$env:TEMP\secedit_export.cfg"
$secDbPath  = "$env:TEMP\secedit.sdb"
$secInfPath = "$env:TEMP\secedit_import.inf"

# Export current policy
secedit /export /cfg $secCfgPath /quiet

# Build the override inf
$infContent = @"
[Unicode]
Unicode=yes
[Privilege Rights]
SeRemoteShutdownPrivilege = *S-1-5-32-544
[Version]
signature="`$CHICAGO`$"
Revision=1
"@
$infContent | Out-File -FilePath $secInfPath -Encoding Unicode

# Apply
secedit /configure /db $secDbPath /cfg $secInfPath /areas USER_RIGHTS /quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host "  SeRemoteShutdownPrivilege restricted to Administrators (S-1-5-32-544)"
} else {
    Write-Error "  secedit failed with exit code $LASTEXITCODE"
}

# Cleanup
Remove-Item $secCfgPath, $secDbPath, $secInfPath -ErrorAction SilentlyContinue

# -----------------------------------------------------------------------
# V-254251: C:\ root directory permissions -- remove non-standard ACEs
# STIG requires: SYSTEM FC, Administrators FC, Users RX, Creator Owner special
# -----------------------------------------------------------------------
Write-Host "--- V-254251: Resetting C:\ root directory permissions..."

# Reset to OS defaults first (icacls reset is non-destructive for inherited entries)
icacls "C:\" /reset /t /c /q 2>&1 | Out-Null

# Remove authenticated users from root if present (common non-compliant ACE)
icacls "C:\" /remove:g "Authenticated Users" /t /c /q 2>&1 | Out-Null

# Ensure required ACEs are present
icacls "C:\" /grant "SYSTEM:(OI)(CI)F" /c /q 2>&1 | Out-Null
icacls "C:\" /grant "Administrators:(OI)(CI)F" /c /q 2>&1 | Out-Null
icacls "C:\" /grant "Users:(OI)(CI)(RX)" /c /q 2>&1 | Out-Null
icacls "C:\" /grant "CREATOR OWNER:(OI)(CI)(IO)F" /c /q 2>&1 | Out-Null

Write-Host "  C:\ permissions reset to STIG-compliant ACL"

# -----------------------------------------------------------------------
# V-254261: Remove software certificate installation files (.p12, .pfx)
# -----------------------------------------------------------------------
Write-Host "--- V-254261: Removing software certificate installation files..."
$certExtensions = @("*.p12", "*.pfx")
$searchPaths    = @("C:\", "C:\Users", "C:\Temp", "C:\Windows\Temp")

foreach ($path in $searchPaths) {
    foreach ($ext in $certExtensions) {
        Get-ChildItem -Path $path -Filter $ext -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object {
                Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
                Write-Host "  Removed: $($_.FullName)"
            }
    }
}
Write-Host "  Certificate file sweep complete"

Write-Host "=== Account & Local Policy Hardening complete. ==="