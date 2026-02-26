Import-Module PowerSTIG -ErrorAction Stop
# Get target directory from Cloud Build environment variable
$HardeningDir = $env:_HARDENING_TARGET_DIR
if (-not $HardeningDir) {
    throw "HARDENING_TARGET_DIR environment variable is not set."
}
# Normalize path (remove trailing slash if present)
$HardeningDir = $HardeningDir.TrimEnd('\','/')
# Ensure MOF output directory exists
$MofOutputPath = Join-Path $HardeningDir "ApplyWindowsServerStig"
if (!(Test-Path $MofOutputPath)) {
    New-Item -Path $MofOutputPath -ItemType Directory -Force | Out-Null
}
Configuration ApplyWindowsServerStig {
    param
    (
        [parameter()]
        [string]
        $NodeName = 'localhost'
    )
    Import-DscResource -ModuleName PowerSTIG
    Node $NodeName {
        WindowsServer 'ConfigureServer' {
            OsVersion = '2022'
            OsRole    = 'MS'
            OrgSettings = (Join-Path $using:HardeningDir "WindowsServer-2022-MS-2.1.org.pamdata.xml")
            Exception   = @{
                'V-254439' = @{'Identity'='Guests'}
                'V-254435' = @{'Identity'='Guests'}
                'V-254501' = @{'Identity'='Everyone'}
                'V-254446' = @{'ValueData'='0'}
                'V-254289' = @{'PolicyValue'='0'}
                'V-254290' = @{'PolicyValue'='0'}
                'V-254291' = @{'PolicyValue'='0'}
                'V-254292' = @{'PolicyValue'='Disabled'}
            }
            SkipRule = @('V-254254.c')
        }
    }
}
# Compile MOF
ApplyWindowsServerStig -OutputPath $MofOutputPath
