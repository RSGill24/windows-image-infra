# apply_mof.ps1
# Applies the compiled DSC MOF configuration to the local machine to enforce
# all DISA STIG settings defined in create_mof.ps1.
#
# This script uses Start-DscConfiguration to push the MOF in the
# ApplyWindowsServerStig folder to localhost.
#
# Flags used:
#   -Path     : Directory containing the compiled localhost.mof file
#   -Wait     : Block execution until the DSC job completes (synchronous)
#   -Verbose  : Stream detailed progress output to the console
#   -Force    : Apply the configuration even if a DSC job is already running
#
# Must be run as Administrator.
# Requires create_mof.ps1 to have been run first to generate the MOF file.

Start-DscConfiguration -Path "$PSScriptRoot\ApplyWindowsServerStig" -Wait -Verbose -ComputerName 'localhost' -Force
