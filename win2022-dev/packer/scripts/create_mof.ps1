# create_mof.ps1
# Compiles a DSC MOF using PowerSTIG.
#
# FIX: Removed all Exception entries that caused STIG regressions:
#   - V-254446 ValueData='0'         was DISABLING blank-password protection (CAT I!)
#   - V-254289 PolicyValue='0'       was setting max password age to NEVER
#   - V-254290 PolicyValue='0'       was setting min password age to 0
#   - V-254291 PolicyValue='0'       was setting min password length to 0
#   - V-254292 PolicyValue='Disabled' was disabling password complexity
#   - V-254501 Identity='Everyone'   was granting Everyone remote shutdown right
#
# FIX: Added V-254289 through V-254293 (all AccountPolicy rules) to SkipRule.
#   FIX: Added V-254285 through V-254288 (lockout policy rules) to SkipRule.
#   FIX: Added V-254445 and V-254465 (SecurityOption rules) to SkipRule.
#        SecurityOption DSC resource also writes to the SCE database and breaks
#        WinRM mid-session exactly like AccountPolicy. Both handled by
#        stig_remediation_fixes.ps1 after all uploads are complete.
#   AccountPolicy DSC resource writes to the SCE security database during
#   Start-DscConfiguration, which causes Windows to re-enforce GPO-derived
#   WinRM restrictions mid-session -- breaking Packer's WinRM connection before
#   subsequent provisioners can run. These rules are handled exclusively by
#   account_policy.ps1 which runs after all file uploads are complete.
#
# Only ISSO-approved exceptions remain: V-254439 and V-254435 (Guests group).
# All password/lockout policy values are driven by the org.pamdata.xml file.

Write-Host "=== create_mof.ps1 starting ==="

# -----------------------------------------------------------------------
# PRE-COMPILATION CIM CONFLICT CLEANUP
# Aggressively destroys out-of-band DSC modules baked into System32.
# If these exist alongside the Program Files copies, DSC compilation fails.
# -----------------------------------------------------------------------
Write-Host "--- Scanning for duplicate System32 modules ---"
$sys32Dsc = "C:\Windows\system32\WindowsPowerShell\v1.0\Modules"
$conflictingModules = @(
    "AuditPolicyDsc",
    "GPRegistryPolicyDsc",
    "PSDscResources",
    "WindowsDefenderDsc",
    "SecurityPolicyDsc",
    "AuditSystemDsc",
    "CertificateDsc",
    "PowerSTIG"
)

foreach ($mod in $conflictingModules) {
    $badPath = Join-Path $sys32Dsc $mod
    if (Test-Path $badPath) {
        Write-Host "  [!] Found conflict. Force deleting: $badPath" -ForegroundColor Yellow

        # Strip TrustedInstaller protections using native Windows tools
        takeown.exe /F $badPath /R /D Y | Out-Null
        icacls.exe $badPath /grant "Administrators:(OI)(CI)F" /T /Q | Out-Null

        # Nuke the folder
        Remove-Item -Path $badPath -Recurse -Force -ErrorAction SilentlyContinue

        if (Test-Path $badPath) {
            Write-Warning "  FAILED to delete $badPath. CIM conflicts may occur."
        } else {
            Write-Host "  Successfully removed $badPath" -ForegroundColor Green
        }
    }
}
Write-Host "--- Cleanup complete ---"

# -----------------------------------------------------------------------
# Ensuring all module paths are in PSModulePath
# -----------------------------------------------------------------------
$requiredPaths = @(
    "C:\Program Files\WindowsPowerShell\Modules",
    "C:\Windows\system32\WindowsPowerShell\v1.0\Modules",
    "C:\Program Files (x86)\WindowsPowerShell\Modules"
)
foreach ($p in $requiredPaths) {
    if ($p -and ($env:PSModulePath -split ';') -notcontains $p) {
        Write-Host "Adding to PSModulePath: $p"
        $env:PSModulePath = "$p;$env:PSModulePath"
    }
}

# -----------------------------------------------------------------------
# Detecting latest PowerSTIG module
# -----------------------------------------------------------------------
$module = Get-Module PowerSTIG -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
if (-not $module) {
    Write-Error "PowerSTIG module not found. Ensure install_PowerSTIG.ps1 ran successfully."
    exit 1
}
$pstigVersion = $module.Version.ToString()
Write-Host "Found PowerSTIG module $pstigVersion at: $($module.ModuleBase)"

