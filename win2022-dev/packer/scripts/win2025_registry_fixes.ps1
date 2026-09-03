#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies every Windows Server 2025 STIG *registry* rule directly to the
    registry, without DSC, and verifies each write by reading it back.

.DESCRIPTION
    WHY THIS SCRIPT EXISTS
    ----------------------
    The hardening layer in this repo was authored against the Windows Server
    2022 STIG (V-254xxx). The pipeline now builds and scans Windows Server 2025,
    whose STIG uses a completely different V-ID range (V-278xxx / V-279xxx /
    V-285xxx). Every hardcoded 2022 V-ID in create_mof.ps1, install_dsc_deps.ps1
    and the pamdata XML silently matched nothing, so:
      * DSC SkipRule entries were no-ops (WinRM rules applied and killed Packer)
      * organizational value overrides never applied
      * only settings that coincidentally share a registry key with a 2025 rule
        passed the SCC scan

    Rather than replace one hardcoded V-ID table with another (which goes stale
    the next time DISA renumbers), this script reads the AUTHORITATIVE source:
    the processed STIG XML that PowerSTIG ships inside its own module. That XML
    is the same content DISA SCC scans against, so the Key / ValueName /
    ValueType / ValueData applied here are correct by construction and stay
    correct across STIG releases.

    WHAT IT APPLIES
    ---------------
    Only <RegistryRule> entries. Rule classes that cannot persist in a captured
    image, or that would break the build, are excluded by design (see EXCLUSIONS
    below). User rights, advanced audit policy, and certificate rules are not
    RegistryRule types at all, so they are excluded structurally, not by list.

    WHY NOT RELY ON DSC
    -------------------
    This runs independently of DSC/CIM/MOF. A DSC apply that partially fails
    (CIM class conflicts, WinRM drop mid-apply, LCM timeouts) leaves the image
    largely unhardened with no clear signal. This script is a deterministic
    backstop: it either sets the value and proves it by read-back, or it reports
    the failure per rule.

.PARAMETER SkipFips
    Do not apply the FIPS algorithm policy rule. FIPS mode changes SChannel and
    .NET crypto behaviour; if a build ever dies immediately after the FIPS line,
    re-run with this switch to confirm the cause.

.PARAMETER AdditionalSkipRules
    Extra V-IDs to exclude, on top of the built-in exclusions.

.PARAMETER ExpectedRuleList
    Optional path to a text/CSV file whose first column holds V-IDs that MUST be
    covered. Any listed ID not applied is reported at the end. Used to catch
    silent drift between the remediation estimate and what the STIG XML holds.

