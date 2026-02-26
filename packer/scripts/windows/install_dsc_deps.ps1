param (
    # The hardening directory where the final org settings XML will be written.
    # Defaults to the script's own directory (= CloudBuild _HARDENING_TARGET_DIR).
    [string]$HardeningDir = $PSScriptRoot
)

Write-Host "Installing PowerSTIG dependencies..."

# Import PowerSTIG so its module manifest is accessible
Import-Module PowerSTIG -Force

# Retrieve the highest installed version of PowerSTIG
$module = Get-Module PowerSTIG -ListAvailable |
          Sort-Object Version -Descending |
          Select-Object -First 1

if (-not $module) {
    Write-Error "PowerSTIG module not found. Run install_PowerSTIG.ps1 first."
    exit 1
}
Write-Host "Found PowerSTIG version: $($module.Version)"

# System-wide module paths
$systemModulePath = "C:\Program Files\WindowsPowerShell\Modules"
$dscSystemPath    = "C:\Windows\system32\WindowsPowerShell\v1.0\Modules"

# -----------------------------------------------------------------------
# Step 1: Install each required dependency at its exact declared version
# -----------------------------------------------------------------------
foreach ($dep in $module.RequiredModules) {
    Write-Host "Installing dependency: $($dep.Name) $($dep.Version)"
    Install-Module -Name $dep.Name `
                   -RequiredVersion $dep.Version `
                   -Scope AllUsers `
                   -Force `
                   -AllowClobber

    # Copy into DSC LCM system32 path so MOF compilation can resolve the resource
    $srcPath = Join-Path $systemModulePath "$($dep.Name)\$($dep.Version)"
    $dstPath = Join-Path $dscSystemPath    $dep.Name

    if (Test-Path $srcPath) {
        Write-Host "  Copying $($dep.Name) to DSC system path..."
        if (!(Test-Path $dstPath)) {
            New-Item -Path $dstPath -ItemType Directory -Force | Out-Null
        }
        Copy-Item -Path $srcPath `
                  -Destination (Join-Path $dstPath $dep.Version) `
                  -Recurse -Force
    } else {
        Write-Warning "  Module source path not found, skipping copy: $srcPath"
    }
}

# -----------------------------------------------------------------------
# Step 2: Copy PowerSTIG itself into the DSC LCM system32 path
# -----------------------------------------------------------------------
Write-Host "Copying PowerSTIG to DSC system path..."
$pstigSrc = Join-Path $systemModulePath "PowerSTIG\$($module.Version)"
$pstigDst = Join-Path $dscSystemPath    "PowerSTIG"
if (Test-Path $pstigSrc) {
    if (!(Test-Path $pstigDst)) {
        New-Item -Path $pstigDst -ItemType Directory -Force | Out-Null
    }
    Copy-Item -Path $pstigSrc `
              -Destination (Join-Path $pstigDst $module.Version) `
              -Recurse -Force
}

# -----------------------------------------------------------------------
# Step 3: Auto-generate the org settings XML from the module's default file
# -----------------------------------------------------------------------
# PowerSTIG ships a complete .org.default.xml inside the module for each STIG
# version. This file contains an entry for every rule that has an allowable range.
# We copy it to the hardening dir as our base, then apply PAM-specific overrides.
#
# This is the definitive fix for "Org Setting not found for V-XXXXXX" — it ensures
# the XML is always complete for whatever PowerSTIG version is installed, without
# having to manually maintain the file between module updates.

$stigVersion   = "2.1"    # Latest Windows Server 2022 MS STIG supported by PowerSTIG
$defaultOrgXml = Join-Path $pstigSrc "StigData\Processed\Windows.Server.2022-MS-$stigVersion.org.default.xml"
$outputOrgXml  = Join-Path $HardeningDir "WindowsServer-2022-MS-2.1.org.pamdata.xml"

