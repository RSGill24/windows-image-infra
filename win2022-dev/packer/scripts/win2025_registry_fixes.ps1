#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Comprehensive Windows Server 2025 STIG registry/GPO fixes.
    Covers all CAT I and CAT II registry-based findings not handled by
    PowerSTIG DSC or other dedicated scripts.
    Run AFTER apply_mof.ps1 so DSC does not overwrite these settings.
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

function Set-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [string]$Type = "DWord",
        [string]$STIG
    )
    try {
        if (!(Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
        $actual = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
        if ($actual -eq $Value) {
            Write-Fixed "[$STIG] $Name = $Value"
        } else {
            Write-Warn "[$STIG] $Name = $actual (expected $Value)"
            $script:ErrorCount++
        }
    } catch {
        Write-Warn "[$STIG] Failed to set $Name at $Path : $_"
        $script:ErrorCount++
    }
}

# ============================================================
# CAT I — HIGH SEVERITY
# ============================================================

Write-Section "CAT I: AutoPlay / AutoRun (V-278099, V-278100, V-278101)"

# V-278099: AutoPlay turned off for nonvolume devices
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" `
    -Name "NoAutoplayfornonVolume" -Value 1 -STIG "V-278099"

# V-278100: Default AutoRun behavior — do not execute any autorun commands
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
    -Name "NoAutorun" -Value 1 -STIG "V-278100"

# V-278101: AutoPlay disabled for all drives
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
    -Name "NoDriveTypeAutoRun" -Value 255 -STIG "V-278101"

Write-Section "CAT I: Windows Installer (V-278121)"

# V-278121: Disable Always install with elevated privileges
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer" `
    -Name "AlwaysInstallElevated" -Value 0 -STIG "V-278121"

Write-Section "CAT I: Anonymous Enumeration (V-278217)"

# V-278217: No anonymous enumeration of shares
Set-RegistryValue `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
    -Name "RestrictAnonymous" -Value 1 -STIG "V-278217"

Write-Section "CAT I: Network Hardening (V-278082, V-278083, V-278084, V-278085)"

# V-278082: IPv6 source routing highest protection level
Set-RegistryValue `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" `
    -Name "DisableIPSourceRouting" -Value 2 -STIG "V-278082"

# V-278083: IPv4 source routing highest protection level
Set-RegistryValue `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" `
    -Name "DisableIPSourceRouting" -Value 2 -STIG "V-278083"

# V-278084: ICMP redirects must not override OSPF routes
Set-RegistryValue `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" `
    -Name "EnableICMPRedirect" -Value 0 -STIG "V-278084"

# V-278085: Ignore NetBIOS name release requests except from WINS
Set-RegistryValue `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Netbt\Parameters" `
    -Name "NoNameReleaseOnDemand" -Value 1 -STIG "V-278085"

Write-Section "CAT I: Application Compatibility & Windows Update (V-278098, V-278104)"

# V-278098: App Compat Program Inventory must not collect data
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat" `
    -Name "DisableInventory" -Value 1 -STIG "V-278098"

# V-278104: Windows Update must not get updates from other PCs on internet
# DODownloadMode: 0=Off, 1=LAN only, 2=Group, 3=Internet — must not be 3
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" `
    -Name "DODownloadMode" -Value 1 -STIG "V-278104"

Write-Section "CAT I: Legal Banner Title (V-278208)"

# V-278208: Legal banner dialog box title
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name "LegalNoticeCaption" -Value "US Department of Defense Warning Statement" `
    -Type "String" -STIG "V-278208"

# ============================================================
# CAT II — MEDIUM SEVERITY
# ============================================================

Write-Section "CAT II: Lock Screen & Display (V-278080, V-278095)"

# V-278080: No slide shows on lock screen
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" `
    -Name "NoLockScreenSlideshow" -Value 1 -STIG "V-278080"

# V-278095: Network selection UI not on logon screen
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
    -Name "DontDisplayNetworkSelectionUI" -Value 1 -STIG "V-278095"

Write-Section "CAT II: SMB & Network Client (V-278086, V-278210, V-278213, V-278214)"

# V-278086: Insecure SMB guest logons disabled
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation" `
    -Name "AllowInsecureGuestAuth" -Value 0 -STIG "V-278086"

# V-278210: MS network client: Digitally sign always
Set-RegistryValue `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" `
    -Name "RequireSecuritySignature" -Value 1 -STIG "V-278210"

# V-278213: MS network server: Digitally sign always
Set-RegistryValue `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters" `
    -Name "RequireSecuritySignature" -Value 1 -STIG "V-278213"

# V-278214: MS network server: Digitally sign if client agrees
Set-RegistryValue `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters" `
    -Name "EnableSecuritySignature" -Value 1 -STIG "V-278214"

Write-Section "CAT II: Process & Credential Hardening (V-278088, V-278089, V-278102)"

# V-278088: Command line data in process creation events
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit" `
    -Name "ProcessCreationIncludeCmdLine_Enabled" -Value 1 -STIG "V-278088"

# V-278089: Remote host delegation of nonexportable credentials
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation" `
    -Name "AllowProtectedCreds" -Value 1 -STIG "V-278089"

# V-278102: No admin account enumeration during elevation
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\CredUI" `
    -Name "EnumerateAdministrators" -Value 0 -STIG "V-278102"

Write-Section "CAT II: Group Policy & Telemetry (V-278092, V-278103)"

# V-278092: GPO reprocess even if unchanged
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Group Policy\{35378EAC-683F-11D2-A89A-00C04FBBCFA2}" `
    -Name "NoGPOListChanges" -Value 0 -STIG "V-278092"

# V-278103: Telemetry limited to Security (0) or Basic (1)
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
    -Name "AllowTelemetry" -Value 1 -STIG "V-278103"

Write-Section "CAT II: Printing (V-278093, V-278094)"

# V-278093: No downloading print drivers over HTTP
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers" `
    -Name "DisableWebPnPDownload" -Value 1 -STIG "V-278093"

# V-278094: No printing over HTTP
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers" `
    -Name "DisableHTTPPrinting" -Value 1 -STIG "V-278094"

Write-Section "CAT II: Power / Wake Authentication (V-278096, V-278097)"

# V-278096: Prompt auth on wake (on battery)
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\0e796bdb-100d-47d6-a2d5-f7d2daa51f51" `
    -Name "DCSettingIndex" -Value 1 -STIG "V-278096"

# V-278097: Prompt auth on wake (plugged in)
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\0e796bdb-100d-47d6-a2d5-f7d2daa51f51" `
    -Name "ACSettingIndex" -Value 1 -STIG "V-278097"

Write-Section "CAT II: Event Log Sizes (V-278105, V-278106, V-278107)"

# V-278105: Application event log >= 32768 KB
wevtutil sl Application /ms:33554432
Write-Fixed "[V-278105] Application log set to 32768 KB (33554432 bytes)"

# V-278106: Security event log >= 196608 KB (1 week of records)
wevtutil sl Security /ms:201326592
Write-Fixed "[V-278106] Security log set to 196608 KB (201326592 bytes)"

# V-278107: System event log >= 32768 KB
wevtutil sl System /ms:33554432
Write-Fixed "[V-278107] System log set to 32768 KB (33554432 bytes)"

Write-Section "CAT II: SmartScreen & Defender (V-278108)"

# V-278108: Microsoft Defender SmartScreen enabled
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
    -Name "EnableSmartScreen" -Value 1 -STIG "V-278108"

Write-Section "CAT II: Remote Desktop Services (V-278112, V-278113, V-278114, V-278115, V-278116)"

# V-278112: No saving passwords in RDP client
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" `
    -Name "DisablePasswordSaving" -Value 1 -STIG "V-278112"

# V-278113: No drive redirection in RDP
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" `
    -Name "fDisableCdm" -Value 1 -STIG "V-278113"

# V-278114: Always prompt for password on RDP connection
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" `
    -Name "fPromptForPassword" -Value 1 -STIG "V-278114"

# V-278115: Require secure RPC for RDP
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" `
    -Name "fEncryptRPCTraffic" -Value 1 -STIG "V-278115"

# V-278116: RDP encryption set to High Level
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" `
    -Name "MinEncryptionLevel" -Value 3 -STIG "V-278116"

Write-Section "CAT II: RSS Feeds, Search Index, Installer (V-278117, V-278119, V-278120)"

# V-278117: No downloading RSS feed attachments
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Internet Explorer\Feeds" `
    -Name "DisableEnclosureDownload" -Value 1 -STIG "V-278117"

# V-278119: No indexing of encrypted files
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" `
    -Name "AllowIndexingEncryptedStoresOrItems" -Value 0 -STIG "V-278119"

# V-278120: Prevent users from changing install options
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer" `
    -Name "EnableUserControl" -Value 0 -STIG "V-278120"

Write-Section "CAT II: PowerShell Logging (V-278124, V-278131)"

# V-278124: PowerShell script block logging
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" `
    -Name "EnableScriptBlockLogging" -Value 1 -STIG "V-278124"

# V-278131: PowerShell Transcription
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription" `
    -Name "EnableTranscripting" -Value 1 -STIG "V-278131"

Write-Section "CAT II: RPC & SAM (V-278180, V-278182)"

# V-278180: Restrict unauthenticated RPC clients
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Rpc" `
    -Name "RestrictRemoteClients" -Value 1 -STIG "V-278180"

# V-278182: Restrict remote SAM calls to Administrators only
Set-RegistryValue `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
    -Name "RestrictRemoteSAM" -Value "O:BAG:BAD:(A;;RC;;;BA)" `
    -Type "String" -STIG "V-278182"

Write-Section "CAT II: Smart Card & Security Options (V-278209, V-278220, V-278221, V-278222)"

# V-278209: Smart Card removal — Lock Workstation
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" `
    -Name "ScRemoveOption" -Value "1" -Type "String" -STIG "V-278209"

# V-278220: Services using Local System use computer identity for NTLM
Set-RegistryValue `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
    -Name "UseMachineId" -Value 1 -STIG "V-278220"

# V-278221: NTLM no fall back to Null session
Set-RegistryValue `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Control\LSA\MSV1_0" `
    -Name "AllowNullSessionFallback" -Value 0 -STIG "V-278221"

# V-278222: Prevent PKU2U online identities
Set-RegistryValue `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Control\LSA\pku2u" `
    -Name "AllowOnlineID" -Value 0 -STIG "V-278222"

Write-Section "CAT II: Kerberos & NTLM Session Security (V-278223, V-278227, V-278228)"

# V-278223: Kerberos — AES only, no DES/RC4
# 2147483640 = 0x7FFFFFF8 — all except DES and RC4
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters" `
    -Name "SupportedEncryptionTypes" -Value 2147483640 -STIG "V-278223"

# V-278227: NTLM SSP client — NTLMv2 + 128-bit encryption (537395200 = 0x20080000)
Set-RegistryValue `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" `
    -Name "NTLMMinClientSec" -Value 537395200 -STIG "V-278227"

# V-278228: NTLM SSP server — NTLMv2 + 128-bit encryption
Set-RegistryValue `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" `
    -Name "NTLMMinServerSec" -Value 537395200 -STIG "V-278228"

Write-Section "CAT II: Crypto & Private Keys (V-278229, V-278230)"

# V-278229: Require password for private keys
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Cryptography" `
    -Name "ForceKeyProtection" -Value 2 -STIG "V-278229"

# V-278230: FIPS compliant algorithms
Set-RegistryValue `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\FIPSAlgorithmPolicy" `
    -Name "Enabled" -Value 1 -STIG "V-278230"

Write-Section "CAT II: UAC (V-278232, V-278234, V-278235)"

# V-278232: UAC approval mode for built-in Administrator
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name "FilterAdministratorToken" -Value 1 -STIG "V-278232"

# V-278234: UAC prompt admins for consent on secure desktop
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name "ConsentPromptBehaviorAdmin" -Value 2 -STIG "V-278234"

# V-278235: UAC deny standard user elevation requests
Set-RegistryValue `
    -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name "ConsentPromptBehaviorUser" -Value 0 -STIG "V-278235"

# ============================================================
# Summary
# ============================================================

Write-Section "REGISTRY FIXES SUMMARY"

if ($ErrorCount -eq 0) {
    Write-Host "  All registry/GPO fixes applied successfully." -ForegroundColor Green
} else {
    Write-Host "  $ErrorCount item(s) need attention." -ForegroundColor Yellow
}

exit $ErrorCount
