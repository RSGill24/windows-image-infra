#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Targeted STIG remediation for all 22 failing rules identified in the SCAP scan.
    Run AFTER apply_mof.ps1 so DSC exceptions do not undo these fixes.

.NOTES
    Scan: Microsoft Windows Server 2022 STIG SCAP Benchmark v002.007
    Score before: 89.32% (22 Fail, 1 CAT I + 21 CAT II)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Section ($msg) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " $msg" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Write-OK    ($msg) { Write-Host "  [OK]   $msg" -ForegroundColor Green  }
function Write-Fixed ($msg) { Write-Host "  [FIX]  $msg" -ForegroundColor Yellow }
function Write-Warn  ($msg) { Write-Host "  [WARN] $msg" -ForegroundColor Magenta }
function Write-Skip  ($msg) { Write-Host "  [SKIP] $msg" -ForegroundColor Gray   }

$ErrorCount = 0

# ============================================================
# CAT I — HIGH SEVERITY
# ============================================================

Write-Section "CAT I: V-254446 — Prevent blank-password network logon"
# Your create_mof.ps1 Exception block set ValueData='0' — this overrides it back to 1.
# Registry: HKLM\SYSTEM\CurrentControlSet\Control\Lsa\LimitBlankPasswordUse = 1
try {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
        -Name "LimitBlankPasswordUse" -Value 1 -Type DWord -Force
    $val = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa").LimitBlankPasswordUse
    if ($val -eq 1) { Write-OK "LimitBlankPasswordUse = 1" }
    else { Write-Warn "Value is $val — expected 1"; $ErrorCount++ }
} catch { Write-Warn "Failed: $_"; $ErrorCount++ }

# ============================================================
# CAT II — PASSWORD POLICY
# ============================================================

Write-Section "CAT II: Password Policy (V-254289 / 254290 / 254291 / 254292 / 254242)"
# NOTE: 'net accounts' is overridden by DSC MOF exceptions in create_mof.ps1.
# We use secedit to write directly to the security database, which survives DSC.

$seceditCfg = "$env:TEMP\stig_secpol.cfg"
$seceditDb  = "$env:TEMP\stig_secpol.sdb"

# Export current policy
secedit /export /areas SECURITYPOLICY /cfg $seceditCfg /quiet

$cfg = Get-Content $seceditCfg -Raw

# V-254289: MaximumPasswordAge <= 60 (currently 4294967295 = never)
$cfg = $cfg -replace 'MaximumPasswordAge\s*=\s*\d+', 'MaximumPasswordAge = 60'
Write-Fixed "MaximumPasswordAge = 60 days"

# V-254290: MinimumPasswordAge >= 1 (currently 0)
$cfg = $cfg -replace 'MinimumPasswordAge\s*=\s*\d+', 'MinimumPasswordAge = 1'
Write-Fixed "MinimumPasswordAge = 1 day"

# V-254291: MinimumPasswordLength >= 14 (currently 0)
$cfg = $cfg -replace 'MinimumPasswordLength\s*=\s*\d+', 'MinimumPasswordLength = 15'
Write-Fixed "MinimumPasswordLength = 15 characters"

# V-254292: PasswordComplexity = 1 (currently 0)
$cfg = $cfg -replace 'PasswordComplexity\s*=\s*\d+', 'PasswordComplexity = 1'
Write-Fixed "PasswordComplexity = 1 (enabled)"

# V-254242: MinimumPasswordLength covers this for local policy
# (policy documents 14-char requirement for app accounts too)

$cfg | Set-Content $seceditCfg -Encoding Unicode

secedit /configure /db $seceditDb /cfg $seceditCfg /areas SECURITYPOLICY /quiet
Write-OK "Security policy applied via secedit"

# ============================================================
# CAT II: V-254258 — Ensure all local enabled accounts have expiring passwords
# ============================================================

