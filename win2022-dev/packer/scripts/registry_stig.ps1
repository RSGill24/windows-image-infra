Write-Host "=== Applying Registry STIG ==="

# V-254343.b
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
  -Name "LmCompatibilityLevel" -Value 1 -Type DWord

# V-254344
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
  -Name "NoLMHash" -Value 1 -Type DWord

# V-254357
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" `
  -Name "ClearPageFileAtShutdown" -Value 1 -Type DWord

# V-254358 / 359 / 360 (Event log sizes)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Security" `
  -Name "MaxSize" -Value 196608 -Type DWord

Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application" `
  -Name "MaxSize" -Value 32768 -Type DWord

Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\System" `
  -Name "MaxSize" -Value 32768 -Type DWord

# V-254432
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
  -Name "ConsentPromptBehaviorAdmin" -Value 4 -Type DWord

Write-Host "=== Registry STIG Applied ==="
