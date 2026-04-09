#Requires -RunAsAdministrator
$ErrorActionPreference = 'Continue'

Write-Host "=== Setting DoD Consent Banner ===" -ForegroundColor Cyan

$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"

# V-254458 — Title (shown as bold header in LogonUI)
$bannerCaption = "DoD Notice and Consent Banner"

# V-254457 — Body text
# Windows LogonUI renders \r\n as actual line breaks in the dialog.
# Keeping WARNING____WARNING on its own line separates it visually
# from the body, matching the correct rendering in Image 1.
# The full text must NOT exceed ~4096 chars or registry truncation occurs.
$bannerText = "WARNING____WARNING`r`n`r`n" +
"You are accessing a U.S. Government information system, which includes:`r`n" +
"1) this computer`r`n" +
"2) this computer network`r`n" +
"3) all Government-furnished computers connected to this network`r`n" +
"4) all Government-furnished devices and storage media attached to this network`r`n`r`n" +
"You understand and consent to the following:`r`n" +
"You may access this information system for authorized use only.`r`n" +
"Unauthorized use of the system is prohibited and subject to criminal and civil penalties.`r`n`r`n" +
"You have no reasonable expectation of privacy regarding any communication or data.`r`n" +
"At any time, the Government may monitor, intercept, audit, and search data on this system.`r`n`r`n" +
"This system may contain Controlled Unclassified Information (CUI).`r`n" +
"Accessing and using this system indicates your understanding of this warning."
# Set registry values
Set-ItemProperty -Path $regPath -Name "LegalNoticeCaption" -Value $bannerCaption -Type String -Force
Set-ItemProperty -Path $regPath -Name "LegalNoticeText"    -Value $bannerText    -Type String -Force

# Verify
$finalCaption = (Get-ItemProperty $regPath).LegalNoticeCaption
$finalText    = (Get-ItemProperty $regPath).LegalNoticeText

if ($finalCaption -eq $bannerCaption) {
    Write-Host "  [OK] Caption: $finalCaption" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Caption mismatch — got: $finalCaption" -ForegroundColor Red
    exit 1
}

if ($finalText -like "WARNING____WARNING*") {
    Write-Host "  [OK] Text set correctly" -ForegroundColor Green
    Write-Host "  [OK] Text length: $($finalText.Length) characters" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Text mismatch" -ForegroundColor Red
    exit 1
}

Write-Host "=== Banner Done ===" -ForegroundColor Cyan
exit 0