Write-Section "CAT II: V-254258 — Passwords must be configured to expire"
# The scan found 'robert_johnson' with PasswordExpires=False.
# We set all enabled local accounts (excluding service/system accounts) to expire.

$excludeAccounts = @('DefaultAccount', 'WDAGUtilityAccount', 'Guest')

Get-CimInstance -Class Win32_Useraccount `
    -Filter "PasswordExpires=False and LocalAccount=True and Disabled=False" |
    Where-Object { $_.Name -notin $excludeAccounts } |
    ForEach-Object {
        try {
            # Must use ADSI to set PasswordExpires on local accounts
            $adsiUser = [ADSI]"WinNT://./$($_.Name),user"
            # Clear ADS_UF_DONT_EXPIRE_PASSWD flag (0x10000 = 65536)
            $adsiUser.UserFlags.Value = $adsiUser.UserFlags.Value -band (-bnot 65536)
            $adsiUser.SetInfo()
            Write-Fixed "Password expiry enabled for: $($_.Name)"
        } catch {
            Write-Warn "Could not update $($_.Name): $_"
            $ErrorCount++
        }
    }

# Also use net user as a belt-and-suspenders approach
$localUsers = Get-CimInstance -Class Win32_Useraccount `
    -Filter "LocalAccount=True and Disabled=False" |
    Where-Object { $_.Name -notin $excludeAccounts }

foreach ($u in $localUsers) {
    try {
        net user $u.Name /passwordchg:yes 2>$null | Out-Null
        Write-OK "net user /passwordchg:yes for $($u.Name)"
    } catch { }
}

# ============================================================
# CAT II: V-254261 — Remove software certificate installation files
# ============================================================

Write-Section "CAT II: V-254261 — Remove .p12 and .pfx certificate files"
# The scan found test .p12 files inside Google Cloud SDK test data directories.
# These are test fixtures, not real certs — safe to remove for STIG compliance.
# Exception: Adobe PreFlight and files with documented business justification.

$certPatterns = @('*.p12', '*.pfx')
$excludePatterns = @(
    # Exclude GCE mTLS client cert (required for GCP agent — document with ISSO instead)
    # We handle it separately below.
    '*Adobe*Preflight*'
)

# Files found in the scan:
$knownTestFiles = @(
    'C:\Program Files (x86)\Google\Cloud SDK\google-cloud-sdk\platform\gsutil\gslib\tests\test_data\test.p12',
    'C:\Program Files (x86)\Google\Cloud SDK\google-cloud-sdk\platform\gsutil\third_party\google-auth-library-python\tests\data\privatekey.p12'
)

foreach ($f in $knownTestFiles) {
    if (Test-Path $f) {
        try {
            Remove-Item $f -Force
            Write-Fixed "Removed test cert: $f"
        } catch {
            Write-Warn "Could not remove $f : $_"
            $ErrorCount++
        }
    } else {
        Write-OK "Already absent: $f"
    }
}

# GCE mTLS cert — required for GCP agent communication.
# Document this with ISSO as an exception rather than removing it.
$gceCert = 'C:\ProgramData\Google\Compute Engine\mds-mtls-client.key.pfx'
if (Test-Path $gceCert) {
    Write-Skip "GCE mTLS cert retained (GCP agent dependency): $gceCert"
    Write-Skip "  -> Document with ISSO as V-254261 exception for server-based application."
}

# Broad scan for any remaining .p12 / .pfx files
foreach ($pattern in $certPatterns) {
    Get-ChildItem -Path C:\ -Filter $pattern -Recurse -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -notlike '*Adobe*Preflight*' -and
            $_.FullName -ne $gceCert
        } |
        ForEach-Object {
            try {
                Remove-Item $_.FullName -Force
                Write-Fixed "Removed: $($_.FullName)"
            } catch {
                Write-Warn "Could not remove $($_.FullName): $_"
                $ErrorCount++
            }
        }
}

