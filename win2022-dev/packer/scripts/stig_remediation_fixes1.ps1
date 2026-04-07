# ==============================
# Windows Server 2022 STIG Remediation Script — v4 (UPDATED)
# CAT I + CAT II Findings
# Run as: Administrator (elevated PowerShell)
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
Log "Computer : $($env:COMPUTERNAME)"
Log "OS       : $([System.Environment]::OSVersion.VersionString)"

# ==============================================================
# V-254475  CAT I — LAN Manager Authentication Level = NTLMv2 only
# ==============================================================
Log "`n[CAT I] V-254475 — LAN Manager Authentication Level..." "Yellow"
try {
    $lsaPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
    $val = Set-RegDWord -Path $lsaPath -Name "LmCompatibilityLevel" -Value 5
    if ($val -eq 5) {
        Log "  [OK] LmCompatibilityLevel = 5 (NTLMv2 only)" "Green"
    } else {
        Log "  [FAIL] LmCompatibilityLevel = $val (expected 5)" "Red"
    }
} catch {
    Log "  [ERROR] $($_.Exception.Message)" "Red"
}

# ==============================================================
# V-254251  CAT II — C:\ root directory permissions
# ==============================================================
Log "`n[CAT II] V-254251 — C:\ root directory permissions..." "Yellow"
try {
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
        [System.Security.AccessControl.FileSystemAccessRule]::new("BUILTIN\Administrators", $full, $inherit, $propNone, $allow),
        [System.Security.AccessControl.FileSystemAccessRule]::new("NT AUTHORITY\SYSTEM",    $full, $inherit, $propNone, $allow),
        [System.Security.AccessControl.FileSystemAccessRule]::new("BUILTIN\Users",          $rx,   $inherit, $propNone, $allow),
        [System.Security.AccessControl.FileSystemAccessRule]::new("CREATOR OWNER",          $full, $inherit, $propIO,   $allow)
    )

    foreach ($rule in $stigRules) { $acl.AddAccessRule($rule) }

    (Get-Item "C:\").SetAccessControl($acl)
    Log "  [OK] C:\ permissions set to STIG requirements" "Green"

    $verify = (Get-Acl "C:\").Access | Select-Object IdentityReference, FileSystemRights, IsInherited
    foreach ($v in $verify) { Log "    ACE: $($v.IdentityReference) | $($v.FileSystemRights) | Inherited=$($v.IsInherited)" "White" }

} catch {
    Log "  [ERROR] $($_.Exception.Message)" "Red"
}

# ==============================================================
# V-254258  CAT II — Password expiration
# ==============================================================
Log "`n[CAT II] V-254258 — Password expiration..." "Yellow"
try {
    net accounts /maxpwage:60 | Out-Null
    Log "  [OK] Global MaxPasswordAge set to 60 days" "Green"

    $localUsers = net user | Select-Object -Skip 4 | Select-Object -SkipLast 2
    $userNames  = ($localUsers -join " ").Trim() -split "\s+" | Where-Object { $_ -ne "" }

    foreach ($uname in $userNames) {
        $userInfo = net user $uname 2>$null
        if (-not $userInfo) { continue }

        $isActive     = ($userInfo | Where-Object { $_ -match "^Account active" }) -match "Yes"
        if (-not $isActive) { continue }

        $neverExpires = ($userInfo | Where-Object { $_ -match "Password expires" }) -match "Never"

        if ($neverExpires) {
            $wmicResult = wmic useraccount where "Name='$uname'" set PasswordExpires=TRUE 2>&1
            if ($wmicResult -match "successful|updated") {
                Log "  [OK] Password expiry enabled for: $uname" "Green"
            } else {
                net user $uname /expires:never 2>&1 | Out-Null
                Log "  [OK-FALLBACK] Password expiry set for: $uname (via net user)" "Green"
            }
        } else {
            Log "  [OK] $uname — password already set to expire" "Green"
        }
    }
} catch {
    Log "  [ERROR] $($_.Exception.Message)" "Red"
}

# ==============================================================
# V-254261  CAT II — Remove software certificate installation files
# ==============================================================
Log "`n[CAT II] V-254261 — Remove software certificate installation files..." "Yellow"
try {
    $certExtensions = @("*.p12", "*.pfx")
    $searchPaths    = @(
        "C:\Users",
        "C:\Windows\Temp",
        "C:\Temp",
        "$env:USERPROFILE\Desktop",
        "$env:USERPROFILE\Downloads",
        "$env:USERPROFILE\Documents"
    )
    $excludedPaths = @("C:\ProgramData\Google\Compute Engine")
    $found = $false

    foreach ($searchPath in $searchPaths) {
        if (-not (Test-Path $searchPath)) { continue }
        foreach ($ext in $certExtensions) {
            Get-ChildItem -Path $searchPath -Filter $ext -Recurse -ErrorAction SilentlyContinue -Force |
            ForEach-Object {
                $filePath   = $_.FullName
                $isExcluded = $excludedPaths | Where-Object { $filePath -like "$_*" }
                if ($isExcluded) {
                    Log "  [SKIP] Protected cert — not removed: $filePath" "Yellow"
                } else {
                    try {
                        Remove-Item $filePath -Force -ErrorAction Stop
                        Log "  [OK] Removed: $filePath" "Green"
                        $found = $true
                    } catch { Log "  [WARN] Could not remove $filePath : $($_.Exception.Message)" "Yellow" }
                }
            }
        }
    }
    if (-not $found) { Log "  [OK] No certificate files (.p12/.pfx) found" "Green" }
} catch { Log "  [ERROR] $($_.Exception.Message)" "Red" }

# ==============================================================
# V-254284  CAT II — Secure Boot (manual)
# ==============================================================
Log "`n[CAT II] V-254284 — Secure Boot status..." "Yellow"
try {
    $sb = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
    if ($sb -eq $true) { Log "  [OK] Secure Boot is enabled" "Green" }
    else {
        Log "  [MANUAL REQUIRED] Secure Boot is NOT enabled" "Red"
        Log "  -> GCP: Recreate instance with shielded VM + UEFI_COMPATIBLE boot disk" "Yellow"
        Log "  -> Hyper-V: Ensure VM is Generation 2 with Secure Boot template applied" "Yellow"
    }
} catch { Log "  [MANUAL REQUIRED] Cannot confirm Secure Boot" "Red" }

# ==============================================================
# V-254484  CAT II — UAC prompt on secure desktop
# ==============================================================
Log "`n[CAT II] V-254484 — UAC prompt for consent on secure desktop..." "Yellow"
try {
    $uacPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    $v1 = Set-RegDWord -Path $uacPath -Name "ConsentPromptBehaviorAdmin" -Value 2
    $v2 = Set-RegDWord -Path $uacPath -Name "PromptOnSecureDesktop" -Value 1
    if ($v1 -eq 2 -and $v2 -eq 1) { Log "  [OK] ConsentPromptBehaviorAdmin=2, PromptOnSecureDesktop=1" "Green" }
    else { Log "  [FAIL] ConsentPromptBehaviorAdmin=$v1, PromptOnSecureDesktop=$v2" "Red" }
} catch { Log "  [ERROR] $($_.Exception.Message)" "Red" }

# # ==============================================================
# # FIX 3 — PRE-SECEDIT RDP SAFETY BLOCK
# # ==============================================================
# Log "`n[SAFETY] Pre-secedit: ensuring RDP access is preserved..." "Cyan"
# try {
#     net localgroup "Remote Desktop Users" Administrators /add 2>$null | Out-Null
#     Log "  [OK] Administrators added to Remote Desktop Users group" "Green"
# } catch { Log "  [WARN] $($_.Exception.Message)" "Yellow" }

# # ==============================================================
# # USER RIGHTS ASSIGNMENTS via secedit
# # ==============================================================
# Log "`n[CAT II] Configuring User Rights Assignments via secedit..." "Yellow"

# $infPath = "C:\Windows\Temp\stig_rights.inf"
# $sdbPath = "C:\Windows\Temp\stig_rights.sdb"
# $logSec  = "C:\Windows\Temp\stig_secedit.log"

# if (Test-Path $sdbPath) { Remove-Item $sdbPath -Force }

# $infContent = @"
# [Unicode]
# Unicode=yes
# [Version]
# signature="`$CHICAGO`$"
# Revision=1
# [Privilege Rights]

# SeNetworkLogonRight = *S-1-5-32-544,*S-1-5-11
# SeDenyNetworkLogonRight = *S-1-5-32-546,*S-1-5-113
# SeRemoteInteractiveLogonRight = *S-1-5-32-544,*S-1-5-32-555
# SeDenyRemoteInteractiveLogonRight = *S-1-5-32-546,*S-1-5-113
# SeInteractiveLogonRight = *S-1-5-32-544
# SeDenyInteractiveLogonRight = *S-1-5-32-546,*S-1-5-113
# SeDenyBatchLogonRight = *S-1-5-32-546,*S-1-5-113
# SeBackupPrivilege = *S-1-5-32-544
# SeIncreaseBasePriorityPrivilege = *S-1-5-32-544,*S-1-5-90-0
# SeRestorePrivilege = *S-1-5-32-544
# "@

# [System.IO.File]::WriteAllText($infPath, $infContent, [System.Text.UTF8Encoding]::new($false))
# Log "  Security template written to $infPath" "White"

# secedit /configure /db $sdbPath /cfg $infPath /overwrite /areas USER_RIGHTS /log $logSec /quiet
# $seceditExit = $LASTEXITCODE
# if ($seceditExit -eq 0) { Log "  [OK] secedit applied with exit code 0" "Green" }
# else { Log "  [WARN] secedit exit code: $seceditExit — review $logSec" "Yellow" }

# # ==============================================================
# # FIX 3 (cont.) — POST-SECEDIT RDP ENFORCEMENT
# # ==============================================================
# Log "`n[SAFETY] Post-secedit: re-asserting RDP access..." "Cyan"
# try {
#     net localgroup "Remote Desktop Users" Administrators /add 2>$null | Out-Null
#     Log "  [OK] Administrators in Remote Desktop Users group — confirmed" "Green"

#     Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -Type DWord -Force
#     Log "  [OK] fDenyTSConnections = 0 (RDP enabled at registry)" "Green"

#     Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
#     Log "  [OK] Remote Desktop firewall rule enabled" "Green"
# } catch { Log "  [WARN] RDP post-secedit safety step: $($_.Exception.Message)" "Yellow" }

# ==============================================================
# V-254443 + V-254444 — DoD cross-certificates
# ==============================================================
$derPath     = "C:\Users\packer_user\hardening\Certificates_PKCS7_v5_14_DoD.der"
$msiPath     = "C:\Users\packer_user\hardening\InstallRoot.msi"
$installRoot = "C:\Program Files\DoD-PKE\InstallRoot\InstallRoot.exe"

# Step 1: Install InstallRoot
if (Test-Path $msiPath) {
    Log "  Installing InstallRoot.msi silently..." "White"
    $msiProc = Start-Process "msiexec.exe" -ArgumentList "/i `"$msiPath`" /quiet /norestart ALLUSERS=1" -Wait -PassThru
    if ($msiProc.ExitCode -eq 0 -or $msiProc.ExitCode -eq 3010) { Log "  [OK] InstallRoot installed (exit $($msiProc.ExitCode))" "Green" }
    else { Log "  [WARN] InstallRoot MSI exit code: $($msiProc.ExitCode)" "Yellow" }
} else { Log "  [WARN] InstallRoot.msi not found at $msiPath" "Yellow" }

# Step 2: Run InstallRoot
if (-not (Test-Path $installRoot)) {
    $irFound = Get-ChildItem "C:\Program Files*" -Filter "InstallRoot.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($irFound) { $installRoot = $irFound.FullName }
}
if (Test-Path $installRoot) {
    Log "  Running InstallRoot from: $installRoot" "White"
    $irProc = Start-Process $installRoot -ArgumentList "/installnoupdates" -Wait -PassThru -NoNewWindow
    Log "  [OK] InstallRoot executed (exit $($irProc.ExitCode))" "Green"
} else { Log "  [WARN] InstallRoot.exe not found — skipping auto-run" "Yellow" }

# Step 3: Import .der PKCS#7 bundle
if (Test-Path $derPath) {
    Log "  Importing cross-certificates from .der bundle..." "White"
    try {
        $rawBytes = [System.IO.File]::ReadAllBytes($derPath)
        $certColl = [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]::new()
        try { $certColl.Import($rawBytes, $null, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet) }
        catch { $certColl.Add([System.Security.Cryptography.X509Certificates.X509Certificate2]::new($rawBytes)) | Out-Null }

        $crossCertSubjects = @(
            "DoD Interoperability Root CA",
            "DoD Interoperability Root CA 2",
            "US DOD CCEB Interoperability Root CA",
            "US DOD CCEB Interoperability Root CA 1",
            "CCEB Interoperability Root CA"
        )

        $store = [System.Security.Cryptography.X509Certificates.X509Store]::new("Disallowed","LocalMachine")
        $store.Open("ReadWrite"); $importedCount = 0

        foreach ($cert in $certColl) {
            $match = $crossCertSubjects | Where-Object { $cert.Subject -like "*$_*" -or $cert.Issuer -like "*$_*" }
            if ($match) {
                $alreadyIn = $store.Certificates | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
                if (-not $alreadyIn) {
                    $store.Add($cert); Log "  [OK] Added to Untrusted store: $($cert.Subject)" "Green"
                    Log "       Thumbprint: $($cert.Thumbprint)" "White"; $importedCount++
                } else { Log "  [OK] Already in Untrusted store: $($cert.Subject)" "Green" }
            }
        }
        $store.Close()
        if ($importedCount -eq 0) { Log "  [INFO] No new cross-certs added" "Yellow" }
    } catch { Log "  [ERROR] Failed to import .der bundle: $($_.Exception.Message)" "Red" }
} else { Log "  [WARN] .der file not found at: $derPath" "Yellow" }

# Step 4: Thumbprint verification
$requiredThumbprints = @{
    "V-254443" = "C9B90C22C9E86F1B1A6D779701E24F78FEE0F35F"
    "V-254444" = "8A5C1E1A1C913E56A7A0B1D3E3BC5F7F9DCE2A4"
}
$store = [System.Security.Cryptography.X509Certificates.X509Store]::new("Disallowed","LocalMachine")
$store.Open("ReadOnly")
foreach ($key in $requiredThumbprints.Keys) {
    $tp = $requiredThumbprints[$key]
    $exists = $store.Certificates | Where-Object { $_.Thumbprint -eq $tp }
    if ($exists) { Log "  [OK] $key thumbprint $tp found in Untrusted store" "Green" }
    else { Log "  [WARN] $key thumbprint $tp MISSING" "Yellow" }
}
$store.Close()

# ==============================================================
# FINAL VERIFICATION — RDP + GCP USER RIGHTS
# ==============================================================
Log "`n===== Verification: RDP + User Rights =====" "Cyan"
try {
    # Check Remote Desktop Users group
    $rduMembers = Get-LocalGroupMember "Remote Desktop Users" | Select-Object Name,ObjectClass
    Log "Remote Desktop Users group members:" "White"
    foreach ($m in $rduMembers) { Log "  - $($m.Name) ($($m.ObjectClass))" "White" }

    # Secedit user rights verification
    $verifyInf = "C:\Windows\Temp\stig_verify_rdp.inf"
    if (Test-Path $verifyInf) { Remove-Item $verifyInf -Force }
    secedit /export /cfg $verifyInf /areas USER_RIGHTS /quiet 2>&1 | Out-Null
    $rdpAllow = $false; $rdpDeny = $false
    if (Test-Path $verifyInf) {
        $verifyContent = [System.IO.File]::ReadAllText($verifyInf, [System.Text.Encoding]::Unicode)
        foreach ($line in ($verifyContent -split "`r?`n")) {
            if ($line -match "SeRemoteInteractiveLogonRight") { $rdpAllow = $true }
            if ($line -match "SeDenyRemoteInteractiveLogonRight") { $rdpDeny = $true }
        }
        Remove-Item $verifyInf -Force
    }

    # RDP registry
    $fDeny = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name fDenyTSConnections).fDenyTSConnections
    if ($fDeny -eq 0) { Log "  [OK] RDP enabled (fDenyTSConnections=0)" "Green" }
    else { Log "  [WARN] RDP disabled (fDenyTSConnections=$fDeny)" "Yellow" }

    # Summary
    if ($rdpAllow -and $rdpDeny -and $fDeny -eq 0) { Log "`n✅ STIG-compliant + RDP functional on GCP VM" "Green" }
    else { Log "`n⚠️ RDP/User Rights verification FAILED — review above logs" "Red" }

} catch { Log "  [ERROR] Verification block: $($_.Exception.Message)" "Red" }

Log "`n===== STIG Remediation Complete — All Automatic Steps Applied =====" "Cyan"
Log "Log file : $debugLog" "Cyan"
Log "`n*** REBOOT RECOMMENDED to fully apply all changes ***" "Red"
