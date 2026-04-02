# =========================================================
# Install Nessus Agent from GCS (Production)
# =========================================================

Write-Host "=== Installing Nessus Agent ===" -ForegroundColor Cyan

$bucketPath   = "gs://org-sec-agents-bucket/NessusAgent-11.1.2-x64.msi"
$downloadPath = "C:\Users\packer_user\hardening\NessusAgent-11.1.2-x64.msi"

# Download
gcloud storage cp $bucketPath $downloadPath

if (!(Test-Path $downloadPath)) {
    Write-Error "Download failed!"
    exit 1
}

# Validate size
$fileSize = (Get-Item $downloadPath).Length
if ($fileSize -lt 10000000) {
    Write-Error "Downloaded file is invalid!"
    exit 1
}

# Install
Start-Process msiexec.exe -ArgumentList "/i `"$downloadPath`" /quiet /norestart" -Wait

# Verify
$service = Get-Service -Name "Tenable Nessus Agent" -ErrorAction SilentlyContinue

if (-not $service) {
    Write-Error "Nessus installation failed!"
    exit 1
}

Write-Host "Nessus Agent installed successfully." -ForegroundColor Green
