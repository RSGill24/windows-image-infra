#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies ALL advanced audit policy subcategories required by Windows Server 2025 STIG.
    Covers V-278048 through V-278077, V-278199, V-278942 to V-278947, V-279922/V-279923.

    FIX: auditpol settings alone do NOT survive image capture/reboot.
    This script now writes audit.csv to Local Group Policy so settings
    persist when a new VM boots from the captured image.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

function Write-OK   ($m) { Write-Host "  [OK]   $m" -ForegroundColor Green  }
function Write-Fail ($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red    }
function Write-Warn ($m) { Write-Host "  [WARN] $m" -ForegroundColor Yellow }

Write-Host "`n=== Applying Advanced Audit Policy (Win2025 STIG) ===" -ForegroundColor Cyan

$ErrorCount = 0

# -----------------------------------------------------------------------
# V-278199: Ensure advanced audit policy overrides basic audit policy
# Set in BOTH registry and Local Group Policy
# -----------------------------------------------------------------------
$regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
Set-ItemProperty -Path $regPath -Name 'SCENoApplyLegacyAuditPolicy' -Value 1 -Type DWord -Force
Write-OK "V-278199: SCENoApplyLegacyAuditPolicy = 1"

# Also set via Group Policy registry key
$gpRegPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System\Audit'
if (!(Test-Path $gpRegPath)) { New-Item -Path $gpRegPath -Force | Out-Null }
Set-ItemProperty -Path $gpRegPath -Name 'ProcessCreationIncludeCmdLine_Enabled' -Value 1 -Type DWord -Force

# -----------------------------------------------------------------------
# Audit subcategory definitions with GUIDs for audit.csv
# -----------------------------------------------------------------------
$auditSettings = @(
    # Account Logon
    @{ Subcategory = "Credential Validation";           GUID = "{0CCE923F-69AE-11D9-BED3-505054503030}"; Success = "enable"; Failure = "enable"; STIG = "V-278048" },

    # Account Management
    @{ Subcategory = "Other Account Management Events"; GUID = "{0CCE923A-69AE-11D9-BED3-505054503030}"; Success = "enable"; Failure = "enable"; STIG = "V-278049" },
    @{ Subcategory = "User Account Management";         GUID = "{0CCE9235-69AE-11D9-BED3-505054503030}"; Success = "enable"; Failure = "enable"; STIG = "V-278052" },

    # Detailed Tracking
    @{ Subcategory = "Plug and Play Events";            GUID = "{0CCE9248-69AE-11D9-BED3-505054503030}"; Success = "enable"; Failure = "disable"; STIG = "V-278053" },
    @{ Subcategory = "Process Creation";                GUID = "{0CCE922B-69AE-11D9-BED3-505054503030}"; Success = "enable"; Failure = "disable"; STIG = "V-278054" },

    # Logon/Logoff
    @{ Subcategory = "Account Lockout";                 GUID = "{0CCE9217-69AE-11D9-BED3-505054503030}"; Success = "enable"; Failure = "enable"; STIG = "V-278055/056" },
    @{ Subcategory = "Group Membership";                GUID = "{0CCE9249-69AE-11D9-BED3-505054503030}"; Success = "enable"; Failure = "disable"; STIG = "V-278057" },

    # Object Access
    @{ Subcategory = "Other Object Access Events";      GUID = "{0CCE9227-69AE-11D9-BED3-505054503030}"; Success = "enable"; Failure = "enable"; STIG = "V-278062/063" },
    @{ Subcategory = "Removable Storage";               GUID = "{0CCE9245-69AE-11D9-BED3-505054503030}"; Success = "enable"; Failure = "enable"; STIG = "V-278064/065" },
    @{ Subcategory = "File System";                     GUID = "{0CCE921D-69AE-11D9-BED3-505054503030}"; Success = "enable"; Failure = "enable"; STIG = "V-278942/943" },
    @{ Subcategory = "Handle Manipulation";             GUID = "{0CCE9223-69AE-11D9-BED3-505054503030}"; Success = "enable"; Failure = "enable"; STIG = "V-278944/945" },
    @{ Subcategory = "Registry";                        GUID = "{0CCE921E-69AE-11D9-BED3-505054503030}"; Success = "enable"; Failure = "enable"; STIG = "V-278946/947" },

    # Policy Change
    @{ Subcategory = "Audit Policy Change";             GUID = "{0CCE922F-69AE-11D9-BED3-505054503030}"; Success = "enable"; Failure = "enable"; STIG = "V-278067" },
    @{ Subcategory = "Authorization Policy Change";     GUID = "{0CCE9231-69AE-11D9-BED3-505054503030}"; Success = "enable"; Failure = "disable"; STIG = "V-278069" },

    # Privilege Use
    @{ Subcategory = "Sensitive Privilege Use";          GUID = "{0CCE9228-69AE-11D9-BED3-505054503030}"; Success = "enable"; Failure = "enable"; STIG = "V-278070/071/V-279922/923" },

    # System
    @{ Subcategory = "IPsec Driver";                    GUID = "{0CCE9213-69AE-11D9-BED3-505054503030}"; Success = "enable"; Failure = "enable"; STIG = "V-278072/073" },
    @{ Subcategory = "Security System Extension";       GUID = "{0CCE9211-69AE-11D9-BED3-505054503030}"; Success = "enable"; Failure = "disable"; STIG = "V-278077" }
)

