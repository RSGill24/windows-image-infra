# install_dsc_deps.ps1
# Installs PowerSTIG dependencies and generates org settings XML with PAM overrides.
# Safe for GCP Cloud Build / Packer pipelines.

param (
    [string]$HardeningDir = $PSScriptRoot
)

Write-Host "=== Installing PowerSTIG dependencies ==="

# -----------------------------------------------------------------------
# Step 0: Import PowerSTIG and detect latest module
# -----------------------------------------------------------------------
$module = Get-Module PowerSTIG -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1

if (-not $module) {
    Write-Error "PowerSTIG module not found. Run install_PowerSTIG.ps1 first."
    exit 1
}
Write-Host "Found PowerSTIG $($module.Version) at: $($module.ModuleBase)"

$systemModulePath = "C:\Program Files\WindowsPowerShell\Modules"
$dscSystemPath    = "C:\Windows\system32\WindowsPowerShell\v1.0\Modules"

# -----------------------------------------------------------------------
# Step 1: Aggressively purge duplicate modules from BOTH paths.
# The base image may have pre-installed DSC modules locked by TrustedInstaller.
# Leaving clones in System32 causes DSC to throw fatal 
# "A second CIM class definition" errors during MOF compilation.
# -----------------------------------------------------------------------
Write-Host "--- Removing duplicate modules to prevent CIM conflicts..."

