# create_mof.ps1
# Compiles a DSC MOF using PowerSTIG.


Write-Host "=== create_mof.ps1 starting ==="


# Ensuring all module paths are in PSModulePath

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


# Detecting latest PowerSTIG module

$module = Get-Module PowerSTIG -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
if (-not $module) {
    Write-Error "PowerSTIG module not found. Ensure install_PowerSTIG.ps1 ran successfully."
    exit 1
}
$pstigVersion = $module.Version.ToString()
Write-Host "Found PowerSTIG module $pstigVersion at: $($module.ModuleBase)"


# Detecting STIG XML and parse version

$stigDataPath = Join-Path $module.ModuleBase "StigData\Processed"
$stigXml = Get-ChildItem -Path $stigDataPath -Filter "WindowsServer-2022-MS-*.org.default.xml" |
           Sort-Object Name -Descending | Select-Object -First 1
if (-not $stigXml) {
    Write-Error "No WindowsServer-2022-MS-*.org.default.xml found in $stigDataPath"
    exit 1
}
$stigVersionString = ($stigXml.Name -replace 'WindowsServer-2022-MS-', '' -replace '\.org\.default\.xml', '')
Write-Host "Detected STIG XML: $($stigXml.FullName)"
Write-Host "Detected STIG version: $stigVersionString"


# Paths

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


# Verify DSC resource

Import-Module -Name PowerSTIG -RequiredVersion $pstigVersion -Force
try {
    $dscCheck = Get-DscResource -Name WindowsServer -Module PowerSTIG -ErrorAction Stop
    Write-Host "DSC resource confirmed: $($dscCheck.Name) from $($dscCheck.Module)"
} catch {
    Write-Error "WindowsServer DSC resource not found: $_"
    exit 1
}


# Generate temporary DSC configuration script.

$tempScript = Join-Path $env:TEMP "dsc_config_generated.ps1"

# Escape single quotes in paths for embedding in single-quoted PS strings
$safeOutputPath  = $OutputPath  -replace "'", "''"
$safeOrgSettings = $OrgSettings -replace "'", "''"

$scriptContent = @"
Configuration ApplyWindowsServerStig {
    Import-DscResource -ModuleName PowerSTIG -ModuleVersion $pstigVersion

    Node 'localhost' {
        WindowsServer 'ConfigureServer' {
            OsVersion   = '2022'
            OsRole      = 'MS'
            StigVersion = '$stigVersionString'
            OrgSettings = '$safeOrgSettings'

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

ApplyWindowsServerStig -OutputPath '$safeOutputPath'
"@

Set-Content -Path $tempScript -Value $scriptContent -Encoding UTF8
Write-Host "Generated temporary DSC config script: $tempScript"


# Spawn a fresh PowerShell process to compile the MOF.
# The child process inherits $env:PSModulePath from this process.

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


# Verify MOF was created

$mofFile = Join-Path $OutputPath "localhost.mof"
if (!(Test-Path $mofFile)) {
    Write-Error "MOF file was not generated at: $mofFile"
    exit 1
}

Write-Host "MOF generated: $mofFile"
Write-Host "=== DSC configuration compiled successfully ==="
