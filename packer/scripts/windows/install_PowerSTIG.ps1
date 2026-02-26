# ============================================================
# PowerSTIG Integration Script - Windows Server 2022
# With full structured logging
# ============================================================

#Requires -RunAsAdministrator

param(
    [string]$OutputPath  = 'C:\Users\packer_user\hardening\STIG_Output',
    [string]$StigVersion = '1.5',
    [string]$LogPath     = 'C:\Users\packer_user\hardening\Logs\STIG_Run.log'
)

# ════════════════════════════════════════════════════════════
# LOGGING HELPERS
# ════════════════════════════════════════════════════════════

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','STEP','SUCCESS','WARN','ERROR','DEBUG')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logLine   = "[$timestamp] [$Level] $Message"

    # Always write to log file
    Add-Content -Path $LogPath -Value $logLine -Encoding UTF8

    # Colour-coded console output
    switch ($Level) {
        'STEP'    { Write-Host "`n$logLine" -ForegroundColor Cyan    }
        'SUCCESS' { Write-Host "  $logLine" -ForegroundColor Green   }
        'WARN'    { Write-Host "  $logLine" -ForegroundColor Yellow  }
        'ERROR'   { Write-Host "  $logLine" -ForegroundColor Red     }
        'DEBUG'   { Write-Host "  $logLine" -ForegroundColor Gray    }
        default   { Write-Host "  $logLine" -ForegroundColor White   }
    }
}

function Write-StepBanner {
    param([string]$Title, [int]$Step, [int]$Total)
    $bar  = '=' * 60
    $line = "`n$bar`n  STEP $Step/$Total -- $Title`n$bar"
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
    Write-Host $line -ForegroundColor Magenta
}

# ════════════════════════════════════════════════════════════
# INIT -- create log dir & write header
# ════════════════════════════════════════════════════════════

$logDir = Split-Path $LogPath -Parent
New-Item -ItemType Directory -Path $logDir     -Force | Out-Null
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

$header = @"
==============================================================
         PowerSTIG - Windows Server 2022 Hardening
==============================================================
  Run started : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  Host        : $($env:COMPUTERNAME)
  User        : $($env:USERNAME)
  STIG version: $StigVersion
  Output path : $OutputPath
  Log file    : $LogPath
==============================================================
"@

Add-Content -Path $LogPath -Value $header -Encoding UTF8
Write-Host $header -ForegroundColor Cyan

$totalSteps = 7
$stepErrors = @()

# ════════════════════════════════════════════════════════════
# STEP 1 -- Install NuGet & trust PSGallery
# ════════════════════════════════════════════════════════════
Write-StepBanner "Install NuGet Provider & Trust PSGallery" 1 $totalSteps

try {
    Write-Log "Installing NuGet package provider..." 'INFO'
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
    Write-Log "NuGet installed/updated." 'SUCCESS'

    Write-Log "Setting PSGallery as Trusted..." 'INFO'
    Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
    Write-Log "PSGallery trusted." 'SUCCESS'
}
catch {
    Write-Log "NuGet/PSGallery setup failed: $_" 'ERROR'
    $stepErrors += "Step 1: $_"
}

# ════════════════════════════════════════════════════════════
# STEP 2 -- Install required PowerShell modules
# ════════════════════════════════════════════════════════════
Write-StepBanner "Install Required Modules" 2 $totalSteps

$modules = @('PowerSTIG','PSDscResources','SecurityPolicyDsc','AuditPolicyDsc','xWinEventLog')

foreach ($mod in $modules) {
    try {
        if (Get-Module -ListAvailable -Name $mod) {
            $ver = (Get-Module -ListAvailable -Name $mod | Select-Object -First 1).Version
            Write-Log "$mod already installed (v$ver) -- skipping." 'DEBUG'
        }
        else {
            Write-Log "Installing $mod from PSGallery..." 'INFO'
            Install-Module -Name $mod -Force -AllowClobber -Scope AllUsers -ErrorAction Stop
            $ver = (Get-Module -ListAvailable -Name $mod | Select-Object -First 1).Version
            Write-Log "$mod installed successfully (v$ver)." 'SUCCESS'
        }
    }
    catch {
        Write-Log "Failed to install $mod : $_" 'ERROR'
        $stepErrors += "Step 2 [$mod]: $_"
    }
}

