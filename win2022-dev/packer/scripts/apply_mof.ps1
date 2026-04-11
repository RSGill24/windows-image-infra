#Requires -RunAsAdministrator

$ErrorActionPreference = 'Continue'

Write-Host "=== apply_mof.ps1 starting ==="

$BaseDir    = "C:\Windows\Temp"
$OutputPath = Join-Path $PSScriptRoot "MOF"
$mofFile    = Join-Path $OutputPath "localhost.mof"

if (!(Test-Path $mofFile)) {
    Write-Error "MOF file not found at: $mofFile"
    exit 1
}

Stop-DscConfiguration -Force -ErrorAction SilentlyContinue
Remove-DscConfigurationDocument -Stage Current  -Force -ErrorAction SilentlyContinue
Remove-DscConfigurationDocument -Stage Pending  -Force -ErrorAction SilentlyContinue
Remove-DscConfigurationDocument -Stage Previous -Force -ErrorAction SilentlyContinue

$dscScript = "$BaseDir\run_dsc.ps1"

@"
Start-Transcript -Path "$BaseDir\dsc_apply.log" -Append
Start-DscConfiguration -Path "$OutputPath" -Wait -Force -Verbose
Stop-Transcript
"@ | Set-Content -Path $dscScript -Encoding UTF8

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$dscScript`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5)

Unregister-ScheduledTask -TaskName "DSC_Apply_STIG" -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask -TaskName "DSC_Apply_STIG" -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null

Start-Sleep -Seconds 10

# WAIT FOR DSC (fixed detection)
$logFile = "$BaseDir\dsc_apply.log"
$timeout = 1800
$elapsed = 0

Write-Host "Waiting for DSC to complete..."

while ($elapsed -lt $timeout) {
    Start-Sleep -Seconds 15
    $elapsed += 15

    if (Test-Path $logFile) {
        $content = Get-Content $logFile -Tail 20 -ErrorAction SilentlyContinue

        if ($content -match "Operation 'Invoke CimMethod' complete" -or
            $content -match "consistency check completed" -or
            $content -match "LCM:\s+\[\s*End\s+Set") {

            Write-Host "DSC completed"
            break
        }
    }

    Write-Host "Still running... $elapsed sec"
}

# WinRM restore
$winrmScript = "$BaseDir\winrm_restore.ps1"

@"
Set-Service WinRM -StartupType Automatic
Start-Service WinRM
Set-Item WSMan:\localhost\Service\Auth\Basic -Value \$true -Force
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value \$true -Force
"@ | Set-Content -Path $winrmScript -Encoding UTF8

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$winrmScript`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5)

Unregister-ScheduledTask -TaskName "WinRM_Fix" -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask -TaskName "WinRM_Fix" -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null

Start-Sleep -Seconds 30

# Copy banner
$srcBanner = "C:\Users\packer_user\hardening\dod_banner.ps1"
$dstBanner = "C:\Windows\Temp\dod_banner.ps1"

if (Test-Path $srcBanner) {
    Copy-Item $srcBanner $dstBanner -Force
}

# Apply banner
if (Test-Path $dstBanner) {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$dstBanner`""
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5)

    Unregister-ScheduledTask -TaskName "Apply_Banner" -Confirm:$false -ErrorAction SilentlyContinue

    Register-ScheduledTask -TaskName "Apply_Banner" -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null

    Start-Sleep -Seconds 30
}

Write-Host "=== apply_mof COMPLETE ==="
exit 0