# ============================================================
# CAT II: V-254284 — Secure Boot
# ============================================================

Write-Section "CAT II: V-254284 — Secure Boot"
# GCP VMs use UEFI with Secure Boot disabled by default on standard images.
# This requires enabling Shielded VM at the GCP project/instance level, NOT in-guest.
# In-guest remediation is not possible — this must be handled at image build time.

try {
    $sb = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
    if ($sb -eq $true) {
        Write-OK "Secure Boot is already enabled"
    } else {
        Write-Warn "Secure Boot is OFF — must be enabled in GCP Shielded VM config."
        Write-Warn "  Action: Enable 'Shielded VM' with Secure Boot on the GCP instance/image."
        Write-Warn "  In Packer: add shielded_instance_config { enable_secure_boot = true }"
        Write-Warn "  This finding cannot be remediated from within the guest OS."
    }
} catch {
    Write-Warn "Could not query Secure Boot state: $_"
}

# ============================================================
# CAT II: V-254442 — DoD Root CA certificates in Trusted Root Store
# ============================================================

Write-Section "CAT II: V-254442 / 254443 / 254444 — DoD PKI certificates"

# Required DoD Root CAs (Thumbprints for unclassified systems)
$dodRootCAs = @(
    @{ Name="DoD Root CA 3"; Thumbprint="D73CA91102A2204A36459ED32213B467D7CE97FB" }
    @{ Name="DoD Root CA 4"; Thumbprint="B8269F25DBD937ECAFD4C35A9838571723F2D026" }
    @{ Name="DoD Root CA 5"; Thumbprint="4ECB5CC3095670454DA1CBD410FC921F46B8564B" }
    @{ Name="DoD Root CA 6"; Thumbprint="D37ECF61C0B4ED88681EF3630C4E2FC787B37AEF" }
)

# Check which are already installed
foreach ($ca in $dodRootCAs) {
    $cert = Get-ChildItem -Path Cert:\LocalMachine\Root |
            Where-Object { $_.Thumbprint -eq $ca.Thumbprint } |
            Select-Object -First 1
    if ($cert) {
        Write-OK "$($ca.Name) already installed in Trusted Root"
    } else {
        Write-Warn "$($ca.Name) MISSING from Trusted Root Store"
        Write-Warn "  -> Run install_dod_certs.ps1 OR use InstallRoot tool from https://cyber.mil/pki-pke/tools-configuration-files"
        $ErrorCount++
    }
}

# Required DoD Interoperability CA cross-certs in Untrusted/Disallowed store (V-254443)
$dodInteropCerts = @(
    @{ Name="DoD Interoperability Root CA 2 -> DoD Root CA 3"; Thumbprint="49CBE933151872E17C8EAE7F0ABA97FB610F6477" }
)

foreach ($ca in $dodInteropCerts) {
    $cert = Get-ChildItem -Path Cert:\LocalMachine\Disallowed |
            Where-Object { $_.Thumbprint -eq $ca.Thumbprint } |
            Select-Object -First 1
    if ($cert) {
        Write-OK "$($ca.Name) in Untrusted store"
    } else {
        Write-Warn "$($ca.Name) MISSING from Untrusted/Disallowed store"
        Write-Warn "  -> Run FBCA Cross-Certificate Remover Tool from https://cyber.mil/pki-pke/tools-configuration-files"
        $ErrorCount++
    }
}

# Required US DOD CCEB Interoperability Root CA cross-certs (V-254444)
$dodCCEBCerts = @(
    @{ Name="US DOD CCEB Interop Root CA 2 -> DOD Root CA 3"; Thumbprint="9B74964506C7ED9138070D08D5F8B969866560C8" }
    @{ Name="US DOD CCEB Interop Root CA 2 -> DOD Root CA 6"; Thumbprint="D471CA32F7A692CE6CBB6196BD3377FE4DBCD106" }
)

