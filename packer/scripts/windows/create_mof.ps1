# create_mof.ps1
# Compiles a DSC MOF and applies it via Start-DscConfiguration.
# Automatically applies STIG 2.1 on Windows Server 2022 VM

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

Import-Module PowerSTIG -Force

# -----------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------
$HardeningDir = $PSScriptRoot
$OutputPath   = Join-Path $HardeningDir "MOF"

# Use the STIG 2.1 org XML you already have
$OrgSettings  = Join-Path $HardeningDir "packer/scripts/windows/WindowsServer-2022-MS-2.1.org.pamdata.xml"

Write-Host "Hardening directory : $HardeningDir"
Write-Host "MOF output path     : $OutputPath"
Write-Host "Org settings file   : $OrgSettings"
Write-Host "PSModulePath        : $env:PSModulePath"

# Create MOF output folder if it does not exist
if (!(Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    Write-Host "Created MOF output directory."
}

# Validate the org settings XML
if (!(Test-Path $OrgSettings)) {
    Write-Error "Org settings XML not found at: $OrgSettings"
    Write-Error "Ensure the STIG 2.1 org XML exists in the specified path."
    exit 1
}

# -----------------------------------------------------------------------
# Verify DSC resource
# -----------------------------------------------------------------------
Write-Host "--- Verifying DSC resources..."
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
        [string]$OrgSettingsPath
    )

    Import-DscResource -ModuleName PowerSTIG

    Node $NodeName {
        WindowsServer 'ConfigureServer' {

            OsVersion   = '2022'
            OsRole      = 'MS'
            StigVersion = '2.1'

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
Write-Host "=== Generating and applying MOF... ==="

# Compile the MOF
ApplyWindowsServerStig -OutputPath $OutputPath -OrgSettingsPath $OrgSettings

$mofFile = Join-Path $OutputPath "localhost.mof"
if (!(Test-Path $mofFile)) {
    Write-Error "MOF file was not generated at: $mofFile"
    exit 1
}
Write-Host "MOF generated: $mofFile"

# Apply DSC configuration automatically
Write-Host "=== Applying DSC configuration... ==="
Start-DscConfiguration -Path $OutputPath -Wait -Force -Verbose

Write-Host "=== DSC configuration applied successfully ==="
