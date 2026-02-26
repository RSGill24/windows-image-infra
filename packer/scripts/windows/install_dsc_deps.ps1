# install_dsc_deps.ps1

Write-Host "Installing PowerSTIG dependencies..."

Import-Module PowerSTIG -Force

$module = Get-Module PowerSTIG -ListAvailable |
          Sort-Object Version -Descending |
          Select-Object -First 1

foreach ($dep in $module.RequiredModules) {
    Write-Host "Installing dependency: $($dep.Name) $($dep.Version)"
    Install-Module -Name $dep.Name `
                   -RequiredVersion $dep.Version `
                   -Force `
                   -AllowClobber
}

Write-Host "Dependencies installed successfully."
