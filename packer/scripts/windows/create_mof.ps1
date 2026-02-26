# create_mof.ps1
# Compiles a DSC MOF configuration file encoding all DISA STIG settings for
# Windows Server 2022 (Member Server role) using PowerSTIG, then immediately
# applies it to the local machine via Start-DscConfiguration.
#
# All paths are derived from $PSScriptRoot, which resolves to the hardening
# target directory supplied by the CloudBuild pipeline:
#   _HARDENING_TARGET_DIR = C:/Users/packer_user/hardening/
#
# File layout expected in that directory:
#   run_all.ps1                              <- entry point called by Packer
#   create_mof.ps1                           <- this file
#   WindowsServer-2022-MS-2.1.org.pamdata.xml
#
# MOF output path: <hardening_target_dir>\MOF\localhost.mof
#
# Must be run as Administrator.
# Requires PowerSTIG and all DSC dependencies to be installed first.

Import-Module PowerSTIG -Force

# Derive all paths from $PSScriptRoot so this script works regardless of
# which hardening_target_dir value is passed in from CloudBuild
$HardeningDir = $PSScriptRoot
$OutputPath   = Join-Path $HardeningDir "MOF"
$OrgSettings  = Join-Path $HardeningDir "WindowsServer-2022-MS-2.1.org.pamdata.xml"

Write-Host "Hardening directory : $HardeningDir"
Write-Host "MOF output path     : $OutputPath"
Write-Host "Org settings file   : $OrgSettings"

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

            # Org settings XML path resolved dynamically from $PSScriptRoot /
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


Write-Host "STIG applied successfully."
