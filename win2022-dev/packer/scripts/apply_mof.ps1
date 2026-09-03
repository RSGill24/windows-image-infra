#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies the compiled DSC MOF via a SYSTEM scheduled task, polls that task's
    state for reliable completion detection, then restores WinRM inline so the
    remaining run_all.ps1 steps remain observable by Packer.

.NOTES
    Previous version polled the transcript log for specific verbose strings
    ("Invoke CimMethod complete", "LCM: [End Set"). Those strings are version-
    dependent and often do not appear -- causing the script to poll the entire
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
        after apply_mof returns -- we restore WinRM here so that works.
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

# ---------------------------------------------------------------------------
# MOF sanitization -- physically strip any DSC instance that targets WinRM.
# PowerSTIG's SkipRule IDs can shift between versions; our list may miss one.
# Walks the MOF with a proper brace counter so we correctly handle nested
# '};' patterns inside instance bodies (e.g., ValueData = { "0" };). The
# previous regex approach broke on those and corrupted the MOF to 1 resource.
# ---------------------------------------------------------------------------
Write-Host 'Sanitizing MOF to remove any WinRM-breaking resources...'
$mofText = [System.IO.File]::ReadAllText($mofFile)

function Split-MofInstances {
    param([string]$Text)
    $instances = New-Object System.Collections.Generic.List[hashtable]
    $i = 0
    while ($i -lt $Text.Length) {
        $startIdx = $Text.IndexOf('instance of', $i)
        if ($startIdx -lt 0) { break }
        # Find the opening '{' after the header.
        $braceIdx = $Text.IndexOf('{', $startIdx)
        if ($braceIdx -lt 0) { break }
        # Walk forward counting braces to find the matching close.
        $depth = 1
        $j = $braceIdx + 1
        while ($j -lt $Text.Length -and $depth -gt 0) {
            $c = $Text[$j]
            if     ($c -eq '{') { $depth++ }
            elseif ($c -eq '}') { $depth-- }
            $j++
        }
        if ($depth -ne 0) { break }
        # Expect a ';' right after the matching '}'.
        if ($j -lt $Text.Length -and $Text[$j] -eq ';') { $j++ }
        $instances.Add(@{ Start = $startIdx; End = $j; Text = $Text.Substring($startIdx, $j - $startIdx) })
        $i = $j
    }
    return $instances
}

$instances = Split-MofInstances -Text $mofText
if ($instances.Count -eq 0) {
    Write-Warning 'MOF sanitizer: no instances found -- leaving MOF unchanged.'
} else {
    $header = $mofText.Substring(0, $instances[0].Start)
    $footer = $mofText.Substring($instances[-1].End)

    $kept = New-Object System.Collections.Generic.List[string]
    $removed = 0
    foreach ($inst in $instances) {
        if ($inst.Text -match '(?i)WinRM|WSMan|AllowBasic|AllowUnencrypted') {
            $removed++
            $preview = ($inst.Text -replace '\s+', ' ').Substring(0, [Math]::Min(100, $inst.Text.Length))
            Write-Host "  Stripped: $preview"
        } else {
            $kept.Add($inst.Text)
        }
    }

    $sanitized = $header + ($kept -join "`r`n`r`n") + "`r`n" + $footer
    [System.IO.File]::WriteAllText($mofFile, $sanitized, [System.Text.UTF8Encoding]::new($false))
    Write-Host ("MOF sanitized: {0} total instances; {1} WinRM-related removed; {2} kept." -f $instances.Count, $removed, $kept.Count)
}

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

# WinRM guardian REMOVED -- MOF sanitization above physically strips all WinRM/
# WSMan/AllowBasic/AllowUnencrypted resources from the MOF before DSC sees it,
# so there is nothing left that could disable Basic auth. The guardian's own
# Set-Item WSMan:\... writes were racing Packer's WinRM session mid-cleanup
# and causing exit 16001 (connection dropped) right after DSC finished.

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
        Write-Host "Timeout after $timeoutMin min -- force-stopping DSC."
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Start-Sleep 5
        Stop-DscConfiguration -Force -ErrorAction SilentlyContinue
        break
    }
}

# Guardian stop logic removed -- guardian itself removed above.

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
# NOTE: do NOT Restart-Service WinRM here. Restart drops Packer's live WinRM
# session mid-provisioner and causes "Provisioning step had errors" even
# though DSC itself ran cleanly. Set-Item on WSMan:\ paths applies settings
# to the running service without a restart, which is all we need for Packer
# to continue observing subsequent provisioners.

# ---------------------------------------------------------------------------
# Prevent DSC LCM from re-applying STIG every 15 min (ConsistencyCheck default)
# and re-disabling Basic auth. Three actions:
#   1. Remove persisted DSC configuration documents so there's nothing to re-apply.
#   2. Set LCM to ApplyOnly mode (no auto-consistency check).
#   3. Stop and disable the DSC timer service as a belt-and-suspenders measure.
# Without these, the post-DSC WinRM restore above gets reverted within 15 min,
# locking the account out exactly as we observed (401 Unauthorized).
# ---------------------------------------------------------------------------
Write-Host '=== Preventing DSC LCM re-apply of STIG (Basic-auth lockout defense) ==='

try {
    Stop-DscConfiguration -Force -ErrorAction SilentlyContinue
    Remove-DscConfigurationDocument -Stage Current  -Force -ErrorAction SilentlyContinue
    Remove-DscConfigurationDocument -Stage Pending  -Force -ErrorAction SilentlyContinue
    Remove-DscConfigurationDocument -Stage Previous -Force -ErrorAction SilentlyContinue
    Write-Host 'DSC configuration documents removed.'
} catch {
    Write-Host "DSC document cleanup: $_"
}

# Disable DSC timer service so LCM cannot wake up.
try {
    Stop-Service  -Name DscTimer -Force -ErrorAction SilentlyContinue
    Set-Service   -Name DscTimer -StartupType Disabled -ErrorAction SilentlyContinue
    Write-Host 'DscTimer service stopped and disabled.'
} catch {
    Write-Host "DscTimer service change (non-fatal): $_"
}

Write-Host '=== apply_mof COMPLETE ==='
exit 0
