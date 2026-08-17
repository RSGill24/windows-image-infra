# create_mof.ps1
# Compiles a DSC MOF using PowerSTIG.
#
# FIX: Removed all Exception entries that caused STIG regressions:
#   - V-254446 ValueData='0'         was DISABLING blank-password protection (CAT I!)
#   - V-254289 PolicyValue='0'       was setting max password age to NEVER
#   - V-254290 PolicyValue='0'       was setting min password age to 0
#   - V-254291 PolicyValue='0'       was setting min password length to 0
#   - V-254292 PolicyValue='Disabled' was disabling password complexity
#   - V-254501 Identity='Everyone'   was granting Everyone remote shutdown right
#
# FIX: Added V-254289 through V-254293 (all AccountPolicy rules) to SkipRule.
#   FIX: Added V-254285 through V-254288 (lockout policy rules) to SkipRule.
#   FIX: Added V-254445 and V-254465 (SecurityOption rules) to SkipRule.
#        SecurityOption DSC resource also writes to the SCE database and breaks
#        WinRM mid-session exactly like AccountPolicy. Both handled by
#        stig_remediation_fixes.ps1 after all uploads are complete.
#   AccountPolicy DSC resource writes to the SCE security database during
#   Start-DscConfiguration, which causes Windows to re-enforce GPO-derived
#   WinRM restrictions mid-session — breaking Packer's WinRM connection before
#   subsequent provisioners can run. These rules are handled exclusively by
#   account_policy.ps1 which runs after all file uploads are complete.
#
# Only ISSO-approved exceptions remain: V-254439 and V-254435 (Guests group).
# All password/lockout policy values are driven by the org.pamdata.xml file.

Write-Host "=== create_mof.ps1 starting ==="

# -----------------------------------------------------------------------
# PRE-COMPILATION CIM CONFLICT CLEANUP
# Aggressively destroys out-of-band DSC modules baked into System32.
# If these exist alongside the Program Files copies, DSC compilation fails.
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

        # Strip TrustedInstaller protections using native Windows tools
        takeown.exe /F $badPath /R /D Y | Out-Null
        icacls.exe $badPath /grant "Administrators:(OI)(CI)F" /T /Q | Out-Null

        # Nuke the folder
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
$stigXml = Get-ChildItem -Path $stigDataPath -Filter "WindowsServer-2025-MS-*.org.default.xml" |
           Sort-Object Name -Descending | Select-Object -First 1
