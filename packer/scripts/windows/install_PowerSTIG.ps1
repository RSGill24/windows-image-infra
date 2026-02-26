# install_PowerSTIG.ps1

Write-Host "Installing PowerSTIG..."

# Ensure TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Trust PSGallery
if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
}

# Install NuGet if missing
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -Force
}

# Install PowerSTIG
Install-Module -Name PowerSTIG -Scope AllUsers -Force -AllowClobber

Import-Module PowerSTIG -Force

Write-Host "PowerSTIG installed successfully."