# -----------------------------------------------------------------------
# Detecting STIG XML and parse version
# -----------------------------------------------------------------------
$stigDataPath = Join-Path $module.ModuleBase "StigData\Processed"
$stigXml = Get-ChildItem -Path $stigDataPath -Filter "WindowsServer-2025-MS-*.org.default.xml" |
           Sort-Object Name -Descending | Select-Object -First 1
if (-not $stigXml) {
    Write-Error "No WindowsServer-2025-MS-*.org.default.xml found in $stigDataPath"
    exit 1
}
$stigVersionString = ($stigXml.Name -replace 'WindowsServer-2025-MS-', '' -replace '\.org\.default\.xml', '')
Write-Host "Detected STIG XML: $($stigXml.FullName)"
Write-Host "Detected STIG version: $stigVersionString"

# -----------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------
$HardeningDir = $PSScriptRoot
$OutputPath   = Join-Path $HardeningDir "MOF"
$OrgSettings  = Join-Path $HardeningDir ($stigXml.Name -replace '\.org\.default\.xml', '.org.pamdata.xml')

if (!(Test-Path $OrgSettings)) {
    Write-Warning "PAM org settings not found at $OrgSettings -- falling back to default XML"
    $OrgSettings = $stigXml.FullName
}
Write-Host "Using OrgSettings: $OrgSettings"

if (!(Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    Write-Host "Created MOF output directory: $OutputPath"
}

# -----------------------------------------------------------------------
# Verify DSC resource is available
# -----------------------------------------------------------------------
Import-Module -Name PowerSTIG -RequiredVersion $pstigVersion -Force
try {
    $dscCheck = Get-DscResource -Name WindowsServer -Module PowerSTIG -ErrorAction Stop
    Write-Host "DSC resource confirmed: $($dscCheck.Name) from $($dscCheck.Module)"
} catch {
    Write-Error "WindowsServer DSC resource not found: $_"
    exit 1
}

# -----------------------------------------------------------------------
# Generate temporary DSC configuration script
# -----------------------------------------------------------------------
# -----------------------------------------------------------------------
# Build the DSC skip list FROM the 2025 STIG content, not from a hardcoded
# V-ID table.
#
# WHY: this file previously listed 25 hardcoded V-254xxx (Server 2022) IDs in
# SkipRule. The build targets Server 2025, whose STIG uses V-278xxx/V-285xxx,
# so every one of those entries matched nothing. Nothing was actually skipped --
# in particular the six WinRM rules were applied by DSC mid-build, which severs
# Packer's own WinRM session. Deriving the list from the installed STIG content
# cannot go stale the next time DISA renumbers.
# -----------------------------------------------------------------------
Write-Host "`n--- Deriving skip list from $($stigXml.Name) ---"

$ruleContentFile = Get-ChildItem -Path $stigDataPath -Filter "WindowsServer-2025-MS-*.xml" -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -notmatch '\.org\.' } |
                   Sort-Object Name -Descending |
                   Select-Object -First 1

if (-not $ruleContentFile) {
    Write-Error "No WindowsServer-2025-MS-*.xml rule content found in $stigDataPath"
    exit 1
}
Write-Host "Rule content: $($ruleContentFile.Name)"

[xml]$ruleXml = Get-Content -Path $ruleContentFile.FullName -Raw -Encoding UTF8

$dynamicSkips = New-Object System.Collections.Generic.List[string]

# --- WinRM registry rules -------------------------------------------------
# Matched by KEY PATH, not by V-ID. Applying any of these disables Basic auth
# or unencrypted traffic on the live WinRM listener and kills the build.
# Excluded from the image at the caller's direction; applied via domain GPO at
# first boot instead.
foreach ($r in $ruleXml.SelectNodes('//RegistryRule/Rule')) {
    $k = $r.SelectSingleNode('Key')
    if ($null -ne $k -and $k.InnerText -match '\\WinRM\\(Client|Service)|\\WSMAN\\') {
        $dynamicSkips.Add($r.GetAttribute('id')) | Out-Null
    }
}
Write-Host "  WinRM rules skipped:            $($dynamicSkips.Count)"

# --- SecurityOption rules that write the SCE database ---------------------
# SecurityOptionDsc writes through the Security Configuration Engine, which
# re-enforces GPO-derived WinRM restrictions mid-apply -- the same failure mode
# as AccountPolicy. These two are re-applied by account_policy.ps1 afterwards.
$sceCount = 0
foreach ($r in $ruleXml.SelectNodes('//SecurityOptionRule/Rule')) {
    $on = $r.SelectSingleNode('OptionName')
    if ($null -ne $on -and $on.InnerText -match 'LAN Manager authentication level|LDAP client signing') {
        $dynamicSkips.Add($r.GetAttribute('id')) | Out-Null
        $sceCount++
    }
}
Write-Host "  SCE-writing SecurityOptions:    $sceCount"

