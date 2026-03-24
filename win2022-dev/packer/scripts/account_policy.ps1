Write-Host "=== Applying Account Policy STIG ==="

net accounts /minpwlen:15
net accounts /lockoutthreshold:3
net accounts /lockoutduration:15
net accounts /lockoutwindow:15
net accounts /maxpwage:60
net accounts /minpwage:1

Write-Host "=== Account Policy Fixed ==="
