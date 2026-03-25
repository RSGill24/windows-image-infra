# install_dsc_deps.ps1
# Installs PowerSTIG dependencies, copies modules to DSC LCM path,
# generates org settings XML with PAM overrides.
# Safe for GCP Cloud Build / Packer pipelines.
# FIX: Removes duplicate CertificateDsc module copies before installing
#      to prevent "A second CIM class definition" DSC compilation errors.

param (
    [string]$HardeningDir = $PSScriptRoot
)

Write-Host "=== Installing PowerSTIG dependencies ==="

# -----------------------------------------------------------------------
# Step 0: Import PowerSTIG and detect latest module
# -----------------------------------------------------------------------
$module = Get-Module PowerSTIG -ListAvailable |
          Sort-Object Version -Descending | Select-Object -First 1

if (-not $module) {
    Write-Error "PowerSTIG module not found. Run install_PowerSTIG.ps1 first."
    exit 1
}
Write-Host "Found PowerSTIG $($module.Version) at: $($module.ModuleBase)"

$systemModulePath = "C:\Program Files\WindowsPowerShell\Modules"
$dscSystemPath    = "C:\Windows\system32\WindowsPowerShell\v1.0\Modules"

# -----------------------------------------------------------------------
# FIX 1: Remove duplicate module copies from BOTH paths before installing
# This prevents "A second CIM class definition for DSC_CertificateImport"
# errors that occur when CertificateDsc 5.0.0 exists in both:
#   C:\Program Files\WindowsPowerShell\Modules\CertificateDsc\5.0.0
#   C:\Windows\system32\WindowsPowerShell\v1.0\Modules\CertificateDsc\5.0.0
# -----------------------------------------------------------------------
Write-Host "--- Removing duplicate/stale module copies to prevent CIM conflicts..."