.NOTES
    Must run AFTER install_PowerSTIG.ps1 (needs the module's StigData).
    Must run AFTER apply_mof.ps1 so DSC cannot overwrite these values.
    Runs after every other registry writer so its values are the ones captured.
    repair_winrm_for_packer.ps1 is uploaded but not invoked - nothing in this
    pipeline touches WinRM, so there is nothing for it to repair.
#>

[CmdletBinding()]
param(
    [switch]  $SkipFips,
    [string[]]$AdditionalSkipRules = @(),
    [string]  $ExpectedRuleList
)

# Deliberately NOT using Set-StrictMode -Version Latest: this script walks XML
# nodes whose optional child elements are absent on many rules, and StrictMode
# turns every absent-property read into a terminating error.
$ErrorActionPreference = 'Continue'

function Write-Section { param([string]$m)
    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host " $m" -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan
}
function Write-OK   { param([string]$m) Write-Host "  [OK]   $m" -ForegroundColor Green   }
function Write-Fix  { param([string]$m) Write-Host "  [FIX]  $m" -ForegroundColor Yellow  }
function Write-Warn { param([string]$m) Write-Host "  [WARN] $m" -ForegroundColor Magenta }
function Write-Skip { param([string]$m) Write-Host "  [SKIP] $m" -ForegroundColor Gray    }
function Write-Bad  { param([string]$m) Write-Host "  [FAIL] $m" -ForegroundColor Red     }

Write-Section "Windows Server 2025 STIG - direct registry remediation"

# =======================================================================
# EXCLUSIONS
# =======================================================================
# Excluded at the caller's direction (applied via domain GPO at first boot
# instead of being baked into the image):
#
#   WinRM         V-278125..V-278130 - disabling Basic auth / unencrypted
#                 traffic mid-build severs Packer's own WinRM session and the
#                 instance is torn down with the provisioner still running.
#                 ALSO enforced below by a key-path guard so a renumbered STIG
#                 cannot reintroduce them under new V-IDs.
#   User rights   Not RegistryRule (UserRightRule) - excluded structurally.
#                 They also do not persist through image capture without a GPO.
#   Audit policy  Not RegistryRule (AuditPolicyRule) - excluded structurally.
#   DoD certs     Not RegistryRule (CertificateRule) - excluded structurally.
#                 install_dod_certs.ps1 owns the cert store work.
#   OpenSSH       V-285313..V-285323 - sshd is not installed by this pipeline;
#                 owned by openssh_stig.ps1, which is not wired in by default.
# =======================================================================

$WinRmRules = @('V-278125','V-278126','V-278127','V-278128','V-278129','V-278130')

$SshRules = @(
    'V-285313','V-285314','V-285315','V-285316','V-285317','V-285318',
    'V-285319','V-285320','V-285321','V-285322','V-285323'
)

# Certificate rules that are expressed as registry rules in some STIG releases.
$CertRules = @('V-278192','V-278193','V-278194')

$FipsRules = @('V-278230')

# Rules that PowerSTIG ships with NO ValueData, NO OrganizationValueTestString
# and no OrganizationValueRequired flag -- nothing can be derived from the
# benchmark, so the rule would be reported unresolved and left unwritten.
# Verified against PowerSTIG 4.30.0 / WindowsServer-2025-MS-1.1 on a live build.
# Organizational values where PowerSTIG's own bound is LOWER than what DISA SCC
# actually enforces. These take precedence over the pamdata XML and over any
# value derived from OrganizationValueTestString.
#
# Discovered by scanning a built image with SCC: the rule was applied, reported
# "already compliant" against PowerSTIG's bound, and STILL failed the scan.
$OrgValueOverrides = @{
    # V-278106 Security event log must hold at least one week of audit records.
    # PowerSTIG ships OrganizationValueTestString "'{0}' -ge '196608'", so 196608
    # satisfies PowerSTIG but SCC fails it. A larger value satisfies any -ge bound,
    # and 5 GB on the 250 GB image disk is not a meaningful cost.
    'V-278106' = '5120000'
}

$FallbackValues = @{
    # V-278103 Windows Telemetry must be Security (0) or Basic (1).
    # 0 = Security is the DoD-appropriate setting for a non-Enterprise SKU.
    'V-278103' = '0'
}

$SkipRules = @($WinRmRules + $SshRules + $CertRules + $AdditionalSkipRules) |
             Where-Object { $_ } | Sort-Object -Unique

if ($SkipFips) { $SkipRules = @($SkipRules + $FipsRules) | Sort-Object -Unique }

# Key-path guard. Independent of V-ID numbering: any rule whose registry key
# matches one of these patterns is refused no matter what it is called. This is
# the safety net that the old hardcoded V-254xxx SkipRule list failed to be.
$ForbiddenKeyPatterns = @(
    '\\WinRM\\Client',
    '\\WinRM\\Service',
    '\\WSMAN\\'
)

Write-Host "  Excluded V-IDs      : $($SkipRules.Count)"
Write-Host "  Forbidden key paths : $($ForbiddenKeyPatterns -join ', ')"
Write-Host "  FIPS rule           : $(if ($SkipFips) { 'SKIPPED (-SkipFips)' } else { 'applied last' })"

# =======================================================================
# STEP 1 - Locate the processed Server 2025 STIG XML shipped by PowerSTIG
# =======================================================================
Write-Section "STEP 1: Locate authoritative Server 2025 STIG content"

$module = Get-Module PowerSTIG -ListAvailable |
          Sort-Object Version -Descending |
          Select-Object -First 1

if (-not $module) {
    Write-Bad "PowerSTIG module not found. install_PowerSTIG.ps1 must run first."
    exit 1
}
Write-OK "PowerSTIG $($module.Version) at $($module.ModuleBase)"

$stigDataPath = Join-Path $module.ModuleBase 'StigData\Processed'
if (-not (Test-Path $stigDataPath)) {
    Write-Bad "StigData\Processed not found under $($module.ModuleBase)"
    exit 1
}

# Match the rule content file, not the .org.default.xml companion.
$stigXmlFile = Get-ChildItem -Path $stigDataPath -Filter 'WindowsServer-2025-MS-*.xml' -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -notmatch '\.org\.' } |
               Sort-Object Name -Descending |
               Select-Object -First 1

