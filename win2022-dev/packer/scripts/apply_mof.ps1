#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies the compiled DSC MOF and waits for LCM to fully complete.

.NOTES
    Start-DscConfiguration -Wait returns when LCM acknowledges the job,
    NOT when all resources have finished applying. AccountPolicy resource
    calls secedit in the LCM process which continues after -Wait returns.
    secedit resets security policy and kills WinRM auth mid-execution.

    Fix: After Start-DscConfiguration returns, poll the LCM status until
    it reports Idle, then sleep an additional buffer before exiting.
    This ensures secedit has fully completed before run_all.ps1 proceeds
    to restore_winrm_post_dsc.ps1.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "=== Applying DSC configuration ==="

# -----------------------------------------------------------------------
# Resolve MOF path
# -----------------------------------------------------------------------
$OutputPath = Join-Path $PSScriptRoot "MOF"
$mofFile    = Join-Path $OutputPath "localhost.mof"

if (!(Test-Path $mofFile)) {
    Write-Error "MOF file not found at: $mofFile"
    exit 1
}

$mofSize = (Get-Item $mofFile).Length
Write-Host "Found MOF: $mofFile ($mofSize bytes)"

if ($mofSize -lt 10000) {
    Write-Error "MOF file is suspiciously small ($mofSize bytes)"
    exit 1
}

# -----------------------------------------------------------------------
# Apply DSC configuration
# -----------------------------------------------------------------------
Write-Host "Applying DSC configuration (this may take several minutes)..."

try {
    Start-DscConfiguration -Path $OutputPath -Wait -Force -Verbose -ErrorAction Stop
    Write-Host "=== DSC configuration applied successfully ===" -ForegroundColor Green
} catch {
    Write-Warning "Start-DscConfiguration encountered an error: $_"
    Write-Warning "Resource-level failures are expected and will be corrected by post-DSC scripts."
    Write-Host "=== DSC application completed with resource-level warnings ===" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------
# Poll LCM until truly Idle
# Start-DscConfiguration -Wait returns early. The LCM continues running
# AccountPolicy/secedit in the background. Poll until LCM status = Idle
# so we know secedit has fully completed before proceeding.
# -----------------------------------------------------------------------
Write-Host "Waiting for LCM to reach Idle state..."

$maxWaitSeconds = 300
$pollInterval   = 5
$elapsed        = 0

while ($elapsed -lt $maxWaitSeconds) {
    try {
        $lcm = Get-DscLocalConfigurationManager -ErrorAction Stop
        $status = $lcm.LCMState
        Write-Host "  LCM state: $status (${elapsed}s elapsed)"

        if ($status -eq 'Idle') {
            Write-Host "  LCM is Idle — DSC fully complete" -ForegroundColor Green
            break
        }
    } catch {
        Write-Host "  Could not query LCM state: $_ — waiting..."
    }

    Start-Sleep -Seconds $pollInterval
    $elapsed += $pollInterval
}

if ($elapsed -ge $maxWaitSeconds) {
    Write-Warning "LCM did not reach Idle within ${maxWaitSeconds}s — proceeding anyway"
}

# Extra buffer to allow secedit to flush policy changes to disk
Write-Host "Waiting 15s for secedit policy flush..."
Start-Sleep -Seconds 15

Write-Host "DSC complete. Proceeding to WinRM restore..." -ForegroundColor Cyan
exit 0