Write-Log "Importing PowerSTIG module..." 'INFO'
try {
    Import-Module PowerSTIG -ErrorAction Stop
    Write-Log "PowerSTIG imported." 'SUCCESS'
}
catch {
    Write-Log "Cannot import PowerSTIG -- aborting: $_" 'ERROR'
    exit 1
}

# ════════════════════════════════════════════════════════════
# STEP 3 -- List available STIG versions
# ════════════════════════════════════════════════════════════
Write-StepBanner "Query Available STIG Versions" 3 $totalSteps

try {
    Write-Log "Fetching available Windows Server 2022 STIG versions..." 'INFO'
    $stigList = Get-StigList -StigType WindowsServer |
                Where-Object { $_.TechnologyVersion -eq '2022' }

    if ($stigList) {
        $stigList | ForEach-Object {
            Write-Log "  Found: $($_.StigId)  Version: $($_.StigVersion)  Released: $($_.PublishDate)" 'DEBUG'
        }
        Write-Log "Total versions found: $($stigList.Count)" 'SUCCESS'

        $match = $stigList | Where-Object { $_.StigVersion -eq $StigVersion }
        if (-not $match) {
            Write-Log "Requested StigVersion '$StigVersion' not found. Available: $(($stigList.StigVersion) -join ', ')" 'WARN'
        }
        else {
            Write-Log "StigVersion '$StigVersion' confirmed available." 'SUCCESS'
        }
    }
    else {
        Write-Log "No STIG versions found for Windows Server 2022." 'WARN'
    }
}
catch {
    Write-Log "Failed to query STIG list: $_" 'ERROR'
    $stepErrors += "Step 3: $_"
}

# ════════════════════════════════════════════════════════════
# STEP 4 -- Generate DSC Configuration file
# ════════════════════════════════════════════════════════════
Write-StepBanner "Generate DSC Configuration" 4 $totalSteps

$configPath = Join-Path $OutputPath 'WindowsServer2022_STIG.ps1'

