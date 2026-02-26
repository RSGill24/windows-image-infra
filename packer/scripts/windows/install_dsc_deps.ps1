Write-Host "Installing PowerSTIG dependencies..."

# Import PowerSTIG so its module manifest is accessible
Import-Module PowerSTIG -Force

# Retrieve the highest installed version of PowerSTIG to read its dependency list
$module = Get-Module PowerSTIG -ListAvailable |
          Sort-Object Version -Descending |
          Select-Object -First 1

# Iterate over each declared required module and install at the exact version specified
foreach ($dep in $module.RequiredModules) {
    Write-Host "Installing dependency: $($dep.Name) $($dep.Version)"
    Install-Module -Name $dep.Name `
                   -RequiredVersion $dep.Version `
                   -Force `
                   -AllowClobber   # Prevent errors if commands overlap with existing modules
}

Write-Host "Dependencies installed successfully."
