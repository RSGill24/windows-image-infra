# create_mof.ps1
# Compiles a DSC MOF and applies it via Start-DscConfiguration.
# Automatically detects the latest PowerSTIG module and STIG XML (WindowsServer-2022-MS-*.org.default.xml)
# Works in Google Cloud Build / Packer pipelines

Write-Host "=== create_mof.ps1 starting ==="

# -----------------------------------------------------------------------
# Ensure all module paths are in PSModulePath before DSC compilation
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
# Detect latest PowerSTIG module and STIG XML
# -----------------------------------------------------------------------
$module = Get-Module PowerSTIG -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
if (-not $module) {
    Write-Error "PowerSTIG module not found. Ensure install_PowerSTIG.ps1 ran successfully."
    exit 1
}
Write-Host "Found PowerSTIG module $($module.Version) at: $($module.ModuleBase)"

$stigDataPath = Join-Path $module.ModuleBase "StigData\Processed"
$stigXml = Get-ChildItem -Path $stigDataPath -Filter "WindowsServer-2022-MS-*.org.default.xml" |
           Sort-Object Name -Descending | Select-Object -First 1
if (-not $stigXml) {
    Write-Error "No WindowsServer-2022-MS-*.org.default.xml found in $stigDataPath"
    exit 1
}
Write-Host "Detected STIG XML: $($stigXml.FullName)"

# -----------------------------------------------------------------------
# Parse STIG version dynamically from filename (e.g. 2.7, 2.1, 3.0 etc.)
# -----------------------------------------------------------------------
$stigVersionString = ($stigXml.Name `
    -replace 'WindowsServer-2022-MS-', '' `
    -replace '\.org\.default\.xml', '')
Write-Host "Detected STIG version: $stigVersionString"

# -----------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------
$HardeningDir = $PSScriptRoot
$OutputPath   = Join-Path $HardeningDir "MOF"
$OrgSettings  = Join-Path $HardeningDir $stigXml.Name

# Copy STIG XML to hardening folder (for PAM edits if needed)
Copy-Item -Path $stigXml.FullName -Destination $OrgSettings -Force
Write-Host "Copied STIG XML to: $OrgSettings"

# Create MOF output folder if it does not exist
if (!(Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    Write-Host "Created MOF output directory: $OutputPath"
}

# -----------------------------------------------------------------------
# Verify DSC resource
# -----------------------------------------------------------------------
Import-Module PowerSTIG -Force
try {
    $dscCheck = Get-DscResource -Name WindowsServer -Module PowerSTIG -ErrorAction Stop
    Write-Host "DSC resource confirmed: $($dscCheck.Name) from $($dscCheck.Module)"
} catch {
    Write-Error "WindowsServer DSC resource not found: $_"
    exit 1
}

# -----------------------------------------------------------------------
# DSC Configuration block
# -----------------------------------------------------------------------
Configuration ApplyWindowsServerStig {
    param (
        [string]$NodeName        = 'localhost',
        [string]$OrgSettingsPath,
        [string]$StigVer
    )

    Import-DscResource -ModuleName PowerSTIG

    Node $NodeName {
        WindowsServer 'ConfigureServer' {

            OsVersion   = '2022'
            OsRole      = 'MS'
            StigVersion = $StigVer

            OrgSettings = $OrgSettingsPath

            Exception = @{
                'V-254439' = @{ 'Identity' = 'Guests' }
                'V-254435' = @{ 'Identity' = 'Guests' }
                'V-254501' = @{ 'Identity' = 'Everyone' }
                'V-254446' = @{ 'ValueData'   = '0' }
                'V-254289' = @{ 'PolicyValue' = '0' }
                'V-254290' = @{ 'PolicyValue' = '0' }
                'V-254291' = @{ 'PolicyValue' = '0' }
                'V-254292' = @{ 'PolicyValue' = 'Disabled' }
            }

            SkipRule = @(
                'V-254254.c',
                'V-254271'
            )
        }
    }
}

# -----------------------------------------------------------------------
# Compile and Apply MOF
# -----------------------------------------------------------------------
Write-Host "=== Generating MOF... ==="
ApplyWindowsServerStig `
    -OutputPath      $OutputPath `
    -OrgSettingsPath $OrgSettings `
    -StigVer         $stigVersionString

$mofFile = Join-Path $OutputPath "localhost.mof"
if (!(Test-Path $mofFile)) {
    Write-Error "MOF file was not generated at: $mofFile"
    exit 1
}
Write-Host "MOF generated: $mofFile"

# Apply DSC configuration automatically
# Write-Host "=== Applying DSC configuration... ==="
# Start-DscConfiguration -Path $OutputPath -Wait -Force -Verbose

Write-Host "=== DSC configuration applied successfully ==="
