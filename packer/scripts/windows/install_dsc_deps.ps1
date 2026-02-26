param (
    # Where to write the final org settings XML.
    # Defaults to the script's own directory (= CloudBuild _HARDENING_TARGET_DIR).
    [string]$HardeningDir = $PSScriptRoot
)

Write-Host "=== Installing PowerSTIG dependencies ==="

# Import PowerSTIG so its module manifest is accessible
Import-Module PowerSTIG -Force

# Get the highest installed version of PowerSTIG
$module = Get-Module PowerSTIG -ListAvailable |
          Sort-Object Version -Descending |
          Select-Object -First 1

if (-not $module) {
    Write-Error "PowerSTIG module not found. Run install_PowerSTIG.ps1 first."
    exit 1
}
Write-Host "Found PowerSTIG $($module.Version) at: $($module.ModuleBase)"

$systemModulePath = "C:\Program Files\WindowsPowerShell\Modules"
$dscSystemPath    = "C:\Windows\system32\WindowsPowerShell\v1.0\Modules"

# -----------------------------------------------------------------------
# Step 1: Install each required dependency at its exact declared version
#         and copy into the DSC LCM system32 module path
# -----------------------------------------------------------------------
foreach ($dep in $module.RequiredModules) {
    Write-Host "--- Installing: $($dep.Name) $($dep.Version)"

    Install-Module -Name $dep.Name `
                   -RequiredVersion $dep.Version `
                   -Scope AllUsers `
                   -Force `
                   -AllowClobber

    # Copy to DSC LCM system32 path — LCM runs as SYSTEM and resolves modules here
    $srcPath = Join-Path $systemModulePath "$($dep.Name)\$($dep.Version)"
    $dstDir  = Join-Path $dscSystemPath    $dep.Name
    $dstPath = Join-Path $dstDir           $dep.Version

    if (Test-Path $srcPath) {
        if (!(Test-Path $dstDir)) { New-Item -Path $dstDir -ItemType Directory -Force | Out-Null }
        Write-Host "    Copying to DSC path: $dstPath"
        Copy-Item -Path $srcPath -Destination $dstPath -Recurse -Force
    } else {
        Write-Warning "    Source not found at $srcPath — skipping copy"
    }
}

# -----------------------------------------------------------------------
# Step 2: Copy PowerSTIG itself into the DSC LCM system32 path
# -----------------------------------------------------------------------
Write-Host "--- Copying PowerSTIG to DSC system path..."
$pstigSrc = $module.ModuleBase   # exact path of installed module, e.g. ...PowerSTIG\4.29.0
$pstigDst = Join-Path $dscSystemPath "PowerSTIG\$($module.Version)"
if (!(Test-Path (Split-Path $pstigDst))) {
    New-Item -Path (Split-Path $pstigDst) -ItemType Directory -Force | Out-Null
}
Copy-Item -Path $pstigSrc -Destination $pstigDst -Recurse -Force
Write-Host "    Copied to: $pstigDst"

# -----------------------------------------------------------------------
# Step 3: Locate the .org.default.xml inside the installed module
# -----------------------------------------------------------------------
# PowerSTIG stores it at:
#   <ModuleBase>\StigData\Processed\WindowsServer-2022-MS-<version>.org.default.xml
# We search for any matching file so we're not brittle about the exact STIG version string.

$stigDataPath  = Join-Path $module.ModuleBase "StigData\Processed"
Write-Host "--- Searching for org.default.xml in: $stigDataPath"

# Search for the Windows Server 2022 MS org default file (any STIG release)
$defaultOrgFile = Get-ChildItem -Path $stigDataPath `
                    -Filter "WindowsServer-2022-MS-*.org.default.xml" `
                    -ErrorAction SilentlyContinue |
                  Sort-Object Name -Descending |
                  Select-Object -First 1

if (-not $defaultOrgFile) {
    Write-Error "No WindowsServer-2022-MS-*.org.default.xml found in $stigDataPath"
    Write-Error "Available files:"
    Get-ChildItem -Path $stigDataPath -Filter "*.org.default.xml" | ForEach-Object { Write-Error "  $($_.Name)" }
    exit 1
}

Write-Host "Found org default file: $($defaultOrgFile.FullName)"

# -----------------------------------------------------------------------
# Step 4: Copy the default XML to the hardening dir and apply PAM overrides
# -----------------------------------------------------------------------
$outputOrgXml = Join-Path $HardeningDir "WindowsServer-2022-MS-2.1.org.pamdata.xml"
Write-Host "Copying to: $outputOrgXml"
Copy-Item -Path $defaultOrgFile.FullName -Destination $outputOrgXml -Force

