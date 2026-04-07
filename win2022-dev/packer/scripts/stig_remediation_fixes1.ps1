# =========================
# FULL STIG REMEDIATION SCRIPT (Pipeline-Safe, Server 2022)
# =========================

$ErrorActionPreference = "Continue"
$tempPath = "C:\Windows\Temp"
if (-not (Test-Path $tempPath)) { New-Item -ItemType Directory -Path $tempPath -Force | Out-Null }

# -----------------------------
# 1. Configure password & account policies
# -----------------------------
Write-Host "Setting password & account policies..." -ForegroundColor Cyan
net accounts /maxpwage:60
net accounts /minpwlen:15
wmic useraccount set PasswordExpires=TRUE

# -----------------------------
# 2. Set AdminRenamed password
# -----------------------------
Write-Host "Setting AdminRenamed password..." -ForegroundColor Cyan
$adminUser = "AdminRenamed"
$adminPass = "Str0ng@Passw0rd!2026"
net user $adminUser $adminPass
net user $adminUser /active:yes

# -----------------------------
# 3. Remove other local admins
# -----------------------------
Write-Host "Removing non-required local admins..." -ForegroundColor Cyan
$otherAdmins = @("packer_user","rajindergill0925")
foreach ($u in $otherAdmins) { 
    net localgroup Administrators $u /delete -ErrorAction SilentlyContinue
    net user $u /active:no
}

# -----------------------------
# 4. Enable NTLMv2
# -----------------------------
Write-Host "Enabling NTLMv2..." -ForegroundColor Cyan
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LmCompatibilityLevel" -Value 5

# -----------------------------
# 5. Enable RDP for Admin only
# -----------------------------
Write-Host "Enabling RDP access..." -ForegroundColor Cyan
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
# Ensure Administrators in Remote Desktop Users
net localgroup "Remote Desktop Users" Administrators /add 2>&1 | Out-Null

# -----------------------------
# 6. Reset Security Database
# -----------------------------
Write-Host "Resetting Security DB..." -ForegroundColor Yellow
$secDB = "C:\Windows\Security\Database\secedit.sdb"
if (Test-Path $secDB) { Rename-Item $secDB ($secDB -replace '.sdb','_old.sdb') -ErrorAction SilentlyContinue }
$defDB = "$env:windir\inf\defltbase.inf"
secedit /configure /db $secDB /cfg $defDB /overwrite /quiet

# -----------------------------
# 7. Apply final User Rights (STIG-compliant)
# -----------------------------
Write-Host "Applying STIG User Rights..." -ForegroundColor Yellow
$infPath = Join-Path $tempPath "final_stig.inf"
$infContent = @"
[Unicode]
Unicode=yes
[Version]
signature=`"$CHICAGO$`"
Revision=1

[Privilege Rights]
; Allow log on locally (Administrators only)
SeInteractiveLogonRight = *S-1-5-32-544

; Deny log on locally (Guests + Local Accounts)
SeDenyInteractiveLogonRight = *S-1-5-32-546,*S-1-5-113

; Allow log on through RDS (Administrators + Remote Desktop Users)
SeRemoteInteractiveLogonRight = *S-1-5-32-544,*S-1-5-32-555

; Deny log on through RDS (Guests + Local Accounts)
SeDenyRemoteInteractiveLogonRight = *S-1-5-32-546,*S-1-5-113

; Deny log on as a batch job (Guests + Local Accounts)
SeDenyBatchLogonRight = *S-1-5-32-546,*S-1-5-113

; Access this computer from network (Administrators + Authenticated Users)
SeNetworkLogonRight = *S-1-5-32-544,*S-1-5-11

; Deny access from network (Guests + Local Accounts)
SeDenyNetworkLogonRight = *S-1-5-32-546,*S-1-5-113

; Backup, Restore, Increase priority
SeBackupPrivilege = *S-1-5-32-544
SeRestorePrivilege = *S-1-5-32-544
SeIncreaseBasePriorityPrivilege = *S-1-5-32-544,*S-1-5-90-0
"@

$infContent | Out-File -FilePath $infPath -Encoding Unicode -Force
$finalDB = Join-Path $tempPath "final_stig.sdb"
if (Test-Path $finalDB) { Remove-Item $finalDB -Force }
secedit /configure /db $finalDB /cfg $infPath /areas USER_RIGHTS /overwrite /quiet

# -----------------------------
# 8. Post-secedit: RDP group enforcement
# -----------------------------
net localgroup "Remote Desktop Users" Administrators /add 2>&1 | Out-Null
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0

# -----------------------------
# 9. Refresh Group Policies
# -----------------------------
gpupdate /force

# -----------------------------
# 10. Certificates & C:\ permissions
# -----------------------------
$hardeningPath = "C:\Users\packer_user\hardening"
if (Test-Path $hardeningPath) {
    Get-ChildItem "$hardeningPath\*.cer","$hardeningPath\*.crt" -ErrorAction SilentlyContinue | ForEach-Object {
        Import-Certificate -FilePath $_.FullName -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
    }
}
icacls C:\ /grant:r "Administrators:(F)" /inheritance:r

# -----------------------------
# 11. Reboot
# -----------------------------
Write-Host "===== REMEDIATION COMPLETE. REBOOTING NOW =====" -ForegroundColor Green
Restart-Computer -Force
