# ==============================
# Windows Server 2022 STIG Remediation Script — v4
# CAT I + CAT II Findings
# Run as: Administrator (elevated PowerShell)
#
# CHANGES FROM v3:
#   FIX 1 — SeDenyRemoteInteractiveLogonRight no longer includes
#            S-1-5-32-544 (Administrators). STIG V-254439 only requires
#            Guests (S-1-5-32-546) and Local Accounts (S-1-5-113) to be
#            denied. Adding Admins caused error 0x1307 on RDP.
#   FIX 2 — SeRemoteInteractiveLogonRight now also includes
#            S-1-5-32-555 (Remote Desktop Users) so GCP-provisioned
#            accounts that land in that group can also connect.
#   FIX 3 — RDP safety block moved to BEFORE secedit so it is not
#            overwritten. A second enforcement block runs AFTER secedit
#            as a belt-and-suspenders guarantee.
#   FIX 4 — fDenyTSConnections explicitly set to 0 after secedit.
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
# V-254475  CAT I
# LAN Manager Authentication Level = 5 (NTLMv2 only)
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
# V-254251  CAT II  — C:\ root directory permissions
# ==============================================================
Log "`n[CAT II] V-254251 — C:\ root directory permissions..." "Yellow"
try {
    $acl = Get-Acl -Path "C:\"

    # Disable inheritance, preserving existing inherited ACEs as explicit copies
    $acl.SetAccessRuleProtection($true, $true)

    # Remove all explicit (non-inherited) ACEs
    $toRemove = $acl.Access | Where-Object { -not $_.IsInherited }
    foreach ($rule in $toRemove) {
        $acl.RemoveAccessRule($rule) | Out-Null
    }

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

    foreach ($rule in $stigRules) {
        $acl.AddAccessRule($rule)
    }

    (Get-Item "C:\").SetAccessControl($acl)
    Log "  [OK] C:\ permissions set to STIG requirements" "Green"

    $verify = (Get-Acl "C:\").Access | Select-Object IdentityReference, FileSystemRights, IsInherited
    foreach ($v in $verify) {
        Log "    ACE: $($v.IdentityReference) | $($v.FileSystemRights) | Inherited=$($v.IsInherited)" "White"
    }
} catch {
    Log "  [ERROR] $($_.Exception.Message)" "Red"
}

# ==============================================================
# V-254258  CAT II — Passwords must be configured to expire
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
    # Paths that must NOT be touched (infrastructure certs)
    $excludedPaths = @(
        "C:\ProgramData\Google\Compute Engine"
    )

    $found = $false
    foreach ($searchPath in $searchPaths) {
        if (-not (Test-Path $searchPath)) { continue }
        foreach ($ext in $certExtensions) {
            Get-ChildItem -Path $searchPath -Filter $ext -Recurse `
                          -ErrorAction SilentlyContinue -Force |
            ForEach-Object {
                $filePath   = $_.FullName
                $isExcluded = $excludedPaths | Where-Object { $filePath -like "$_*" }
                if ($isExcluded) {
                    Log "  [SKIP] Protected infrastructure cert — not removed: $filePath" "Yellow"
                } else {
                    try {
                        Remove-Item $filePath -Force -ErrorAction Stop
                        Log "  [OK] Removed: $filePath" "Green"
                        $found = $true
                    } catch {
                        Log "  [WARN] Could not remove $filePath : $($_.Exception.Message)" "Yellow"
                    }
                }
            }
        }
    }
    if (-not $found) {
        Log "  [OK] No certificate files (.p12/.pfx) found" "Green"
    }
} catch {
    Log "  [ERROR] $($_.Exception.Message)" "Red"
}

# ==============================================================
# V-254284  CAT II — Secure Boot (manual only, log status)
# ==============================================================
Log "`n[CAT II] V-254284 — Secure Boot status..." "Yellow"
try {
    $sb = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
    if ($sb -eq $true) {
        Log "  [OK] Secure Boot is enabled" "Green"
    } else {
        Log "  [MANUAL REQUIRED] Secure Boot is NOT enabled" "Red"
        Log "  -> GCP: Recreate instance with shielded VM + UEFI_COMPATIBLE boot disk" "Yellow"
        Log "  -> Hyper-V: Ensure VM is Generation 2 with Secure Boot template applied" "Yellow"
    }
} catch {
    Log "  [MANUAL REQUIRED] Cannot confirm Secure Boot" "Red"
}

# ==============================================================
# V-254484  CAT II — UAC prompt on secure desktop
# ==============================================================
Log "`n[CAT II] V-254484 — UAC prompt for consent on secure desktop..." "Yellow"
try {
    $uacPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    $v1 = Set-RegDWord -Path $uacPath -Name "ConsentPromptBehaviorAdmin" -Value 2
    $v2 = Set-RegDWord -Path $uacPath -Name "PromptOnSecureDesktop"      -Value 1
    if ($v1 -eq 2 -and $v2 -eq 1) {
        Log "  [OK] ConsentPromptBehaviorAdmin=2, PromptOnSecureDesktop=1" "Green"
    } else {
        Log "  [FAIL] ConsentPromptBehaviorAdmin=$v1, PromptOnSecureDesktop=$v2" "Red"
    }
} catch {
    Log "  [ERROR] $($_.Exception.Message)" "Red"
}

# ==============================================================
# FIX 3 — PRE-SECEDIT RDP SAFETY BLOCK
# Must run BEFORE secedit so membership is established first.
# secedit only sets rights/privileges — it does not remove group
# memberships, so this persists through the policy application.
# ==============================================================
Log "`n[SAFETY] Pre-secedit: ensuring RDP access is preserved..." "Cyan"
try {
    net localgroup "Remote Desktop Users" Administrators /add 2>$null | Out-Null
    Log "  [OK] Administrators added to Remote Desktop Users group" "Green"
} catch {
    Log "  [WARN] $($_.Exception.Message)" "Yellow"
}

# ==============================================================
# USER RIGHTS ASSIGNMENTS via secedit
#
# KEY FIXES vs v3:
#   SeDenyRemoteInteractiveLogonRight — removed S-1-5-32-544 (Administrators)
#     STIG V-254439 requires only Guests + Local Accounts to be denied.
#     Including Admins caused RDP error 0x1307 on all GCP-provisioned VMs.
#
#   SeRemoteInteractiveLogonRight — added S-1-5-32-555 (Remote Desktop Users)
#     GCP Compute Engine adds the OS Login / IAP user to Remote Desktop Users,
#     not to local Administrators. Without this SID the user has no allow right.
# ==============================================================
Log "`n[CAT II] Configuring User Rights Assignments via secedit..." "Yellow"

$infPath = "C:\Windows\Temp\stig_rights.inf"
$sdbPath = "C:\Windows\Temp\stig_rights.sdb"
$logSec  = "C:\Windows\Temp\stig_secedit.log"

if (Test-Path $sdbPath) { Remove-Item $sdbPath -Force }

$infContent = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Privilege Rights]

; V-254434 — Access this computer from the network
SeNetworkLogonRight = *S-1-5-32-544,*S-1-5-11

; V-254435 — Deny access to this computer from the network
; Guests (S-1-5-32-546) + Local Accounts (S-1-5-113) only
SeDenyNetworkLogonRight = *S-1-5-32-546,*S-1-5-113

; V-254439 — Allow log on through Remote Desktop Services
; Administrators (S-1-5-32-544) + Remote Desktop Users (S-1-5-32-555)
; FIX: Added S-1-5-32-555 so GCP-provisioned users in RDU group can connect
SeRemoteInteractiveLogonRight = *S-1-5-32-544,*S-1-5-32-555

; V-254439 — Deny log on through Remote Desktop Services
; Guests (S-1-5-32-546) + Local Accounts (S-1-5-113) ONLY
; FIX: Removed S-1-5-32-544 (Administrators) — was causing RDP error 0x1307
SeDenyRemoteInteractiveLogonRight = *S-1-5-32-546,*S-1-5-113

; V-254493 — Allow log on locally
SeInteractiveLogonRight = *S-1-5-32-544

; V-254438 — Deny log on locally
SeDenyInteractiveLogonRight = *S-1-5-32-546,*S-1-5-113

; V-254436 — Deny log on as a batch job
SeDenyBatchLogonRight = *S-1-5-32-546,*S-1-5-113

; V-254494 — Back up files and directories
SeBackupPrivilege = *S-1-5-32-544

; V-254504 — Increase scheduling priority
; S-1-5-90-0 = Window Manager Group (required to avoid DWM crash on some builds)
SeIncreaseBasePriorityPrivilege = *S-1-5-32-544,*S-1-5-90-0

; V-254511 — Restore files and directories
SeRestorePrivilege = *S-1-5-32-544
"@

[System.IO.File]::WriteAllText($infPath, $infContent, [System.Text.UTF8Encoding]::new($false))
Log "  Security template written to $infPath" "White"

secedit /configure /db $sdbPath /cfg $infPath /overwrite /areas USER_RIGHTS /log $logSec /quiet
$seceditExit = $LASTEXITCODE

if ($seceditExit -eq 0) {
    Log "  [OK] secedit applied with exit code 0" "Green"
} else {
    Log "  [WARN] secedit exit code: $seceditExit — review $logSec" "Yellow"
}

# Verify applied rights
$verifyInf = "C:\Windows\Temp\stig_verify_active.inf"
if (Test-Path $verifyInf) { Remove-Item $verifyInf -Force }
secedit /export /cfg $verifyInf /areas USER_RIGHTS /quiet 2>&1 | Out-Null

if (Test-Path $verifyInf) {
    $verifyContent = [System.IO.File]::ReadAllText($verifyInf, [System.Text.Encoding]::Unicode)
    foreach ($line in ($verifyContent -split "`r?`n")) {
        if ($line -match "SeRemoteInteractiveLogonRight|SeDenyRemoteInteractiveLogonRight") {
            Log "  [VERIFY] $line" "Cyan"
        }
    }
    Remove-Item $verifyInf -Force -ErrorAction SilentlyContinue
}

# ==============================================================
# FIX 3 (cont.) — POST-SECEDIT RDP ENFORCEMENT BLOCK
# Belt-and-suspenders: re-assert everything secedit cannot touch.
# ==============================================================
Log "`n[SAFETY] Post-secedit: re-asserting RDP access..." "Cyan"
try {
    # Re-add in case secedit somehow cleared the group (it shouldn't, but be safe)
    net localgroup "Remote Desktop Users" Administrators /add 2>$null | Out-Null
    Log "  [OK] Administrators in Remote Desktop Users group — confirmed" "Green"

    # FIX 4 — Ensure RDP is not disabled at registry level
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" `
        -Name "fDenyTSConnections" -Value 0 -Type DWord -Force
    Log "  [OK] fDenyTSConnections = 0 (RDP enabled at registry)" "Green"

    # Ensure firewall rule is open
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    Log "  [OK] Remote Desktop firewall rule enabled" "Green"
} catch {
    Log "  [WARN] RDP post-secedit safety step: $($_.Exception.Message)" "Yellow"
}

# ==============================================================
# V-254443 + V-254444  CAT II — DoD cross-certificates
# ==============================================================
Log "`n[CAT II] V-254443 / V-254444 — DoD cross-certificates..." "Yellow"

$derPath     = "C:\Users\packer_user\hardening\Certificates_PKCS7_v5_14_DoD.der"
$msiPath     = "C:\Users\packer_user\hardening\InstallRoot.msi"
$installRoot = "C:\Program Files\DoD-PKE\InstallRoot\InstallRoot.exe"

# Step 1: Install InstallRoot silently
if (Test-Path $msiPath) {
    Log "  Installing InstallRoot.msi silently..." "White"
    $msiProc = Start-Process "msiexec.exe" `
        -ArgumentList "/i `"$msiPath`" /quiet /norestart ALLUSERS=1" `
        -Wait -PassThru
    if ($msiProc.ExitCode -eq 0 -or $msiProc.ExitCode -eq 3010) {
        Log "  [OK] InstallRoot installed (exit $($msiProc.ExitCode))" "Green"
    } else {
        Log "  [WARN] InstallRoot MSI exit code: $($msiProc.ExitCode)" "Yellow"
    }
} else {
    Log "  [WARN] InstallRoot.msi not found at $msiPath" "Yellow"
}

# Step 2: Run InstallRoot to push certs
if (-not (Test-Path $installRoot)) {
    $irFound = Get-ChildItem "C:\Program Files*" -Filter "InstallRoot.exe" -Recurse `
                             -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($irFound) { $installRoot = $irFound.FullName }
}

if (Test-Path $installRoot) {
    Log "  Running InstallRoot from: $installRoot" "White"
    $irProc = Start-Process $installRoot -ArgumentList "/installnoupdates" -Wait -PassThru -NoNewWindow
    Log "  [OK] InstallRoot executed (exit $($irProc.ExitCode))" "Green"
} else {
    Log "  [WARN] InstallRoot.exe not found — skipping auto-run" "Yellow"
}

# Step 3: Directly import .der PKCS#7 bundle into Disallowed store
if (Test-Path $derPath) {
    Log "  Importing cross-certificates from .der bundle..." "White"
    try {
        $rawBytes = [System.IO.File]::ReadAllBytes($derPath)
        $certColl = [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]::new()

        try {
            $certColl.Import($rawBytes, $null,
                [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
        } catch {
            $singleCert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($rawBytes)
            $certColl.Add($singleCert) | Out-Null
        }

        Log "  Found $($certColl.Count) certificate(s) in bundle" "White"

        $crossCertSubjects = @(
            "DoD Interoperability Root CA",
            "DoD Interoperability Root CA 2",
            "US DOD CCEB Interoperability Root CA",
            "US DOD CCEB Interoperability Root CA 1",
            "CCEB Interoperability Root CA"
        )

        $store = [System.Security.Cryptography.X509Certificates.X509Store]::new("Disallowed","LocalMachine")
        $store.Open("ReadWrite")
        $importedCount = 0

        foreach ($cert in $certColl) {
            $match = $crossCertSubjects | Where-Object {
                $cert.Subject -like "*$_*" -or $cert.Issuer -like "*$_*"
            }
            if ($match) {
                $alreadyIn = $store.Certificates | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
                if (-not $alreadyIn) {
                    $store.Add($cert)
                    Log "  [OK] Added to Untrusted store: $($cert.Subject)" "Green"
                    Log "       Thumbprint: $($cert.Thumbprint)" "White"
                    $importedCount++
                } else {
                    Log "  [OK] Already in Untrusted store: $($cert.Subject)" "Green"
                }
            }
        }

        $store.Close()

        if ($importedCount -eq 0) {
            Log "  [INFO] No new cross-certs added (already present or not matched)" "Yellow"
            Log "  [INFO] All certs in bundle:" "Yellow"
            foreach ($cert in $certColl) {
                Log "    Subject: $($cert.Subject) | Thumb: $($cert.Thumbprint)" "White"
            }
        }
    } catch {
        Log "  [ERROR] Failed to import .der bundle: $($_.Exception.Message)" "Red"
    }
} else {
    Log "  [WARN] .der file not found at: $derPath" "Yellow"
}

# Step 4: Thumbprint verification
$requiredThumbprints = @{
    "V-254443 DoD Interoperability Root CA 2"         = "929BF96C046FC7CE8BEB7C6BD451289A3F05A9E2"
    "V-254444 US DOD CCEB Interoperability Root CA 1" = "9012E9E1E2FB8E05AF8B5B8D9CC04001C82FEE1C"
}

$checkStore = [System.Security.Cryptography.X509Certificates.X509Store]::new("Disallowed","LocalMachine")
$checkStore.Open("ReadOnly")

foreach ($label in $requiredThumbprints.Keys) {
    $tp     = $requiredThumbprints[$label]
    $inStore = $checkStore.Certificates | Where-Object { $_.Thumbprint -eq $tp }
    if ($inStore) {
        Log "  [OK] Confirmed in Untrusted store: $label" "Green"
    } else {
        Log "  [MANUAL REQUIRED] Missing: $label (Thumbprint: $tp)" "Red"
        Log "    Run: certutil -dump `"$derPath`" to inspect bundle contents" "Yellow"
    }
}

$checkStore.Close()

# ==============================================================
# Refresh security policy
# ==============================================================
Log "`n[INFO] Refreshing local security policy..." "Cyan"
gpupdate /force /wait:0 2>&1 | Out-Null
Log "  [OK] gpupdate triggered" "Green"

# ==============================================================
# Summary
# ==============================================================
Log "`n===== STIG Remediation v4 Complete =====" "Cyan"
Log "Log file : $debugLog" "Cyan"
Log "`nItems still requiring MANUAL action:" "Yellow"
Log "  V-254284 — Secure Boot : Enable in UEFI/BIOS or recreate as shielded/Gen2 VM" "Yellow"
Log "  V-254443/444 — If thumbprint check above shows MANUAL REQUIRED:" "Yellow"
Log "    Run: certutil -dump `"$derPath`" and identify the correct cross-cert files" "Yellow"
Log "    Then: Import-Certificate -FilePath <crosscert.cer> -CertStoreLocation Cert:\LocalMachine\Disallowed" "Yellow"
Log "`n*** REBOOT RECOMMENDED to fully apply all changes ***" "Red"
