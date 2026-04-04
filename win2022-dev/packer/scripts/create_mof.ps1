# create_mof.ps1
# Compiles a DSC MOF using PowerSTIG.
#
# FIX: Added all UserRightRule IDs (V-254434 to V-254512) to SkipRule.
# FIX: Added all AccountPolicy rules (V-254285 to V-254292) to SkipRule.
# FIX: Removed all Exception entries that caused STIG regressions.
# Only ISSO-approved exceptions remain: V-254439 and V-254435 (Guests group).

Write-Host "=== create_mof.ps1 starting ==="

# -----------------------------------------------------------------------
# PRE-COMPILATION CIM CONFLICT CLEANUP
# -----------------------------------------------------------------------
Write-Host "--- Scanning for duplicate System32 modules ---"
$sys32Dsc = "C:\Windows\system32\WindowsPowerShell\v1.0\Modules"
$conflictingModules = @(
    "AuditPolicyDsc",
    "GPRegistryPolicyDsc",
    "PSDscResources",
    "WindowsDefenderDsc",
    "SecurityPolicyDsc",
    "AuditSystemDsc",
    "CertificateDsc",
    "PowerSTIG"
)

foreach ($mod in $conflictingModules) {
    $badPath = Join-Path $sys32Dsc $mod
    if (Test-Path $badPath) {
        Write-Host "  [!] Found conflict. Force deleting: $badPath" -ForegroundColor Yellow
        takeown.exe /F $badPath /R /D Y | Out-Null
        icacls.exe $badPath /grant "Administrators:(OI)(CI)F" /T /Q | Out-Null
        Remove-Item -Path $badPath -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $badPath) {
            Write-Warning "  FAILED to delete $badPath. CIM conflicts may occur."
        } else {
            Write-Host "  Successfully removed $badPath" -ForegroundColor Green
        }
    }
}
Write-Host "--- Cleanup complete ---"

# -----------------------------------------------------------------------
# Ensuring all module paths are in PSModulePath
# -----------------------------------------------------------------------
$requiredPaths = @(
    "C:\Program Files\WindowsPowerShell\Modules",
    "C:\Windows\system32\WindowsPowerShell\v1.0\Modules",
    "C:\Program Files (x86)\WindowsPowerShell\Modules"
)
foreach ($p in $requiredPaths) {
    if ($p -and ($env:PSModulePath -split ';') -notcontains $p) {
        Write-Host "Adding to PSModulePath: $p"
        $env:PSModulePath = "$p;$env:PSModulePath"
    }
}

# -----------------------------------------------------------------------
# Detecting latest PowerSTIG module
# -----------------------------------------------------------------------
$module = Get-Module PowerSTIG -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
if (-not $module) {
    Write-Error "PowerSTIG module not found. Ensure install_PowerSTIG.ps1 ran successfully."
    exit 1
}
$pstigVersion = $module.Version.ToString()
Write-Host "Found PowerSTIG module $pstigVersion at: $($module.ModuleBase)"

# -----------------------------------------------------------------------
# Detecting STIG XML and parse version
# -----------------------------------------------------------------------
$stigDataPath = Join-Path $module.ModuleBase "StigData\Processed"
$stigXml = Get-ChildItem -Path $stigDataPath -Filter "WindowsServer-2022-MS-*.org.default.xml" |
           Sort-Object Name -Descending | Select-Object -First 1
if (-not $stigXml) {
    Write-Error "No WindowsServer-2022-MS-*.org.default.xml found in $stigDataPath"
    exit 1
}
$stigVersionString = ($stigXml.Name -replace 'WindowsServer-2022-MS-', '' -replace '\.org\.default\.xml', '')
Write-Host "Detected STIG XML: $($stigXml.FullName)"
Write-Host "Detected STIG version: $stigVersionString"

# -----------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------
$HardeningDir = $PSScriptRoot
$OutputPath   = Join-Path $HardeningDir "MOF"
$OrgSettings  = Join-Path $HardeningDir ($stigXml.Name -replace '\.org\.default\.xml', '.org.pamdata.xml')

