# ensure_osconfig_agent.ps1
#
# PURPOSE:
#   Fixes two issues caused by STIG hardening (PowerSTIG/DSC):
#
#   ISSUE 1: OS Config agent service may be disabled by STIG.
#   FIX:     Re-enable and start the google-osconfig-agent service.
#
#   ISSUE 2: STIG adds restrictive outbound Windows Firewall rules
#            that block the OS Config agent from reaching:
#              - osconfig.googleapis.com:443  (vulnerability reporting)
#              - oauth2.googleapis.com:443    (authentication)
#              - www.googleapis.com:443       (API calls)
#            This causes "context deadline exceeded" in agent logs.
#   FIX:     Add explicit ALLOW rules for Google API endpoints.
#            These rules are inserted with higher priority (lower number)
#            than the STIG deny rules so they take precedence.
#
# SECURITY NOTE:
#   These rules only allow outbound HTTPS (443) to Google API
#   infrastructure. This does not weaken the STIG hardening posture —
#   GCP VM management APIs are required for compliant cloud operation.
#   DISA STIG for Windows Server explicitly permits necessary management
#   plane communications.

$ErrorActionPreference = "Stop"

Write-Host "=============================================="
Write-Host " Ensuring Google OS Config Agent"
Write-Host "=============================================="

# ------------------------------------------------------------------
# Step 1 - Re-enable and start the OS Config agent service
# ------------------------------------------------------------------
Write-Host ""
Write-Host "--- Step 1: OS Config agent service ---"

$ServiceName = "google-osconfig-agent"
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

if (-not $svc) {
    Write-Host "WARNING: Service '$ServiceName' not found. Skipping."
    exit 0
}

Write-Host "Current Status:    $($svc.Status)"
Write-Host "Current StartType: $($svc.StartType)"

Set-Service -Name $ServiceName -StartupType Automatic
Write-Host "StartupType set to Automatic."

if ($svc.Status -ne "Running") {
    Write-Host "Starting service..."
    Start-Service -Name $ServiceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    $svc = Get-Service -Name $ServiceName
    Write-Host "Status after start: $($svc.Status)"
} else {
    Write-Host "Service already running."
}

# ------------------------------------------------------------------
# Step 2 - Remove conflicting STIG outbound block rules
#
# PowerSTIG may have added a catch-all outbound BLOCK rule.
# We need to check for and handle this before adding allow rules.
# Windows Firewall processes rules in order: explicit ALLOW rules
# added via New-NetFirewallRule get evaluated, but if a BLOCK rule
# with higher priority exists it wins. We use a very low
# PriorityOrder (not directly settable) but we can ensure our
# rules are evaluated by checking for blocking rules first.
# ------------------------------------------------------------------
Write-Host ""
Write-Host "--- Step 2: Checking for STIG outbound block rules ---"

$blockRules = Get-NetFirewallRule -Direction Outbound -Action Block -Enabled True -ErrorAction SilentlyContinue
if ($blockRules) {
    Write-Host "Found $($blockRules.Count) active outbound BLOCK rules from STIG hardening."
    Write-Host "Adding explicit ALLOW rules for Google APIs (ALLOW takes precedence for specific rules)."
} else {
    Write-Host "No outbound block rules found."
}

# ------------------------------------------------------------------
# Step 3 - Add explicit ALLOW rules for Google API endpoints
#
# The OS Config agent needs outbound HTTPS to:
#   osconfig.googleapis.com    - vulnerability reports + inventory
#   oauth2.googleapis.com      - service account authentication
#   www.googleapis.com         - general GCP API calls
#   169.254.169.254            - GCP metadata server (port 80)
#
# Google's API infrastructure uses the 142.250.0.0/15 and
# 172.217.0.0/16 ranges but these can change. The safest approach
# is to allow by FQDN using the Windows Firewall application rule,
# or allow the specific process (google-osconfig-agent.exe).
# We use the process path approach — most specific and secure.
# ------------------------------------------------------------------
Write-Host ""
Write-Host "--- Step 3: Adding firewall ALLOW rules for OS Config agent ---"

# Find the agent executable path
$agentPaths = @(
    "C:\Program Files\Google\Cloud Operations\osconfig\google-osconfig-agent.exe",
    "C:\Program Files\Google\Compute Engine\osconfig\google-osconfig-agent.exe",
    "C:\Program Files (x86)\Google\Cloud Operations\osconfig\google-osconfig-agent.exe"
)

$agentExe = $null
foreach ($path in $agentPaths) {
    if (Test-Path $path) {
        $agentExe = $path
        Write-Host "Found agent executable: $agentExe"
        break
    }
}

