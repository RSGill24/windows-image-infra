# Variables
$gcpInstanceName = Invoke-RestMethod -Uri "http://169.254.169.254/computeMetadata/v1/instance/name" -Headers @{"Metadata-Flavor" = "Google"}
$gcpInstanceId   = Invoke-RestMethod -Uri "http://169.254.169.254/computeMetadata/v1/instance/id" -Headers @{"Metadata-Flavor" = "Google"}
$gcpImageNameLong = Invoke-RestMethod -Uri "http://169.254.169.254/computeMetadata/v1/instance/image" -Headers @{"Metadata-Flavor" = "Google"}
$gcpImageName = $gcpImageNameLong.Split("/")[-1]
$auditUuid = [guid]::NewGuid()

$scriptDir = $PSScriptRoot
$outputPath = Join-Path $scriptDir 'DSC_Audit_Results.csv'
$referenceMofPath = Join-Path $scriptDir 'ApplyWindowsServerStig'

# ---------------------------------------------------------
# ✅ STEP 1: APPLY STIG (FIX FAILED RULES)
# ---------------------------------------------------------
Write-Host "=== Applying STIG Configuration ==="

Start-DscConfiguration `
    -Path $referenceMofPath `
    -Wait `
    -Verbose `
    -Force

Write-Host "=== STIG Apply Completed ==="

# ---------------------------------------------------------
# ✅ STEP 2: VERIFY (AUDIT AGAIN)
# ---------------------------------------------------------
Write-Host "=== Running Compliance Check ==="

$results = Test-DscConfiguration -Detailed

# ---------------------------------------------------------
# FORMAT RESULTS
# ---------------------------------------------------------
$formattedResults = @()

foreach ($r in $results.ResourcesInDesiredState) {
    $r | Add-Member -NotePropertyName Compliance -NotePropertyValue "TRUE" -Force
    $r | Add-Member -NotePropertyName GCPInstanceName -NotePropertyValue $gcpInstanceName -Force
    $r | Add-Member -NotePropertyName GCPInstanceId -NotePropertyValue $gcpInstanceId -Force
    $r | Add-Member -NotePropertyName GCPImageName -NotePropertyValue $gcpImageName -Force
    $r | Add-Member -NotePropertyName GCPAuditUuid -NotePropertyValue $auditUuid -Force
    $formattedResults += $r
}

foreach ($r in $results.ResourcesNotInDesiredState) {
    $r | Add-Member -NotePropertyName Compliance -NotePropertyValue "FALSE" -Force
    $r | Add-Member -NotePropertyName GCPInstanceName -NotePropertyValue $gcpInstanceName -Force
    $r | Add-Member -NotePropertyName GCPInstanceId -NotePropertyValue $gcpInstanceId -Force
    $r | Add-Member -NotePropertyName GCPImageName -NotePropertyValue $gcpImageName -Force
    $r | Add-Member -NotePropertyName GCPAuditUuid -NotePropertyValue $auditUuid -Force
    $formattedResults += $r
}

# Export
$formattedResults | Export-Csv -Path $outputPath -NoTypeInformation

Write-Host "=== Compliance Report Generated ==="
