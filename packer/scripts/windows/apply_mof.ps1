Write-Host "=== Applying DSC configuration..."
Start-DscConfiguration `
    -Path    $OutputPath `
    -Wait `
    -Verbose `
    -Force

Write-Host "=== STIG applied successfully. ==="