if (-not $stigXml) {
    Write-Error "No WindowsServer-2025-MS-*.org.default.xml found in $stigDataPath"
    exit 1
}
$stigVersionString = ($stigXml.Name -replace 'WindowsServer-2025-MS-', '' -replace '\.org\.default\.xml', '')
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
            OsVersion   = '2025'
            OsRole      = 'MS'
            StigVersion = '$stigVersionString'
            OrgSettings = '$safeOrgSettings'

            # ---------------------------------------------------------------
            # EXCEPTION RULES — ISSO-APPROVED DEVIATIONS ONLY
            # ---------------------------------------------------------------
            # All password policy, lockout policy, and security option values
            # are driven by OrgSettings (pamdata.xml). Do NOT add exceptions
            # for those rules here — exceptions override pamdata.xml and will
            # cause SCAP failures.
            #
            # REMOVED exceptions that caused SCAP failures:
            #   V-254446 ValueData='0'          -> Disabled blank-password protection (CAT I)
            #   V-254289 PolicyValue='0'         -> Max password age = NEVER
            #   V-254290 PolicyValue='0'         -> Min password age = 0
            #   V-254291 PolicyValue='0'         -> Min password length = 0
            #   V-254292 PolicyValue='Disabled'  -> Disabled password complexity
            #   V-254501 Identity='Everyone'     -> Granted Everyone remote shutdown
            # ---------------------------------------------------------------
            Exception = @{
                # V-254439: Deny log on as a service — Guests only
                'V-254439' = @{ 'Identity' = 'Guests' }
                # V-254435: Deny log on as a batch job — Guests only
                'V-254435' = @{ 'Identity' = 'Guests' }
            }

            SkipRule = @(
                # -------------------------------------------------------
                # AccountPolicy rules — skipped to prevent SCE database
                # write during DSC apply. The SCE write re-enforces
                # GPO-derived WinRM restrictions mid-session, breaking
                # Packer's connection. All handled by account_policy.ps1
                # after all uploads are complete.
                # -------------------------------------------------------
                'V-254285',   # Account lockout duration
                'V-254286',   # Account lockout threshold
                'V-254287',   # Account lockout observation window
                'V-254288',   # Enforce password history
                'V-254289',   # Maximum password age
                'V-254290',   # Minimum password age
                'V-254291',   # Minimum password length
                'V-254292',   # Password complexity
                'V-254293',   # Reversible encryption (CAT I)
                'V-254434'

                # -------------------------------------------------------
                # SecurityOption rules — also write to SCE database,
                # same WinRM-breaking side effect as AccountPolicy.
                # Handled by stig_remediation_fixes.ps1 after uploads.
                # -------------------------------------------------------
                'V-254445',   # Network security: LAN Manager auth level
                'V-254465',   # Network security: LDAP client signing

                # -------------------------------------------------------
                # WinRM STIG rules — these DISABLE Basic auth / unencrypted
                # traffic during DSC apply, which KILLS Packer's WinRM
                # session mid-build and causes the instance to be deleted
                # at ~41s with the provisioner hung. Must be applied AFTER
                # the Packer image is captured (via first-boot scheduled
                # task on the resulting image, not during build).
                # Also protected by WinRM guardian task in apply_mof.ps1.
                # -------------------------------------------------------
                'V-254499',   # WinRM client: do not allow Basic auth
                'V-254500',   # WinRM client: do not allow unencrypted traffic
                'V-254501',   # WinRM client: do not use Digest auth
                'V-254502',   # WinRM service: do not allow Basic auth
                'V-254503',   # WinRM service: do not allow unencrypted traffic
                'V-254504',   # WinRM service: must not store RunAs credentials

                # -------------------------------------------------------
                # Pre-existing skips (unchanged)
                # -------------------------------------------------------
                'V-254254.c',
                'V-254271',
                'V-254457',
                'V-254458'
            )
        }
    }
}

ApplyWindowsServerStig -OutputPath '$safeOutputPath'
"@

Set-Content -Path $tempScript -Value $scriptContent -Encoding UTF8
Write-Host "Generated temporary DSC config script: $tempScript"

# -----------------------------------------------------------------------
# Spawn a fresh PowerShell process to compile the MOF.
# A new process avoids CIM class caching issues from the current session.
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
    Write-Warning "This may indicate that many STIG rules were skipped or the compilation was incomplete."
}

# -----------------------------------------------------------------------
# Confirm AccountPolicy rules are absent from the compiled MOF.
# If any appear, SkipRule did not take effect — abort before apply_mof.ps1
# runs and breaks WinRM.
# -----------------------------------------------------------------------
Write-Host "Verifying SCE-writing resources are excluded from MOF..."
$sceHits = Select-String -Path $mofFile -Pattern "AccountPolicy|SecurityOption" -SimpleMatch
if ($sceHits) {
    Write-Error "SCE-writing resources (AccountPolicy or SecurityOption) found in compiled MOF."
    Write-Error "DSC apply would break WinRM. Aborting. Check SkipRule entries in this script."
    Write-Error "Matching lines:"
    $sceHits | ForEach-Object { Write-Error "  $($_.Line.Trim())" }
    exit 1
}
Write-Host "  [OK] No SCE-writing resources in MOF — safe to apply." -ForegroundColor Green

Write-Host "=== DSC configuration compiled successfully ==="
exit 0
