Write-Host "Applying DSC configuration..."
Start-DscConfiguration `
    -Path $OutputPath `
    -Wait `
    -Verbose `
    -Force
