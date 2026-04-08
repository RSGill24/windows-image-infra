# ==============================
# DoD Consent Banner Configuration
# V-254457 (LegalNoticeText) + V-254458 (LegalNoticeCaption)
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

# V-254458 — LegalNoticeCaption (title of the banner popup)
$bannerCaption = "DoD Notice and Consent Banner"

# V-254457 — LegalNoticeText (full body text)
$bannerText = "WARNING_____WARNING`r`n`r`nYou are accessing a U.S. Government information system, which includes: 1) this computer, 2) this computer network, 3) all Government-furnished computers connected to this network, and 4) all Government-furnished devices and storage media attached to this network or to a computer on this network. You understand and consent to the following: you may access this information system for authorized use only; unauthorized use of the system is prohibited and subject to criminal and civil penalties. You have no reasonable expectation of privacy regarding any communication or data transiting or stored on this information system. At any time and for any lawful Government purpose, the Government may monitor, intercept, audit, and search and seize any communication or data transiting or stored on this information system, and any communication or data transiting or stored on this information system may be disclosed or used for any lawful Government purpose. This information system may contain Controlled Unclassified Information (CUI) that is subject to safeguarding or dissemination controls in accordance with law, regulation, or Government-wide policy. Accessing and using this system indicates your understanding of this warning."

try {
    # V-254458 — Set Caption
    Set-ItemProperty -Path $regPath -Name "LegalNoticeCaption" -Value $bannerCaption -Type String -Force
    $captionVal = (Get-ItemProperty $regPath).LegalNoticeCaption
    if ($captionVal -eq $bannerCaption) {
        Log "  [OK] V-254458 LegalNoticeCaption = '$captionVal'" "Green"
    } else {
        Log "  [FAIL] LegalNoticeCaption mismatch — got: $captionVal" "Red"
    }

    # V-254457 — Set Text
    Set-ItemProperty -Path $regPath -Name "LegalNoticeText" -Value $bannerText -Type String -Force
    $textVal = (Get-ItemProperty $regPath).LegalNoticeText
    if ($textVal -eq $bannerText) {
        Log "  [OK] V-254457 LegalNoticeText set successfully" "Green"
    } else {
        Log "  [FAIL] LegalNoticeText mismatch" "Red"
    }

} catch {
    Log "  [ERROR] $($_.Exception.Message)" "Red"
}

# ----------------------------
# Also enforce via secedit for GP compliance
# ----------------------------
Log "`n  Enforcing via secedit..." "Yellow"

$infPath = "C:\Windows\Temp\banner.inf"
$sdbPath = "C:\Windows\Temp\banner.sdb"
$logSec  = "C:\Windows\Temp\banner_secedit.log"

# secedit requires escaped text — newlines not supported in INF values,
# so we use registry method above as primary and secedit as reinforcement
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

# ----------------------------
# Verification
# ----------------------------
Log "`n===== Verification =====" "Cyan"

$finalCaption = (Get-ItemProperty $regPath).LegalNoticeCaption
$finalText    = (Get-ItemProperty $regPath).LegalNoticeText

Log "  V-254458 Caption : $finalCaption" "Green"
Log "  V-254457 Text preview : $($finalText.Substring(0, [Math]::Min(60, $finalText.Length)))..." "Green"

# Confirm caption matches STIG requirement
if ($finalCaption -match "^(DoD Notice and Consent Banner|US Department of Defense Warning Statement)$") {
    Log "  [PASS] Caption matches STIG V-254458 requirement" "Green"
} else {
    Log "  [FAIL] Caption does NOT match STIG V-254458 requirement" "Red"
}

# Confirm text starts correctly
if ($finalText -like "WARNING*") {
    Log "  [PASS] Text starts with WARNING as required" "Green"
} else {
    Log "  [FAIL] Text does not start with WARNING" "Red"
}

# Cleanup temp files
Remove-Item $infPath -Force -ErrorAction SilentlyContinue
Remove-Item $sdbPath -Force -ErrorAction SilentlyContinue

Log "`n===== Banner Setup Complete =====" "Cyan"
Log "  Banner appears on next login / RDP session — no reboot needed" "Yellow"
Log "  Log : $debugLog" "Cyan"
