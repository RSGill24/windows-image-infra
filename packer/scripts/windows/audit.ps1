# Variables
$gcpInstanceName = Invoke-RestMethod -Uri "http://169.254.169.254/computeMetadata/v1/instance/name" -Headers @{"Metadata-Flavor" = "Google"}
$gcpInstanceId = Invoke-RestMethod -Uri "http://169.254.169.254/computeMetadata/v1/instance/id" -Headers @{"Metadata-Flavor" = "Google"}
$gcpImageNameLong = Invoke-RestMethod -Uri "http://169.254.169.254/computeMetadata/v1/instance/image" -Headers @{"Metadata-Flavor" = "Google"}
$gcpImageName = $gcpImageNameLong.Split("/")[-1]
$auditUuid = [guid]::NewGuid()

$outputPath = "C:/Users/packer_user/hardening/DSC_Audit_Results.csv"

# Run DSC Test
$results = Test-DscConfiguration -ReferenceConfiguration C:\Users\packer_user\hardening\ApplyWindowsServerStig\localhost.mof

# Initialize an array to hold formatted results
$formattedResults = @()

# Process resources in desired state (if any)
if ($results.ResourcesInDesiredState.Count -gt 0) {
    $results.ResourcesInDesiredState | ForEach-Object {
        # Clone all existing properties dynamically and add metadata
        $result = $_ | Select-Object *
        $result | Add-Member -MemberType NoteProperty -Name Compliance -Value "TRUE"
        $result | Add-Member -MemberType NoteProperty -Name GCPInstanceName -Value $gcpInstanceName
        $result | Add-Member -MemberType NoteProperty -Name GCPInstanceId -Value $gcpInstanceId
        $result | Add-Member -MemberType NoteProperty -Name GCPImageName -Value $gcpImageName
        $result | Add-Member -MemberType NoteProperty -Name GCPAuditUuid -Value $auditUuid

        $formattedResults += $result
    }
}

# Process resources not in desired state (if any)
if ($results.ResourcesNotInDesiredState.Count -gt 0) {
    $results.ResourcesNotInDesiredState | ForEach-Object {
        # Clone all existing properties dynamically and add metadata
        $result = $_ | Select-Object *
        $result | Add-Member -MemberType NoteProperty -Name Compliance -Value "FALSE"
        $result | Add-Member -MemberType NoteProperty -Name GCPInstanceName -Value $gcpInstanceName
        $result | Add-Member -MemberType NoteProperty -Name GCPInstanceId -Value $gcpInstanceId
        $result | Add-Member -MemberType NoteProperty -Name GCPImageName -Value $gcpImageName
        $result | Add-Member -MemberType NoteProperty -Name GCPAuditUuid -Value $auditUuid

        $formattedResults += $result
    }
}

# Export to CSV
$formattedResults | Export-Csv -Path $outputPath -NoTypeInformation
