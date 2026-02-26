$requiredPaths = @(
    "C:\Program Files\WindowsPowerShell\Modules",           # AllUsers install location
    "C:\Windows\system32\WindowsPowerShell\v1.0\Modules",  # DSC LCM system path
    "C:\Program Files (x86)\WindowsPowerShell\Modules"     # 32-bit fallback
)

foreach ($p in $requiredPaths) {
    if ($p -and ($env:PSModulePath -split ';') -notcontains $p) {
        Write-Host "Adding to PSModulePath: $p"
        $env:PSModulePath = "$p;$env:PSModulePath"
    }
}

Import-Module PowerSTIG -Force

# Derive all paths from $PSScriptRoot so this script works regardless of
# which hardening_target_dir value is passed in from CloudBuild
$HardeningDir = $PSScriptRoot
$OutputPath   = Join-Path $HardeningDir "MOF"
$OrgSettings  = Join-Path $HardeningDir "WindowsServer-2022-MS-2.1.org.pamdata.xml"

Write-Host "Hardening directory : $HardeningDir"
Write-Host "MOF output path     : $OutputPath"
Write-Host "Org settings file   : $OrgSettings"
Write-Host "PSModulePath        : $env:PSModulePath"

# Create the MOF output folder if it does not already exist
if (!(Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    Write-Host "Created MOF output directory."
}

# Validate that the org settings XML is present before attempting MOF compilation
if (!(Test-Path $OrgSettings)) {
    Write-Error "Org settings file not found at: $OrgSettings"
    exit 1
}

# Verify DSC resources are resolvable before attempting compilation
Write-Host "Verifying DSC resources are available..."
try {
    $dscCheck = Get-DscResource -Name WindowsServer -Module PowerSTIG -ErrorAction Stop
    Write-Host "DSC resource confirmed: $($dscCheck.Name) from $($dscCheck.Module)"
} catch {
    Write-Error "WindowsServer DSC resource not found. Ensure install_dsc_deps.ps1 ran successfully. Error: $_"
    exit 1
}

# Define the DSC configuration block
Configuration ApplyWindowsServerStig {
    param (
        [string]$NodeName = 'localhost'   # Target node; 'localhost' applies settings to this machine
    )

    # Import the PowerSTIG DSC composite resource within the configuration context
    Import-DscResource -ModuleName PowerSTIG

    Node $NodeName {
        WindowsServer 'ConfigureServer' {

            OsVersion = '2022'    # Target OS version
            OsRole    = 'MS'      # MS = Member Server (as opposed to DC = Domain Controller)

            # StigVersion omitted to automatically use the latest available version.
            # Version 2.1 was removed from PowerSTIG as of 3/3/25.

            # Org settings XML resolved dynamically from $PSScriptRoot /
            # CloudBuild _HARDENING_TARGET_DIR
            OrgSettings = $OrgSettings

            # Exceptions override specific STIG rules where the default would break
            # legitimate GCP/IAP remote access workflows or cost-saving features.
            Exception = @{

                # --- Remote Desktop Access Exceptions ---
                # Allow local accounts (Guests excluded from deny list) to use Remote Desktop
                'V-254439' = @{ 'Identity' = 'Guests' }

                # Allow Admin accounts (Guests excluded from deny list) to connect via RDP
                'V-254435' = @{ 'Identity' = 'Guests' }

                # --- Shutdown Rights Exception ---
                # Allow any logged-in user to shut down the machine to enhance cost savings.
                # 'Everyone' used because PowerSTIG does not correctly format multi-value
                # responses for this rule (e.g., Administrators + Local).
                'V-254501' = @{ 'Identity' = 'Everyone' }

                # --- Password Policy Exceptions ---
                # The following rules are waived because GCP/IAP handles authentication
                # externally. No direct local password access is permitted by GCP networking.

                # Allow blank passwords (GCP manages authentication)
                'V-254446' = @{ 'ValueData' = '0' }

                # Permit use of blank passwords at the policy level
                'V-254289' = @{ 'PolicyValue' = '0' }

                # Disable minimum password age so pam_admin password can be cycled on demand,
                # removing the need to store, memorize, or version-manage it across images
                'V-254290' = @{ 'PolicyValue' = '0' }

                # Allow blank password at the policy level
                'V-254291' = @{ 'PolicyValue' = '0' }

                # Disable password complexity requirement (GCP handles auth)
                'V-254292' = @{ 'PolicyValue' = 'Disabled' }
            }

            # Rules skipped entirely due to known bugs or features not present in this environment
            SkipRule = @(
                'V-254254.c',  # Known PowerSTIG bug — see https://github.com/microsoft/PowerStig/issues/1360
                'V-254271'     # PNRP (Peer Name Resolution Protocol) feature not present on Server 2022/2025
            )
        }
    }
}

# Compile the DSC configuration and write the MOF file to $OutputPath
Write-Host "Generating MOF..."
ApplyWindowsServerStig -OutputPath $OutputPath

# Confirm the MOF was actually created before attempting to apply it
$mofFile = Join-Path $OutputPath "localhost.mof"
if (!(Test-Path $mofFile)) {
    Write-Error "MOF file was not generated at: $mofFile"
    exit 1
}
Write-Host "MOF generated successfully: $mofFile"

# Apply the compiled MOF to enforce STIG settings on the local machine
# -Wait    : Block until the DSC job completes (synchronous execution)
# -Verbose : Stream detailed progress output to the console
# -Force   : Apply even if a DSC job is already running
Write-Host "Applying DSC configuration..."
Start-DscConfiguration `
    -Path $OutputPath `
    -Wait `
    -Verbose `
    -Force

Write-Host "STIG applied successfully."
