Write-Host "Installing PowerSTIG..."

# Enforce TLS 1.2 so PSGallery HTTPS connections succeed on older .NET defaults.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Install NuGet provider FIRST — required before Set-PSRepository or Install-Module
# can reach PSGallery. -ForceBootstrap avoids the interactive ShouldContinue prompt
# that throws NullReferenceException under non-interactive contexts (WinRM, SYSTEM).
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ForceBootstrap
}

# Trust PSGallery so Install-Module does not prompt for confirmation.
if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
}

# Install PowerSTIG for all users so it is available system-wide (e.g., SYSTEM
# scheduled task context). -AllowClobber overwrites any conflicting commands.
Install-Module -Name PowerSTIG -Scope AllUsers -Force -AllowClobber -AcceptLicense

# Import into the current session so subsequent scripts can use it immediately.
Import-Module PowerSTIG -Force

Write-Host "PowerSTIG installed successfully."
