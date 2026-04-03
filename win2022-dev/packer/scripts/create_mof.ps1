# create_mof.ps1
# Compiles a DSC MOF using PowerSTIG.
#
# FIX: Added all UserRightRule IDs (V-254434 to V-254512) to SkipRule.
#      DSC UserRightRule resource calls secedit internally, same as
#      AccountPolicy. secedit resets the security policy database and
#      kills the active WinRM session mid-build. All user rights rules
#      are handled by stig_remediation_fixes.ps1 post-DSC.
#
# FIX: Added all AccountPolicy rules (V-254285 to V-254292) to SkipRule.
#      Same secedit problem. Handled by account_policy.ps1 post-DSC.
#
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
                # AccountPolicy rules — skipped to prevent secedit from
                # killing the WinRM session during DSC execution.
                # DSC AccountPolicy resource calls secedit internally which
                # resets the security policy database and terminates the
                # active WinRM PowerShell process.
                # All rules handled by account_policy.ps1 post-DSC.
                # -------------------------------------------------------
                'V-254285',   # Account lockout duration >= 15 min
                'V-254286',   # Account lockout threshold <= 3
                'V-254287',   # Reset lockout counter >= 15 min
                'V-254288',   # Minimum password age >= 1 day
                'V-254289',   # Maximum password age <= 60 days
                'V-254290',   # Minimum password length >= 14
                'V-254291',   # Password complexity = Enabled
                'V-254292',   # Password history >= 24

                # -------------------------------------------------------
                # UserRightRule rules — skipped for the same reason.
                # DSC UserRightRule resource also calls secedit internally.
                # Full list sourced from WindowsServer-2022-MS-2.7.xml.
                # All rules handled by stig_remediation_fixes.ps1 post-DSC.
                # -------------------------------------------------------
                'V-254434',   # Access this computer from the network
                'V-254435',   # Deny access to this computer from the network
                'V-254436',   # Deny log on as a batch job
                'V-254437',   # Deny log on as a service
                'V-254438',   # Deny log on locally
                'V-254439',   # Deny log on through Remote Desktop Services
                'V-254440',   # Enable computer and user accounts trusted for delegation
                'V-254491',   # Access Credential Manager as a trusted caller
                'V-254492',   # Act as part of the operating system
                'V-254493',   # Allow log on locally
                'V-254494',   # Back up files and directories
                'V-254495',   # Create a pagefile
                'V-254496',   # Create a token object
                'V-254497',   # Create global objects
                'V-254498',   # Create permanent shared objects
                'V-254499',   # Create symbolic links
                'V-254500',   # Debug programs
                'V-254501',   # Force shutdown from a remote system
                'V-254502',   # Generate security audits
                'V-254503',   # Impersonate a client after authentication
                'V-254504',   # Increase scheduling priority
                'V-254505',   # Load and unload device drivers
                'V-254506',   # Lock pages in memory
                'V-254507',   # Manage auditing and security log
                'V-254508',   # Modify firmware environment values
                'V-254509',   # Perform volume maintenance tasks
                'V-254510',   # Profile single process
                'V-254511',   # Restore files and directories
                'V-254512'    # Take ownership of files or other objects
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
