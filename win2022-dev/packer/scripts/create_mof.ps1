# create_mof.ps1
# Generates the DSC MOF file from PowerSTIG STIG baseline.
# Covers all 22 STIG failures found in SCC scan.

param (
    [string]$HardeningDir = $PSScriptRoot
)

Write-Host "=== Generating DSC MOF ==="

Import-Module PowerSTIG -ErrorAction Stop

# -----------------------------------------------------------------------
# Locate org settings XML (dynamic -- matches whatever version is present)
# -----------------------------------------------------------------------
$orgXml = Get-ChildItem -Path $HardeningDir `
            -Filter "WindowsServer-2022-MS-*.org.pamdata.xml" `
            -ErrorAction SilentlyContinue |
          Sort-Object Name -Descending |
          Select-Object -First 1

if (-not $orgXml) {
    Write-Error "No org.pamdata.xml found in $HardeningDir -- run install_dsc_deps.ps1 first."
    exit 1
}
Write-Host "Using org settings: $($orgXml.FullName)"

$OutputPath = Join-Path $HardeningDir "MOF"
if (!(Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

# -----------------------------------------------------------------------
# DSC Configuration block
# -----------------------------------------------------------------------
Configuration HardenWS2022 {

    Import-DscResource -ModuleName PowerSTIG

    Node localhost {

        WindowsServer Baseline {
            OsVersion   = '2022'
            OsRole      = 'MS'
            OrgSettings = $using:orgXml.FullName
            Exception   = @{
                # V-254284: Secure Boot — cannot be enforced via DSC/GPO inside a VM.
                # Handled in harden_ww.pkr.hcl via enable_secure_boot = true (Shielded VM).
                'V-254284' = @{ ValueData = '1' }
            }
        }
    }
}

# -----------------------------------------------------------------------
# Compile the MOF
# -----------------------------------------------------------------------
Write-Host "Compiling MOF to: $OutputPath"
HardenWS2022 -OutputPath $OutputPath

$mofFile = Join-Path $OutputPath "localhost.mof"
if (!(Test-Path $mofFile)) {
    Write-Error "MOF compilation failed -- localhost.mof not found at $OutputPath"
    exit 1
}

Write-Host "=== MOF generated successfully: $mofFile ==="