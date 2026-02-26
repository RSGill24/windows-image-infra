# install_dsc_deps.ps1
# Installs all PowerShell DSC resource dependencies for PowerSTIG
# Copies modules to DSC system path and generates STIG 2.1 XML for Packer

param (
    [string]$HardeningDir = "C:\Users\packer_user\hardening"
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
# Step 1: Install dependencies
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
# Step 2: Copy PowerSTIG itself into DSC system path
# -----------------------------------------------------------------------
Write-Host "--- Copying PowerSTIG to DSC system path..."
$pstigSrc    = $module.ModuleBase
$pstigDstDir = Join-Path $dscSystemPath "PowerSTIG"
$pstigDst    = Join-Path $pstigDstDir   $module.Version
if (!(Test-Path $pstigDstDir)) { New-Item -Path $pstigDstDir -ItemType Directory -Force | Out-Null }
Copy-Item -Path $pstigSrc -Destination $pstigDst -Recurse -Force
Write-Host "    Copied to: $pstigDst"

# -----------------------------------------------------------------------
# Step 3: Locate default STIG 2.1 XML
# -----------------------------------------------------------------------
$stigDataPath = Join-Path $module.ModuleBase "StigData\Processed"
$defaultOrgFile = Get-ChildItem -Path $stigDataPath `
                    -Filter "WindowsServer-2022-MS-2.1.org.default.xml" `
                    -ErrorAction SilentlyContinue |
                  Select-Object -First 1

if (-not $defaultOrgFile) {
    Write-Error "No STIG 2.1 default XML found in $stigDataPath"
    exit 1
}

Write-Host "Found default XML: $($defaultOrgFile.FullName)"

# -----------------------------------------------------------------------
# Step 4: Copy to fixed path for Packer and apply PAM overrides
# -----------------------------------------------------------------------
$outputOrgXml = Join-Path $HardeningDir "WindowsServer-2022-MS-2.1.org.pamdata.xml"
Write-Host "Copying to fixed path: $outputOrgXml"
Copy-Item -Path $defaultOrgFile.FullName -Destination $outputOrgXml -Force

[xml]$orgXml = Get-Content -Path $outputOrgXml -Encoding UTF8

Write-Host "--- Applying PAM org setting overrides ---"

# Define PAM overrides in a hash table
$PamOverrides = @{
    "V-254248" = @{ "ServiceName"="WinDefend"; "StartupType"="Automatic" }
    "V-254265" = @{ "ServiceName"="MpsSvc"; "StartupType"="Automatic" }
    "V-254287" = @{ "PolicyValue"="15" }
    "V-254288" = @{ "PolicyValue"="24" }
    "V-254285" = @{ "PolicyValue"="15" }
    "V-254286" = @{ "PolicyValue"="3" }
    "V-254358" = @{ "ValueData"="32768" }
    "V-254359" = @{ "ValueData"="196608" }
    "V-254360" = @{ "ValueData"="32768" }
    "V-254432" = @{ "ValueData"="4" }
    "V-254456" = @{ "ValueData"="900" }
    "V-254454" = @{ "ValueData"="30" }
    "V-254357" = @{ "ValueData"="100" }
    "V-254343.b" = @{ "ValueData"="1" }
    "V-254344" = @{ "ValueData"="8" }
    "V-254459" = @{ "ValueData"="1" }
    "V-254484" = @{ "ValueData"="1" }
    "V-254458" = @{ "ValueData"="DoD Notice and Consent Banner" }
    "V-254457" = @{ "ValueData"="You are accessing a U.S. Government (USG) Information System (IS) that is provided for USG-authorized use only. By using this IS (which includes any device attached to this IS), you consent to the following conditions: -The USG routinely intercepts and monitors communications on this IS for purposes including, but not limited to, penetration testing, COMSEC monitoring, network operations, and known threat detection. -At any time, the USG may inspect and seize data stored on this IS. -Communications using, or data stored on, this IS are not private, are subject to routine monitoring, interception, and search, and may be disclosed or used for any USG-authorized purpose. -This IS includes security measures (e.g., authentication and access controls) to protect USG interests--not for your personal benefit or privacy." }
}

foreach ($id in $PamOverrides.Keys) {
    $node = $orgXml.OrganizationalSettings.OrganizationalSetting | Where-Object { $_.id -eq $id }
    if ($node) {
        foreach ($attr in $PamOverrides[$id].Keys) {
            $node.SetAttribute($attr, $PamOverrides[$id][$attr])
        }
        Write-Host "  Set $id overrides"
    } else {
        Write-Warning "  $id not found in XML"
    }
}

# Save XML
$orgXml.Save($outputOrgXml)
Write-Host "Org settings XML saved to: $outputOrgXml"

# -----------------------------------------------------------------------
# Step 5: Verify DSC resources are resolvable
# -----------------------------------------------------------------------
Write-Host "--- Verifying DSC resources..."
Get-DscResource -Module PowerSTIG | Select-Object -First 5 | ForEach-Object {
    Write-Host "  DSC resource OK: $($_.Name)"
}

Write-Host "=== Dependencies installed successfully ==="