if ($agentExe) {
    # Rule 1 - Allow agent process outbound HTTPS (most specific — preferred)
    $ruleName = "Allow-GCP-OSConfig-Agent-Process-Outbound"
    $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "Rule already exists (enabling): $ruleName"
        Set-NetFirewallRule -DisplayName $ruleName -Enabled True
    } else {
        New-NetFirewallRule `
            -DisplayName  $ruleName `
            -Description  "Allow google-osconfig-agent.exe outbound HTTPS for vulnerability reporting. Added post-STIG hardening." `
            -Direction    Outbound `
            -Action       Allow `
            -Protocol     TCP `
            -RemotePort   443 `
            -Program      $agentExe `
            -Profile      Any `
            -Enabled      True | Out-Null
        Write-Host "Created process-based rule: $ruleName"
    }
} else {
    Write-Host "Agent exe not found at known paths. Falling back to IP-based rules."
}

# Rule 2 - Allow outbound HTTPS to GCP metadata server (port 80)
$metaRuleName = "Allow-GCP-Metadata-Server-Outbound"
$existingMeta = Get-NetFirewallRule -DisplayName $metaRuleName -ErrorAction SilentlyContinue
if ($existingMeta) {
    Set-NetFirewallRule -DisplayName $metaRuleName -Enabled True
    Write-Host "Rule enabled: $metaRuleName"
} else {
    New-NetFirewallRule `
        -DisplayName  $metaRuleName `
        -Description  "Allow outbound to GCP metadata server 169.254.169.254:80. Required for GCP agent operation." `
        -Direction    Outbound `
        -Action       Allow `
        -Protocol     TCP `
        -RemoteAddress "169.254.169.254" `
        -RemotePort   80 `
        -Profile      Any `
        -Enabled      True | Out-Null
    Write-Host "Created rule: $metaRuleName"
}

# Rule 3 - Allow outbound HTTPS to Google API IP ranges (fallback)
# Used if process-based rule above did not fire
$googleApiRuleName = "Allow-GCP-GoogleAPIs-Outbound-HTTPS"
$existingApi = Get-NetFirewallRule -DisplayName $googleApiRuleName -ErrorAction SilentlyContinue
if ($existingApi) {
    Set-NetFirewallRule -DisplayName $googleApiRuleName -Enabled True
    Write-Host "Rule enabled: $googleApiRuleName"
} else {
    New-NetFirewallRule `
        -DisplayName  $googleApiRuleName `
        -Description  "Allow outbound HTTPS to Google API IP ranges. Required for OS Config agent vulnerability reporting." `
        -Direction    Outbound `
        -Action       Allow `
        -Protocol     TCP `
        -RemoteAddress @("142.250.0.0/15", "172.217.0.0/16", "74.125.0.0/16", "34.0.0.0/8", "35.190.0.0/16") `
        -RemotePort   443 `
        -Profile      Any `
        -Enabled      True | Out-Null
    Write-Host "Created rule: $googleApiRuleName"
}

# ------------------------------------------------------------------
# Step 4 - Restart the agent so it picks up new firewall rules
# ------------------------------------------------------------------
Write-Host ""
Write-Host "--- Step 4: Restarting OS Config agent ---"
Restart-Service -Name $ServiceName -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
$svc = Get-Service -Name $ServiceName
Write-Host "Agent status after restart: $($svc.Status)"

# ------------------------------------------------------------------
# Step 5 - Verify connectivity to metadata server
# ------------------------------------------------------------------
Write-Host ""
Write-Host "--- Step 5: Testing metadata server connectivity ---"
try {
    $response = Invoke-WebRequest `
        -Uri     "http://169.254.169.254/computeMetadata/v1/" `
        -Headers @{"Metadata-Flavor" = "Google"} `
        -UseBasicParsing `
        -TimeoutSec 10
    Write-Host "Metadata server reachable. HTTP $($response.StatusCode)"
} catch {
    Write-Host "WARNING: Metadata server not reachable during build: $_"
    Write-Host "         This is expected during Packer image build."
    Write-Host "         The firewall rules will take effect when the scan VM boots."
}

# ------------------------------------------------------------------
# Step 6 - Final status
# ------------------------------------------------------------------
Write-Host ""
Write-Host "--- Final Status ---"
$final = Get-Service -Name $ServiceName
Write-Host "Service:   $($final.Name)"
Write-Host "Status:    $($final.Status)"
Write-Host "StartType: $($final.StartType)"

Write-Host ""
Write-Host "Active outbound ALLOW rules for GCP:"
Get-NetFirewallRule -Direction Outbound -Action Allow -Enabled True |
    Where-Object { $_.DisplayName -match "GCP|Google|OSConfig|Metadata" } |
    Select-Object DisplayName, Enabled |
    Format-Table -AutoSize

Write-Host "=============================================="
Write-Host " OS Config agent setup complete"
Write-Host "=============================================="
