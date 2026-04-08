# ==============================
# DoD Consent Banner Configuration
# Sets legal notice caption and text for Windows login screen
# ==============================

$debugLog = "C:\Windows\Temp\banner_setup.log"
if (Test-Path $debugLog) { Remove-Item $debugLog -Force }

function Log($msg, $color = "White") {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $debugLog -Value $line
}

Log "===== DoD Consent Banner Setup =====" "Cyan"

$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"

$bannerCaption = "WARNING     WARNING     WARNING"

$bannerText = "You are accessing a U.S. Government information system, which includes: 1) this computer, 2) this computer network, 3) all Government-furnished computers connected to this network, and 4) all Government-furnished devices and storage media attached to this network or to a computer on this network. You understand and consent to the following: you may access this information system for authorized use only; unauthorized use of the system is prohibited and subject to criminal and civil penalties. You have no reasonable expectation of privacy regarding any communication or data transiting or stored on this information system. At any time and for any lawful Government purpose, the Government may monitor, intercept, audit, and search and seize any communication or data transiting or stored on this information system, and any communication or data transiting or stored on this information system may be disclosed or used for any lawful Government purpose. This information system may contain Controlled Unclassified Information (CUI) that is subject to safeguarding or dissemination controls in accordance with law, regulation, or Government-wide policy. Accessing and using this system indicates your understanding of this warning."

try {
    # Set banner caption (title bar of the popup)
    Set-ItemProperty -Path $regPath -Name "LegalNoticeCaption" -Value $bannerCaption -Type String -Force
    $captionVal = (Get-ItemProperty $regPath).LegalNoticeCaption
    if ($captionVal -eq $bannerCaption) {
        Log "  [OK] LegalNoticeCaption set successfully" "Green"
    } else {
        Log "  [FAIL] LegalNoticeCaption mismatch" "Red"
    }

    # Set banner text (body of the popup)
    Set-ItemProperty -Path $regPath -Name "LegalNoticeText" -Value $bannerText -Type String -Force
    $textVal = (Get-ItemProperty $regPath).LegalNoticeText
    if ($textVal -eq $bannerText) {
        Log "  [OK] LegalNoticeText set successfully" "Green"
    } else {
        Log "  [FAIL] LegalNoticeText mismatch" "Red"
    }

} catch {
    Log "  [ERROR] $($_.Exception.Message)" "Red"
}

# Also set via secedit for Group Policy enforcement
Log "`n  Applying via secedit for GP enforcement..." "Yellow"

$infPath = "C:\Windows\Temp\banner.inf"
$sdbPath = "C:\Windows\Temp\banner.sdb"
$logSec  = "C:\Windows\Temp\banner_secedit.log"

$infContent = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Registry Values]
MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\LegalNoticeCaption=1,$bannerCaption
MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\LegalNoticeText=1,$bannerText
"@

Set-Content -Path $infPath -Value $infContent -Encoding Unicode
secedit /configure /db $sdbPath /cfg $infPath /log $logSec /quiet
$seceditExit = $LASTEXITCODE

if ($seceditExit -eq 0) {
    Log "  [OK] secedit applied successfully" "Green"
} else {
    Log "  [WARN] secedit exit code: $seceditExit — check $logSec" "Yellow"
}

# Verify final values
Log "`n===== Verification =====" "Cyan"
$finalCaption = (Get-ItemProperty $regPath).LegalNoticeCaption
$finalText    = (Get-ItemProperty $regPath).LegalNoticeText

Log "  Caption : $finalCaption" "Green"
Log "  Text    : $($finalText.Substring(0, [Math]::Min(80, $finalText.Length)))..." "Green"

Log "`n===== Banner Setup Complete =====" "Cyan"
Log "  The banner will appear at next login/RDP session" "Yellow"
Log "  Log : $debugLog" "Cyan"