# --- Certificate rules ----------------------------------------------------
# install_dod_certs.ps1 owns the certificate stores. Letting DSC also manage
# them causes it to reach for DISA InstallRoot content that is not present in
# the build environment, and the resource blocks.
$certCount = 0
# NOTE: the node is RootCertificateRule, not CertificateRule. The VM run proved
# this: with 'CertificateRule' the derivation reported "Certificate rules
# skipped: 0" while the 2025 STIG actually carries 9 RootCertificateRule
# entries, so DSC was still managing the certificate stores.
foreach ($r in $ruleXml.SelectNodes('//RootCertificateRule/Rule')) {
    $dynamicSkips.Add($r.GetAttribute('id')) | Out-Null
    $certCount++
}
Write-Host "  Certificate rules skipped:      $certCount"

# --- OpenSSH rules --------------------------------------------------------
# sshd is not installed by this pipeline and no script configures it, so DSC
# would either fail these or apply settings to a service that does not exist.
# Excluded from the image at the caller's direction; applied by domain GPO.
# Matched by V-ID *and* by title, so a renumbered OpenSSH rule is still caught.
$sshVids = @(
    'V-285313','V-285314','V-285315','V-285316','V-285317','V-285318',
    'V-285319','V-285320','V-285321','V-285322','V-285323'
)
$sshCount = 0
foreach ($r in $ruleXml.SelectNodes('//Rule')) {
    $rid = $r.GetAttribute('id')
    if (-not $rid) { continue }
    $rbase = ($rid -split '\.')[0]

    $isSsh = $sshVids -contains $rbase
    if (-not $isSsh) {
        $t = $r.SelectSingleNode('Title')
        if ($null -ne $t -and $t.InnerText -match 'OpenSSH|sshd') { $isSsh = $true }
    }
    if ($isSsh) {
        $dynamicSkips.Add($rid) | Out-Null
        $sshCount++
    }
}
Write-Host "  OpenSSH rules skipped:          $sshCount"

# --- Rule CLASSES to exclude ---------------------------------------------
# AccountPolicyRule / AuditPolicyRule / UserRightRule all write through
# secedit/auditpol into the local security database. The SCE write re-enforces
# GPO-derived WinRM restrictions mid-apply and drops Packer's connection; and
# local user-rights / advanced-audit settings do not survive image capture
# anyway, so they must come from a domain GPO at first boot.
$skipTypes = @('AccountPolicyRule','AuditPolicyRule','UserRightRule')

# PowerSTIG exposes SkipRuleType on its composite resources, but the parameter
# has not existed in every release. Probe for it rather than assuming: if it is
# absent, expand the classes into individual V-IDs so the same rules are still
# excluded instead of the compile failing on an unknown property.
$supportsSkipRuleType = @($dscCheck.Properties | ForEach-Object { $_.Name }) -contains 'SkipRuleType'

if ($supportsSkipRuleType) {
    Write-Host "  SkipRuleType supported:         yes"
    $skipRuleTypeLiteral = ($skipTypes | ForEach-Object { "                '$_'" }) -join ",`r`n"
} else {
    Write-Host "  SkipRuleType supported:         NO - expanding classes into individual V-IDs" -ForegroundColor Yellow
    $expanded = 0
    foreach ($t in $skipTypes) {
        foreach ($r in $ruleXml.SelectNodes("//$t/Rule")) {
            $dynamicSkips.Add($r.GetAttribute('id')) | Out-Null
            $expanded++
        }
    }
    Write-Host "  Class rules expanded:           $expanded"
    $skipRuleTypeLiteral = $null
}

$dynamicSkips = @($dynamicSkips | Where-Object { $_ } | Sort-Object -Unique)

if ($dynamicSkips.Count -eq 0) {
    Write-Warning "Derived skip list is EMPTY. Expected at least the WinRM rules."
    Write-Warning "If the build hangs at ~40s with no provisioner output, this is why."
}

# Rendered into the generated configuration below.
$skipRuleLiteral = ($dynamicSkips | ForEach-Object { "                '$_'" }) -join ",`r`n"

Write-Host "  TOTAL individual SkipRule IDs:  $($dynamicSkips.Count)"
Write-Host "  Rule TYPES skipped wholesale:   AccountPolicyRule, AuditPolicyRule, UserRightRule"

# Render the SkipRuleType property only when the installed PowerSTIG supports it.
if ($skipRuleTypeLiteral) {
    $skipRuleTypeBlock = @"
            SkipRuleType = @(
$skipRuleTypeLiteral
            )
"@
} else {
    $skipRuleTypeBlock = "            # SkipRuleType unsupported by this PowerSTIG build --`r`n" +
                         "            # those classes were expanded into SkipRule below."
}

