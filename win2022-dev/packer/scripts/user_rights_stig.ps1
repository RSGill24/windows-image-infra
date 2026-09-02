#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies Windows Server 2025 STIG user rights assignments via secedit.
    Covers V-278183, V-278184, V-278185, V-278187, V-278188,
    V-278243, V-278244, V-278252, V-278253, V-278254, V-278261.
    Run AFTER apply_mof.ps1.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

function Write-OK    ($m) { Write-Host "  [OK]   $m" -ForegroundColor Green  }
function Write-Fixed ($m) { Write-Host "  [FIX]  $m" -ForegroundColor Yellow }
function Write-Warn  ($m) { Write-Host "  [WARN] $m" -ForegroundColor Magenta }
function Write-Section ($m) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " $m" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

$ErrorCount = 0

Write-Section "Applying User Rights Assignments (Win2025 STIG)"

# -----------------------------------------------------------------------
# Well-known SIDs
# -----------------------------------------------------------------------
$SID_Administrators   = '*S-1-5-32-544'
$SID_AuthUsers        = '*S-1-5-11'
$SID_Guests           = '*S-1-5-32-546'
$SID_LocalService     = '*S-1-5-19'
$SID_NetworkService   = '*S-1-5-20'
$SID_Service          = '*S-1-5-6'

# -----------------------------------------------------------------------
# Export current security policy
# -----------------------------------------------------------------------
$seceditCfg = "$env:TEMP\stig_user_rights.cfg"
$seceditDb  = "$env:TEMP\stig_user_rights.sdb"

Remove-Item $seceditCfg -ErrorAction SilentlyContinue
Remove-Item $seceditDb  -ErrorAction SilentlyContinue

Write-Host "  Exporting current user rights policy..."
secedit /export /areas USER_RIGHTS /cfg $seceditCfg /quiet

if (-not (Test-Path $seceditCfg)) {
    Write-Warn "secedit export failed — cannot apply user rights"
    exit 1
}

$cfg = Get-Content $seceditCfg -Raw

# -----------------------------------------------------------------------
# Helper to set a user right in the secedit config
# -----------------------------------------------------------------------
function Set-UserRight {
    param(
        [string]$Right,
        [string]$Value,
        [string]$STIG,
        [string]$Label
    )
    if ($script:cfg -match "$Right\s*=") {
        $script:cfg = $script:cfg -replace "$Right\s*=\s*[^\r\n]*", "$Right = $Value"
    } else {
        $script:cfg = $script:cfg -replace '(\[Privilege Rights\])', "`$1`r`n$Right = $Value"
    }
    Write-Fixed "[$STIG] $Label => $Value"
}

# -----------------------------------------------------------------------
# V-278183: Access this computer from the network = Administrators, Authenticated Users
# -----------------------------------------------------------------------
Set-UserRight -Right "SeNetworkLogonRight" `
    -Value "$SID_Administrators,$SID_AuthUsers" `
    -STIG "V-278183" -Label "Access from network"

# -----------------------------------------------------------------------
# V-278184: Deny access from network = Guests
# -----------------------------------------------------------------------
Set-UserRight -Right "SeDenyNetworkLogonRight" `
    -Value "$SID_Guests" `
    -STIG "V-278184" -Label "Deny access from network"

# -----------------------------------------------------------------------
# V-278185: Deny log on as a batch job = Guests
# -----------------------------------------------------------------------
Set-UserRight -Right "SeDenyBatchLogonRight" `
    -Value "$SID_Guests" `
    -STIG "V-278185" -Label "Deny batch logon"

# -----------------------------------------------------------------------
# V-278187: Deny log on locally = Guests
# -----------------------------------------------------------------------
Set-UserRight -Right "SeDenyInteractiveLogonRight" `
    -Value "$SID_Guests" `
    -STIG "V-278187" -Label "Deny local logon"

# -----------------------------------------------------------------------
# V-278188: Deny log on through Remote Desktop Services = Guests
# -----------------------------------------------------------------------
Set-UserRight -Right "SeDenyRemoteInteractiveLogonRight" `
    -Value "$SID_Guests" `
    -STIG "V-278188" -Label "Deny RDP logon"

# -----------------------------------------------------------------------
# V-278243: Allow log on locally = Administrators
# -----------------------------------------------------------------------
Set-UserRight -Right "SeInteractiveLogonRight" `
    -Value "$SID_Administrators" `
    -STIG "V-278243" -Label "Allow local logon"

# -----------------------------------------------------------------------
# V-278244: Back up files and directories = Administrators
# -----------------------------------------------------------------------
Set-UserRight -Right "SeBackupPrivilege" `
    -Value "$SID_Administrators" `
    -STIG "V-278244" -Label "Backup files"

# -----------------------------------------------------------------------
# V-278252: Generate security audits = Local Service, Network Service
# -----------------------------------------------------------------------
Set-UserRight -Right "SeAuditPrivilege" `
    -Value "$SID_LocalService,$SID_NetworkService" `
    -STIG "V-278252" -Label "Generate audits"

# -----------------------------------------------------------------------
# V-278253: Impersonate a client = Administrators, LOCAL SERVICE, NETWORK SERVICE, SERVICE
# -----------------------------------------------------------------------
Set-UserRight -Right "SeImpersonatePrivilege" `
    -Value "$SID_Administrators,$SID_LocalService,$SID_NetworkService,$SID_Service" `
    -STIG "V-278253" -Label "Impersonate client"

