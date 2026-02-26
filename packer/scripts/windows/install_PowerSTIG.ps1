# Install NuGet Provider
Install-PackageProvider -Name NuGet -Force
 
# Trust PSGallery
Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
 
# Install PowerSTIG
Install-Module -Name PowerSTIG -Force
 
# Apply Windows Server 2022 STIG
Import-Module PowerSTIG
 
$stig = Get-Stig -Name WindowsServer -Version 2022
Invoke-Stig -Stig $stig -Apply
