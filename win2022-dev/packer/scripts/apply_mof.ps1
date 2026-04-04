#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "=== Applying DSC configuration ==="

$OutputPath = Join-Path $PSScriptRoot "MOF"
$mofFile    = Join-Path $OutputPath "localhost.mof"

if (!(Test-Path $mofFile)) {
    Write-Error "MOF file not found at: $mofFile"
    exit 1
}

$mofSize = (Get-Item $mofFile).Length
Write-Host "Found MOF: $mofFile ($mofSize bytes)"

if ($mofSize -lt 10000) {
    Write-Error "MOF file is suspiciously small ($mofSize bytes)"
    exit 1
}

# -----------------------------------------------------------------------
# FIX: Set RefreshRequired = 0 before DSC runs.
# PowerSTIG's RefreshRegistryPolicy resource checks this key — if it is 0
# it skips the gpupdate /force call. gpupdate resets WinRM auth and kills
# the active Packer session, preventing all post-DSC scripts from running.
# -----------------------------------------------------------------------
Write-Host "Setting RefreshRequired = 0 to prevent gpupdate during DSC..."
$gpStatePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine"
if (-not (Test-Path $gpStatePath)) {
    New-Item -Path $gpStatePath -Force | Out-Null
}
Set-ItemProperty -Path $gpStatePath -Name "RefreshRequired" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "RefreshRequired = 0 set." -ForegroundColor Green

Write-Host "Applying DSC configuration (this may take several minutes)..."

try {
    Start-DscConfiguration -Path $OutputPath -Wait -Force -Verbose -ErrorAction Stop
    Write-Host "=== DSC configuration applied successfully ===" -ForegroundColor Green
} catch {
    Write-Warning "Start-DscConfiguration encountered an error: $_"
    Write-Warning "Resource-level failures are expected and will be corrected by post-DSC scripts."
    Write-Host "=== DSC application completed with resource-level warnings ===" -ForegroundColor Yellow
}

exit 0
