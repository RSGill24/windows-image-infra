# install_dsc_deps.ps1
# Installs PowerSTIG dependencies, copies modules to DSC LCM path,
# generates org settings XML with PAM overrides.
# Safe for GCP Cloud Build / Packer pipelines.

param (
    [string]$HardeningDir = $PSScriptRoot
)

Write-Host "=== Installing PowerSTIG dependencies ==="

# -----------------------------------------------------------------------
# Step 0: Import PowerSTIG and detect latest module
# -----------------------------------------------------------------------
$module = Get-Module PowerSTIG -ListAvailable |
          Sort-Object Version -Descending | Select-Object -First 1

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
        Write-Warning "    Source not found at $srcPath -- skipping copy"
    }
}

# -----------------------------------------------------------------------
# Step 2: Copy PowerSTIG itself into the DSC LCM system32 path
# -----------------------------------------------------------------------
$pstigSrc    = $module.ModuleBase
$pstigDstDir = Join-Path $dscSystemPath "PowerSTIG"
$pstigDst    = Join-Path $pstigDstDir   $module.Version
if (!(Test-Path $pstigDstDir)) { New-Item -Path $pstigDstDir -ItemType Directory -Force | Out-Null }
Copy-Item -Path $pstigSrc -Destination $pstigDst -Recurse -Force
Write-Host "Copied PowerSTIG module to DSC path: $pstigDst"

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
    exit 1
}
Write-Host "Found org.default.xml: $($defaultOrgFile.FullName)"

# -----------------------------------------------------------------------
# Step 4: Copy the default XML to the hardening dir and apply PAM overrides
# Dynamic filename -- picks up whatever version is installed (2.7, 3.0, etc.)
# -----------------------------------------------------------------------
$outputOrgXml = Join-Path $HardeningDir ($defaultOrgFile.Name -replace '\.org\.default\.xml', '.org.pamdata.xml')
Copy-Item -Path $defaultOrgFile.FullName -Destination $outputOrgXml -Force
Write-Host "Copied XML to: $outputOrgXml"

[xml]$orgXml = Get-Content -Path $outputOrgXml -Encoding UTF8

Write-Host "--- Applying PAM org setting overrides..."

# Example PAM overrides (can expand for all V-IDs you need)
$overrides = @{
    "V-254248"  = @{ ServiceName="WinDefend"; StartupType="Automatic" }
    "V-254265"  = @{ ServiceName="MpsSvc"; StartupType="Automatic" }
    "V-254287"  = @{ PolicyValue="15" }
    "V-254288"  = @{ PolicyValue="24" }
    "V-254285"  = @{ PolicyValue="15" }
    "V-254286"  = @{ PolicyValue="3" }
}

foreach ($vid in $overrides.Keys) {
    $node = $orgXml.OrganizationalSettings.OrganizationalSetting | Where-Object { $_.id -eq $vid }
    if ($node) {
        foreach ($attr in $overrides[$vid].Keys) {
            $node.SetAttribute($attr, $overrides[$vid][$attr])
        }
        Write-Host "  Set $vid overrides: $($overrides[$vid] | Out-String)"
    } else {
        Write-Warning "  $vid not found in XML"
    }
}

# Save the final XML
$orgXml.Save($outputOrgXml)
Write-Host "Org settings XML saved to: $outputOrgXml"

# -----------------------------------------------------------------------
# Step 5: Verify DSC resources
# -----------------------------------------------------------------------
Write-Host "--- Verifying DSC resources..."
Get-DscResource -Module PowerSTIG | Select-Object -First 5 | ForEach-Object {
    Write-Host "  DSC resource OK: $($_.Name)"
}

Write-Host "=== Dependencies installed successfully. ==="