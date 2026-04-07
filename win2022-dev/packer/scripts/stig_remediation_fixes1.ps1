# ==============================
# Windows Server 2022 STIG Remediation Script — v4 (SAFE - NO RDP ISSUE)
# ==============================

$debugLog = "C:\Windows\Temp\stig_remediation.log"
if (Test-Path $debugLog) { Remove-Item $debugLog -Force }

function Log($msg, $color = "White") {
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $debugLog -Value $line
}

function Set-RegDWord {
    param($Path, $Name, $Value)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -Force
    return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
}

Log "===== STIG Remediation Started v4 =====" "Cyan"

# ==============================================================
# V-254475 — NTLMv2 only
# ==============================================================
Log "`n[CAT I] NTLMv2 Enforcement..." "Yellow"
$lsaPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
$val = Set-RegDWord -Path $lsaPath -Name "LmCompatibilityLevel" -Value 5
Log "  LmCompatibilityLevel = $val" "Green"

# ==============================================================
# V-254251 — C:\ permissions
# ==============================================================
Log "`n[CAT II] C:\ permissions..." "Yellow"
$acl = Get-Acl -Path "C:\"
$acl.SetAccessRuleProtection($true, $true)
$toRemove = $acl.Access | Where-Object { -not $_.IsInherited }
foreach ($rule in $toRemove) { $acl.RemoveAccessRule($rule) | Out-Null }

$inherit  = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit,ObjectInherit"
$propNone = [System.Security.AccessControl.PropagationFlags]::None
$propIO   = [System.Security.AccessControl.PropagationFlags]::InheritOnly
$allow    = [System.Security.AccessControl.AccessControlType]::Allow
$full     = [System.Security.AccessControl.FileSystemRights]::FullControl
$rx       = [System.Security.AccessControl.FileSystemRights]"ReadAndExecute, Synchronize"

$stigRules = @(
    New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Administrators",$full,$inherit,$propNone,$allow),
    New-Object System.Security.AccessControl.FileSystemAccessRule("NT AUTHORITY\SYSTEM",$full,$inherit,$propNone,$allow),
    New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Users",$rx,$inherit,$propNone,$allow),
    New-Object System.Security.AccessControl.FileSystemAccessRule("CREATOR OWNER",$full,$inherit,$propIO,$allow)
)

foreach ($rule in $stigRules) { $acl.AddAccessRule($rule) }
Set-Acl -Path "C:\" -AclObject $acl
Log "  [OK] C:\ permissions set" "Green"

# ==============================================================
# Password policy
# ==============================================================
Log "`n[CAT II] Password policy..." "Yellow"
net accounts /maxpwage:60 | Out-Null
Log "  [OK] Max password age set" "Green"

# ==============================================================
# Remove cert files
# ==============================================================
Log "`n[CAT II] Removing cert files..." "Yellow"
Get-ChildItem "C:\Users","C:\Windows\Temp" -Recurse -Include *.p12,*.pfx -ErrorAction SilentlyContinue |
Remove-Item -Force -ErrorAction SilentlyContinue
Log "  [OK] Cleanup done" "Green"

# ==============================================================
# UAC
# ==============================================================
Log "`n[CAT II] UAC..." "Yellow"
$uacPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
Set-RegDWord -Path $uacPath -Name "ConsentPromptBehaviorAdmin" -Value 2
Set-RegDWord -Path $uacPath -Name "PromptOnSecureDesktop" -Value 1
Log "  [OK] UAC set" "Green"

# ==============================================================
# 🔥 RDP ENSURE (SAFE)
# ==============================================================
Log "`n[FIX] Ensuring RDP access..." "Cyan"
net localgroup "Remote Desktop Users" Administrators /add 2>$null | Out-Null
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
Log "  [OK] RDP enabled" "Green"

# ==============================================================
# InstallRoot + Certs (UNCHANGED)
# ==============================================================
$msiPath = "C:\Users\packer_user\hardening\InstallRoot.msi"
if (Test-Path $msiPath) {
    Start-Process "msiexec.exe" -ArgumentList "/i `"$msiPath`" /quiet /norestart" -Wait
    Log "  [OK] InstallRoot installed" "Green"
}

Log "`n===== COMPLETE =====" "Cyan"
Log "⚠️ REBOOT REQUIRED" "Red"