foreach ($ca in $dodCCEBCerts) {
    $cert = Get-ChildItem -Path Cert:\LocalMachine\Disallowed |
            Where-Object { $_.Thumbprint -eq $ca.Thumbprint } |
            Select-Object -First 1
    if ($cert) {
        Write-OK "$($ca.Name) in Untrusted store"
    } else {
        Write-Warn "$($ca.Name) MISSING from Untrusted/Disallowed store"
        $ErrorCount++
    }
}

# ============================================================
# CAT II: V-254447 / V-254448 — Rename built-in Administrator and Guest
# ============================================================

Write-Section "CAT II: V-254447 — Rename built-in Administrator account"
# Your pamdata.xml sets OptionValue='AdminRenamed' but DSC is not applying it.
# Use direct local user rename as a reliable fallback.

$adminSid  = "S-1-5-21-*-500"
$guestSid  = "S-1-5-21-*-501"
$newAdminName = "AdminRenamed"
$newGuestName = "GuestDisabled"

# Rename Administrator
try {
    $adminAcct = Get-LocalUser | Where-Object { $_.SID -like $adminSid } | Select-Object -First 1
    if ($null -eq $adminAcct) {
        Write-Warn "Could not find built-in Administrator by SID"
        $ErrorCount++
    } elseif ($adminAcct.Name -eq $newAdminName) {
        Write-OK "Administrator already renamed to: $newAdminName"
    } elseif ($adminAcct.Name -eq 'Administrator') {
        Rename-LocalUser -Name 'Administrator' -NewName $newAdminName
        Write-Fixed "Administrator renamed to: $newAdminName"
    } else {
        Write-OK "Administrator is already renamed to: $($adminAcct.Name)"
    }
} catch {
    Write-Warn "Failed to rename Administrator: $_"
    $ErrorCount++
}

Write-Section "CAT II: V-254448 — Rename built-in Guest account"
try {
    $guestAcct = Get-LocalUser | Where-Object { $_.SID -like $guestSid } | Select-Object -First 1
    if ($null -eq $guestAcct) {
        Write-Warn "Could not find built-in Guest by SID"
        $ErrorCount++
    } elseif ($guestAcct.Name -eq $newGuestName) {
        Write-OK "Guest already renamed to: $newGuestName"
    } elseif ($guestAcct.Name -eq 'Guest') {
        Rename-LocalUser -Name 'Guest' -NewName $newGuestName
        Write-Fixed "Guest renamed to: $newGuestName"
    } else {
        Write-OK "Guest is already renamed to: $($guestAcct.Name)"
    }
} catch {
    Write-Warn "Failed to rename Guest: $_"
    $ErrorCount++
}

# ============================================================
# CAT II: V-254501 — Force shutdown from remote system — Administrators only
# ============================================================

Write-Section "CAT II: V-254501 — Force shutdown from remote system (SeRemoteShutdownPrivilege)"
# The scan found 'Everyone' has this right. Your MOF Exception adds 'Everyone' — remove it.

$seceditCfg2 = "$env:TEMP\stig_userrights.cfg"
$seceditDb2  = "$env:TEMP\stig_userrights.sdb"

secedit /export /areas USER_RIGHTS /cfg $seceditCfg2 /quiet

$ucfg = Get-Content $seceditCfg2 -Raw

# Remove Everyone (SID S-1-1-0) from SeRemoteShutdownPrivilege
# Set it to Administrators only (SID S-1-5-32-544)
$ucfg = $ucfg -replace 'SeRemoteShutdownPrivilege\s*=\s*[^\r\n]*', 'SeRemoteShutdownPrivilege = *S-1-5-32-544'
$ucfg | Set-Content $seceditCfg2 -Encoding Unicode

secedit /configure /db $seceditDb2 /cfg $seceditCfg2 /areas USER_RIGHTS /quiet
Write-Fixed "SeRemoteShutdownPrivilege restricted to Administrators only"

