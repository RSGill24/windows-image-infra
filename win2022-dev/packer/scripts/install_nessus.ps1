# install_nessus_from_gcs.ps1
# Downloads Nessus MSI from GCS and installs it silently


# Variables
$bucketName = " org-sec-agents-bucket"
$installerName = "NessusAgent-11.1.2-arm64.msi"
$targetDir = "C:\Users\packer_user\hardening\agents"
$installerPath = Join-Path $targetDir $installerName

# Create target directory
if (!(Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force
}

# Download installer from GCS
Write-Host "Downloading $installerName from gs://$bucketName/ ..."
gsutil cp "gs://$bucketName/$installerName" $installerPath

# Install silently without activation
Write-Host "Installing Nessus agent..."
Start-Process msiexec.exe -ArgumentList "/i `"$installerPath`" /quiet /norestart" -Wait

Write-Host "Nessus installation complete (unactivated)."
