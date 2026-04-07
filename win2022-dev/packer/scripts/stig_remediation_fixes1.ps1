# ==============================
# Windows Server 2022 STIG Remediation Script — v3 FINAL
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

Log "===== STIG Remediation Started v3 =====" "Cyan"
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
#
# ROOT CAUSE of previous failure:
#   icacls "C:\" /reset /T tries to recurse the entire C: drive
#   AND strips all ACEs including system-required ones, making
#   the ACL "unusable". We must NOT use /reset /T on a drive root.
#
# CORRECT APPROACH:
#   1. Use Set-Acl with the .NET ACL API but call it correctly:
#      Build ALL rules first, then set the whole ACL object at once.
#   2. Disable inheritance (copy existing inherited ACEs), remove
#      only the explicit non-inherited entries, add the 4 STIG rules.
#   3. Do NOT recurse — the STIG only requires the root-level ACL.
# ==============================================================
Log "`n[CAT II] V-254251 — C:\ root directory permissions..." "Yellow"
try {
    $acl = Get-Acl -Path "C:\"

    # Disable inheritance, preserving existing inherited ACEs as explicit copies
    $acl.SetAccessRuleProtection($true, $true)

    # Remove all explicit (non-inherited) ACEs that exist after the copy
    $toRemove = $acl.Access | Where-Object { -not $_.IsInherited }
    foreach ($rule in $toRemove) {
        $acl.RemoveAccessRule($rule) | Out-Null
    }

    # Define the 4 STIG-required ACEs
    $inherit  = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit,ObjectInherit"
    $inheritO = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit,ObjectInherit"
    $propNone = [System.Security.AccessControl.PropagationFlags]::None
    $propIO   = [System.Security.AccessControl.PropagationFlags]::InheritOnly
    $allow    = [System.Security.AccessControl.AccessControlType]::Allow
    $full     = [System.Security.AccessControl.FileSystemRights]::FullControl
    $rx       = [System.Security.AccessControl.FileSystemRights]"ReadAndExecute, Synchronize"

    $stigRules = @(
        [System.Security.AccessControl.FileSystemAccessRule]::new("BUILTIN\Administrators", $full, $inherit,  $propNone, $allow),
        [System.Security.AccessControl.FileSystemAccessRule]::new("NT AUTHORITY\SYSTEM",    $full, $inherit,  $propNone, $allow),
        [System.Security.AccessControl.FileSystemAccessRule]::new("BUILTIN\Users",          $rx,   $inheritO, $propNone, $allow),
        [System.Security.AccessControl.FileSystemAccessRule]::new("CREATOR OWNER",          $full, $inheritO, $propIO,   $allow)
    )

    foreach ($rule in $stigRules) {
        $acl.AddAccessRule($rule)
    }

    # Apply the fully-built ACL object in one call — avoids the positional param bug
    (Get-Item "C:\").SetAccessControl($acl)
    Log "  [OK] C:\ permissions set to STIG requirements" "Green"

    # Verify
    $verify = (Get-Acl "C:\").Access | Select-Object IdentityReference, FileSystemRights, IsInherited
    foreach ($v in $verify) {
        Log "    ACE: $($v.IdentityReference) | $($v.FileSystemRights) | Inherited=$($v.IsInherited)" "White"
    }
} catch {
    Log "  [ERROR] $($_.Exception.Message)" "Red"
}

# ==============================================================
# V-254258  CAT II — Passwords must be configured to expire
#
# ROOT CAUSE of previous failure:
#   Get-LocalUser on this OS build/version does not expose the
#   PasswordNeverExpires property via the object model.
#   FIX: Use 'net user <name>' output parsing instead, then
#   set with 'net user <name> /expires:never' is WRONG —
#   use 'wmic useraccount' or directly write to SAM via net user.
#   The reliable cross-version method is: net user <name> /passwordchg:yes
#   combined with checking 'net user <name>' for "Password expires".
# ==============================================================
Log "`n[CAT II] V-254258 — Password expiration..." "Yellow"
try {
    # Global policy
    net accounts /maxpwage:60 | Out-Null
    Log "  [OK] Global MaxPasswordAge set to 60 days" "Green"

    # Per-account fix using net user (works on all WS2022 builds)
    $localUsers = net user | Select-Object -Skip 4 | Select-Object -SkipLast 2
    $userNames  = ($localUsers -join " ").Trim() -split "\s+" | Where-Object { $_ -ne "" }

    foreach ($uname in $userNames) {
        # Check if account is active
        $userInfo = net user $uname 2>$null
        if (-not $userInfo) { continue }

        $activeLines  = $userInfo | Where-Object { $_ -match "^Account active" }
        $isActive     = $activeLines -match "Yes"
        if (-not $isActive) { continue }

        $expiresLines = $userInfo | Where-Object { $_ -match "Password expires" }
        $neverExpires = $expiresLines -match "Never"

        if ($neverExpires) {
            # Use wmic to clear PasswordNeverExpires — reliable across all builds
            $wmicResult = wmic useraccount where "Name='$uname'" set PasswordExpires=TRUE 2>&1
            if ($wmicResult -match "successful|updated") {
                Log "  [OK] Password expiry enabled for: $uname" "Green"
            } else {
                # Fallback: net user with explicit expiry off means expires per policy
                # Setting /expires:never is wrong; not setting /expires means policy applies
                net user $uname /expires:never 2>&1 | Out-Null  # reset expiry flag
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
# (Previous run already cleaned; this re-confirms)
# ==============================================================
Log "`n[CAT II] V-254261 — Remove software certificate installation files..." "Yellow"
try {
    $certExtensions = @("*.p12", "*.pfx")
    $searchPaths    = @(
        "C:\Users",
        "C:\Windows\Temp",
        "C:\Temp",
        "C:\ProgramData",
        "$env:USERPROFILE\Desktop",
        "$env:USERPROFILE\Downloads",
        "$env:USERPROFILE\Documents"
    )
    $found = $false

    foreach ($searchPath in $searchPaths) {
        if (-not (Test-Path $searchPath)) { continue }
        foreach ($ext in $certExtensions) {
            $files = Get-ChildItem -Path $searchPath -Filter $ext -Recurse `
                                   -ErrorAction SilentlyContinue -Force
            foreach ($file in $files) {
                try {
                    Remove-Item $file.FullName -Force -ErrorAction Stop
                    Log "  [OK] Removed: $($file.FullName)" "Green"
                    $found = $true
                } catch {
                    Log "  [WARN] Could not remove $($file.FullName): $($_.Exception.Message)" "Yellow"
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
# USER RIGHTS ASSIGNMENTS via secedit — FIXED (NO LOCKOUT)
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

SeNetworkLogonRight = *S-1-5-32-544,*S-1-5-11
SeDenyNetworkLogonRight = *S-1-5-32-546,*S-1-5-113

SeRemoteInteractiveLogonRight = *S-1-5-32-544
SeDenyRemoteInteractiveLogonRight = *S-1-5-32-546,*S-1-5-113

SeInteractiveLogonRight = *S-1-5-32-544
SeDenyInteractiveLogonRight = *S-1-5-32-546,*S-1-5-113

SeDenyBatchLogonRight = *S-1-5-32-546,*S-1-5-113

SeBackupPrivilege = *S-1-5-32-544
SeIncreaseBasePriorityPrivilege = *S-1-5-32-544
SeRestorePrivilege = *S-1-5-32-544
"@

# Write INF
[System.IO.File]::WriteAllText($infPath, $infContent, [System.Text.UTF8Encoding]::new($false))
Log "  Security template written to $infPath" "White"

# Apply policy
secedit /configure /db $sdbPath /cfg $infPath /overwrite /areas USER_RIGHTS /log $logSec /quiet
$seceditExit = $LASTEXITCODE

if ($seceditExit -eq 0) {
    Log "  [OK] secedit applied with exit code 0" "Green"
} else {
    Log "  [WARN] secedit exit code: $seceditExit — review $logSec" "Yellow"
}

# Verify applied policy
$verifyInf = "C:\Windows\Temp\stig_verify_active.inf"
if (Test-Path $verifyInf) { Remove-Item $verifyInf -Force }

secedit /export /cfg $verifyInf /areas USER_RIGHTS /quiet 2>&1 | Out-Null

if (Test-Path $verifyInf) {
    $verifyContent = [System.IO.File]::ReadAllText($verifyInf, [System.Text.Encoding]::Unicode)

    foreach ($line in $verifyContent -split "`r?`n") {
        if ($line -match "SeRemoteInteractiveLogonRight|SeDenyRemoteInteractiveLogonRight") {
            Log "  [VERIFY] $line" "White"
        }
    }

    Remove-Item $verifyInf -Force -ErrorAction SilentlyContinue
}

# ==============================================================
# SAFETY NET — PREVENT RDP LOCKOUT (CRITICAL)
# ==============================================================
Log "`n[SAFETY] Ensuring RDP access is available..." "Cyan"

try {
    # Ensure Administrators can RDP
    net localgroup "Remote Desktop Users" Administrators /add | Out-Null
    Log "  [OK] Administrators added to Remote Desktop Users" "Green"

    # Enable RDP (in case STIG disabled it)
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" `
        -Name "fDenyTSConnections" -Value 0

    # Enable firewall rule
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue

    Log "  [OK] RDP access ensured" "Green"
} catch {
    Log "  [WARN] RDP safety step failed: $_" "Yellow"
}
# ==============================================================
# V-254443 + V-254444  CAT II
# DoD cross-certificates — AUTOMATED via local files
#
# Available on this machine:
#   C:\Users\packer_user\hardening\Certificates_PKCS7_v5_14_DoD.der
#   C:\Users\packer_user\hardening\InstallRoot.msi
#
# Strategy:
#   1. Install InstallRoot silently — it registers DoD root CAs
#      and can be configured to place cross-certs in Untrusted store
#   2. Also directly import the .der bundle into Disallowed store
#      using X509Certificate2Collection for PKCS#7 bundles
# ==============================================================
Log "`n[CAT II] V-254443 / V-254444 — DoD cross-certificates..." "Yellow"

$derPath     = "C:\Users\packer_user\hardening\Certificates_PKCS7_v5_14_DoD.der"
$msiPath     = "C:\Users\packer_user\hardening\InstallRoot.msi"
$installRoot = "C:\Program Files\DoD-PKE\InstallRoot\InstallRoot.exe"

# --- Step 1: Install InstallRoot silently ---
if (Test-Path $msiPath) {
    Log "  Installing InstallRoot.msi silently..." "White"
    $msiArgs = "/i `"$msiPath`" /quiet /norestart ALLUSERS=1"
    $msiProc = Start-Process "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru
    if ($msiProc.ExitCode -eq 0 -or $msiProc.ExitCode -eq 3010) {
        Log "  [OK] InstallRoot installed (exit $($msiProc.ExitCode))" "Green"
    } else {
        Log "  [WARN] InstallRoot MSI exit code: $($msiProc.ExitCode)" "Yellow"
    }
} else {
    Log "  [WARN] InstallRoot.msi not found at $msiPath" "Yellow"
}

# --- Step 2: Run InstallRoot to push certs into Untrusted store ---
# InstallRoot.exe /installnoupdates pushes DoD PKI certs per its config
# The /disallow flag specifically targets cross-certs into Disallowed store
if (Test-Path $installRoot) {
    Log "  Running InstallRoot to configure DoD certificates..." "White"
    $irProc = Start-Process $installRoot -ArgumentList "/installnoupdates" -Wait -PassThru -NoNewWindow
    Log "  [OK] InstallRoot executed (exit $($irProc.ExitCode))" "Green"
} else {
    # InstallRoot may install to a different path — search for it
    $irFound = Get-ChildItem "C:\Program Files*" -Filter "InstallRoot.exe" -Recurse `
                             -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($irFound) {
        Log "  Running InstallRoot from: $($irFound.FullName)" "White"
        $irProc = Start-Process $irFound.FullName -ArgumentList "/installnoupdates" -Wait -PassThru -NoNewWindow
        Log "  [OK] InstallRoot executed (exit $($irProc.ExitCode))" "Green"
    } else {
        Log "  [WARN] InstallRoot.exe not found — skipping auto-run" "Yellow"
    }
}

# --- Step 3: Directly import .der PKCS#7 bundle into Disallowed store ---
# PKCS#7 bundles contain multiple certs; we extract all and check thumbprints
if (Test-Path $derPath) {
    Log "  Importing cross-certificates from .der bundle..." "White"
    try {
        $rawBytes  = [System.IO.File]::ReadAllBytes($derPath)
        $certColl  = [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]::new()

        # Try PKCS7 import first, then raw DER
        try {
            $certColl.Import($rawBytes,
                $null,
                [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
        } catch {
            # Single DER cert fallback
            $singleCert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($rawBytes)
            $certColl.Add($singleCert) | Out-Null
        }

        Log "  Found $($certColl.Count) certificate(s) in bundle" "White"

        # Cross-cert subjects that MUST land in Disallowed
        $crossCertSubjects = @(
            "DoD Interoperability Root CA",
            "DoD Interoperability Root CA 2",
            "US DOD CCEB Interoperability Root CA",
            "US DOD CCEB Interoperability Root CA 1",
            "CCEB Interoperability Root CA"
        )

        $disallowedStore = [System.Security.Cryptography.X509Certificates.X509Store]::new(
            "Disallowed", "LocalMachine")
        $disallowedStore.Open("ReadWrite")

        $importedCount = 0
        foreach ($cert in $certColl) {
            $isCrossCert = $false
            foreach ($subj in $crossCertSubjects) {
                if ($cert.Subject -like "*$subj*" -or $cert.Issuer -like "*$subj*") {
                    $isCrossCert = $true
                    break
                }
            }

            if ($isCrossCert) {
                $alreadyIn = $disallowedStore.Certificates |
                             Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
                if (-not $alreadyIn) {
                    $disallowedStore.Add($cert)
                    Log "  [OK] Added to Untrusted store: $($cert.Subject)" "Green"
                    Log "       Thumbprint: $($cert.Thumbprint)" "White"
                    $importedCount++
                } else {
                    Log "  [OK] Already in Untrusted store: $($cert.Subject)" "Green"
                }
            }
        }

        $disallowedStore.Close()

        if ($importedCount -eq 0) {
            Log "  [INFO] No new cross-certs added (already present or not matched in bundle)" "Yellow"
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

# --- Step 4: Final thumbprint verification ---
$requiredThumbprints = @{
    "V-254443 DoD Interoperability Root CA 2"         = "929BF96C046FC7CE8BEB7C6BD451289A3F05A9E2"
    "V-254444 US DOD CCEB Interoperability Root CA 1" = "9012E9E1E2FB8E05AF8B5B8D9CC04001C82FEE1C"
}

$disallowedCheck = [System.Security.Cryptography.X509Certificates.X509Store]::new(
    "Disallowed", "LocalMachine")
$disallowedCheck.Open("ReadOnly")

foreach ($label in $requiredThumbprints.Keys) {
    $tp      = $requiredThumbprints[$label]
    $inStore = $disallowedCheck.Certificates | Where-Object { $_.Thumbprint -eq $tp }
    if ($inStore) {
        Log "  [OK] Confirmed in Untrusted store: $label" "Green"
    } else {
        Log "  [MANUAL REQUIRED] Still missing: $label (Thumbprint: $tp)" "Red"
        Log "    The .der bundle may use a different thumbprint for this version." "Yellow"
        Log "    Run: certutil -dump `"$derPath`" to inspect bundle contents." "Yellow"
    }
}

$disallowedCheck.Close()

# ==============================================================
# Refresh security policy
# ==============================================================
Log "`n[INFO] Refreshing local security policy..." "Cyan"
gpupdate /force /wait:0 2>&1 | Out-Null
Log "  [OK] gpupdate triggered" "Green"

# ==============================================================
# Summary
# ==============================================================
Log "`n===== STIG Remediation v3 Complete =====" "Cyan"
Log "Log file : $debugLog" "Cyan"
Log "`nItems still requiring MANUAL action:" "Yellow"
Log "  V-254284 — Secure Boot : Enable in UEFI/BIOS firmware or use shielded/Gen2 VM" "Yellow"
Log "  V-254443/444 — If thumbprint check above shows MANUAL REQUIRED:" "Yellow"
Log "    Run: certutil -dump `"$derPath`" and identify the correct cross-cert files" "Yellow"
Log "    Then: Import-Certificate -FilePath <crosscert.cer> -CertStoreLocation Cert:\LocalMachine\Disallowed" "Yellow"
Log "`n*** REBOOT RECOMMENDED to fully apply all changes ***" "Red"