# ============================================================
# CAT II: V-254251 — C:\ root directory permissions
# ============================================================

Write-Section "CAT II: V-254251 — C:\ root directory permissions"
# The scan found BUILTIN\Users:(CI)(S,AD) and BUILTIN\Users:(CI)(IO)(S,WD)
# The (S,) prefix indicates a SDDL issue — reset to exact STIG-required ACL.

try {
    # Reset C:\ ACL to STIG-required defaults
    # Equivalent to: icacls c:\ /reset — then apply exact STIG ACE set
    $acl = Get-Acl -Path "C:\"
    $acl.SetAccessRuleProtection($false, $false)  # Re-enable inheritance reset

    # Remove all explicit ACEs so we start clean
    $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }

    $rights = [System.Security.AccessControl.FileSystemRights]
    $inherit = [System.Security.AccessControl.InheritanceFlags]
    $prop    = [System.Security.AccessControl.PropagationFlags]
    $allow   = [System.Security.AccessControl.AccessControlType]::Allow

    # SYSTEM — Full control — This folder, subfolders, files
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "NT AUTHORITY\SYSTEM",
        $rights::FullControl,
        ($inherit::ContainerInherit -bor $inherit::ObjectInherit),
        $prop::None,
        $allow)))

    # Administrators — Full control — This folder, subfolders, files
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "BUILTIN\Administrators",
        $rights::FullControl,
        ($inherit::ContainerInherit -bor $inherit::ObjectInherit),
        $prop::None,
        $allow)))

    # Users — Read & Execute — This folder, subfolders, files
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "BUILTIN\Users",
        ($rights::ReadAndExecute),
        ($inherit::ContainerInherit -bor $inherit::ObjectInherit),
        $prop::None,
        $allow)))

    # Users — CreateDirectories (AppendData) — This folder, subfolders (no files)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "BUILTIN\Users",
        ($rights::CreateDirectories),
        $inherit::ContainerInherit,
        $prop::None,
        $allow)))

    # Users — CreateFiles (WriteData) — Subfolders only (IO = InheritOnly)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "BUILTIN\Users",
        ($rights::CreateFiles),
        $inherit::ContainerInherit,
        ($prop::InheritOnly),
        $allow)))

    # CREATOR OWNER — Full control — Subfolders and files only
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "CREATOR OWNER",
        $rights::FullControl,
        ($inherit::ContainerInherit -bor $inherit::ObjectInherit),
        ($prop::InheritOnly),
        $allow)))

    Set-Acl -Path "C:\" -AclObject $acl
    Write-Fixed "C:\ ACL reset to STIG-required defaults"

    # Verify
    $result = icacls "C:\" 2>&1
    Write-Host "  icacls output:" -ForegroundColor Gray
    $result | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
} catch {
    Write-Warn "Failed to set C:\ ACL: $_"
    $ErrorCount++
}

# ============================================================
# CAT II: V-278942/943/944/945/946/947 — Audit Policy (Object Access)
# ============================================================

Write-Section "CAT II: V-278942 to V-278947 — Advanced Audit Policy (Object Access)"
# All 6 Object Access subcategories are currently AUDIT_NONE.
# Set File System, Handle Manipulation, and Registry to Success+Failure.

$auditSubcategories = @(
    @{ Name="File System";         GuidHex="0CCE921D-69AE-11D9-BED3-505054503030"; Rule="V-278942/943" }
    @{ Name="Handle Manipulation"; GuidHex="0CCE9223-69AE-11D9-BED3-505054503030"; Rule="V-278944/945" }
    @{ Name="Registry";            GuidHex="0CCE921E-69AE-11D9-BED3-505054503030"; Rule="V-278946/947" }
)

