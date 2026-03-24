Write-Host "========== START STIG HARDENING =========="

# ---------------------------------------------------------
# 1️⃣ Install PowerSTIG + DSC
# ---------------------------------------------------------
&"$PSScriptRoot\install_PowerSTIG.ps1"
&"$PSScriptRoot\install_dsc_deps.ps1"

# ---------------------------------------------------------
# 2️⃣ Install DoD Certificates
# ---------------------------------------------------------
if (Test-Path "$PSScriptRoot\install_dod_certs.ps1") {
    &"$PSScriptRoot\install_dod_certs.ps1"
}

# ---------------------------------------------------------
# 3️⃣ Apply PowerSTIG (MOF based)
# ---------------------------------------------------------
&"$PSScriptRoot\create_mof.ps1"
&"$PSScriptRoot\apply_mof.ps1"

# ---------------------------------------------------------
# 4️⃣ APPLY YOUR CUSTOM FIXES (VERY IMPORTANT)
# ---------------------------------------------------------
Write-Host "=== Applying Custom STIG Fixes ==="

&"$PSScriptRoot\registry_stig.ps1"
&"$PSScriptRoot\services_stig.ps1"
&"$PSScriptRoot\account_policy.ps1"
&"$PSScriptRoot\audit.ps1"

# ---------------------------------------------------------
# 5️⃣ FINAL AUDIT
# ---------------------------------------------------------
Write-Host "=== Running Final Audit ==="

$results = Test-DscConfiguration -Detailed

$reportPath = Join-Path $PSScriptRoot "DSC_Audit_Results.csv"
$final = @()

foreach ($r in $results.ResourcesInDesiredState) {
    $r | Add-Member -NotePropertyName Compliance -NotePropertyValue "TRUE" -Force
    $final += $r
}

foreach ($r in $results.ResourcesNotInDesiredState) {
    $r | Add-Member -NotePropertyName Compliance -NotePropertyValue "FALSE" -Force
    $final += $r
}

$final | Export-Csv -Path $reportPath -NoTypeInformation

Write-Host "Report saved at: $reportPath"