if (!(Test-Path $OrgSettings)) {
    Write-Warning "PAM org settings not found at $OrgSettings -- falling back to default XML"
    $OrgSettings = $stigXml.FullName
}
Write-Host "Using OrgSettings: $OrgSettings"

if (!(Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    Write-Host "Created MOF output directory: $OutputPath"
}

# -----------------------------------------------------------------------
# Verify DSC resource is available
# -----------------------------------------------------------------------
Import-Module -Name PowerSTIG -RequiredVersion $pstigVersion -Force
try {
    $dscCheck = Get-DscResource -Name WindowsServer -Module PowerSTIG -ErrorAction Stop
    Write-Host "DSC resource confirmed: $($dscCheck.Name) from $($dscCheck.Module)"
} catch {
    Write-Error "WindowsServer DSC resource not found: $_"
    exit 1
}

# -----------------------------------------------------------------------
# Generate temporary DSC configuration script
# -----------------------------------------------------------------------
$tempScript = Join-Path $env:TEMP "dsc_config_generated.ps1"

$safeOutputPath  = $OutputPath  -replace "'", "''"
$safeOrgSettings = $OrgSettings -replace "'", "''"

$scriptContent = @"
Configuration ApplyWindowsServerStig {
    Import-DscResource -ModuleName PowerSTIG -ModuleVersion $pstigVersion

    Node 'localhost' {
        WindowsServer 'ConfigureServer' {
            OsVersion   = '2022'
            OsRole      = 'MS'
            StigVersion = '$stigVersionString'
            OrgSettings = '$safeOrgSettings'

            Exception = @{
                'V-254439' = @{ 'Identity' = 'Guests' }
                'V-254435' = @{ 'Identity' = 'Guests' }
            }

            SkipRule = @(
                'V-254254.c',
                'V-254271',

                # AccountPolicy — handled by account_policy.ps1
                'V-254285', 'V-254286', 'V-254287', 'V-254288',
                'V-254289', 'V-254290', 'V-254291', 'V-254292',

                # UserRightRule — handled by stig_remediation_fixes.ps1
                'V-254434', 'V-254435', 'V-254436', 'V-254437', 'V-254438',
                'V-254439', 'V-254440', 'V-254491', 'V-254492', 'V-254493',
                'V-254494', 'V-254495', 'V-254496', 'V-254497', 'V-254498',
                'V-254499', 'V-254500', 'V-254501', 'V-254502', 'V-254503',
                'V-254504', 'V-254505', 'V-254506', 'V-254507', 'V-254508',
                'V-254509', 'V-254510', 'V-254511', 'V-254512'
            )
        }
    }
}

ApplyWindowsServerStig -OutputPath '$safeOutputPath'
"@

Set-Content -Path $tempScript -Value $scriptContent -Encoding UTF8
Write-Host "Generated temporary DSC config script: $tempScript"

# -----------------------------------------------------------------------
# Spawn a fresh PowerShell process to compile the MOF
# -----------------------------------------------------------------------
Write-Host "=== Generating MOF... ==="
$result = Start-Process powershell `
    -ArgumentList "-ExecutionPolicy Bypass -NonInteractive -File `"$tempScript`"" `
    -Wait `
    -PassThru `
    -NoNewWindow

if ($result.ExitCode -ne 0) {
    Write-Error "DSC configuration compilation failed with exit code $($result.ExitCode)"
    exit $result.ExitCode
}

# -----------------------------------------------------------------------
# Verify MOF was created
# -----------------------------------------------------------------------
$mofFile = Join-Path $OutputPath "localhost.mof"
if (!(Test-Path $mofFile)) {
    Write-Error "MOF file was not generated at: $mofFile"
    exit 1
}

$mofSize = (Get-Item $mofFile).Length
Write-Host "MOF generated: $mofFile (size: $mofSize bytes)"

if ($mofSize -lt 50000) {
    Write-Warning "MOF file is unusually small ($mofSize bytes). Expected > 50 KB."
}

Write-Host "=== DSC configuration compiled successfully ==="
exit 0