# -----------------------------------------------------------------------
# V-278254: Increase scheduling priority = Administrators
# -----------------------------------------------------------------------
Set-UserRight -Right "SeIncreaseBasePriorityPrivilege" `
    -Value "$SID_Administrators" `
    -STIG "V-278254" -Label "Increase priority"

# -----------------------------------------------------------------------
# V-278261: Restore files and directories = Administrators
# -----------------------------------------------------------------------
Set-UserRight -Right "SeRestorePrivilege" `
    -Value "$SID_Administrators" `
    -STIG "V-278261" -Label "Restore files"

# -----------------------------------------------------------------------
# Apply the modified config via secedit (immediate effect)
# -----------------------------------------------------------------------
Write-Section "Applying user rights via secedit"

$cfg | Set-Content $seceditCfg -Encoding Unicode
secedit /configure /db $seceditDb /cfg $seceditCfg /areas USER_RIGHTS /quiet

if ($LASTEXITCODE -eq 0) {
    Write-OK "secedit /configure USER_RIGHTS succeeded"
} else {
    Write-Warn "secedit returned exit code $LASTEXITCODE"
    Write-Warn "Check: $env:windir\security\logs\scesrv.log"
    $ErrorCount++
}

# -----------------------------------------------------------------------
# Persist user rights via Local Group Policy GptTmpl.inf
# This ensures settings survive image capture and reboot
# -----------------------------------------------------------------------
Write-Section "Persisting user rights via Local Group Policy"

$gptDir = "$env:SystemRoot\System32\GroupPolicy\Machine\Microsoft\Windows NT\SecEdit"
if (!(Test-Path $gptDir)) {
    New-Item -Path $gptDir -ItemType Directory -Force | Out-Null
}

$gptTmplPath = Join-Path $gptDir "GptTmpl.inf"

# Read existing GptTmpl.inf or create new
$infContent = ""
if (Test-Path $gptTmplPath) {
    $infContent = Get-Content $gptTmplPath -Raw
}

# Build the Privilege Rights section
$privRightsSection = @"
[Privilege Rights]
SeNetworkLogonRight = $SID_Administrators,$SID_AuthUsers
SeDenyNetworkLogonRight = $SID_Guests
SeDenyBatchLogonRight = $SID_Guests
SeDenyInteractiveLogonRight = $SID_Guests
SeDenyRemoteInteractiveLogonRight = $SID_Guests
SeInteractiveLogonRight = $SID_Administrators
SeBackupPrivilege = $SID_Administrators
SeAuditPrivilege = $SID_LocalService,$SID_NetworkService
SeImpersonatePrivilege = $SID_Administrators,$SID_LocalService,$SID_NetworkService,$SID_Service
SeIncreaseBasePriorityPrivilege = $SID_Administrators
SeRestorePrivilege = $SID_Administrators
"@

# If GptTmpl.inf already has a [Privilege Rights] section, replace it
if ($infContent -match '\[Privilege Rights\]') {
    $infContent = $infContent -replace '(?s)\[Privilege Rights\].*?(?=\[|$)', "$privRightsSection`r`n"
} else {
    # Append to existing or create new
    if ($infContent -match '\[Unicode\]') {
        $infContent += "`r`n$privRightsSection"
    } else {
        $infContent = "[Unicode]`r`nUnicode=yes`r`n[Version]`r`nsignature=`"`$CHICAGO`$`"`r`nRevision=1`r`n$privRightsSection"
    }
}

Set-Content -Path $gptTmplPath -Value $infContent -Encoding Unicode -Force
Write-OK "GptTmpl.inf written to: $gptTmplPath"

# Update gpt.ini to register the Security CSE
$gptIniPath = "$env:SystemRoot\System32\GroupPolicy\gpt.ini"
$secCSE = "[{827D319E-6EAC-11D2-A4EA-00C04F79F83A}{803E14A0-B4FB-11D0-A0D0-00A0C90F574B}]"
if (Test-Path $gptIniPath) {
    $gptContent = Get-Content $gptIniPath -Raw
    if ($gptContent -notmatch "827D319E") {
        if ($gptContent -match 'gPCMachineExtensionNames=') {
            $gptContent = $gptContent -replace '(gPCMachineExtensionNames=\[)', "`$1$secCSE"
        } else {
            $gptContent = $gptContent -replace '(\[General\])', "`$1`r`ngPCMachineExtensionNames=[$secCSE]"
        }
        if ($gptContent -match 'Version=(\d+)') {
            $newVer = [int]$Matches[1] + 1
            $gptContent = $gptContent -replace 'Version=\d+', "Version=$newVer"
        }
        Set-Content -Path $gptIniPath -Value $gptContent -Encoding ASCII -Force
        Write-OK "Updated gpt.ini with Security CSE"
    }
} else {
    $gptContent = "[General]`r`ngPCMachineExtensionNames=[$secCSE]`r`nVersion=1`r`ngPCFunctionality=0"
    Set-Content -Path $gptIniPath -Value $gptContent -Encoding ASCII -Force
    Write-OK "Created gpt.ini with Security CSE"
}

# Force gpupdate
gpupdate /force /target:computer 2>&1 | Out-Null
Write-OK "gpupdate /force completed"

# -----------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------
Remove-Item $seceditCfg -ErrorAction SilentlyContinue
Remove-Item $seceditDb  -ErrorAction SilentlyContinue

Write-Section "User Rights Summary"

if ($ErrorCount -eq 0) {
    Write-Host "  All user rights applied successfully." -ForegroundColor Green
} else {
    Write-Host "  $ErrorCount issue(s) need attention." -ForegroundColor Yellow
}

exit $ErrorCount
