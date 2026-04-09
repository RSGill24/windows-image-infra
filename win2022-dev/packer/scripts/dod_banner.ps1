#Requires -RunAsAdministrator
$ErrorActionPreference = 'Continue'

Write-Host "=== Setting DoD Consent Banner ===" -ForegroundColor Cyan

$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"

# V-254458 — Title
$bannerCaption = "DoD Notice and Consent Banner"

# V-254457 — WARNING line, then full text as one paragraph below
$bannerText = "WARNING_____WARNING`r`n`r`nYou are accessing a U.S. Government information system, which includes: 1) this computer, 2) this computer network, 3) all Government-furnished computers connected to this network, and 4) all Government-furnished devices and storage media attached to this network or to a computer on this network. You understand and consent to the following: you may access this information system for authorized use only; unauthorized use of the system is prohibited and subject to criminal and civil penalties. You have no reasonable expectation of privacy regarding any communication or data transiting or stored on this information system. At any time and for any lawful Government purpose, the Government may monitor, intercept, audit, and search and seize any communication or data transiting or stored on this information system, and any communication or data transiting or stored on this information system may be disclosed or used for any lawful Government purpose. This information system may contain Controlled Unclassified Information (CUI) that is subject to safeguarding or dissemination controls in accordance with law, regulation, or Government-wide policy. Accessing and using this system indicates your understanding of this warning."

# Set registry values
Set-ItemProperty -Path $regPath -Name "LegalNoticeCaption" -Value $bannerCaption -Type String -Force
Set-ItemProperty -Path $regPath -Name "LegalNoticeText"    -Value $bannerText    -Type String -Force

# -----------------------------------------------------------------------
# Verify — read back from registry to confirm exactly what was written
# -----------------------------------------------------------------------
$finalCaption = (Get-ItemProperty $regPath).LegalNoticeCaption
$finalText    = (Get-ItemProperty $regPath).LegalNoticeText

if ($finalCaption -eq $bannerCaption) {
    Write-Host "  [OK] Caption: $finalCaption" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Caption mismatch — got: $finalCaption" -ForegroundColor Red
    exit 1
}

if ($finalText -like "WARNING_____WARNING*") {
    Write-Host "  [OK] Text set correctly" -ForegroundColor Green
    Write-Host "  [OK] Text length: $($finalText.Length) characters" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Text mismatch — got: $($finalText.Substring(0, [Math]::Min(50, $finalText.Length)))" -ForegroundColor Red
    exit 1
}

Write-Host "=== Banner Done ===" -ForegroundColor Cyan
exit 0
