# install_dsc_deps.ps1
# Installs PowerSTIG dependencies, copies modules to DSC LCM path,
# and generates org settings XML with all required STIG overrides.

param (
    [string]$HardeningDir = $PSScriptRoot
)

Write-Host "=== Installing PowerSTIG dependencies ==="

# -----------------------------------------------------------------------
# Step 0: Locate installed PowerSTIG module
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
# Step 1: Install each dependency and copy to DSC LCM system32 path
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
# Step 3: Locate the .org.default.xml inside the installed module
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
# Step 4: Copy and apply ALL required org setting overrides
# This now covers every V-ID that was failing in the SCC scan.
# -----------------------------------------------------------------------
$outputOrgXml = Join-Path $HardeningDir ($defaultOrgFile.Name -replace '\.org\.default\.xml', '.org.pamdata.xml')
Copy-Item -Path $defaultOrgFile.FullName -Destination $outputOrgXml -Force
Write-Host "Copied XML to: $outputOrgXml"

[xml]$orgXml = Get-Content -Path $outputOrgXml -Encoding UTF8

Write-Host "--- Applying org setting overrides..."

$overrides = @{
    # AV and Firewall services
    "V-254248"   = @{ ServiceName="WinDefend";  StartupType="Automatic" }
    "V-254265"   = @{ ServiceName="MpsSvc";     StartupType="Automatic" }

    # Password policy -- fixes V-254289, V-254290, V-254291
    "V-254285"   = @{ PolicyValue="15" }   # lockout duration
    "V-254286"   = @{ PolicyValue="3"  }   # lockout threshold
    "V-254287"   = @{ PolicyValue="15" }   # reset lockout counter
    "V-254288"   = @{ PolicyValue="24" }   # password history
    "V-254289"   = @{ PolicyValue="60" }   # max password age (V-254289)
    "V-254290"   = @{ PolicyValue="1"  }   # min password age (V-254290)
    "V-254291"   = @{ PolicyValue="14" }   # min password length (V-254291)

    # DoD banner
    "V-254457"   = @{ ValueData="You are accessing a U.S. Government (USG) Information System (IS) that is provided for USG-authorized use only. By using this IS, you consent to monitoring, interception, and search of all data." }
    "V-254458"   = @{ ValueData="DoD Notice and Consent Banner" }
    "V-254459"   = @{ ValueData="1" }
    "V-254484"   = @{ ValueData="1" }

    # Event log sizes
    "V-254357"   = @{ ValueData="100"    }
    "V-254358"   = @{ ValueData="32768"  }
    "V-254359"   = @{ ValueData="196608" }
    "V-254360"   = @{ ValueData="32768"  }

    # Misc
    "V-254343.b" = @{ ValueData="1"  }
    "V-254344"   = @{ ValueData="8"  }
    "V-254432"   = @{ ValueData="4"  }
    "V-254454"   = @{ ValueData="30" }
    "V-254456"   = @{ ValueData="900"}

    # Account rename targets (V-254447 / V-254448)
    # OptionValue must not be 'Administrator' or 'Guest'
    "V-254447"   = @{ OptionValue="Local_Admin"  }
    "V-254448"   = @{ OptionValue="Local_Guest"  }

    # User rights (V-254499 / V-254435 / V-254501)
    "V-254499"   = @{ Identity="Administrators" }
    "V-254435"   = @{ Identity="Enterprise Admins,Domain Admins,(Local account and member of Administrators group|Local account),Guests" }

    # DoD cert locations -- point to the local cert store (empty = auto-detected by PowerSTIG)
    "V-254442.a" = @{ Location="" }
    "V-254442.b" = @{ Location="" }
    "V-254442.c" = @{ Location="" }
    "V-254442.d" = @{ Location="" }
    "V-254443"   = @{ Location="" }
    "V-254444"   = @{ Location="" }
}

foreach ($vid in $overrides.Keys) {
    $node = $orgXml.OrganizationalSettings.OrganizationalSetting |
            Where-Object { $_.id -eq $vid }
    if ($node) {
        foreach ($attr in $overrides[$vid].Keys) {
            $node.SetAttribute($attr, $overrides[$vid][$attr])
        }
        Write-Host "  Set [$vid]: $($overrides[$vid] | ConvertTo-Json -Compress)"
    } else {
        Write-Warning "  $vid not found in XML -- skipping"
    }
}

$orgXml.Save($outputOrgXml)
Write-Host "Org settings XML saved to: $outputOrgXml"

# -----------------------------------------------------------------------
# Step 5: Verify DSC resources loaded correctly
# -----------------------------------------------------------------------
Write-Host "--- Verifying DSC resources..."
Get-DscResource -Module PowerSTIG | Select-Object -First 5 | ForEach-Object {
    Write-Host "  DSC resource OK: $($_.Name)"
}

Write-Host "=== Dependencies installed successfully. ==="