# -----------------------------------------------------------------------
# STEP 1: Write audit.csv to Local Group Policy (persists across reboot)
# -----------------------------------------------------------------------
Write-Host "`n--- Writing Local Group Policy audit.csv ---" -ForegroundColor Cyan

$auditCsvDir = "$env:SystemRoot\System32\GroupPolicy\Machine\Microsoft\Windows NT\Audit"
if (!(Test-Path $auditCsvDir)) {
    New-Item -Path $auditCsvDir -ItemType Directory -Force | Out-Null
}

$csvLines = @()
$csvLines += "Machine Name,Policy Target,Subcategory,Subcategory GUID,Inclusion Setting,Exclusion Setting,Setting Value"

foreach ($s in $auditSettings) {
    # Setting Value: 0=No Auditing, 1=Success, 2=Failure, 3=Success and Failure
    $val = 0
    if ($s.Success -eq "enable" -and $s.Failure -eq "enable") { $val = 3 }
    elseif ($s.Success -eq "enable") { $val = 1 }
    elseif ($s.Failure -eq "enable") { $val = 2 }

    $csvLines += ",System,$($s.Subcategory),$($s.GUID),,$($s.Subcategory),$val"
}

$auditCsvPath = Join-Path $auditCsvDir "audit.csv"
$csvLines | Set-Content -Path $auditCsvPath -Encoding Unicode -Force
Write-OK "audit.csv written to: $auditCsvPath ($($csvLines.Count - 1) policies)"

# Also ensure the GPO machine extensions are registered so audit.csv is processed
$gpExtPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine"
$gptIniPath = "$env:SystemRoot\System32\GroupPolicy\gpt.ini"
if (Test-Path $gptIniPath) {
    $gptContent = Get-Content $gptIniPath -Raw
    # Add audit policy CSE GUID if not present
    $auditCSE = "[{F3BC9527-9206-11D0-8CB8-00A0C9190DCB}{B05566AC-FE9C-4368-BE01-1A8540221F67}]"
    if ($gptContent -notmatch "F3BC9527") {
        $gptContent = $gptContent -replace '(gPCMachineExtensionNames=\[)', "`$1$auditCSE"
        # Increment version
        if ($gptContent -match 'Version=(\d+)') {
            $newVer = [int]$Matches[1] + 1
            $gptContent = $gptContent -replace 'Version=\d+', "Version=$newVer"
        }
        Set-Content -Path $gptIniPath -Value $gptContent -Encoding ASCII -Force
        Write-OK "Updated gpt.ini with audit policy CSE"
    }
} else {
    # Create gpt.ini if it doesn't exist
    $gptContent = @"
[General]
gPCMachineExtensionNames=[{F3BC9527-9206-11D0-8CB8-00A0C9190DCB}{B05566AC-FE9C-4368-BE01-1A8540221F67}]
Version=1
gPCFunctionality=0
"@
    Set-Content -Path $gptIniPath -Value $gptContent -Encoding ASCII -Force
    Write-OK "Created gpt.ini with audit policy CSE"
}

