# install_PowerSTIG.ps1
# Installs the PowerSTIG module from the PowerShell Gallery.
# PowerSTIG is a PowerShell DSC composite resource that automates the application
# of DISA Security Technical Implementation Guides (STIGs) to Windows systems.
#
# -Scope CurrentUser  : Installs for the current user only (no system-wide admin rights needed for the install itself)
# -Force              : Skips confirmation prompts and overwrites any existing version

Install-Module -Name PowerStig -Scope CurrentUser -Force
