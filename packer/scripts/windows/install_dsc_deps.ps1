# install_dsc_deps.ps1
# Installs all PowerShell DSC resource module dependencies required by PowerSTIG.
#
# PowerSTIG relies on several supporting DSC resource modules (e.g., AuditPolicyDsc,
# SecurityPolicyDsc, xDnsServer, etc.). This script automatically discovers those
# required modules from the installed PowerSTIG manifest and installs each one.
#
# Must be run AFTER install_PowerSTIG.ps1 and BEFORE create_mof.ps1.
# The DSC resources must be present on disk before the MOF can be compiled.

# Retrieve the list of required modules declared in the PowerSTIG module manifest,
# then pipe each one to Install-Module to ensure all dependencies are available.
$(Get-Module PowerStig -ListAvailable).RequiredModules | ForEach-Object {
    $PSITEM | Install-Module -Force
}