# -----------------------------------------------------------------------
# STEP 2: Apply immediately via auditpol (for current session)
# -----------------------------------------------------------------------
Write-Host "`n--- Applying via auditpol (immediate effect) ---" -ForegroundColor Cyan

foreach ($s in $auditSettings) {
    $out = & auditpol /set /subcategory:"$($s.Subcategory)" /success:$($s.Success) /failure:$($s.Failure) 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-OK "[$($s.STIG)] $($s.Subcategory) = Success:$($s.Success) Failure:$($s.Failure)"
    } else {
        Write-Fail "$($s.Subcategory) failed (exit $LASTEXITCODE): $out"
        $ErrorCount++
    }
}

# -----------------------------------------------------------------------
# STEP 3: Also backup auditpol to persist via restore-on-boot approach
# -----------------------------------------------------------------------
Write-Host "`n--- Backing up auditpol policy ---" -ForegroundColor Cyan

$backupPath = "$env:SystemRoot\Security\audit\audit.csv"
$backupDir = Split-Path $backupPath
if (!(Test-Path $backupDir)) { New-Item -Path $backupDir -ItemType Directory -Force | Out-Null }
auditpol /backup /file:"$backupPath" 2>&1 | Out-Null
if (Test-Path $backupPath) {
    Write-OK "auditpol backup saved to: $backupPath"
} else {
    Write-Warn "auditpol backup failed"
}

# -----------------------------------------------------------------------
# STEP 4: Force Group Policy update to apply the audit.csv
# -----------------------------------------------------------------------
Write-Host "`n--- Forcing Group Policy update ---" -ForegroundColor Cyan
gpupdate /force /target:computer 2>&1 | Out-Null
Write-OK "gpupdate /force completed"

# -----------------------------------------------------------------------
# Verification
# -----------------------------------------------------------------------
Write-Host "`n--- Verification ---" -ForegroundColor Cyan

foreach ($s in $auditSettings) {
    $sub = $s.Subcategory
    $result = & auditpol /get /subcategory:"$sub" 2>&1
    $line   = $result | Select-String $sub
    if ($line) {
        $expectSuccess = ($s.Success -eq "enable")
        $expectFailure = ($s.Failure -eq "enable")

        if ($expectSuccess -and $expectFailure) {
            if ($line -match 'Success and Failure') {
                Write-OK "$sub : Success and Failure [COMPLIANT]"
            } else {
                Write-Warn "$sub : expected Success+Failure, got: $line"
                $ErrorCount++
            }
        } elseif ($expectSuccess -and -not $expectFailure) {
            if ($line -match 'Success') {
                Write-OK "$sub : Success [COMPLIANT]"
            } else {
                Write-Warn "$sub : expected Success, got: $line"
                $ErrorCount++
            }
        } elseif (-not $expectSuccess -and $expectFailure) {
            if ($line -match 'Failure') {
                Write-OK "$sub : Failure [COMPLIANT]"
            } else {
                Write-Warn "$sub : expected Failure, got: $line"
                $ErrorCount++
            }
        }
    } else {
        Write-Warn "$sub : Could not parse auditpol output"
    }
}

Write-Host "`n=== Audit Policy Complete (errors: $ErrorCount) ===" -ForegroundColor Cyan
exit $ErrorCount