if (-not $stigXmlFile) {
    Write-Bad "No WindowsServer-2025-MS-*.xml found in $stigDataPath"
    Write-Bad "The installed PowerSTIG version has no Server 2025 content. Cannot proceed."
    Write-Host "  Files present:" -ForegroundColor Gray
    Get-ChildItem -Path $stigDataPath -Filter 'WindowsServer-*' |
        Select-Object -First 25 |
        ForEach-Object { Write-Host "    $($_.Name)" -ForegroundColor Gray }
    exit 1
}
Write-OK "STIG content: $($stigXmlFile.Name)"

try {
    [xml]$stig = Get-Content -Path $stigXmlFile.FullName -Raw -Encoding UTF8
} catch {
    Write-Bad "Failed to parse $($stigXmlFile.FullName): $_"
    exit 1
}

$registryRules = @($stig.SelectNodes('//RegistryRule/Rule'))
if ($registryRules.Count -eq 0) {
    Write-Bad "No <RegistryRule>/<Rule> nodes found. Unexpected XML shape - aborting."
    exit 1
}
Write-OK "Registry rules found in STIG content: $($registryRules.Count)"

# =======================================================================
# STEP 2 - Organizational values
# =======================================================================
# Rules with OrganizationValueRequired='True' carry no literal ValueData. The
# required value comes from the org settings XML, or - when that is missing an
# entry - can be derived from OrganizationValueTestString, which is a PowerShell
# comparison template such as "'{0}' -ge '32768'". Deriving from the test string
# is what makes event-log sizing and timeout rules pass without a hand-maintained
# table, and it is exactly the bound SCC tests against.
# =======================================================================
Write-Section "STEP 2: Resolve organizational values"

$orgValues = @{}

$orgXmlFile = Get-ChildItem -Path $PSScriptRoot -Filter 'WindowsServer-2025-MS-*.org.pamdata.xml' -ErrorAction SilentlyContinue |
              Sort-Object Name -Descending |
              Select-Object -First 1

if ($orgXmlFile) {
    try {
        [xml]$orgXml = Get-Content -Path $orgXmlFile.FullName -Raw -Encoding UTF8
        foreach ($node in $orgXml.SelectNodes('//OrganizationalSetting')) {
            $id = $node.GetAttribute('id')
            $vd = $node.GetAttribute('ValueData')
            if ($id -and $vd -ne '') { $orgValues[$id] = $vd }
        }
        Write-OK "Loaded $($orgValues.Count) org values from $($orgXmlFile.Name)"

        $stale = @($orgValues.Keys | Where-Object { $_ -like 'V-254*' })
        if ($stale.Count -gt 0) {
            Write-Warn "$($stale.Count) org values use Server 2022 V-IDs and match nothing in the 2025 STIG."
            Write-Warn "They are ignored here; values are derived from the STIG test strings instead."
        }
    } catch {
        Write-Warn "Could not parse $($orgXmlFile.Name): $_ - deriving all org values from test strings."
    }
} else {
    Write-Warn "No *.org.pamdata.xml in $PSScriptRoot - deriving all org values from test strings."
}

function Resolve-OrgValue {
    <#
        Derives the value that satisfies a PowerSTIG OrganizationValueTestString.
        Templates seen in Windows STIG content:
            "'{0}' -ge '32768'"          -> 32768   (minimum: meet the bound exactly)
            "'{0}' -le '900'"            -> 900     (maximum: meet the bound exactly)
            "'{0}' -eq '1'"              -> 1
            "{0} -ge 1 -and {0} -le 30"  -> 1       (first satisfying bound)
        Returns $null when nothing can be derived, so the caller can skip loudly
        rather than write a wrong value.
    #>
    param([string]$TestString)

    if ([string]::IsNullOrWhiteSpace($TestString)) { return $null }

    # -eq is unambiguous, so prefer it.
    if ($TestString -match "-eq\s+'?([^'\s]+)'?") { return $Matches[1] }
    # For a minimum bound, the bound itself is compliant.
    if ($TestString -match "-ge\s+'?([^'\s]+)'?") { return $Matches[1] }
    # For a maximum bound, the bound itself is compliant.
    if ($TestString -match "-le\s+'?([^'\s]+)'?") { return $Matches[1] }
    # Strict bounds need a step; only meaningful for integers.
    if ($TestString -match "-gt\s+'?(-?\d+)'?")   { return ([int]$Matches[1] + 1).ToString() }
    if ($TestString -match "-lt\s+'?(-?\d+)'?")   { return ([int]$Matches[1] - 1).ToString() }

    return $null
}

