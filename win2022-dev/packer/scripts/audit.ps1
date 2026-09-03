#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Enables the registry setting that lets domain-applied advanced audit policy
    take effect. Does NOT set audit subcategories.

.DESCRIPTION
    WHAT CHANGED AND WHY
    --------------------
    This script used to run `auditpol /set` for the Object Access subcategories
    (File System, Handle Manipulation, Registry). Advanced audit policy is
    excluded from the image at the caller's direction and applied by domain GPO
    at first boot, because it does not reliably survive image capture and
    sysprep -- the project's own remediation estimate marks these rules
    "audit.ps1 (build only) + GPO / does not persist in image".

    AuditPolicyRule is skipped as a whole class in the DSC MOF (create_mof.ps1),
    and the auditpol calls in stig_remediation_fixes.ps1 were removed for the
    same reason. Setting subcategories here as well would have been the last
    place the build still wrote audit policy.

    WHAT REMAINS, AND WHY IT MATTERS
    --------------------------------
    SCENoApplyLegacyAuditPolicy = 1 is a *registry* value, so it persists into
    the image. It is also a prerequisite: without it, Windows applies the legacy
    audit *category* settings and silently ignores the advanced *subcategory*
    settings that the domain GPO pushes. Leaving it unset would make the GPO
    audit policy appear to apply and then do nothing.

    win2025_registry_fixes.ps1 also sets this value from the STIG content. This
    script sets it explicitly as a belt-and-braces guarantee, and because it
    runs earlier in run_all.ps1.
#>

$ErrorActionPreference = 'Continue'

function Write-OK   ($m) { Write-Host "  [OK]   $m" -ForegroundColor Green   }
function Write-Bad  ($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red     }
function Write-Skip ($m) { Write-Host "  [SKIP] $m" -ForegroundColor Gray    }

Write-Host "`n=== Audit policy prerequisites ===" -ForegroundColor Cyan

$ErrorCount = 0
$regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'

try {
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null }

    Set-ItemProperty -Path $regPath -Name 'SCENoApplyLegacyAuditPolicy' `
                     -Value 1 -Type DWord -Force -ErrorAction Stop

    $verify = (Get-ItemProperty -Path $regPath -Name 'SCENoApplyLegacyAuditPolicy' -ErrorAction Stop).SCENoApplyLegacyAuditPolicy
    if ($verify -eq 1) {
        Write-OK "SCENoApplyLegacyAuditPolicy = 1 (subcategory settings override categories)"
    } else {
        Write-Bad "SCENoApplyLegacyAuditPolicy read back as $verify, expected 1"
        $ErrorCount++
    }
} catch {
    Write-Bad "Failed to set SCENoApplyLegacyAuditPolicy: $_"
    $ErrorCount++
}

Write-Host ""
Write-Skip "Audit subcategories are NOT set here - domain GPO applies them at first boot."
Write-Skip "Covers: Account Logon, Account Management, Detailed Tracking, Logon/Logoff,"
Write-Skip "        Object Access, Policy Change, Privilege Use, System."

Write-Host "`n=== Audit prerequisites complete (errors: $ErrorCount) ===" -ForegroundColor Cyan
exit $ErrorCount
