# install_dsc_deps.ps1
# Installs PowerSTIG required module dependencies.

$(Get-Module PowerStig -ListAvailable).RequiredModules | % { $PSITEM | Install-Module -Force }