# =======================================================================
# STEP 3 - Apply
# =======================================================================
Write-Section "STEP 3: Apply registry rules"

# PowerSTIG ValueType spellings -> Set-ItemProperty -Type values.
# PowerShell hashtable keys are case-insensitive, so a single spelling covers
# every casing PowerSTIG uses ('Dword', 'DWord', 'DWORD' all resolve here).
$TypeMap = @{
    'Dword'             = 'DWord'
    'Qword'             = 'QWord'
    'String'            = 'String'
    'MultiString'       = 'MultiString'
    'ExpandableString'  = 'ExpandString'
    'ExpandString'      = 'ExpandString'
    'Binary'            = 'Binary'
}

function ConvertTo-PsRegistryPath {
    param([string]$Key)
    if ([string]::IsNullOrWhiteSpace($Key)) { return $null }
    $p = $Key.Trim()
    $p = $p -replace '^HKEY_LOCAL_MACHINE\\', 'HKLM:\'
    $p = $p -replace '^HKEY_CURRENT_USER\\',  'HKCU:\'
    $p = $p -replace '^HKEY_USERS\\',         'HKU:\'
    $p = $p -replace '^HKEY_CLASSES_ROOT\\',  'HKCR:\'
    $p = $p -replace '^HKLM\\',               'HKLM:\'
    if ($p -notmatch '^HK[A-Z]{2,3}:\\') { return $null }
    return $p
}

function Get-NodeText {
    param($Node, [string]$Name)
    $child = $Node.SelectSingleNode($Name)
    if ($null -eq $child) { return $null }
    return $child.InnerText
}

$applied     = New-Object System.Collections.Generic.List[string]
$alreadyOk   = New-Object System.Collections.Generic.List[string]
$failed      = New-Object System.Collections.Generic.List[string]
$skipped     = New-Object System.Collections.Generic.List[string]
$unresolved  = New-Object System.Collections.Generic.List[string]

# FIPS is applied last: it changes SChannel/.NET crypto behaviour, and if it
# ever does destabilise the build, everything else is already written.
$ordered = @(
    @($registryRules | Where-Object { $FipsRules -notcontains $_.GetAttribute('id') })
    @($registryRules | Where-Object { $FipsRules -contains    $_.GetAttribute('id') })
)