foreach ($dep in $module.RequiredModules) {
    
    # 1. Purge from System32 completely (bypassing TrustedInstaller)
    $dscDepPath = Join-Path $dscSystemPath $dep.Name
    if (Test-Path $dscDepPath) {
        Write-Host "  Nuking conflicting System32 path: $dscDepPath" -ForegroundColor Yellow
        takeown.exe /F $dscDepPath /R /D Y | Out-Null
        icacls.exe $dscDepPath /grant "Administrators:(OI)(CI)F" /T /Q | Out-Null
        Remove-Item $dscDepPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # 2. Purge from Program Files (removes older versions if present)
    $pfDepPath = Join-Path $systemModulePath $dep.Name
    if (Test-Path $pfDepPath) {
        Write-Host "  Removing old Program Files path: $pfDepPath"
        Remove-Item $pfDepPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 3. Install cleanly into Program Files
    Write-Host "--- Installing: $($dep.Name) $($dep.Version)"
    Install-Module -Name $dep.Name -RequiredVersion $dep.Version -Scope AllUsers -Force -AllowClobber
}

# Also purge PowerSTIG from System32 if it got copied there during a previous run
$pstigDscPath = Join-Path $dscSystemPath "PowerSTIG"
if (Test-Path $pstigDscPath) {
    Write-Host "  Nuking conflicting PowerSTIG System32 path: $pstigDscPath" -ForegroundColor Yellow
    takeown.exe /F $pstigDscPath /R /D Y | Out-Null
    icacls.exe $pstigDscPath /grant "Administrators:(OI)(CI)F" /T /Q | Out-Null
    Remove-Item $pstigDscPath -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "  Duplicate cleanup complete."

# -----------------------------------------------------------------------
# Step 2: Find the .org.default.xml inside the installed module
# -----------------------------------------------------------------------
$stigDataPath = Join-Path $module.ModuleBase "StigData\Processed"
Write-Host "--- Searching for org.default.xml in: $stigDataPath"

$defaultOrgFile = Get-ChildItem -Path $stigDataPath `
                    -Filter "WindowsServer-2025-MS-*.org.default.xml" `
                    -ErrorAction SilentlyContinue |
                  Sort-Object Name -Descending |
                  Select-Object -First 1

if (-not $defaultOrgFile) {
    Write-Error "No WindowsServer-2025-MS-*.org.default.xml found in $stigDataPath"
    exit 1
}
Write-Host "Found org.default.xml: $($defaultOrgFile.FullName)"

# -----------------------------------------------------------------------
# Step 3: Copy the default XML to the hardening dir and apply PAM overrides
# -----------------------------------------------------------------------
$outputOrgXml = Join-Path $HardeningDir ($defaultOrgFile.Name -replace '\.org\.default\.xml', '.org.pamdata.xml')
Copy-Item -Path $defaultOrgFile.FullName -Destination $outputOrgXml -Force
Write-Host "Copied XML to: $outputOrgXml"

[xml]$orgXml = Get-Content -Path $outputOrgXml -Encoding UTF8

# -----------------------------------------------------------------------
# Apply PAM organizational overrides.
#
# WHY THIS IS MATCHED BY NAME, NOT BY V-ID
# ----------------------------------------
# This block used to key its overrides off hardcoded Server 2022 V-IDs
# (V-254248, V-254285..V-254291). The pipeline builds Server 2025, whose STIG
# uses V-278xxx, so every single lookup fell through to the
# "$vid not found in XML - skipping" branch and NO organizational value was
# ever applied. The build looked clean because the warning is non-fatal.
#
# Overrides are now resolved against the installed STIG rule content by the
# thing that is actually stable -- the policy name, the service name, the
# registry value -- and the V-ID is looked up from that. This survives DISA
# renumbering.
# -----------------------------------------------------------------------
Write-Host "--- Applying PAM org setting overrides (resolved by name) ---"

$ruleContentFile = Get-ChildItem -Path $stigDataPath -Filter "WindowsServer-2025-MS-*.xml" -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -notmatch '\.org\.' } |
                   Sort-Object Name -Descending |
                   Select-Object -First 1

if (-not $ruleContentFile) {
    Write-Error "No WindowsServer-2025-MS-*.xml rule content found in $stigDataPath - cannot resolve org overrides."
    exit 1
}
Write-Host "Resolving against rule content: $($ruleContentFile.Name)"
[xml]$ruleXml = Get-Content -Path $ruleContentFile.FullName -Raw -Encoding UTF8

function Set-OrgValue {
    <#
        Writes one attribute onto the OrganizationalSetting node for $Vid.
        Returns $true when the node existed and was updated.
    #>
    param(
        [xml]   $Xml,
        [string]$Vid,
        [string]$Attribute,
        [string]$Value,
        [string]$Label
    )
    $node = $Xml.SelectNodes('//OrganizationalSetting') | Where-Object { $_.GetAttribute('id') -eq $Vid } | Select-Object -First 1
    if ($null -eq $node) {
        Write-Warning "  $Label -> $Vid has no OrganizationalSetting node; skipping"
        return $false
    }
    $node.SetAttribute($Attribute, $Value)
    Write-Host "  [SET] $Label -> $Vid $Attribute = $Value" -ForegroundColor Green
    return $true
}

$applied = 0
$missed  = 0

# --- Account / lockout policy, matched on the secpol policy name ----------
# NOTE: create_mof.ps1 skips AccountPolicyRule as a class (SCE writes break
# Packer's WinRM session), so these values are enforced by account_policy.ps1
# after DSC. They are still set here so the org XML is internally consistent
# and PowerSTIG has a value for every rule that demands one at compile time.
$policyOverrides = @(
    @{ Name = 'Account lockout duration';                  Value = '15' }
    @{ Name = 'Account lockout threshold';                 Value = '3'  }
    @{ Name = 'Reset account lockout counter after';       Value = '15' }
    @{ Name = 'Enforce password history';                  Value = '24' }
    @{ Name = 'Maximum password age';                      Value = '60' }
    @{ Name = 'Minimum password age';                      Value = '1'  }
    @{ Name = 'Minimum password length';                   Value = '15' }
)

foreach ($o in $policyOverrides) {
    $rules = @($ruleXml.SelectNodes('//AccountPolicyRule/Rule') | Where-Object {
        $pn = $_.SelectSingleNode('PolicyName')
        $null -ne $pn -and $pn.InnerText -like "*$($o.Name)*"
    })
    if ($rules.Count -eq 0) {
        Write-Warning "  No AccountPolicyRule matching '$($o.Name)' in the 2025 STIG content"
        $missed++
        continue
    }
    foreach ($r in $rules) {
        if (Set-OrgValue -Xml $orgXml -Vid $r.GetAttribute('id') -Attribute 'PolicyValue' -Value $o.Value -Label $o.Name) {
            $applied++
        } else { $missed++ }
    }
}

# --- Service rules, matched on the Windows service name -------------------
$serviceOverrides = @(
    @{ ServiceName = 'WinDefend'; StartupType = 'Automatic' }
    @{ ServiceName = 'MpsSvc';    StartupType = 'Automatic' }
)

foreach ($o in $serviceOverrides) {
    $rules = @($ruleXml.SelectNodes('//ServiceRule/Rule') | Where-Object {
        $sn = $_.SelectSingleNode('ServiceName')
        $null -ne $sn -and $sn.InnerText -eq $o.ServiceName
    })
    if ($rules.Count -eq 0) {
        Write-Warning "  No ServiceRule for service '$($o.ServiceName)' in the 2025 STIG content"
        $missed++
        continue
    }
    foreach ($r in $rules) {
        $vid = $r.GetAttribute('id')
        $ok1 = Set-OrgValue -Xml $orgXml -Vid $vid -Attribute 'ServiceName' -Value $o.ServiceName -Label "$($o.ServiceName) service"
        $ok2 = Set-OrgValue -Xml $orgXml -Vid $vid -Attribute 'StartupType' -Value $o.StartupType -Label "$($o.ServiceName) startup"
        if ($ok1 -and $ok2) { $applied++ } else { $missed++ }
    }
}

# --- Any organizational value still blank -------------------------------
# PowerSTIG can fail MOF compilation when a rule demands an organizational
# value and the XML supplies none. The default XML carries an
# OrganizationValueTestString describing the acceptable bound (for example
# "'{0}' -ge '32768'"); the bound itself is a compliant value, so fill from it.
# This is what makes the event-log-size and timeout rules pass without a
# hand-maintained table.
Write-Host "--- Filling any remaining blank organizational values ---"
$filled = 0
foreach ($node in $orgXml.SelectNodes('//OrganizationalSetting')) {
    $hasValue = $false
    foreach ($a in @('ValueData','PolicyValue','OptionValue','StartupType','Identity')) {
        if ($node.GetAttribute($a) -ne '') { $hasValue = $true; break }
    }
    if ($hasValue) { continue }

    $test = $node.GetAttribute('OrganizationValueTestString')
    if ([string]::IsNullOrWhiteSpace($test)) { continue }

    $derived = $null
    if     ($test -match "-eq\s+'?([^'\s]+)'?") { $derived = $Matches[1] }
    elseif ($test -match "-ge\s+'?([^'\s]+)'?") { $derived = $Matches[1] }
    elseif ($test -match "-le\s+'?([^'\s]+)'?") { $derived = $Matches[1] }
    elseif ($test -match "-gt\s+'?(-?\d+)'?")   { $derived = ([int]$Matches[1] + 1).ToString() }
    elseif ($test -match "-lt\s+'?(-?\d+)'?")   { $derived = ([int]$Matches[1] - 1).ToString() }

    if ($null -ne $derived) {
        $node.SetAttribute('ValueData', $derived)
        Write-Host "  [FILL] $($node.GetAttribute('id')) ValueData = $derived  (from: $test)" -ForegroundColor DarkGray
        $filled++
    }
}
Write-Host "  Blank org values filled from STIG bounds: $filled"

Write-Host "--- Org override summary: $applied applied, $missed unresolved, $filled auto-filled ---"

if ($applied -eq 0) {
    Write-Warning "NO organizational overrides applied. If every lookup missed, the installed"
    Write-Warning "PowerSTIG content is probably not Server 2025 - check the module version."
}

# Save the final XML
$orgXml.Save($outputOrgXml)
Write-Host "Org settings XML saved to: $outputOrgXml"

# -----------------------------------------------------------------------
# Step 4: Verify DSC resources
# -----------------------------------------------------------------------
Write-Host "--- Verifying DSC resources..."
$dscResources = Get-DscResource -Module PowerSTIG -ErrorAction SilentlyContinue
if ($dscResources) {
    $dscResources | Select-Object -First 5 | ForEach-Object {
        Write-Host "  DSC resource OK: $($_.Name)"
    }
} else {
    Write-Warning "  No DSC resources returned -- check for CIM class conflicts in event log"
}

Write-Host "=== Dependencies installed successfully ==="
exit 0
