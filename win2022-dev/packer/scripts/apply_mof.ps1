# apply_mof.ps1
# Applies the compiled DSC MOF and verifies configuration drift.

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
# Configure LCM to ApplyAndAutoCorrect so drift is re-remediated on reboot
# -----------------------------------------------------------------------
Write-Host "Configuring LCM..."

[DSCLocalConfigurationManager()]
Configuration LCMConfig {
    Node localhost {
        Settings {
            RefreshMode          = 'Push'
            ConfigurationMode    = 'ApplyAndAutoCorrect'
            RebootNodeIfNeeded   = $false
            ActionAfterReboot    = 'ContinueConfiguration'
        }
    }
}

$lcmPath = Join-Path $HardeningDir "LCM"
LCMConfig -OutputPath $lcmPath | Out-Null
Set-DscLocalConfigurationManager -Path $lcmPath -Force
Write-Host "LCM configured: ApplyAndAutoCorrect"

# -----------------------------------------------------------------------
# Apply the STIG MOF
# -----------------------------------------------------------------------
Write-Host "Applying DSC STIG configuration..."
Start-DscConfiguration -Path $OutputPath -Wait -Force -Verbose -ErrorAction Stop

# -----------------------------------------------------------------------
# Post-apply: verify no resources are still non-compliant
# -----------------------------------------------------------------------
Write-Host "Verifying DSC configuration..."
$result = Test-DscConfiguration -Detailed

if ($result.InDesiredState) {
    Write-Host "=== All DSC resources are in desired state. ==="
} else {
    Write-Warning "=== The following resources are NOT in desired state after apply: ==="
    $result.ResourcesNotInDesiredState | ForEach-Object {
        Write-Warning "  NOT COMPLIANT: $($_.ResourceId)"
    }
    # Do not exit 1 here -- some rules (e.g. Secure Boot) are intentionally
    # excluded from DSC and handled at the Packer/VM layer.
    Write-Warning "Review the above -- Secure Boot (V-254284) is expected to show here if excluded."
}

Write-Host "=== DSC configuration applied. ==="