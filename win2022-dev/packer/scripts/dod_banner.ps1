#Requires -RunAsAdministrator
$ErrorActionPreference = 'Continue'

Write-Host "=== Setting DoD Consent Banner ===" -ForegroundColor Cyan

$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"

$bannerCaption = "DoD Notice and Consent Banner"

$bodyText = "You are accessing a U.S. Government information system, which includes: 1) this computer, 2) this computer network, 3) all Government-furnished computers connected to this network, and 4) all Government-furnished devices and storage media attached to this network or to a computer on this network. You understand and consent to the following: you may access this information system for authorized use only; unauthorized use of the system is prohibited and subject to criminal and civil penalties. You have no reasonable expectation of privacy regarding any communication or data transiting or stored on this information system. At any time and for any lawful Government purpose, the Government may monitor, intercept, audit, and search and seize any communication or data transiting or stored on this information system, and any communication or data transiting or stored on this information system may be disclosed or used for any lawful Government purpose. This information system may contain Controlled Unclassified Information (CUI) that is subject to safeguarding or dissemination controls in accordance with law, regulation, or Government-wide policy. Accessing and using this system indicates your understanding of this warning."

# -----------------------------------------------------------------------
# FIX: String concatenation se newline banao runtime pe
# Packer kisi bhi escape sequence ko corrupt karta hai file upload mein
# Isliye newline ko runtime pe programmatically inject karo
# -----------------------------------------------------------------------
$warningLine = "WARNING____WARNING"
$newline     = [System.Environment]::NewLine

# Combine karo runtime pe — koi escape sequence nahi
$bannerText  = $warningLine + $newline + $newline + $bodyText

# Registry mein set karo
Set-ItemProperty -Path $regPath -Name "LegalNoticeCaption" -Value $bannerCaption -Type String -Force
Set-ItemProperty -Path $regPath -Name "LegalNoticeText"    -Value $bannerText    -Type String -Force

# Double confirm — wapas read karke verify karo
$stored = (Get-ItemProperty $regPath).LegalNoticeText
Write-Host "  Stored text byte check:" -ForegroundColor Gray
Write-Host "  Char 18: $([int][char]$stored[18]) (should be 13 for CR)" -ForegroundColor Gray
Write-Host "  Char 19: $([int][char]$stored[19]) (should be 10 for LF)" -ForegroundColor Gray

# Verify
$finalCaption = (Get-ItemProperty $regPath).LegalNoticeCaption
$finalText    = (Get-ItemProperty $regPath).LegalNoticeText

if ($finalCaption -eq $bannerCaption) {
    Write-Host "  [OK] Caption: $finalCaption" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Caption mismatch" -ForegroundColor Red
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
