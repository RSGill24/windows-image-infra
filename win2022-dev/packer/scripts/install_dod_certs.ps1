#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs all required DoD PKI certificates for STIG compliance using the official
    DoD InstallRoot tool. 
    Fixes: V-254442 (DoD Root CAs), V-254443 (DoD Interop cross-certs),
           V-254444 (US DOD CCEB Interop cross-certs)

.NOTES
    FIX: Replaced web-download logic with a local InstallRoot.msi execution to bypass
         DISA firewall blocks on GCP IPs.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Section ($msg) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " $msg" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}
function Write-OK   ($msg) { Write-Host "  [OK]    $msg" -ForegroundColor Green }
function Write-Warn ($msg) { Write-Host "  [WARN]  $msg" -ForegroundColor Magenta }
function Write-Info ($msg) { Write-Host "  [INFO]  $msg" -ForegroundColor Gray }

$ErrorCount = 0

# -----------------------------------------------------------------------
# STEP 1 — Install the InstallRoot MSI
# -----------------------------------------------------------------------
Write-Section "Step 1: Installing DoD InstallRoot Tool"

$msiPath = Join-Path $PSScriptRoot "InstallRoot.msi"

if (-not (Test-Path $msiPath)) {
    Write-Error "InstallRoot.msi not found at $msiPath. Make sure Packer uploaded it!"
    exit 1
}

Write-Info "Running MSI installer silently..."
$installProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msiPath`" /qn /norestart" -Wait -PassThru

if ($installProcess.ExitCode -eq 0) {
    Write-OK "InstallRoot.msi installed successfully."
} else {
    Write-Warn "MSI installer returned exit code: $($installProcess.ExitCode)"
    $ErrorCount++
}

# -----------------------------------------------------------------------
# STEP 2 — Execute InstallRoot to inject the certificates
# -----------------------------------------------------------------------
Write-Section "Step 2: Injecting Certificates via InstallRoot"

# InstallRoot usually installs to Program Files. Check both standard and x86.
$exePath = "C:\Program Files\DoD-PKE\InstallRoot\InstallRoot.exe"
if (-not (Test-Path $exePath)) {
    $exePath = "C:\Program Files (x86)\DoD-PKE\InstallRoot\InstallRoot.exe"
}

if (-not (Test-Path $exePath)) {
    Write-Warn "Could not locate InstallRoot.exe after MSI installation!"
    $ErrorCount++
} else {
    Write-Info "Executing: $exePath /InstallRoot /unattended"
    $runProcess = Start-Process -FilePath $exePath -ArgumentList "/InstallRoot", "/unattended" -Wait -NoNewWindow -PassThru
    
    if ($runProcess.ExitCode -eq 0) {
        Write-OK "Certificates injected successfully."
    } else {
        Write-Warn "InstallRoot.exe returned exit code: $($runProcess.ExitCode)"
        $ErrorCount++
    }
}

# -----------------------------------------------------------------------
# STEP 3 — Verify all required certs are present
# -----------------------------------------------------------------------
Write-Section "Step 3: Verification (STIG Checks)"

$certChecks = @(
    # V-254442 (Trusted Root)
    @{ Name="DoD Root CA 3"; Store="Cert:\LocalMachine\Root"; Thumb="D73CA91102A2204A36459ED32213B467D7CE97FB" },
    @{ Name="DoD Root CA 4"; Store="Cert:\LocalMachine\Root"; Thumb="B8269F25DBD937ECAFD4C35A9838571723F2D026" },
    @{ Name="DoD Root CA 5"; Store="Cert:\LocalMachine\Root"; Thumb="4ECB5CC3095670454DA1CBD410FC921F46B8564B" },
    @{ Name="DoD Root CA 6"; Store="Cert:\LocalMachine\Root"; Thumb="D37ECF61C0B4ED88681EF3630C4E2FC787B37AEF" },
    
    # V-254443 / V-254444 (Disallowed Cross-Certs)
    @{ Name="DoD Interop (DoD Root CA 3)"; Store="Cert:\LocalMachine\Disallowed"; Thumb="49CBE933151872E17C8EAE7F0ABA97FB610F6477" },
    @{ Name="CCEB Interop (DoD Root CA 3)"; Store="Cert:\LocalMachine\Disallowed"; Thumb="9B74964506C7ED9138070D08D5F8B969866560C8" },
    @{ Name="CCEB Interop (DoD Root CA 6)"; Store="Cert:\LocalMachine\Disallowed"; Thumb="D471CA32F7A692CE6CBB6196BD3377FE4DBCD106" }
)

foreach ($ca in $certChecks) {
    $found = Get-ChildItem -Path $ca.Store -ErrorAction SilentlyContinue | Where-Object { $_.Thumbprint -eq $ca.Thumb }
    if ($found) {
        Write-OK "$($ca.Name) is present in $($ca.Store)"
    } else {
        Write-Warn "MISSING: $($ca.Name) in $($ca.Store)"
        $ErrorCount++
    }
}

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
Write-Section "DoD Certificate Installation Summary"

if ($ErrorCount -eq 0) {
    Write-Host "  All DoD certificates installed and verified." -ForegroundColor Green
    Write-Host "  V-254442, V-254443, V-254444 should PASS on next SCAP scan." -ForegroundColor Green
} else {
    Write-Host "  $ErrorCount issue(s) detected with certificate installation." -ForegroundColor Yellow
}

# Reset LASTEXITCODE to prevent native commands from overriding the custom exit code
$global:LASTEXITCODE = 0
exit $ErrorCount
