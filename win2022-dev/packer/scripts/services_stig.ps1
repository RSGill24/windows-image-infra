Write-Host "=== Applying Services STIG (Targeted Fix) ==="

# Antivirus (V-254248)
Set-Service -Name WinDefend -StartupType Automatic
Start-Service WinDefend -ErrorAction SilentlyContinue

# Firewall (V-254265)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\MpsSvc" -Name "Start" -Value 2 -Type DWord -Force
Write-Host "Set MpsSvc (Windows Defender Firewall) to Automatic via Registry"

# Preserve WinRM HTTPS port BEFORE enabling firewall profiles
# Without this, enabling all profiles blocks port 5986 and kills the Packer session
netsh advfirewall firewall add rule name="WinRM-HTTPS" dir=in action=allow protocol=TCP localport=5986
netsh advfirewall firewall add rule name="WinRM-HTTP"  dir=in action=allow protocol=TCP localport=5985
Write-Host "WinRM firewall rules added before enabling profiles"

# Now safe to enable firewall profiles
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
Write-Host "Firewall profiles enabled"

Write-Host "=== Services STIG Fixed ==="
exit 0
