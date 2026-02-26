# apply_mof.ps1



Write-Host "=== Applying DSC configuration ==="

# Resolve MOF path relative to this script's directory -- $OutputPath from
# create_mof.ps1 does not carry over into a separate script invocation
$OutputPath = Join-Path $PSScriptRoot "MOF"
$mofFile    = Join-Path $OutputPath "localhost.mof"

# Fail fast if MOF was never compiled
if (!(Test-Path $mofFile)) {
    Write-Error "MOF file not found at: $mofFile -- ensure create_mof.ps1 ran successfully before this script."
    exit 1
}

Write-Host "Found MOF: $mofFile"
Write-Host "Applying DSC configuration..."

Start-DscConfiguration -Path $OutputPath -Wait -Force -Verbose

if ($LASTEXITCODE -ne 0) {
    Write-Error "Start-DscConfiguration failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host "=== STIG applied successfully. ==="
