Write-Host "=== Applying Services STIG (Targeted Fix) ==="

# Antivirus (V-254248)
Set-Service -Name WinDefend -StartupType Automatic
Start-Service WinDefend

# Firewall (V-254265)
Set-Service -Name MpsSvc -StartupType Automatic
Start-Service MpsSvc

# Ensure firewall ON
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True

Write-Host "=== Services STIG Fixed ==="
