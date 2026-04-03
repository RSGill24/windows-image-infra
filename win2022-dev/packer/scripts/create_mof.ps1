# create_mof.ps1
# Compiles a DSC MOF using PowerSTIG.
#
# FIX: Added all AccountPolicy STIG rules (V-254285 to V-254292) to SkipRule.
#      DSC AccountPolicy resource calls secedit internally which resets the
#      security policy database and kills the active WinRM session mid-build.
#      These rules are handled correctly by account_policy.ps1 which runs
#      AFTER DSC via net accounts + secedit in a controlled manner.
#
# FIX: Removed all Exception entries that caused STIG regressions:
#   - V-254446 ValueData='0'          was DISABLING blank-password protection (CAT I!)
#   - V-254289 PolicyValue='0'        was setting max password age to NEVER
#   - V-254290 PolicyValue='0'        was setting min password age to 0
#   - V-254291 PolicyValue='0'        was setting min password length to 0
#   - V-254292 PolicyValue='Disabled' was disabling password complexity
#   - V-254501 Identity='Everyone'    was granting Everyone remote shutdown right
#
# Only ISSO-approved exceptions remain: V-254439 and V-254435 (Guests group).
# All password/lockout policy values are driven by the org.pamdata.xml file.

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

            # ---------------------------------------------------------------
            # EXCEPTION RULES — ISSO-APPROVED DEVIATIONS ONLY
            # ---------------------------------------------------------------
            Exception = @{
                # V-254439: Deny log on as a service — Guests only
                'V-254439' = @{ 'Identity' = 'Guests' }
                # V-254435: Deny log on as a batch job — Guests only
                'V-254435' = @{ 'Identity' = 'Guests' }
            }

            SkipRule = @(
                'V-254254.c',
                'V-254271',

                # -------------------------------------------------------
                # AccountPolicy rules — ALL skipped here.
                # DSC AccountPolicy resource calls secedit internally.
                # secedit resets the security policy database and kills
                # the active WinRM session mid-build, preventing all
                # subsequent scripts from running.
                # These rules are fully handled by account_policy.ps1
                # which runs AFTER DSC using net accounts + secedit
                # in a controlled post-DSC step.
                # -------------------------------------------------------
                'V-254285',   # Account lockout duration >= 15 min
                'V-254286',   # Account lockout threshold <= 3
                'V-254287',   # Reset lockout counter >= 15 min
                'V-254288',   # Minimum password age >= 1 day
                'V-254289',   # Maximum password age <= 60 days
                'V-254290',   # Minimum password length >= 14
                'V-254291',   # Password complexity = Enabled
                'V-254292'    # Password history >= 24
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
    Write-Warning "This may indicate rules were skipped or compilation was incomplete."
}

Write-Host "=== DSC configuration compiled successfully ==="
exit 0