# Load as XML for targeted overrides
[xml]$orgXml = Get-Content $outputOrgXml -Encoding UTF8

# Helper: update an existing OrganizationalSetting attribute, warn if not found
function Set-OrgSetting {
    param([xml]$xml, [string]$id, [string]$attr, [string]$value)
    $node = $xml.OrganizationalSettings.OrganizationalSetting |
            Where-Object { $_.id -eq $id }
    if ($node) {
        $node.SetAttribute($attr, $value)
        Write-Host "  Set $id : $attr = $value"
    } else {
        Write-Warning "  Org setting $id not found in XML — may have been removed in this STIG version"
    }
}

Write-Host "--- Applying PAM org setting overrides..."

# AV + Firewall services (Windows Defender defaults on GCP Server 2022)
Set-OrgSetting $orgXml "V-254248" "ServiceName" "WinDefend"
Set-OrgSetting $orgXml "V-254248" "StartupType"  "Automatic"
Set-OrgSetting $orgXml "V-254265" "ServiceName" "MpsSvc"
Set-OrgSetting $orgXml "V-254265" "StartupType"  "Automatic"

# Account lockout reset counter >= 15 minutes (V-254287)
Set-OrgSetting $orgXml "V-254287" "PolicyValue" "15"

# Password history >= 24 (V-254288)
Set-OrgSetting $orgXml "V-254288" "PolicyValue" "24"

# Minimum password length >= 15 (V-254285)
Set-OrgSetting $orgXml "V-254285" "PolicyValue" "15"

# Account lockout duration 1–3 minutes (V-254286)
Set-OrgSetting $orgXml "V-254286" "PolicyValue" "3"

# Event log sizes
Set-OrgSetting $orgXml "V-254358" "ValueData" "32768"
Set-OrgSetting $orgXml "V-254359" "ValueData" "196608"
Set-OrgSetting $orgXml "V-254360" "ValueData" "32768"

# Account lockout threshold <= 4 (V-254432)
Set-OrgSetting $orgXml "V-254432" "ValueData" "4"

# Session lock timeout <= 900 seconds (V-254456)
Set-OrgSetting $orgXml "V-254456" "ValueData" "900"

# Max password age <= 30 days (V-254454)
Set-OrgSetting $orgXml "V-254454" "ValueData" "30"

# Firewall public profile log dropped packets (V-254357)
Set-OrgSetting $orgXml "V-254357" "ValueData" "100"

# Kerberos encryption type (V-254343.b) — 1 = AES128+AES256
Set-OrgSetting $orgXml "V-254343.b" "ValueData" "1"

# LAN Manager auth level (V-254344) — 8 = NTLMv2 only
Set-OrgSetting $orgXml "V-254344" "ValueData" "8"

# Audit subcategories
Set-OrgSetting $orgXml "V-254459" "ValueData" "1"
Set-OrgSetting $orgXml "V-254484" "ValueData" "1"

# Legal notice banner title and caption (DoD standard)
Set-OrgSetting $orgXml "V-254458" "ValueData" "DoD Notice and Consent Banner"
Set-OrgSetting $orgXml "V-254457" "ValueData" "You are accessing a U.S. Government (USG) Information System (IS) that is provided for USG-authorized use only. By using this IS (which includes any device attached to this IS), you consent to the following conditions: -The USG routinely intercepts and monitors communications on this IS for purposes including, but not limited to, penetration testing, COMSEC monitoring, network operations, and known threat detection. -At any time, the USG may inspect and seize data stored on this IS. -Communications using, or data stored on, this IS are not private, are subject to routine monitoring, interception, and search, and may be disclosed or used for any USG-authorized purpose. -This IS includes security measures (e.g., authentication and access controls) to protect USG interests--not for your personal benefit or privacy."

# Save the updated XML
$orgXml.Save($outputOrgXml)
Write-Host "Org settings XML saved to: $outputOrgXml"

# Print the final XML contents for Packer log visibility / debugging
Write-Host "--- Final org settings XML contents:"
Get-Content $outputOrgXml | ForEach-Object { Write-Host "  $_" }

# -----------------------------------------------------------------------
# Step 5: Confirm DSC resources are resolvable
# -----------------------------------------------------------------------
Write-Host "--- Verifying DSC resources..."
Get-DscResource -Module PowerSTIG | Select-Object -First 5 | ForEach-Object {
    Write-Host "  DSC resource OK: $($_.Name)"
}

Write-Host "=== Dependencies installed successfully. ==="