$tempScript = Join-Path $env:TEMP "dsc_config_generated.ps1"

$safeOutputPath  = $OutputPath  -replace "'", "''"
$safeOrgSettings = $OrgSettings -replace "'", "''"

$scriptContent = @"
Configuration ApplyWindowsServerStig {
    Import-DscResource -ModuleName PowerSTIG -ModuleVersion $pstigVersion

    Node 'localhost' {
        WindowsServer 'ConfigureServer' {
            OsVersion   = '2025'
            OsRole      = 'MS'
            StigVersion = '$stigVersionString'
            OrgSettings = '$safeOrgSettings'

            # NOTE: this file is GENERATED by create_mof.ps1. Do not edit it and
            # do not hardcode V-IDs into it. Both lists below are derived from
            # the installed Server 2025 STIG content; see create_mof.ps1 for why.

            # Rule classes excluded from the image (secedit/auditpol writers).
$skipRuleTypeBlock

            # Individual rules excluded: WinRM, SCE-writing security options,
            # and certificate rules.
            SkipRule = @(
$skipRuleLiteral
            )
        }
    }
}

ApplyWindowsServerStig -OutputPath '$safeOutputPath'
"@

Set-Content -Path $tempScript -Value $scriptContent -Encoding UTF8
Write-Host "Generated temporary DSC config script: $tempScript"

# -----------------------------------------------------------------------
# Spawn a fresh PowerShell process to compile the MOF.
# A new process avoids CIM class caching issues from the current session.
# -----------------------------------------------------------------------
Write-Host "=== Generating MOF... ==="
$result = Start-Process powershell `
    -ArgumentList "-ExecutionPolicy Bypass -NonInteractive -File `"$tempScript`"" `
    -Wait `
    -PassThru `
    -NoNewWindow

if ($result.ExitCode -ne 0) {
    Write-Error "DSC configuration compilation failed with exit code $($result.ExitCode)"
    exit $result.ExitCode
}

# -----------------------------------------------------------------------
# Verify MOF was created
# -----------------------------------------------------------------------
$mofFile = Join-Path $OutputPath "localhost.mof"
if (!(Test-Path $mofFile)) {
    Write-Error "MOF file was not generated at: $mofFile"
    exit 1
}

$mofSize = (Get-Item $mofFile).Length
Write-Host "MOF generated: $mofFile (size: $mofSize bytes)"

if ($mofSize -lt 50000) {
    Write-Warning "MOF file is unusually small ($mofSize bytes). Expected > 50 KB."
    Write-Warning "This may indicate that many STIG rules were skipped or the compilation was incomplete."
}

# -----------------------------------------------------------------------
# Confirm AccountPolicy rules are absent from the compiled MOF.
# If any appear, SkipRule did not take effect -- abort before apply_mof.ps1
# runs and breaks WinRM.
# -----------------------------------------------------------------------
Write-Host "Verifying SCE-writing resources are excluded from MOF..."
$sceHits = Select-String -Path $mofFile -Pattern "AccountPolicy|SecurityOption" -SimpleMatch

# The WinRM check is the one that actually protects the build: if a WinRM key
# reached the MOF, applying it will sever Packer's session and the instance is
# torn down with the provisioner still running. Fail here instead.
$winrmHits = Select-String -Path $mofFile -Pattern "WinRM\\\\Client|WinRM\\\\Service|WSMAN"
if ($winrmHits) {
    Write-Error "WinRM registry rules found in the compiled MOF. Applying them would"
    Write-Error "kill Packer's WinRM session mid-build. The derived SkipRule list did not"
    Write-Error "cover them. Aborting before apply_mof.ps1 runs."
    $winrmHits | Select-Object -First 10 | ForEach-Object { Write-Error "  $($_.Line.Trim())" }
    exit 1
}
Write-Host "  [OK] No WinRM rules in MOF - Packer session is safe." -ForegroundColor Green

if ($sceHits) {
    Write-Error "SCE-writing resources (AccountPolicy or SecurityOption) found in compiled MOF."
    Write-Error "DSC apply would break WinRM. Aborting. Check SkipRule entries in this script."
    Write-Error "Matching lines:"
    $sceHits | ForEach-Object { Write-Error "  $($_.Line.Trim())" }
    exit 1
}
Write-Host "  [OK] No SCE-writing resources in MOF -- safe to apply." -ForegroundColor Green

Write-Host "=== DSC configuration compiled successfully ==="
exit 0
