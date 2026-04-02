# ==============================
# Nessus Agent Installation Script
# ==============================

# ----------------------------
# CONFIGURATION
# ----------------------------
$bucketPath    = "gs://org-sec-agents-bucket/NessusAgent-11.1.2-x64.msi"
$downloadPath  = "C:\Windows\Temp\NessusAgent-11.1.2-x64.msi"
$logPath       = "C:\Windows\Temp\nessus_install.log"
$installPath   = "C:\Program Files\Tenable\Nessus Agent"
$serviceName   = "Tenable Nessus Agent"
$activateAgent = $false       # Set to $true if you want automatic linking
$activationKey = "YOUR_ACTIVATION_KEY"
$nessusServer  = "YOUR_NESSUS_SERVER"

# ----------------------------
# 1. Uninstall existing Nessus Agent (clean via MSI product DB)
# ----------------------------
Write-Host "[1/6] Checking for existing Nessus Agent installation..." -ForegroundColor Yellow

$nessusApp = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*Nessus Agent*" }
if ($nessusApp) {
    Write-Host "Found: $($nessusApp.Name) v$($nessusApp.Version) — uninstalling..." -ForegroundColor Yellow
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    $result = $nessusApp.Uninstall()
    if ($result.ReturnValue -eq 0) {
        Write-Host "Uninstall complete." -ForegroundColor Green
    } else {
        Write-Warning "Uninstall returned code $($result.ReturnValue) — continuing anyway."
    }
} else {
    Write-Host "No existing Nessus Agent found. Proceeding with fresh install." -ForegroundColor Cyan
}

# Remove any leftover files/dirs
Remove-Item $downloadPath                          -Force   -ErrorAction SilentlyContinue
Remove-Item $installPath                           -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\ProgramData\Tenable\Nessus Agent"  -Recurse -Force -ErrorAction SilentlyContinue

# Confirm clean state
Write-Host "Install dir clean : $(-not (Test-Path $installPath))"
Write-Host "Data dir clean    : $(-not (Test-Path 'C:\ProgramData\Tenable\Nessus Agent'))"
Write-Host "Service gone      : $($null -eq (Get-Service -Name $serviceName -ErrorAction SilentlyContinue))"

# ----------------------------
# 2. Download MSI from GCS
# ----------------------------
Write-Host "[2/6] Downloading Nessus Agent MSI..." -ForegroundColor Yellow
gcloud storage cp $bucketPath $downloadPath

if (-not (Test-Path $downloadPath)) {
    Write-Warning "MSI download failed. Cannot continue installation."
    return
}

$fileSize = (Get-Item $downloadPath).Length
Write-Host "Download successful: $downloadPath" -ForegroundColor Green
Write-Host "File size: $([math]::Round($fileSize / 1MB, 1)) MB ($fileSize bytes)"

Unblock-File $downloadPath

# ----------------------------
# 3. Install MSI
# ----------------------------
Write-Host "[3/6] Installing Nessus Agent..." -ForegroundColor Yellow
$msiArgs = "/i `"$downloadPath`" /quiet /norestart /l*v `"$logPath`""
Start-Process msiexec.exe -ArgumentList $msiArgs -Wait -Verb RunAs
Write-Host "MSI installation complete. Log: $logPath" -ForegroundColor Green

# ----------------------------
# 4. Verify binaries
# ----------------------------
Write-Host "[4/6] Verifying agent binaries..." -ForegroundColor Yellow
$cliPath        = Join-Path $installPath "nessuscli.exe"
$serviceBinPath = Join-Path $installPath "nessus-service.exe"

Write-Host "nessuscli.exe exists:      $(Test-Path $cliPath)"
Write-Host "nessus-service.exe exists: $(Test-Path $serviceBinPath)"

# ----------------------------
# 5. Configure service
# ----------------------------
Write-Host "[5/6] Configuring Nessus service..." -ForegroundColor Yellow
$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($svc) {
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    Set-Service -Name $serviceName -StartupType Manual
    $startMode = (Get-WmiObject Win32_Service -Filter "Name='$serviceName'").StartMode
    Write-Host "Service configured: $($svc.DisplayName) | Status: Stopped | StartupType: $startMode" -ForegroundColor Green
} else {
    Write-Warning "Service '$serviceName' not found — installation may have failed."
}

# ----------------------------
# 6. Optional: Start & link agent
# ----------------------------
Write-Host "[6/6] Starting and linking agent (if requested)..." -ForegroundColor Yellow
if ($activateAgent -and (Test-Path $cliPath)) {
    Start-Service -Name $serviceName
    Write-Host "Service started successfully." -ForegroundColor Green
    & "$cliPath" link --key $activationKey --host $nessusServer
    Write-Host "Agent linked successfully." -ForegroundColor Green
} else {
    Write-Host "Activation skipped. Service stopped, ready for post-boot activation." -ForegroundColor Cyan
}

# ----------------------------
# Cleanup MSI
# ----------------------------
Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue
Write-Host "MSI cleaned up." -ForegroundColor Gray

# ----------------------------
# DONE
# ----------------------------
$finalStatus    = (Get-Service -Name $serviceName -ErrorAction SilentlyContinue).Status
$finalStartMode = (Get-WmiObject Win32_Service -Filter "Name='$serviceName'").StartMode

Write-Host "`n=== Nessus Agent installation complete ===" -ForegroundColor Green
Write-Host "Install path : $installPath"                         -ForegroundColor Cyan
Write-Host "Data path    : C:\ProgramData\Tenable\Nessus Agent"  -ForegroundColor Cyan
Write-Host "Service      : $finalStatus | StartupType: $finalStartMode" -ForegroundColor Cyan
Write-Host "MSI log      : $logPath"                             -ForegroundColor Cyan
Write-Host "Activation   : Deferred to post-boot startup script (unless $activateAgent)" -ForegroundColor Cyan