$configScript = @"
Configuration WindowsServer2022_STIG {
    param (
        [string[]]`$ComputerName = 'localhost'
    )

    Import-DscResource -ModuleName PowerSTIG

    Node `$ComputerName {
        WindowsServer BaseLine {
            OsVersion   = '2022'
            StigVersion = '$StigVersion'
            OsRole      = 'MS'
            Exception   = @{
                # Example: 'V-253280' = @{ ValueData = '0' }
            }
            SkipRule    = @()
        }
    }
}
"@

try {
    Write-Log "Writing DSC config to: $configPath" 'INFO'
    $configScript | Out-File -FilePath $configPath -Encoding UTF8 -Force
    $lineCount = (Get-Content $configPath).Count
    Write-Log "Config file written ($lineCount lines)." 'SUCCESS'
}
catch {
    Write-Log "Failed to write DSC config: $_" 'ERROR'
    $stepErrors += "Step 4: $_"
    exit 1
}

# ════════════════════════════════════════════════════════════
# STEP 5 -- Compile DSC MOF
# ════════════════════════════════════════════════════════════
Write-StepBanner "Compile DSC MOF File" 5 $totalSteps

try {
    Write-Log "Dot-sourcing config script..." 'INFO'
    . $configPath

    Write-Log "Compiling MOF into: $OutputPath" 'INFO'
    WindowsServer2022_STIG -OutputPath $OutputPath | Out-Null

    $mofFile = Join-Path $OutputPath 'localhost.mof'
    if (Test-Path $mofFile) {
        $mofSize = (Get-Item $mofFile).Length
        Write-Log "MOF compiled successfully -- size: $mofSize bytes." 'SUCCESS'
    }
    else {
        Write-Log "MOF file not found after compilation -- check DSC errors above." 'WARN'
    }
}
catch {
    Write-Log "MOF compilation failed: $_" 'ERROR'
    $stepErrors += "Step 5: $_"
    exit 1
}

# ════════════════════════════════════════════════════════════
# STEP 6 -- Apply DSC / LCM Configuration
# ════════════════════════════════════════════════════════════
Write-StepBanner "Apply STIG via DSC" 6 $totalSteps

try {
    Write-Log "Configuring LCM (Local Configuration Manager)..." 'INFO'
    Set-DscLocalConfigurationManager -Path $OutputPath -Force -Verbose 4>&1 |
        ForEach-Object { Write-Log "  [LCM] $_" 'DEBUG' }
    Write-Log "LCM configured." 'SUCCESS'

    Write-Log "Applying DSC configuration (this may take several minutes)..." 'INFO'
    $applyStart = Get-Date
    Start-DscConfiguration -Path $OutputPath -Force -Wait -Verbose 4>&1 |
        ForEach-Object { Write-Log "  [DSC] $_" 'DEBUG' }
    $applyDuration = [int](New-TimeSpan -Start $applyStart -End (Get-Date)).TotalSeconds
    Write-Log "DSC application finished in $applyDuration seconds." 'SUCCESS'
}
catch {
    Write-Log "DSC apply failed: $_" 'ERROR'
    $stepErrors += "Step 6: $_"
}

# ════════════════════════════════════════════════════════════
# STEP 7 -- Audit / Compliance Report
# ════════════════════════════════════════════════════════════
Write-StepBanner "Compliance Audit & Report" 7 $totalSteps

try {
    Write-Log "Running Test-DscConfiguration..." 'INFO'
    $result = Test-DscConfiguration -Path $OutputPath -Detailed

    $compliant    = $result.ResourcesInDesiredState
    $nonCompliant = $result.ResourcesNotInDesiredState

    Write-Log "Compliant resources    : $($compliant.Count)"    'SUCCESS'
    Write-Log "Non-compliant resources: $($nonCompliant.Count)" $(if ($nonCompliant.Count -gt 0) { 'WARN' } else { 'SUCCESS' })

    if ($nonCompliant) {
        Write-Log "--- Non-Compliant Items ---" 'WARN'
        $nonCompliant | ForEach-Object {
            Write-Log "  FAIL  ResourceId: $($_.ResourceId)  Type: $($_.ResourceType)" 'WARN'
        }

        $reportPath = Join-Path $OutputPath 'NonCompliant_Items.csv'
        $nonCompliant | Export-Csv -Path $reportPath -NoTypeInformation -Force
        Write-Log "Non-compliant report saved: $reportPath" 'WARN'
    }
    else {
        Write-Log "All resources are compliant -- system fully hardened." 'SUCCESS'
    }
}
catch {
    Write-Log "Compliance audit failed: $_" 'ERROR'
    $stepErrors += "Step 7: $_"
}

# ════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ════════════════════════════════════════════════════════════

$endTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$summary = @"

==============================================================
  STIG RUN SUMMARY
  Finished : $endTime
  Steps run: $totalSteps
  Errors   : $($stepErrors.Count)
$(if ($stepErrors) { "  Error details:" + ($stepErrors | ForEach-Object { "`n    - $_" }) })
  Log file : $LogPath
==============================================================
"@

Add-Content -Path $LogPath -Value $summary -Encoding UTF8

if ($stepErrors.Count -eq 0) {
    Write-Host $summary -ForegroundColor Green
}
else {
    Write-Host $summary -ForegroundColor Yellow
    Write-Host "  Some steps had errors -- review log: $LogPath" -ForegroundColor Red
}
