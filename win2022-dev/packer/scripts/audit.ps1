#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies ALL advanced audit policy subcategories required by Windows Server 2025 STIG.
    Covers V-278048 through V-278077, V-278199, V-278942 to V-278947, V-279922/V-279923.
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
# -----------------------------------------------------------------------
$regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
$current = (Get-ItemProperty -Path $regPath -Name 'SCENoApplyLegacyAuditPolicy' -ErrorAction SilentlyContinue).SCENoApplyLegacyAuditPolicy
if ($current -ne 1) {
    Set-ItemProperty -Path $regPath -Name 'SCENoApplyLegacyAuditPolicy' -Value 1 -Type DWord
    Write-OK "V-278199: SCENoApplyLegacyAuditPolicy = 1"
} else {
    Write-OK "V-278199: SCENoApplyLegacyAuditPolicy already set"
}

# -----------------------------------------------------------------------
# Apply ALL required audit subcategory settings via auditpol
# -----------------------------------------------------------------------
$auditSettings = @(
    # Account Logon
    @{ Subcategory = "Credential Validation";           STIG = "V-278048"; Success = "enable"; Failure = "enable" },

    # Account Management
    @{ Subcategory = "Other Account Management Events"; STIG = "V-278049"; Success = "enable"; Failure = "enable" },
    @{ Subcategory = "User Account Management";         STIG = "V-278052"; Success = "enable"; Failure = "enable" },

    # Detailed Tracking
    @{ Subcategory = "Plug and Play Events";            STIG = "V-278053"; Success = "enable"; Failure = "disable" },
    @{ Subcategory = "Process Creation";                STIG = "V-278054"; Success = "enable"; Failure = "disable" },

    # Logon/Logoff
    @{ Subcategory = "Account Lockout";                 STIG = "V-278056"; Success = "disable"; Failure = "enable" },
    @{ Subcategory = "Group Membership";                STIG = "V-278057"; Success = "enable"; Failure = "disable" },

    # Object Access
    @{ Subcategory = "Other Object Access Events";      STIG = "V-278062/063"; Success = "enable"; Failure = "enable" },
    @{ Subcategory = "Removable Storage";               STIG = "V-278064/065"; Success = "enable"; Failure = "enable" },
    @{ Subcategory = "File System";                     STIG = "V-278942/943"; Success = "enable"; Failure = "enable" },
    @{ Subcategory = "Handle Manipulation";             STIG = "V-278944/945"; Success = "enable"; Failure = "enable" },
    @{ Subcategory = "Registry";                        STIG = "V-278946/947"; Success = "enable"; Failure = "enable" },

    # Policy Change
    @{ Subcategory = "Audit Policy Change";             STIG = "V-278067"; Success = "enable"; Failure = "enable" },
    @{ Subcategory = "Authorization Policy Change";     STIG = "V-278069"; Success = "enable"; Failure = "disable" },

    # Privilege Use
    @{ Subcategory = "Sensitive Privilege Use";          STIG = "V-278070/071/V-279922/923"; Success = "enable"; Failure = "enable" },

    # System
    @{ Subcategory = "IPsec Driver";                    STIG = "V-278072/073"; Success = "enable"; Failure = "enable" },
    @{ Subcategory = "Security System Extension";       STIG = "V-278077"; Success = "enable"; Failure = "disable" }
)

foreach ($s in $auditSettings) {
    Write-Host "  Setting [$($s.STIG)]: '$($s.Subcategory)' Success=$($s.Success) Failure=$($s.Failure)"

    $out = & auditpol /set /subcategory:"$($s.Subcategory)" /success:$($s.Success) /failure:$($s.Failure) 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-OK "$($s.Subcategory) set successfully"
    } else {
        Write-Fail "$($s.Subcategory) failed (exit $LASTEXITCODE): $out"
        $ErrorCount++
    }
}

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

        $hasSuccess = $line -match 'Success'
        $hasFailure = $line -match 'Failure'

        if ($expectSuccess -and $expectFailure) {
            if ($line -match 'Success and Failure') {
                Write-OK "$sub : Success and Failure [COMPLIANT]"
            } else {
                Write-Warn "$sub : expected Success+Failure, got: $line"
                $ErrorCount++
            }
        } elseif ($expectSuccess -and -not $expectFailure) {
            if ($hasSuccess) {
                Write-OK "$sub : Success [COMPLIANT]"
            } else {
                Write-Warn "$sub : expected Success, got: $line"
                $ErrorCount++
            }
        } elseif (-not $expectSuccess -and $expectFailure) {
            if ($hasFailure) {
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
