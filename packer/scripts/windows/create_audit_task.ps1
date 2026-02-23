# Define the path to your .bat file
$Ps1FilePath = "C:/Users/packer_user/hardening/run_only_audit.ps1"

# Define the action to run the .bat file
$Action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File $Ps1FilePath"

# Define the trigger for every 2 weeks
$BiWeeklyTrigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 2 -DaysOfWeek Wednesday -At 9am

# If biweekly works, this may be overkill. test both for now.
$LogonTrigger = New-ScheduledTaskTrigger -AtLogOn

# Define task settings to allow execution if missed
$Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries -DontStopOnIdleEnd -MultipleInstances Parallel

# Register the task to run as SYSTEM with both triggers
Register-ScheduledTask -TaskName "Push_DISA_STIG_Audit" -Action $Action -Trigger $BiWeeklyTrigger, $LogonTrigger -Settings $Settings -User "SYSTEM" -RunLevel Highest