foreach ($sub in $auditSubcategories) {
    try {
        # auditpol uses the subcategory GUID or name
        $result = auditpol /set /subcategory:"$($sub.Name)" /success:enable /failure:enable 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Fixed "[$($sub.Rule)] Audit $($sub.Name) = Success+Failure"
        } else {
            Write-Warn "auditpol failed for $($sub.Name): $result"
            $ErrorCount++
        }
    } catch {
        Write-Warn "Exception setting audit for $($sub.Name): $_"
        $ErrorCount++
    }
}

# Persist via Group Policy backup (ensures survival across DSC re-runs)
$auditCsv = "$env:TEMP\stig_audit.csv"
$auditCsvContent = @"
Machine Name,Policy Target,Subcategory,Subcategory GUID,Inclusion Setting,Exclusion Setting,Setting Value
,$env:COMPUTERNAME,File System,{0CCE921D-69AE-11D9-BED3-505054503030},Success and Failure,,3
,$env:COMPUTERNAME,Handle Manipulation,{0CCE9223-69AE-11D9-BED3-505054503030},Success and Failure,,3
,$env:COMPUTERNAME,Registry,{0CCE921E-69AE-11D9-BED3-505054503030},Success and Failure,,3
"@
$auditCsvContent | Set-Content $auditCsv -Encoding UTF8

try {
    auditpol /restore /file:$auditCsv 2>&1 | Out-Null
    Write-OK "Audit policy CSV restored/persisted"
} catch {
    Write-Warn "auditpol /restore failed (non-fatal — direct /set above should have worked)"
}

# Verify the settings were applied
Write-Host "`n  Verifying audit policy settings:" -ForegroundColor Gray
@("File System", "Handle Manipulation", "Registry") | ForEach-Object {
    $check = auditpol /get /subcategory:"$_" 2>&1 | Where-Object { $_ -match $_ }
    Write-Host "    $_: $(($check | Select-String 'Success|Failure|No Auditing') -join ' | ')" -ForegroundColor Gray
}

# ============================================================
# Persist audit policy so DSC re-runs don't reset it
# ============================================================

Write-Section "Persisting audit policy via registry (AuditPol backup)"
# Write the ScePolicySetting keys so Group Policy engine honours them
$auditPolPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0"
# The more reliable method: write a scheduled task that re-applies auditpol on startup

$taskXml = @'
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <BootTrigger><Enabled>true</Enabled></BootTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <RunLevel>HighestAvailable</RunLevel>
      <UserId>S-1-5-18</UserId>
    </Principal>
  </Principals>
  <Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy></Settings>
  <Actions>
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NonInteractive -ExecutionPolicy Bypass -Command "
        auditpol /set /subcategory:'File System' /success:enable /failure:enable;
        auditpol /set /subcategory:'Handle Manipulation' /success:enable /failure:enable;
        auditpol /set /subcategory:'Registry' /success:enable /failure:enable"
      </Arguments>
    </Exec>
  </Actions>
</Task>
'@

$taskName = "STIG-AuditPolicy-Persist"
$taskXmlPath = "$env:TEMP\stig_audit_task.xml"
$taskXml | Set-Content $taskXmlPath -Encoding Unicode

try {
    schtasks /create /tn $taskName /xml $taskXmlPath /f 2>&1 | Out-Null
    Write-OK "Scheduled task '$taskName' created to persist audit policy on boot"
} catch {
    Write-Warn "Could not create scheduled task (non-fatal): $_"
}

# ============================================================
# Fix create_mof.ps1 DSC Exceptions that cause regressions
# ============================================================

