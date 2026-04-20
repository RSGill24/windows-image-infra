#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies the compiled DSC MOF via a SYSTEM scheduled task, polls that task's
    state for reliable completion detection, then restores WinRM inline so the
    remaining run_all.ps1 steps remain observable by Packer.

.NOTES
    Previous version polled the transcript log for specific verbose strings
    ("Invoke CimMethod complete", "LCM: [End Set"). Those strings are version-
    dependent and often do not appear — causing the script to poll the entire
    30 min timeout even when DSC finished in 8 min.

    This version:
      - Polls Get-ScheduledTask .State (Ready when done). Reliable.
      - Streams the last changed log line so progress is visible.
      - Hard-caps at 25 min and force-stops DSC if still running.
      - Restores WinRM Basic auth + AllowUnencrypted immediately after DSC so
        Packer's WinRM session survives STIG registry writes that disable
        Basic auth mid-apply. Without this, Packer loses output stream and
        every subsequent provisioner appears to hang.
      - Removed the Post_STIG_All scheduled task. run_all.ps1 now re-runs
        dod_banner, account_policy, audit, etc. INLINE in the WinRM session
        after apply_mof returns — we restore WinRM here so that works.
#>

$ErrorActionPreference = 'Continue'

Write-Host "=== apply_mof.ps1 starting ==="

$BaseDir    = 'C:\Windows\Temp'
$OutputPath = Join-Path $PSScriptRoot 'MOF'
$mofFile    = Join-Path $OutputPath  'localhost.mof'
$logFile    = Join-Path $BaseDir     'dsc_apply.log'
$dscScript  = Join-Path $BaseDir     'run_dsc.ps1'
$taskName   = 'DSC_Apply_STIG'
$timeoutMin = 25

if (!(Test-Path $mofFile)) {
    Write-Error "MOF file not found at: $mofFile"
    exit 1
}

Write-Host 'Clearing stale DSC state...'
Stop-DscConfiguration                       -Force -ErrorAction SilentlyContinue
Remove-DscConfigurationDocument -Stage Current  -Force -ErrorAction SilentlyContinue
Remove-DscConfigurationDocument -Stage Pending  -Force -ErrorAction SilentlyContinue
Remove-DscConfigurationDocument -Stage Previous -Force -ErrorAction SilentlyContinue
Remove-Item $logFile -Force -ErrorAction SilentlyContinue

# Script that the SYSTEM scheduled task will run. Transcripted for visibility.
@"
Start-Transcript -Path "$logFile"
try {
    Start-DscConfiguration -Path "$OutputPath" -Wait -Force -Verbose
    Write-Host "=== DSC_APPLY_DONE ==="
} catch {
    Write-Host "=== DSC_APPLY_FAIL: `$_ ==="
}
Stop-Transcript
"@ | Set-Content -Path $dscScript -Encoding UTF8

$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
$action    = New-ScheduledTaskAction -Execute 'powershell.exe' `
             -Argument "-ExecutionPolicy Bypass -File `"$dscScript`""
$trigger   = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5)

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask   -TaskName $taskName -Action $action -Trigger $trigger `
                         -Principal $principal -Force | Out-Null

Start-Sleep -Seconds 10

Write-Host ("Polling task '{0}' (timeout: {1} min). State=Ready means done." -f $taskName, $timeoutMin)

$start    = Get-Date
$lastSize = 0

while ($true) {
    Start-Sleep -Seconds 20
    $elapsed = [int]((Get-Date) - $start).TotalSeconds

    $task  = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    $state = if ($task) { $task.State } else { 'Gone' }

    # Stream last newly-appended log line so user sees real DSC progress.
    $tail = ''
    if (Test-Path $logFile) {
        $size = (Get-Item $logFile).Length
        if ($size -ne $lastSize) {
            $lastSize = $size
            $line = Get-Content $logFile -Tail 1 -ErrorAction SilentlyContinue
            if ($line) { $tail = ' | ' + $line.Trim() }
        }
    }

    Write-Host ("[{0,5}s] task={1}{2}" -f $elapsed, $state, $tail)

    if ($state -eq 'Ready' -or $state -eq 'Gone') {
        Write-Host 'DSC task finished.'
        break
    }
    if ($elapsed -ge ($timeoutMin * 60)) {
        Write-Host "Timeout after $timeoutMin min — force-stopping DSC."
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Start-Sleep 5
        Stop-DscConfiguration -Force -ErrorAction SilentlyContinue
        break
    }
}

# ---------------------------------------------------------------------------
# Restore WinRM inline. STIG DSC registry rules can set
#   HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service\AllowBasic = 0
# which kills Packer's WinRM session mid-apply. Undo those writes here so
# every remaining provisioner (registry_stig, services_stig, account_policy,
# audit, apply_remaining_fixes, stig_remediation_fixes, dod_banner reassert)
# remains observable in Packer's output.
# ---------------------------------------------------------------------------
Write-Host '=== Post-DSC: Restoring WinRM for remaining provisioners ==='

try { Set-Item WSMan:\localhost\Service\Auth\Basic       -Value $true -Force } catch { Write-Host "Basic auth restore: $_" }
try { Set-Item WSMan:\localhost\Service\Auth\Negotiate   -Value $true -Force } catch { Write-Host "Negotiate restore: $_" }
try { Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true -Force } catch { Write-Host "AllowUnencrypted restore: $_" }

$gpoPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service'
if (Test-Path $gpoPath) {
    Remove-ItemProperty $gpoPath -Name AllowBasic   -ErrorAction SilentlyContinue
    Remove-ItemProperty $gpoPath -Name DisableRunAs -ErrorAction SilentlyContinue
}

try { Set-Service WinRM -StartupType Automatic } catch { Write-Host "Set-Service: $_" }
try { Restart-Service WinRM -Force }             catch { Write-Host "Restart-Service: $_" }

Write-Host '=== apply_mof COMPLETE ==='
exit 0
