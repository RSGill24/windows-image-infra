# apply_mof.ps1
# Applies the compiled DSC MOF and verifies configuration state.

param (
    [string]$HardeningDir = $PSScriptRoot
)

Write-Host "=== Applying DSC configuration ==="

$OutputPath = Join-Path $HardeningDir "MOF"
$mofFile    = Join-Path $OutputPath "localhost.mof"

if (!(Test-Path $mofFile)) {
    Write-Error "MOF file not found at: $mofFile -- ensure create_mof.ps1 ran successfully."
    exit 1
}
Write-Host "Found MOF: $mofFile"

# -----------------------------------------------------------------------
# Configure LCM: ApplyAndAutoCorrect ensures drift is re-remediated on reboot
# -----------------------------------------------------------------------
Write-Host "Configuring LCM..."

[DSCLocalConfigurationManager()]
Configuration LCMConfig {
    Node localhost {
        Settings {
            RefreshMode        = 'Push'
            ConfigurationMode  = 'ApplyAndAutoCorrect'
            RebootNodeIfNeeded = $false
            ActionAfterReboot  = 'ContinueConfiguration'
        }
    }
}

$lcmPath = Join-Path $HardeningDir "LCM"
if (!(Test-Path $lcmPath)) { New-Item -Path $lcmPath -ItemType Directory -Force | Out-Null }
LCMConfig -OutputPath $lcmPath | Out-Null
Set-DscLocalConfigurationManager -Path $lcmPath -Force
Write-Host "LCM configured: ApplyAndAutoCorrect"

# -----------------------------------------------------------------------
# Apply the STIG MOF
# -----------------------------------------------------------------------
Write-Host "Applying DSC STIG configuration..."
Start-DscConfiguration -Path $OutputPath -Wait -Force -Verbose -ErrorAction Stop

# -----------------------------------------------------------------------
# Post-apply verification
# -----------------------------------------------------------------------
Write-Host "Verifying DSC configuration state..."
$result = Test-DscConfiguration -Detailed

if ($result.InDesiredState) {
    Write-Host "=== All DSC resources are in desired state. ==="
} else {
    Write-Warning "The following resources are NOT in desired state after apply:"
    $result.ResourcesNotInDesiredState | ForEach-Object {
        Write-Warning "  NOT COMPLIANT: $($_.ResourceId)"
    }
    Write-Warning "Note: V-254284 (Secure Boot) is expected here -- handled at Packer layer."
}

Write-Host "=== DSC configuration applied. ==="
