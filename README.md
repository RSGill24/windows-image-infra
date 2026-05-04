# Phase 2: Windows Database Customization

This phase builds upon **Phase 1** (STIG-hardened Windows Server 2022 image) and adds optional database layers (Oracle or MySQL).

## Architecture

```
Phase 1: win2022-dev/
├─ Hardened Windows Server 2022 image
├─ STIG compliance applied
├─ Security agents installed (Nessus, BigFix, Trellix)
└─ Output: pww-windows-2022-hardened (GCP image family)

                    ↓

Phase 2: phase2/
├─ Sources Phase 1 image as base
├─ Installs Oracle OR MySQL (based on parameter)
├─ Uses Ansible for orchestration (Linux side)
└─ Output: pww-windows-2022-db (GCP image family)
```

## Files Structure

```
phase2/
├── Dockerfile                       # Linux container with Packer + Ansible
├── docker-entrypoint-phase2.sh      # Entrypoint: fetches secrets, runs Packer
├── cloudbuild2.yaml                 # GCP Cloud Build configuration
└── packer/
    ├── customize_db.pkr.hcl         # Packer template (sources Phase 1)
    └── scripts/
        ├── database_orchestrator.ps1 # Main orchestrator (conditional logic)
        ├── install_mysql.ps1         # MySQL installation script
        └── install_oracle.ps1        # Oracle installation script
```

## How It Works

### 1. Phase 1 (Prerequisite)
Ensures Phase 1 has completed:
```bash
cd win2022-dev
gcloud builds submit --config=cloudbuild1.yaml
# Output: pww-windows-2022-hardened image family
```

### 2. Phase 2: Build Process

**Step 1: Prepare**
```bash
cd phase2
```

**Step 2: Build and Push Docker Image**
```bash
gcloud builds submit --config=cloudbuild2.yaml
# This builds and pushes the Phase 2 builder image to Artifact Registry
```

**Step 3: Create Cloud Run Job (Manual)**
In the GCP Console:
- Go to Cloud Run → Jobs
- Create new job: `database-image-build`
- Container image: `us-east4-docker.pkg.dev/<PROJECT_ID>/packer-images/windows-packer-db-customizer:latest`
- CPU: 8, Memory: 32 GB (database builds need more resources)
- Timeout: 2 hours
- Service account: `packer-win-sa@<PROJECT_ID>.iam.gserviceaccount.com`

**Step 4: Set Environment Variables (in Cloud Run Job)**
```bash
PROJECT_ID=big-mender-473219-r2
SOURCE_IMAGE_PROJECT_ID=big-mender-473219-r2
SOURCE_IMAGE_FAMILY=pww-windows-2022-hardened  # Phase 1 output
IMAGE_FAMILY=pww-windows-2022-db              # Phase 2 output
ZONE=us-east4-b
MACHINE_TYPE=e2-standard-8
SERVICE_ACCOUNT_EMAIL=packer-win-sa@big-mender-473219-r2.iam.gserviceaccount.com
WINRM_SECRET=packer-winrm-password
INSTALLATION_TARGET_DIR=C:/Users/packer_user/installation/
PACKER_TEMPLATE=customize_db.pkr.hcl
DATABASE_TYPE=mysql              # ← KEY: mysql, oracle, or none
```

**Step 5: Execute Job**
```bash
gcloud beta run jobs execute database-image-build \
  --project=big-mender-473219-r2 \
  --region=us-east4
```

## Database Installation Parameters

### MySQL
```bash
# Set environment variable
export DATABASE_TYPE=mysql

# Or in Cloud Run Job environment
gcloud beta run jobs execute database-image-build \
  --set-env-vars="DATABASE_TYPE=mysql" \
  --project=big-mender-473219-r2 \
  --region=us-east4
```
**Result:** MySQL Server 8.0 installed, port 3306, service: MySQL80

### Oracle
```bash
# Set environment variable
export DATABASE_TYPE=oracle

# Or in Cloud Run Job environment
gcloud beta run jobs execute database-image-build \
  --set-env-vars="DATABASE_TYPE=oracle" \
  --project=big-mender-473219-r2 \
  --region=us-east4
```
**Result:** Oracle Database Free (23c) installed, port 1521, requires pre-staging or manual setup

### None (Default)
```bash
# Set environment variable
export DATABASE_TYPE=none

# Or skip the variable (default)
gcloud beta run jobs execute database-image-build \
  --project=big-mender-473219-r2 \
  --region=us-east4
```
**Result:** Phase 1 hardened image only, no database tools

## Installation Scripts

### `database_orchestrator.ps1`
- Main entry point for database installation
- Accepts `DatabaseType` parameter (oracle, mysql, none)
- Routes to appropriate installer script
- Handles error tracking and logging

### `install_mysql.ps1`
- Downloads MySQL 8.0 from official source
- Installs via MSI installer
- Creates MySQL80 service
- Configures Windows Firewall (port 3306)
- Sets service to auto-start

### `install_oracle.ps1`
- Handles Oracle Database Free (23c) setup
- Configures listener (port 1521) and Enterprise Manager (port 5500)
- Sets ORACLE_HOME environment variable
- Adds Oracle bin directory to PATH
- Configures Windows Firewall rules
- **Note:** Oracle requires pre-staged installer or manual setup; download separately if needed

## Usage Examples

### Example 1: Build MySQL-enabled image
```bash
# Set up environment
export PROJECT_ID=big-mender-473219-r2
export SOURCE_IMAGE_FAMILY=pww-windows-2022-hardened
export IMAGE_FAMILY=pww-windows-2022-mysql
export DATABASE_TYPE=mysql

# Build and push builder image
gcloud builds submit --config=phase2/cloudbuild2.yaml

# Execute Cloud Run Job with MySQL
gcloud beta run jobs execute database-image-build \
  --set-env-vars="DATABASE_TYPE=mysql" \
  --project=$PROJECT_ID \
  --region=us-east4
```

### Example 2: Build Oracle-enabled image
```bash
export IMAGE_FAMILY=pww-windows-2022-oracle
export DATABASE_TYPE=oracle

gcloud builds submit --config=phase2/cloudbuild2.yaml

gcloud beta run jobs execute database-image-build \
  --set-env-vars="DATABASE_TYPE=oracle" \
  --project=$PROJECT_ID \
  --region=us-east4
```

## Troubleshooting

### Database Installation Fails
1. Check WinRM connectivity: Ensure `packer-winrm-password` secret exists
2. Verify Phase 1 image exists in the specified family
3. Check Packer logs in Cloud Run job execution
4. For Oracle: Ensure installer is pre-staged or manually deployed

### Service Won't Start
- **MySQL:** Check port 3306 not in use, verify MSI installation
- **Oracle:** Ensure ORACLE_HOME is set, check listener configuration

### Firewall Issues
- Verify firewall rules are created: `Get-NetFirewallRule | grep -i mysql`
- Allow inbound on required ports (3306, 1521)

## Security Notes

1. **Credentials:** WinRM password stored securely in Secret Manager
2. **IAP:** All connections use Identity-Aware Proxy
3. **Firewall:** Only necessary ports opened
4. **vTPM & Secure Boot:** Enabled on all instances
5. **Image Deprecation:** Old images automatically deprecated

## Next Steps

- Monitor job execution in Cloud Run
- Verify database functionality: Connect via appropriate client
- Test application deployment using the generated image
- Consider additional hardening for database-specific compliance (CIS, etc.)
