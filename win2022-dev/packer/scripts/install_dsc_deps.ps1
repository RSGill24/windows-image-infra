# install_dsc_deps.ps1
# Installs PowerSTIG dependencies and generates org settings XML with PAM overrides.
# Safe for GCP Cloud Build / Packer pipelines.

param (
    [string]$HardeningDir = $PSScriptRoot
)

Write-Host "=== Installing PowerSTIG dependencies ==="

# -----------------------------------------------------------------------
# Step 0: Import PowerSTIG and detect latest module
# -----------------------------------------------------------------------
$module = Get-Module PowerSTIG -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1

if (-not $module) {
    Write-Error "PowerSTIG module not found. Run install_PowerSTIG.ps1 first."
    exit 1
}
Write-Host "Found PowerSTIG $($module.Version) at: $($module.ModuleBase)"

$systemModulePath = "C:\Program Files\WindowsPowerShell\Modules"
$dscSystemPath    = "C:\Windows\system32\WindowsPowerShell\v1.0\Modules"

# -----------------------------------------------------------------------
# Step 1: Aggressively purge duplicate modules from BOTH paths.
# -----------------------------------------------------------------------
Write-Host "--- Removing duplicate modules to prevent CIM conflicts..."

foreach ($dep in $module.RequiredModules) {

    # 1. Purge from System32 completely (bypassing TrustedInstaller)
    $dscDepPath = Join-Path $dscSystemPath $dep.Name
    if (Test-Path $dscDepPath) {
        Write-Host "  Nuking conflicting System32 path: $dscDepPath" -ForegroundColor Yellow
        takeown.exe /F $dscDepPath /R /D Y | Out-Null
        icacls.exe $dscDepPath /grant "Administrators:(OI)(CI)F" /T /Q | Out-Null
        Remove-Item $dscDepPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Purge from Program Files (removes older versions if present)
    $pfDepPath = Join-Path $systemModulePath $dep.Name
    if (Test-Path $pfDepPath) {
        Write-Host "  Removing old Program Files path: $pfDepPath"
        Remove-Item $pfDepPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 3. Install cleanly into Program Files
    Write-Host "--- Installing: $($dep.Name) $($dep.Version)"
    Install-Module -Name $dep.Name -RequiredVersion $dep.Version -Scope AllUsers -Force -AllowClobber
}

# Also purge PowerSTIG from System32 if it got copied there during a previous run
$pstigDscPath = Join-Path $dscSystemPath "PowerSTIG"
if (Test-Path $pstigDscPath) {
    Write-Host "  Nuking conflicting PowerSTIG System32 path: $pstigDscPath" -ForegroundColor Yellow
    takeown.exe /F $pstigDscPath /R /D Y | Out-Null
    icacls.exe $pstigDscPath /grant "Administrators:(OI)(CI)F" /T /Q | Out-Null
    Remove-Item $pstigDscPath -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "  Duplicate cleanup complete."

# -----------------------------------------------------------------------
# Step 2: Find the .org.default.xml inside the installed module
# -----------------------------------------------------------------------
$stigDataPath = Join-Path $module.ModuleBase "StigData\Processed"
Write-Host "--- Searching for org.default.xml in: $stigDataPath"

$defaultOrgFile = Get-ChildItem -Path $stigDataPath `
                    -Filter "WindowsServer-2022-MS-*.org.default.xml" `
                    -ErrorAction SilentlyContinue |
                  Sort-Object Name -Descending |
                  Select-Object -First 1

if (-not $defaultOrgFile) {
    Write-Error "No WindowsServer-2022-MS-*.org.default.xml found in $stigDataPath"
    exit 1
}
Write-Host "Found org.default.xml: $($defaultOrgFile.FullName)"

# -----------------------------------------------------------------------
# Step 3: Copy the default XML to the hardening dir and apply PAM overrides
# -----------------------------------------------------------------------
$outputOrgXml = Join-Path $HardeningDir ($defaultOrgFile.Name -replace '\.org\.default\.xml', '.org.pamdata.xml')
Copy-Item -Path $defaultOrgFile.FullName -Destination $outputOrgXml -Force
Write-Host "Copied XML to: $outputOrgXml"

[xml]$orgXml = Get-Content -Path $outputOrgXml -Encoding UTF8

Write-Host "--- Applying PAM org setting overrides..."

$overrides = @{
    "V-254248" = @{ ServiceName="WinDefend";  StartupType="Automatic" }
    "V-254265" = @{ ServiceName="MpsSvc";     StartupType="Automatic" }
    "V-254285" = @{ PolicyValue="15" }
    "V-254286" = @{ PolicyValue="3"  }
    "V-254287" = @{ PolicyValue="15" }
    "V-254288" = @{ PolicyValue="24" }
    "V-254289" = @{ PolicyValue="60" }
    "V-254290" = @{ PolicyValue="1"  }
    "V-254291" = @{ PolicyValue="15" }
}

foreach ($vid in $overrides.Keys) {
    $node = $orgXml.OrganizationalSettings.OrganizationalSetting | Where-Object { $_.id -eq $vid }
    if ($node) {
        foreach ($attr in $overrides[$vid].Keys) {
            $node.SetAttribute($attr, $overrides[$vid][$attr])
        }
        Write-Host "  Set $vid overrides"
    } else {
        Write-Warning "  $vid not found in XML — skipping"
    }
}

$orgXml.Save($outputOrgXml)
Write-Host "Org settings XML saved to: $outputOrgXml"

# -----------------------------------------------------------------------
# Step 4: Verify DSC resources
# -----------------------------------------------------------------------
Write-Host "--- Verifying DSC resources..."
$dscResources = Get-DscResource -Module PowerSTIG -ErrorAction SilentlyContinue
if ($dscResources) {
    $dscResources | Select-Object -First 5 | ForEach-Object {
        Write-Host "  DSC resource OK: $($_.Name)"
    }
} else {
    Write-Warning "  No DSC resources returned — check for CIM class conflicts in event log"
}

# -----------------------------------------------------------------------
# Step 5: Patch GPRegistryPolicyDsc to disable gpupdate
#
# PowerSTIG's RefreshRegistryPolicy resource calls gpupdate /force at the
# end of every DSC run. gpupdate resets WinRM auth settings and kills the
# active Packer WinRM session, preventing all post-DSC scripts from running.
# This patch replaces the gpupdate call with a no-op string so the resource
# completes without breaking the connection.
#
# The patch is version-aware — if the file path changes (module update),
# it will warn instead of silently failing.
# -----------------------------------------------------------------------
Write-Host "--- Patching GPRegistryPolicyDsc to disable gpupdate..." -ForegroundColor Yellow

$gpRegModule  = Get-Module GPRegistryPolicyDsc -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
$patchFile    = $null

if ($gpRegModule) {
    $patchFile = Join-Path $gpRegModule.ModuleBase `
        "DSCResources\MSFT_RefreshRegistryPolicy\MSFT_RefreshRegistryPolicy.psm1"
}

if ($patchFile -and (Test-Path $patchFile)) {
    $content = Get-Content $patchFile -Raw

    if ($content -match 'PATCHED') {
        Write-Host "  [OK] Already patched — skipping" -ForegroundColor Green
    } else {
        # Backup original
        Copy-Item $patchFile "$patchFile.bak" -Force
        Write-Host "  Backup saved: $patchFile.bak"

        # Replace gpupdate call with no-op
        $content = $content -replace `
            "\`$gpupdateResult = Invoke-Command -ScriptBlock \{'N','N' \| gpupdate\.exe /force\}", `
            '$gpupdateResult = "Skipped for Packer build" # PATCHED: gpupdate disabled to preserve WinRM session'

        Set-Content $patchFile $content -Encoding UTF8

        # Verify
        if ((Get-Content $patchFile -Raw) -match 'PATCHED') {
            Write-Host "  [OK] GPRegistryPolicyDsc patched successfully" -ForegroundColor Green
        } else {
            Write-Warning "  Patch may not have applied — verify manually: $patchFile"
        }
    }
} else {
    Write-Warning "  GPRegistryPolicyDsc psm1 not found — module version may have changed"
    Write-Warning "  Run: Get-ChildItem 'C:\Program Files\WindowsPowerShell\Modules\GPRegistryPolicyDsc' -Recurse -Filter '*.psm1'"
}

Write-Host "=== Dependencies installed successfully ==="
