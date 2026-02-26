# install_dsc_deps.ps1
# Installs all PowerShell DSC resource module dependencies required by PowerSTIG,
# copies modules into the DSC LCM system path, and generates the org settings XML
# directly from the installed PowerSTIG module's built-in .org.default.xml file.
#
# WHY THIS FIXES "Org Setting not found for V-254287":
#   PowerSTIG ships a complete .org.default.xml for every STIG version inside the
#   module at: <ModuleBase>\StigData\Processed\WindowsServer-2022-MS-2.1.org.default.xml
#   This file contains an entry for EVERY rule that requires an org setting.
#   We copy it and apply PAM-specific overrides directly — no helper functions,
#   all XML edits are inlined to avoid PowerShell scoping issues with Packer.
#
# Must be run as Administrator.
# Must run AFTER install_PowerSTIG.ps1 and BEFORE create_mof.ps1.

param (
    [string]$HardeningDir = $PSScriptRoot
)

Write-Host "=== Installing PowerSTIG dependencies ==="

Import-Module PowerSTIG -Force

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
# Step 1: Install each dependency and copy to DSC LCM system32 path
# -----------------------------------------------------------------------
foreach ($dep in $module.RequiredModules) {
    Write-Host "--- Installing: $($dep.Name) $($dep.Version)"
    Install-Module -Name $dep.Name `
                   -RequiredVersion $dep.Version `
                   -Scope AllUsers `
                   -Force `
                   -AllowClobber

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
$pstigSrc    = $module.ModuleBase
$pstigDstDir = Join-Path $dscSystemPath "PowerSTIG"
$pstigDst    = Join-Path $pstigDstDir   $module.Version
if (!(Test-Path $pstigDstDir)) { New-Item -Path $pstigDstDir -ItemType Directory -Force | Out-Null }
Copy-Item -Path $pstigSrc -Destination $pstigDst -Recurse -Force
Write-Host "    Copied to: $pstigDst"

# -----------------------------------------------------------------------
# Step 3: Find the .org.default.xml inside the installed module
# -----------------------------------------------------------------------
$stigDataPath = Join-Path $module.ModuleBase "StigData\Processed"
Write-Host "--- Searching for org.default.xml in: $stigDataPath"

$defaultOrgFile = Get-ChildItem -Path $stigDataPath `
                    -Filter "WindowsServer-2022-MS-*.org.default.xml" `
                    -ErrorAction SilentlyContinue |
                  Sort-Object Name -Descending |
                  Select-Object -First 1

if (-not $defaultOrgFile) {
    Write-Error "No WindowsServer-2022-MS-*.org.default.xml found in $stigDataPath"
    Write-Host "Available org.default.xml files:"
    Get-ChildItem -Path $stigDataPath -Filter "*.org.default.xml" |
        ForEach-Object { Write-Host "  $($_.Name)" }
    exit 1
}

Write-Host "Found: $($defaultOrgFile.FullName)"

# -----------------------------------------------------------------------
# Step 4: Copy the default XML to the hardening dir and apply PAM overrides
#         NOTE: All XML edits are inlined — no helper functions — to avoid
#         PowerShell scoping/parsing issues when run by Packer provisioner.
# -----------------------------------------------------------------------
$outputOrgXml = Join-Path $HardeningDir "WindowsServer-2022-MS-2.1.org.pamdata.xml"
Write-Host "Copying to: $outputOrgXml"
Copy-Item -Path $defaultOrgFile.FullName -Destination $outputOrgXml -Force

[xml]$orgXml = Get-Content -Path $outputOrgXml -Encoding UTF8

Write-Host "--- Applying PAM org setting overrides..."

# AV service (Windows Defender on GCP Server 2022)
$node = $orgXml.OrganizationalSettings.OrganizationalSetting | Where-Object { $_.id -eq "V-254248" }
if ($node) { $node.SetAttribute("ServiceName","WinDefend"); $node.SetAttribute("StartupType","Automatic"); Write-Host "  Set V-254248 ServiceName=WinDefend StartupType=Automatic" }
else { Write-Warning "  V-254248 not found in XML" }

# Firewall service (Windows Defender Firewall on GCP Server 2022)
$node = $orgXml.OrganizationalSettings.OrganizationalSetting | Where-Object { $_.id -eq "V-254265" }
if ($node) { $node.SetAttribute("ServiceName","MpsSvc"); $node.SetAttribute("StartupType","Automatic"); Write-Host "  Set V-254265 ServiceName=MpsSvc StartupType=Automatic" }
else { Write-Warning "  V-254265 not found in XML" }

# Reset account lockout counter >= 15 min
$node = $orgXml.OrganizationalSettings.OrganizationalSetting | Where-Object { $_.id -eq "V-254287" }
if ($node) { $node.SetAttribute("PolicyValue","15"); Write-Host "  Set V-254287 PolicyValue=15" }
else { Write-Warning "  V-254287 not found in XML" }

# Password history >= 24
$node = $orgXml.OrganizationalSettings.OrganizationalSetting | Where-Object { $_.id -eq "V-254288" }
if ($node) { $node.SetAttribute("PolicyValue","24"); Write-Host "  Set V-254288 PolicyValue=24" }
else { Write-Warning "  V-254288 not found in XML" }

# Minimum password length >= 15
$node = $orgXml.OrganizationalSettings.OrganizationalSetting | Where-Object { $_.id -eq "V-254285" }
if ($node) { $node.SetAttribute("PolicyValue","15"); Write-Host "  Set V-254285 PolicyValue=15" }
else { Write-Warning "  V-254285 not found in XML" }

# Account lockout duration 1-3 min
$node = $orgXml.OrganizationalSettings.OrganizationalSetting | Where-Object { $_.id -eq "V-254286" }
if ($node) { $node.SetAttribute("PolicyValue","3"); Write-Host "  Set V-254286 PolicyValue=3" }
else { Write-Warning "  V-254286 not found in XML" }

# Security event log size >= 32768 KB
$node = $orgXml.OrganizationalSettings.OrganizationalSetting | Where-Object { $_.id -eq "V-254358" }
if ($node) { $node.SetAttribute("ValueData","32768"); Write-Host "  Set V-254358 ValueData=32768" }
else { Write-Warning "  V-254358 not found in XML" }

# Application event log size >= 196608 KB
$node = $orgXml.OrganizationalSettings.OrganizationalSetting | Where-Object { $_.id -eq "V-254359" }
if ($node) { $node.SetAttribute("ValueData","196608"); Write-Host "  Set V-254359 ValueData=196608" }
else { Write-Warning "  V-254359 not found in XML" }

# System event log size >= 32768 KB
$node = $orgXml.OrganizationalSettings.OrganizationalSetting | Where-Object { $_.id -eq "V-254360" }
if ($node) { $node.SetAttribute("ValueData","32768"); Write-Host "  Set V-254360 ValueData=32768" }
else { Write-Warning "  V-254360 not found in XML" }

# Account lockout threshold <= 4
$node = $orgXml.OrganizationalSettings.OrganizationalSetting | Where-Object { $_.id -eq "V-254432" }
if ($node) { $node.SetAttribute("ValueData","4"); Write-Host "  Set V-254432 ValueData=4" }
else { Write-Warning "  V-254432 not found in XML" }

# Session lock timeout <= 900 seconds
$node = $orgXml.OrganizationalSettings.OrganizationalSetting | Where-Object { $_.id -eq "V-254456" }
if ($node) { $node.SetAttribute("ValueData","900"); Write-Host "  Set V-254456 ValueData=900" }
else { Write-Warning "  V-254456 not found in XML" }

# Max password age <= 30 days
$node = $orgXml.OrganizationalSettings.OrganizationalSetting | Where-Object { $_.id -eq "V-254454" }
if ($node) { $node.SetAttribute("ValueData","30"); Write-Host "  Set V-254454 ValueData=30" }
else { Write-Warning "  V-254454 not found in XML" }

# Firewall public profile log dropped packets = enabled
$node = $orgXml.OrganizationalSettings.OrganizationalSetting | Where-Object { $_.id -eq "V-254357" }
if ($node) { $node.SetAttribute("ValueData","100"); Write-Host "  Set V-254357 ValueData=100" }
else { Write-Warning "  V-254357 not found in XML" }

# Kerberos encryption type = AES128+AES256
$node = $orgXml.OrganizationalSettings.OrganizationalSetting | Where-Object { $_.id -eq "V-254343.b" }
if ($node) { $node.SetAttribute("ValueData","1"); Write-Host "  Set V-254343.b ValueData=1" }
else { Write-Warning "  V-254343.b not found in XML" }

# LAN Manager auth level = NTLMv2 only
$node = $orgXml.OrganizationalSettings.OrganizationalSetting | Where-Object { $_.id -eq "V-254344" }
if ($node) { $node.SetAttribute("ValueData","8"); Write-Host "  Set V-254344 ValueData=8" }
else { Write-Warning "  V-254344 not found in XML" }

# Audit: Logon/Logoff Logon = Success
$node = $orgXml.OrganizationalSettings.OrganizationalSetting | Where-Object { $_.id -eq "V-254459" }
if ($node) { $node.SetAttribute("ValueData","1"); Write-Host "  Set V-254459 ValueData=1" }
else { Write-Warning "  V-254459 not found in XML" }

# Audit: Account Logon Credential Validation = Success
$node = $orgXml.OrganizationalSettings.OrganizationalSetting | Where-Object { $_.id -eq "V-254484" }
if ($node) { $node.SetAttribute("ValueData","1"); Write-Host "  Set V-254484 ValueData=1" }
else { Write-Warning "  V-254484 not found in XML" }

# Legal banner title (DoD standard)
$node = $orgXml.OrganizationalSettings.OrganizationalSetting | Where-Object { $_.id -eq "V-254458" }
if ($node) { $node.SetAttribute("ValueData","DoD Notice and Consent Banner"); Write-Host "  Set V-254458 ValueData=DoD Notice and Consent Banner" }
else { Write-Warning "  V-254458 not found in XML" }

# Legal banner body (DoD standard)
$node = $orgXml.OrganizationalSettings.OrganizationalSetting | Where-Object { $_.id -eq "V-254457" }
if ($node) { $node.SetAttribute("ValueData","You are accessing a U.S. Government (USG) Information System (IS) that is provided for USG-authorized use only. By using this IS (which includes any device attached to this IS), you consent to the following conditions: -The USG routinely intercepts and monitors communications on this IS for purposes including, but not limited to, penetration testing, COMSEC monitoring, network operations, and known threat detection. -At any time, the USG may inspect and seize data stored on this IS. -Communications using, or data stored on, this IS are not private, are subject to routine monitoring, interception, and search, and may be disclosed or used for any USG-authorized purpose. -This IS includes security measures (e.g., authentication and access controls) to protect USG interests--not for your personal benefit or privacy."); Write-Host "  Set V-254457 ValueData=(DoD banner body)" }
else { Write-Warning "  V-254457 not found in XML" }

# Save the final XML
$orgXml.Save($outputOrgXml)
Write-Host "Org settings XML saved to: $outputOrgXml"

# Print the XML to the Packer log for full visibility
Write-Host "--- Final org settings XML contents:"
Get-Content -Path $outputOrgXml | ForEach-Object { Write-Host "  $_" }

# -----------------------------------------------------------------------
# Step 5: Confirm DSC resources are resolvable
# -----------------------------------------------------------------------
Write-Host "--- Verifying DSC resources..."
Get-DscResource -Module PowerSTIG | Select-Object -First 5 | ForEach-Object {
    Write-Host "  DSC resource OK: $($_.Name)"
}

Write-Host "=== Dependencies installed successfully. ==="