foreach ($rule in $ordered) {

    $vid = $rule.GetAttribute('id')
    if (-not $vid) { continue }

    # PowerSTIG splits some rules into V-xxxxxx.a / .b variants; the base ID is
    # what the exclusion lists are written in terms of.
    $baseVid = ($vid -split '\.')[0]

    $title    = Get-NodeText $rule 'Title'
    $severity = $rule.GetAttribute('severity')
    $label    = "$vid [$severity]"

    if ($SkipRules -contains $vid -or $SkipRules -contains $baseVid) {
        Write-Skip "$label - excluded by policy (GPO/first-boot or out of scope)"
        $skipped.Add($vid) | Out-Null
        continue
    }

    $rawKey = Get-NodeText $rule 'Key'
    $path   = ConvertTo-PsRegistryPath $rawKey
    if (-not $path) {
        Write-Warn "$label - unusable registry key '$rawKey'"
        $unresolved.Add($vid) | Out-Null
        continue
    }

    foreach ($pattern in $ForbiddenKeyPatterns) {
        if ($path -match [regex]::Escape($pattern)) {
            Write-Skip "$label - blocked by key-path guard ($pattern) - would sever Packer's WinRM session"
            $skipped.Add($vid) | Out-Null
            $path = $null
            break
        }
    }
    if (-not $path) { continue }

    $valueName = Get-NodeText $rule 'ValueName'
    if ($null -eq $valueName) { $valueName = '' }   # '' = the key's (Default) value

    $rawType = Get-NodeText $rule 'ValueType'
    if (-not $rawType -or -not $TypeMap.ContainsKey($rawType)) {
        Write-Warn "$label - unsupported ValueType '$rawType' at $path\$valueName"
        $unresolved.Add($vid) | Out-Null
        continue
    }
    $psType = $TypeMap[$rawType]

    # ---- resolve the required data -------------------------------------
    $valueData = Get-NodeText $rule 'ValueData'
    $needsOrg  = ($rule.GetAttribute('OrganizationValueRequired') -eq 'True')

    if ($OrgValueOverrides.ContainsKey($baseVid)) {
        $valueData = $OrgValueOverrides[$baseVid]
        Write-Host "    $vid org value OVERRIDDEN (PowerSTIG bound is below SCC's): $valueData" -ForegroundColor DarkGray
    }
    elseif ($needsOrg -or [string]::IsNullOrWhiteSpace($valueData)) {
        if ($orgValues.ContainsKey($vid)) {
            $valueData = $orgValues[$vid]
            Write-Host "    $vid org value from pamdata: $valueData" -ForegroundColor DarkGray
        } elseif ($orgValues.ContainsKey($baseVid)) {
            $valueData = $orgValues[$baseVid]
            Write-Host "    $vid org value from pamdata ($baseVid): $valueData" -ForegroundColor DarkGray
        } else {
            $derived = Resolve-OrgValue (Get-NodeText $rule 'OrganizationValueTestString')
            if ($null -ne $derived) {
                $valueData = $derived
                Write-Host "    $vid org value derived from STIG bound: $valueData" -ForegroundColor DarkGray
            } elseif ($FallbackValues.ContainsKey($baseVid)) {
                $valueData = $FallbackValues[$baseVid]
                Write-Host "    $vid org value from local fallback table: $valueData" -ForegroundColor DarkGray
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($valueData) -and $psType -ne 'String' -and $psType -ne 'MultiString') {
        Write-Warn "$label - no resolvable value for $path\$valueName - NOT written"
        $unresolved.Add($vid) | Out-Null
        continue
    }

    # ---- type-correct the payload --------------------------------------
    $typed = $null
    try {
        switch ($psType) {
            'DWord' {
                $s = $valueData.Trim()
                if ($s -match '^0x[0-9a-fA-F]+$') { $typed = [int64]("0x" + $s.Substring(2)) }
                else                              { $typed = [int64]$s }
                # DWord is 32-bit; values above int32 max must be written unsigned.
                $typed = [uint32]$typed
            }
            'QWord'        { $typed = [uint64]$valueData.Trim() }
            'MultiString'  { $typed = [string[]]($valueData -split "`r`n|`n|;") }
            'Binary'       { $typed = [byte[]] (($valueData -split '[,\s]+' | Where-Object { $_ }) | ForEach-Object { [byte]$_ }) }
            default        { $typed = [string]$valueData }
        }
    } catch {
        Write-Warn "$label - cannot coerce '$valueData' to $psType : $_"
        $unresolved.Add($vid) | Out-Null
        continue
    }

    # ---- write ---------------------------------------------------------
    try {
        if (-not (Test-Path $path)) {
            New-Item -Path $path -Force -ErrorAction Stop | Out-Null
        }

        # Non-throwing existence probe. Get-ItemProperty -ErrorAction Stop inside a
        # try/catch still emits a "TerminatingError" line into any active PowerShell
        # transcript even though the catch swallows it -- on a real build that was one
        # noise line per not-yet-set value, burying the actual results. GetValue()
        # just returns $null for a missing value.
        $existing = $null
        $regKey = Get-Item -Path $path -ErrorAction SilentlyContinue
        if ($regKey) { $existing = $regKey.GetValue($valueName, $null) }
        $hadValue = ($null -ne $existing)

        if ($hadValue -and ("$existing" -eq "$valueData")) {
            Write-OK "$label already compliant - $valueName = $existing"
            $alreadyOk.Add($vid) | Out-Null
            continue
        }

        Set-ItemProperty -Path $path -Name $valueName -Value $typed -Type $psType -Force -ErrorAction Stop

        # Read back. A write that reports success but does not stick (ACL-protected
        # or policy-reverted keys) is the failure mode worth catching.
        $verify = (Get-Item -Path $path -ErrorAction Stop).GetValue($valueName, $null)
        if ("$verify" -eq "$valueData") {
            if ($FipsRules -contains $baseVid) {
                Write-Fix "$label FIPS APPLIED - $valueName = $verify (if the build dies here, re-run with -SkipFips)"
            } else {
                Write-Fix "$label $valueName = $verify   ($path)"
            }
            $applied.Add($vid) | Out-Null
        } else {
            Write-Bad "$label wrote '$valueData' but read back '$verify' at $path\$valueName"
            $failed.Add($vid) | Out-Null
        }
    } catch {
        Write-Bad "$label $path\$valueName : $_"
        $failed.Add($vid) | Out-Null
    }
}

# =======================================================================
# STEP 3b - Supplemental rules
# =======================================================================
# PowerSTIG classifies these as ManualRule, so they carry no Key/ValueName and
# the STEP 3 loop never sees them -- but DISA SCC checks them AUTOMATICALLY and
# fails them. Without this block they are silently missing from the image.
#
# Key/ValueName/ValueData below are not invented: each is taken from the
# RegistryRule PowerSTIG ships for the SAME underlying setting in its
# WindowsServer-2019/2022 content, where it is correctly classified.
#
# Re-check this list when upgrading PowerSTIG: if a rule graduates to
# RegistryRule, STEP 3 will apply it and the entry here becomes a harmless
# no-op (it is idempotent), but the list should be trimmed.
Write-Section "STEP 3b: Supplemental rules (PowerSTIG marks these ManualRule)"

$SupplementalRules = @(
    @{
        Vid   = 'V-278101'; Severity = 'high'
        Title = 'AutoPlay must be disabled for all drives'
        Path  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\policies\Explorer'
        Name  = 'NoDriveTypeAutoRun'; Type = 'DWord'; Data = '255'
    }
    @{
        Vid   = 'V-278180'; Severity = 'medium'
        Title = 'Restrict unauthenticated RPC clients'
        Path  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Rpc'
        Name  = 'RestrictRemoteClients'; Type = 'DWord'; Data = '1'
    }
)

foreach ($sr in $SupplementalRules) {
    $label = "$($sr.Vid) [$($sr.Severity)]"

    if ($SkipRules -contains $sr.Vid) {
        Write-Skip "$label - excluded by policy"
        $skipped.Add($sr.Vid) | Out-Null
        continue
    }

    # If a PowerSTIG upgrade already handled it in STEP 3, do not double-apply.
    if ($applied.Contains($sr.Vid) -or $alreadyOk.Contains($sr.Vid)) {
        Write-Skip "$label - already handled from STIG content this run"
        continue
    }

    try {
        if (-not (Test-Path $sr.Path)) { New-Item -Path $sr.Path -Force -ErrorAction Stop | Out-Null }

        $k   = Get-Item -Path $sr.Path -ErrorAction SilentlyContinue
        $cur = if ($k) { $k.GetValue($sr.Name, $null) } else { $null }

        if ($null -ne $cur -and "$cur" -eq "$($sr.Data)") {
            Write-OK "$label already compliant - $($sr.Name) = $cur"
            $alreadyOk.Add($sr.Vid) | Out-Null
            continue
        }

        Set-ItemProperty -Path $sr.Path -Name $sr.Name -Value ([uint32]$sr.Data) `
                         -Type $sr.Type -Force -ErrorAction Stop

        $verify = (Get-Item -Path $sr.Path -ErrorAction Stop).GetValue($sr.Name, $null)
        if ("$verify" -eq "$($sr.Data)") {
            Write-Fix "$label $($sr.Name) = $verify   ($($sr.Path))"
            $applied.Add($sr.Vid) | Out-Null
        } else {
            Write-Bad "$label wrote '$($sr.Data)' but read back '$verify'"
            $failed.Add($sr.Vid) | Out-Null
        }
    } catch {
        Write-Bad "$label $($sr.Path)\$($sr.Name) : $_"
        $failed.Add($sr.Vid) | Out-Null
    }
}

# =======================================================================
# STEP 4 - Settings SCC checks that the registry alone does not satisfy
# =======================================================================
Write-Section "STEP 4: Companion fixes"

# Event log channel sizing. The STIG registry rules above set the POLICY value
# under SOFTWARE\Policies\...\EventLog\<Channel>\MaxSize, which is what SCC
# reads. wevtutil additionally sizes the live channel so the running system
# actually honours it. Both are needed: policy for the scan, wevtutil for effect.
$logChannels = @(
    @{ Channel = 'Application'; PolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog\Application' }
    @{ Channel = 'Security';    PolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog\Security'    }
    @{ Channel = 'System';      PolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog\System'      }
)

foreach ($c in $logChannels) {
    $polKey = Get-Item -Path $c.PolicyKey -ErrorAction SilentlyContinue
    $maxKb  = if ($polKey) { $polKey.GetValue('MaxSize', $null) } else { $null }
    if ($null -eq $maxKb) {
        Write-Warn "$($c.Channel): no policy MaxSize was set by the STIG rules - leaving channel size alone"
        continue
    }
    try {
        & wevtutil sl $c.Channel /ms:$maxKb 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-OK "$($c.Channel) live channel sized to $maxKb KB (matches policy)"
        } else {
            Write-Warn "$($c.Channel): wevtutil exit $LASTEXITCODE - policy value is still set for the scan"
        }
    } catch {
        Write-Warn "$($c.Channel): wevtutil failed: $_"
    }
}

# PowerShell Transcription writes to OutputDirectory. The STIG only checks the
# registry, but transcription silently no-ops if the directory does not exist.
$transcriptKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription'
$tKey   = Get-Item -Path $transcriptKey -ErrorAction SilentlyContinue
$outDir = if ($tKey) { $tKey.GetValue('OutputDirectory', $null) } else { $null }
if ([string]::IsNullOrWhiteSpace($outDir)) {
    Write-Skip "No PowerShell Transcription OutputDirectory policy to back with a folder"
} elseif (-not (Test-Path $outDir)) {
    try {
        New-Item -Path $outDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        Write-Fix "Created PowerShell transcript directory: $outDir"
    } catch {
        Write-Warn "Could not create transcript directory $outDir : $_"
    }
} else {
    Write-OK "PowerShell transcript directory present: $outDir"
}

# =======================================================================
# STEP 5 - Summary
# =======================================================================
Write-Section "SUMMARY"

$considered = $applied.Count + $alreadyOk.Count + $failed.Count + $unresolved.Count
Write-Host "  Registry rules in STIG content : $($registryRules.Count)"
Write-Host "  Excluded by policy/guard       : $($skipped.Count)"    -ForegroundColor Gray
Write-Host "  Already compliant              : $($alreadyOk.Count)"  -ForegroundColor Green
Write-Host "  Newly applied                  : $($applied.Count)"    -ForegroundColor Yellow
Write-Host "  Unresolved (no value derivable): $($unresolved.Count)" -ForegroundColor Magenta
Write-Host "  Failed to write                : $($failed.Count)"     -ForegroundColor $(if ($failed.Count) { 'Red' } else { 'Green' })
Write-Host "  Effective coverage             : $($applied.Count + $alreadyOk.Count) / $considered"

if ($unresolved.Count -gt 0) {
    Write-Host ""
    Write-Warn "Unresolved rules (need an org value in the pamdata XML):"
    $unresolved | ForEach-Object { Write-Host "    $_" -ForegroundColor Magenta }
}

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Bad "Rules that failed to write:"
    $failed | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
}

# Drift check against the remediation estimate, when one is supplied.
if ($ExpectedRuleList -and (Test-Path $ExpectedRuleList)) {
    Write-Host ""
    Write-Host "  --- Coverage vs $([System.IO.Path]::GetFileName($ExpectedRuleList)) ---" -ForegroundColor Cyan

    $expected = Get-Content $ExpectedRuleList |
                ForEach-Object { ($_ -split ',')[0].Trim() } |
                Where-Object   { $_ -match '^V-\d+$' } |
                Sort-Object -Unique

    $covered = @($applied + $alreadyOk + $skipped) | ForEach-Object { ($_ -split '\.')[0] } | Sort-Object -Unique
    $missing = @($expected | Where-Object { $covered -notcontains $_ })

    Write-Host "  Expected V-IDs : $($expected.Count)"
    Write-Host "  Accounted for  : $($expected.Count - $missing.Count)"
    if ($missing.Count -gt 0) {
        Write-Warn "Expected but NOT present as registry rules in the STIG content:"
        Write-Warn "(these are user-rights / audit-policy / certificate / manual rules, or renumbered)"
        $missing | ForEach-Object { Write-Host "    $_" -ForegroundColor Magenta }
    }
}

Write-Host ""
Write-Host "=== win2025_registry_fixes.ps1 complete ===" -ForegroundColor Cyan

# Only a hard write failure is worth failing the step over. Unresolved rules are
# reported loudly but must not abort a build that is otherwise hardening fine.
exit $failed.Count