foreach ($dep in $module.RequiredModules) {
    # Remove from Program Files path (we will re-install cleanly via Install-Module)
    $pfVersionPath = Join-Path $systemModulePath "$($dep.Name)\$($dep.Version)"
    if (Test-Path $pfVersionPath) {
        Write-Host "  Removing stale copy: $pfVersionPath"
        Remove-Item $pfVersionPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Remove from system32 DSC path (we will re-copy after Install-Module)
    $dscVersionPath = Join-Path $dscSystemPath "$($dep.Name)\$($dep.Version)"
    if (Test-Path $dscVersionPath) {
        Write-Host "  Removing stale DSC copy: $dscVersionPath"
        Remove-Item $dscVersionPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Also remove stale PowerSTIG copy from DSC system32 path
$pstigDscPath = Join-Path $dscSystemPath "PowerSTIG\$($module.Version)"
if (Test-Path $pstigDscPath) {
    Write-Host "  Removing stale PowerSTIG DSC copy: $pstigDscPath"
    Remove-Item $pstigDscPath -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "  Duplicate cleanup complete."

# -----------------------------------------------------------------------
# Step 1: Install each dependency fresh and copy to DSC LCM system32 path
# -----------------------------------------------------------------------
foreach ($dep in $module.RequiredModules) {
    Write-Host "--- Installing: $($dep.Name) $($dep.Version)"
    Install-Module -Name $dep.Name `
                   -RequiredVersion $dep.Version `
                   -Scope AllUsers `
                   -Force `
                   -AllowClobber

    $srcPath = Join-Path $systemModulePath "$($dep.Name)\$($dep.Version)"
    $dstDir  = Join-Path $dscSystemPath    $dep.Name
    $dstPath = Join-Path $dstDir           $dep.Version

    if (Test-Path $srcPath) {
        if (!(Test-Path $dstDir)) { New-Item -Path $dstDir -ItemType Directory -Force | Out-Null }
        Write-Host "    Copying to DSC path: $dstPath"
        Copy-Item -Path $srcPath -Destination $dstPath -Recurse -Force
    } else {
        Write-Warning "    Source not found at $srcPath -- skipping copy"
    }
}

# -----------------------------------------------------------------------
# Step 2: Copy PowerSTIG itself into the DSC LCM system32 path
# -----------------------------------------------------------------------
$pstigSrc    = $module.ModuleBase
$pstigDstDir = Join-Path $dscSystemPath "PowerSTIG"
$pstigDst    = Join-Path $pstigDstDir   $module.Version
if (!(Test-Path $pstigDstDir)) { New-Item -Path $pstigDstDir -ItemType Directory -Force | Out-Null }
Copy-Item -Path $pstigSrc -Destination $pstigDst -Recurse -Force
Write-Host "Copied PowerSTIG module to DSC path: $pstigDst"

# -----------------------------------------------------------------------
# Step 3: Find the .org.default.xml inside the installed module
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
# Step 4: Copy the default XML to the hardening dir and apply PAM overrides
# Dynamic filename -- picks up whatever version is installed (2.7, 3.0, etc.)
# -----------------------------------------------------------------------
$outputOrgXml = Join-Path $HardeningDir ($defaultOrgFile.Name -replace '\.org\.default\.xml', '.org.pamdata.xml')
Copy-Item -Path $defaultOrgFile.FullName -Destination $outputOrgXml -Force
Write-Host "Copied XML to: $outputOrgXml"

[xml]$orgXml = Get-Content -Path $outputOrgXml -Encoding UTF8

Write-Host "--- Applying PAM org setting overrides..."

# FIX 2: Corrected override values to match STIG requirements exactly.
# Previously V-254291 was set to 13 (below STIG minimum of 14) and
# V-254290 comment said 1 but value was 10. Both corrected here.
$overrides = @{
    "V-254248" = @{ ServiceName="WinDefend";  StartupType="Automatic" }
    "V-254265" = @{ ServiceName="MpsSvc";     StartupType="Automatic" }
    "V-254285" = @{ PolicyValue="15" }   # Account lockout duration >= 15 min
    "V-254286" = @{ PolicyValue="3"  }   # Account lockout threshold <= 3
    "V-254287" = @{ PolicyValue="15" }   # Reset lockout counter after >= 15 min
    "V-254288" = @{ PolicyValue="24" }   # Password history = 24
    "V-254289" = @{ PolicyValue="60" }   # Max password age = 60 days
    "V-254290" = @{ PolicyValue="1"  }   # Min password age = 1 day  (FIX: was 10)
    "V-254291" = @{ PolicyValue="15" }   # Min password length = 15  (FIX: was 13, STIG min is 14)
}

foreach ($vid in $overrides.Keys) {
    $node = $orgXml.OrganizationalSettings.OrganizationalSetting | Where-Object { $_.id -eq $vid }
    if ($node) {
        foreach ($attr in $overrides[$vid].Keys) {
            $node.SetAttribute($attr, $overrides[$vid][$attr])
        }
        Write-Host "  Set $vid overrides:"
        $overrides[$vid].GetEnumerator() | ForEach-Object { Write-Host "    $($_.Key) = $($_.Value)" }
    } else {
        Write-Warning "  $vid not found in XML — skipping"
    }
}

# Save the final XML
$orgXml.Save($outputOrgXml)
Write-Host "Org settings XML saved to: $outputOrgXml"

# -----------------------------------------------------------------------
# Step 5: Verify DSC resources — confirm no duplicate CIM errors remain
# -----------------------------------------------------------------------
Write-Host "--- Verifying DSC resources..."

# Force a fresh module load to surface any remaining CIM conflicts early
$dscResources = Get-DscResource -Module PowerSTIG -ErrorAction SilentlyContinue
if ($dscResources) {
    $dscResources | Select-Object -First 5 | ForEach-Object {
        Write-Host "  DSC resource OK: $($_.Name)"
    }
} else {
    Write-Warning "  No DSC resources returned — check for CIM class conflicts in event log"
}

Write-Host "=== Dependencies installed successfully. ==="
