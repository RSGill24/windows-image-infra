# apply_audit_policy.ps1
# Fixes V-278942 to V-278947: File System, Handle Manipulation, and Registry
# audit subcategories. These are NOT applied by PowerSTIG DSC automatically
# and must be set via auditpol directly.
#
# SCC scan showed all three subcategories as AUDIT_NONE -- this script
# sets them to SUCCESS_AND_FAILURE as required by the STIG.

Write-Host "=== Applying Advanced Audit Policy (V-278942 to V-278947) ==="

$auditSettings = @(
    # V-278942 / V-278943 -- File System: Failure + Success
    @{ Category = "Object Access"; Subcategory = "File System";          Success = $true; Failure = $true  },
    # V-278944 / V-278945 -- Handle Manipulation: Failure + Success
    @{ Category = "Object Access"; Subcategory = "Handle Manipulation";  Success = $true; Failure = $true  },
    # V-278946 / V-278947 -- Registry: Failure + Success
    @{ Category = "Object Access"; Subcategory = "Registry";             Success = $true; Failure = $true  }
)

$errors = 0

foreach ($setting in $auditSettings) {
    $successFlag = if ($setting.Success) { "enable" } else { "disable" }
    $failureFlag = if ($setting.Failure) { "enable" } else { "disable" }

    Write-Host "  Setting '$($setting.Subcategory)' -- Success: $successFlag  Failure: $failureFlag"

    $result = auditpol /set /subcategory:"$($setting.Subcategory)" `
                            /success:$successFlag `
                            /failure:$failureFlag 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Error "  FAILED to set '$($setting.Subcategory)': $result"
        $errors++
    } else {
        Write-Host "  OK: $($setting.Subcategory)"
    }
}

# -----------------------------------------------------------------------
# Verify the settings were applied
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "--- Verifying audit policy settings..."

$subcategories = @("File System", "Handle Manipulation", "Registry")
foreach ($sub in $subcategories) {
    $current = auditpol /get /subcategory:"$sub" 2>&1
    Write-Host "  $sub : $($current | Select-String $sub)"
}

if ($errors -gt 0) {
    Write-Error "=== $errors audit policy setting(s) failed. ==="
    exit 1
}

Write-Host "=== Audit policy settings applied successfully. ==="