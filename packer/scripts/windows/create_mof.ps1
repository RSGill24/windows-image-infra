# create_mof.ps1
# Compiles a DSC MOF (Managed Object Format) configuration file that encodes all
# DISA STIG settings for Windows Server 2022 (Member Server role) using PowerSTIG.
#
# The resulting MOF file is written to: .\ApplyWindowsServerStig\localhost.mof
# This MOF is later consumed by apply_mof.ps1 to enforce settings,
# and by audit.ps1 to test compliance via Test-DscConfiguration.
#
# Must be run as Administrator.
# Requires PowerSTIG and all DSC dependencies to be installed first.

# Import the PowerSTIG module so the WindowsServer DSC composite resource is available
Import-Module PowerSTIG

# Define the DSC configuration block
Configuration ApplyWindowsServerStig {
    param
    (
        [parameter()]
        [string]
        $NodeName = 'localhost'   # Target node; 'localhost' applies settings to this machine
    )

    # Import the PowerSTIG DSC resource module within the configuration context
    Import-DscResource -ModuleName PowerSTIG

    Node $NodeName {
        WindowsServer 'ConfigureServer' {

            OsVersion   = '2022'    # Target OS version
            OsRole      = 'MS'      # MS = Member Server (as opposed to DC = Domain Controller)

            # StigVersion is commented out to automatically use the latest available STIG version.
            # Version 2.1 was removed from PowerSTIG as of 3/3/25.
            #StigVersion = '2.1'

            # Path to the org settings XML file that customizes allowed-range STIG values
            # for this environment (e.g., log sizes, lockout thresholds, legal banner text).
            OrgSettings = "$PSScriptRoot\WindowsServer-2022-MS-2_1_org_pamdata.xml"

            # Exceptions override specific STIG rules where the default would break
            # legitimate GCP/IAP remote access workflows or cost-saving features.
            Exception   = @{

                # --- Remote Desktop Access Exceptions ---
                # Allow local accounts (Guests excluded from deny list) to use Remote Desktop.
                'V-254439' = @{'Identity'='Guests'}

                # Allow Admin accounts (Guests excluded from deny list) to connect via RDP.
                'V-254435' = @{'Identity'='Guests'}

                # --- Shutdown Rights Exception ---
                # Allow any logged-in user to shut down the machine.
                # Enhances cost savings by not restricting shutdown to admins only.
                # 'Everyone' is used because PowerSTIG does not correctly format
                # multi-value responses for this rule (e.g., Administrators + Local).
                'V-254501' = @{'Identity'='Everyone'}

                # --- Password Policy Exceptions ---
                # The following password rules are waived because GCP/IAP handles
                # authentication externally. No direct local password access is permitted
                # by GCP networking policies, making strict local password rules redundant.

                # Allow blank passwords (GCP manages authentication)
                'V-254446' = @{'ValueData'='0'}

                # Permit use of blank passwords at the policy level
                'V-254289' = @{'PolicyValue'='0'}

                # Disable minimum password age so pam_admin password can be cycled on demand.
                # This removes the need to store, memorize, or version-manage the password
                # across different images.
                'V-254290' = @{'PolicyValue'='0'}

                # Allow blank password (policy level)
                'V-254291' = @{'PolicyValue'='0'}

                # Disable password complexity requirement (GCP handles auth)
                'V-254292' = @{'PolicyValue'='Disabled'}
            }

            # Rules to skip entirely due to known PowerSTIG bugs or incompatibilities.
            # V-254254.c: Skipped due to an open PowerSTIG bug.
            # See: https://github.com/microsoft/PowerStig/issues/1360
            SkipRule = @('V-254254.c')
            SkipRule = @('V-254271')
        }
    }
}

# Compile the configuration and output the MOF file to the ApplyWindowsServerStig subfolder.
# The -OutputPath ensures the MOF is written relative to this script's directory,
# regardless of the current working directory when the script is invoked.
ApplyWindowsServerStig -OutputPath "$PSScriptRoot\ApplyWindowsServerStig"
