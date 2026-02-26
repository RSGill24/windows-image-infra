# run_all.ps1
# Master orchestration script for DISA STIG compliance setup on GCP Windows Server 2022.
# Run this script once during initial image/VM setup to:
#   1. Install PowerSTIG and its dependencies
#   2. Generate the DSC MOF configuration file
#   3. Apply the STIG configuration via DSC
#   4. Register the scheduled audit task
#
# Must be run as Administrator.
# All scripts are expected to reside in the same directory as this script.

# Step 1: Install the PowerSTIG PowerShell module from PSGallery
& "$PSScriptRoot\install_PowerSTIG.ps1"

# Step 2: Install all required DSC resource module dependencies for PowerSTIG
# Must run before create_mof.ps1 since DSC resources are needed at MOF compile time
& "$PSScriptRoot\install_dsc_deps.ps1"

# Step 3: Compile the DSC MOF file using the STIG configuration and org settings
& "$PSScriptRoot\create_mof.ps1"

# Step 4: Apply the compiled MOF to enforce STIG settings on the local machine
& "$PSScriptRoot\apply_mof.ps1"

# Step 5: Register the scheduled task to run periodic STIG audits and push results to BigQuery
& "$PSScriptRoot\create_audit_task.ps1"
