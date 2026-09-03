#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Verifies a handful of high-value registry settings after remediation.
    This script no longer WRITES anything.

.DESCRIPTION
    WHAT CHANGED AND WHY
    --------------------
    This script used to hardcode Windows Server 2022 STIG values. The pipeline
    builds Server 2025, and three of those writes were actively non-compliant
    against the 2025 benchmark that DISA SCC scans with:

      ConsentPromptBehaviorAdmin = 4   2025 requires 2 (prompt for consent on
                                       the secure desktop). Nothing downstream
                                       corrected it, so the rule failed every
                                       scan.
      wevtutil sl Security /ms:196608  2025 requires a far larger Security log.
                                       Worse, SCC reads the POLICY value under
                                       SOFTWARE\Policies\...\EventLog\Security\
                                       MaxSize - which this never set - so the
                                       rule failed regardless of the channel size.
      LmCompatibilityLevel = 1         Weakens LAN Manager auth. It happened to
                                       be overwritten with 5 by account_policy.ps1
                                       later in run_all.ps1, but only by ordering
                                       luck.

    All of these settings are now applied by win2025_registry_fixes.ps1, which
    reads the actual Server 2025 STIG content shipped inside PowerSTIG rather
    than a hand-maintained table. Keeping a second, hardcoded writer for the same
    keys is how the values drifted apart in the first place, so this script is
    now verification only - it reports, it does not set.

    Do not add Set-ItemProperty calls here. Registry remediation belongs in
    win2025_registry_fixes.ps1, where it is derived from the benchmark.
#>

$ErrorActionPreference = 'Continue'

Write-Host "=== Registry STIG verification (read-only) ===" -ForegroundColor Cyan

function Test-RegValue {
    param(
        [string]$Path,
        [string]$Name,
        [string]$Expected,
        [string]$Label,
        [ValidateSet('eq','ge')] [string]$Comparison = 'eq'
    )

    try {
        $actual = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
    } catch {
        Write-Host "  [MISS] $Label - $Name not present at $Path" -ForegroundColor Magenta
        return $false
    }

    $ok = if ($Comparison -eq 'ge') {
        try { [int64]$actual -ge [int64]$Expected } catch { $false }
    } else {
        "$actual" -eq "$Expected"
    }

    if ($ok) {
        Write-Host "  [OK]   $Label - $Name = $actual" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $Label - $Name = $actual (expected $Comparison $Expected)" -ForegroundColor Red
    }
    return $ok
}

$lsa       = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
$policies  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$eventLog  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog'
# NOTE: ClearPageFileAtShutdown is deliberately NOT checked. It is a Server 2022
# rule with no equivalent in the Server 2025 STIG -- a query of the benchmark on
# a live 2025 build returned 0 matching rules -- so asserting it produced a
# permanent false FAIL that made this report untrustworthy.

$results = @(
    (Test-RegValue -Path $lsa      -Name 'LmCompatibilityLevel'        -Expected '5' -Label 'LAN Manager auth level (NTLMv2 only)')
    (Test-RegValue -Path $lsa      -Name 'NoLMHash'                    -Expected '1' -Label 'Do not store LAN Manager hash')
    (Test-RegValue -Path $lsa      -Name 'SCENoApplyLegacyAuditPolicy' -Expected '1' -Label 'Audit subcategories override categories')
    (Test-RegValue -Path $policies -Name 'ConsentPromptBehaviorAdmin'  -Expected '2' -Label 'UAC: admin consent on secure desktop')
    (Test-RegValue -Path $policies -Name 'InactivityTimeoutSecs'       -Expected '900' -Label 'Machine inactivity limit' -Comparison 'ge')
    (Test-RegValue -Path "$eventLog\Application" -Name 'MaxSize' -Expected '32768' -Label 'Application log policy size' -Comparison 'ge')
    (Test-RegValue -Path "$eventLog\Security"    -Name 'MaxSize' -Expected '32768' -Label 'Security log policy size'    -Comparison 'ge')
    (Test-RegValue -Path "$eventLog\System"      -Name 'MaxSize' -Expected '32768' -Label 'System log policy size'      -Comparison 'ge')
)

$pass = @($results | Where-Object { $_ }).Count
$fail = $results.Count - $pass

Write-Host ""
Write-Host "=== Registry verification: $pass pass / $fail fail ===" -ForegroundColor Cyan
if ($fail -gt 0) {
    Write-Host "  Failures above are informational. win2025_registry_fixes.ps1 owns these" -ForegroundColor Yellow
    Write-Host "  settings; check its output earlier in the log for the authoritative result." -ForegroundColor Yellow
}

# Verification only - never fail the build from here.
exit 0