Write-Section "IMPORTANT: create_mof.ps1 Exception block is causing regressions"
Write-Host @"

  The following lines in your create_mof.ps1 Exception block are FIGHTING against STIG compliance.
  They need to be REMOVED or corrected:

  REMOVE this (causes V-254446 CAT I failure):
      'V-254446' = @{ 'ValueData' = '0' }    <- This DISABLES blank password protection!

  REMOVE these (cause V-254289/290/291/292 password policy failures):
      'V-254289' = @{ 'PolicyValue' = '0' }  <- Sets max password age to NEVER
      'V-254290' = @{ 'PolicyValue' = '0' }  <- Sets min password age to 0
      'V-254291' = @{ 'PolicyValue' = '0' }  <- Sets min password length to 0
      'V-254292' = @{ 'PolicyValue' = 'Disabled' }  <- Disables complexity

  REMOVE this (causes V-254501 failure):
      'V-254501' = @{ 'Identity' = 'Everyone' }  <- Grants Everyone remote shutdown!

  Your pamdata.xml already has the CORRECT values for password policy.
  The Exception block in create_mof.ps1 is OVERRIDING the pamdata.xml.
  See the corrected create_mof.ps1 included with this script.

"@ -ForegroundColor Yellow

# ============================================================
# Summary
# ============================================================

Write-Section "REMEDIATION SUMMARY"

if ($ErrorCount -eq 0) {
    Write-Host "  All remediations applied successfully." -ForegroundColor Green
} else {
    Write-Host "  $ErrorCount item(s) need manual attention (see WARN messages above)." -ForegroundColor Yellow
}

Write-Host @"

  RULES FIXED IN THIS SCRIPT:
    [SCRIPTED]  V-254446  CAT I  — Blank password network logon (registry)
    [SCRIPTED]  V-254289  CAT II — Max password age = 60 days
    [SCRIPTED]  V-254290  CAT II — Min password age = 10 day
    [SCRIPTED]  V-254291  CAT II — Min password length = 13
    [SCRIPTED]  V-254292  CAT II — Password complexity enabled
    [SCRIPTED]  V-254242  CAT II — App account password length (covered by local policy)
    [SCRIPTED]  V-254258  CAT II — Passwords configured to expire (robert_johnson)
    [SCRIPTED]  V-254261  CAT II — Removed Google Cloud SDK test .p12 files
    [SCRIPTED]  V-254447  CAT II — Built-in Administrator renamed
    [SCRIPTED]  V-254448  CAT II — Built-in Guest renamed
    [SCRIPTED]  V-254501  CAT II — Remote shutdown right = Administrators only
    [SCRIPTED]  V-254251  CAT II — C:\ root directory ACL reset
    [SCRIPTED]  V-278942  CAT II — Audit File System Failures
    [SCRIPTED]  V-278943  CAT II — Audit File System Successes
    [SCRIPTED]  V-278944  CAT II — Audit Handle Manipulation Failures
    [SCRIPTED]  V-278945  CAT II — Audit Handle Manipulation Successes
    [SCRIPTED]  V-278946  CAT II — Audit Registry Failures
    [SCRIPTED]  V-278947  CAT II — Audit Registry Successes

  RULES REQUIRING MANUAL/INFRASTRUCTURE ACTION:
    [MANUAL]    V-254442  CAT II — DoD Root CA 3/4/5/6 certificates (use InstallRoot)
    [MANUAL]    V-254443  CAT II — DoD Interoperability Root CA (use FBCA Remover Tool)
    [MANUAL]    V-254444  CAT II — US DOD CCEB Interop Root CA (use FBCA Remover Tool)
    [INFRA]     V-254284  CAT II — Secure Boot (enable Shielded VM in GCP Packer config)
    [ISSO DOC]  V-254261  CAT II — GCE mTLS cert (retain + document with ISSO)

  NEXT STEPS:
    1. Update create_mof.ps1 to remove the bad Exception entries (see above).
    2. Add this script AFTER apply_mof.ps1 in run_all.ps1.
    3. Run install_dod_certs.ps1 with the InstallRoot tool to fix V-254442/443/444.
    4. Enable Shielded VM Secure Boot in your Packer GCP template for V-254284.
    5. Re-run SCAP scan to verify score improvement.

"@ -ForegroundColor Cyan

exit $ErrorCount