if (Test-Path $defaultOrgXml) {
    Write-Host "Found default org settings at: $defaultOrgXml"
    Write-Host "Copying to hardening dir as base: $outputOrgXml"
    Copy-Item -Path $defaultOrgXml -Destination $outputOrgXml -Force

    # -----------------------------------------------------------------------
    # Step 4: Apply PAM-specific overrides to the copied org settings XML
    # -----------------------------------------------------------------------
    # Load the XML, update values that differ from defaults for this environment,
    # then save it back. This keeps the file complete while applying our settings.
    Write-Host "Applying PAM org setting overrides..."
    [xml]$orgXml = Get-Content $outputOrgXml

    # Helper function to set or add an OrganizationalSetting attribute value
    function Set-OrgSetting {
        param([xml]$xml, [string]$id, [string]$attr, [string]$value)
        $node = $xml.OrganizationalSettings.OrganizationalSetting | Where-Object { $_.id -eq $id }
        if ($node) {
            $node.SetAttribute($attr, $value)
            Write-Host "  Updated $id $attr=$value"
        } else {
            Write-Warning "  Org setting $id not found in XML — skipping override (may have been removed in this STIG version)"
        }
    }

    # AV and Firewall services (GCP Windows Server 2022 defaults)
    Set-OrgSetting $orgXml "V-254248" "ServiceName"  "WinDefend"
    Set-OrgSetting $orgXml "V-254248" "StartupType"  "Automatic"
    Set-OrgSetting $orgXml "V-254265" "ServiceName"  "MpsSvc"
    Set-OrgSetting $orgXml "V-254265" "StartupType"  "Automatic"

    # Account lockout reset counter — must be >= 15 min (V-254287)
    Set-OrgSetting $orgXml "V-254287" "PolicyValue"  "15"

    # Password history — must be >= 24 (V-254288)
    Set-OrgSetting $orgXml "V-254288" "PolicyValue"  "24"

    # Minimum password length — set to 15 (exceeds STIG minimum of 14) (V-254285)
    Set-OrgSetting $orgXml "V-254285" "PolicyValue"  "15"

    # Account lockout duration — set to 3 min (within STIG allowed range 1-3) (V-254286)
    Set-OrgSetting $orgXml "V-254286" "PolicyValue"  "3"

    # Event log sizes
    Set-OrgSetting $orgXml "V-254358" "ValueData"    "32768"
    Set-OrgSetting $orgXml "V-254359" "ValueData"    "196608"
    Set-OrgSetting $orgXml "V-254360" "ValueData"    "32768"

    # Account lockout threshold (V-254432) — set to 3 (within STIG allowed range <= 4)
    Set-OrgSetting $orgXml "V-254432" "ValueData"    "4"

    # Session timeout (V-254456) — 900 seconds (15 min maximum)
    Set-OrgSetting $orgXml "V-254456" "ValueData"    "900"

    # Account inactivity (V-254454) — 30 days maximum
    Set-OrgSetting $orgXml "V-254454" "ValueData"    "30"

    # Firewall logging (V-254357) — 100 = enabled
    Set-OrgSetting $orgXml "V-254357" "ValueData"    "100"

    # Kerberos encryption type (V-254343.b) — 1 = AES
    Set-OrgSetting $orgXml "V-254343.b" "ValueData"  "1"

    # LAN Manager auth level (V-254344) — 8 = NTLMv2 only
    Set-OrgSetting $orgXml "V-254344" "ValueData"    "8"

    # Audit policy subcategories
    Set-OrgSetting $orgXml "V-254459" "ValueData"    "1"
    Set-OrgSetting $orgXml "V-254484" "ValueData"    "1"

    # Legal notice banner title and body (DoD standard)
    Set-OrgSetting $orgXml "V-254458" "ValueData"    "DoD Notice and Consent Banner"
    Set-OrgSetting $orgXml "V-254457" "ValueData"    "You are accessing a U.S. Government (USG) Information System (IS) that is provided for USG-authorized use only. By using this IS (which includes any device attached to this IS), you consent to the following conditions: -The USG routinely intercepts and monitors communications on this IS for purposes including, but not limited to, penetration testing, COMSEC monitoring, network operations, and known threat detection. -At any time, the USG may inspect and seize data stored on this IS. -Communications using, or data stored on, this IS are not private, are subject to routine monitoring, interception, and search, and may be disclosed or used for any USG-authorized purpose. -This IS includes security measures (e.g., authentication and access controls) to protect USG interests--not for your personal benefit or privacy."

    # Save the updated XML back to the hardening dir
    $orgXml.Save($outputOrgXml)
    Write-Host "Org settings XML written to: $outputOrgXml"

} else {
    Write-Warning "Default org settings not found at: $defaultOrgXml"
    Write-Warning "PowerSTIG version $($module.Version) may not include STIG 2.1 data."
    Write-Warning "Falling back to manually maintained org settings XML."
    Write-Warning "Ensure WindowsServer-2022-MS-2.1.org.pamdata.xml is present in: $HardeningDir"
}

# -----------------------------------------------------------------------
# Step 5: Confirm DSC resources are resolvable before create_mof.ps1 runs
# -----------------------------------------------------------------------
Write-Host "Refreshing DSC resource cache..."
Get-DscResource -Module PowerSTIG | Select-Object -First 5 | ForEach-Object {
    Write-Host "  DSC resource available: $($_.Name)"
}

Write-Host "Dependencies installed successfully."
