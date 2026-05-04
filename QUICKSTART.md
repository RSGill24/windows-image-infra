# Phase 2 Quick Start Guide

## Prerequisites

✅ Phase 1 image must exist and be available
- GCP Project with image family: `pww-windows-2022-hardened`
- Cloud Run service account with necessary permissions
- WinRM secret in Secret Manager: `packer-winrm-password`

## 5-Minute Setup

### Step 1: Configure Variables
Edit `phase2/cloudbuild2.yaml` or set environment:
```bash
export PROJECT_ID="big-mender-473219-r2"
export DATABASE_TYPE="mysql"  # or "oracle" or "none"
export REGION="us-east4"
```

### Step 2: Build Docker Image
```bash
cd phase2
gcloud builds submit --config=cloudbuild2.yaml
```
**Output:** Docker image pushed to Artifact Registry

### Step 3: Create Cloud Run Job (First Time Only)
```bash
gcloud beta run jobs create database-image-build \
  --image=us-east4-docker.pkg.dev/big-mender-473219-r2/packer-images/windows-packer-db-customizer:latest \
  --region=us-east4 \
  --cpu=8 \
  --memory=32Gi \
  --timeout=7200s \
  --service-account=packer-win-sa@big-mender-473219-r2.iam.gserviceaccount.com \
  --set-env-vars \
  PROJECT_ID=big-mender-473219-r2,\
  SOURCE_IMAGE_PROJECT_ID=big-mender-473219-r2,\
  SOURCE_IMAGE_FAMILY=pww-windows-2022-hardened,\
  IMAGE_FAMILY=pww-windows-2022-db,\
  ZONE=us-east4-b,\
  MACHINE_TYPE=e2-standard-8,\
  SERVICE_ACCOUNT_EMAIL=packer-win-sa@big-mender-473219-r2.iam.gserviceaccount.com,\
  WINRM_SECRET=packer-winrm-password,\
  INSTALLATION_TARGET_DIR=C:/Users/packer_user/installation/,\
  PACKER_TEMPLATE=customize_db.pkr.hcl,\
  DATABASE_TYPE=mysql
```

### Step 4: Execute Job
```bash
gcloud beta run jobs execute database-image-build \
  --region=us-east4 \
  --project=big-mender-473219-r2
```

### Step 5: Monitor Progress
```bash
gcloud run jobs describe database-image-build \
  --region=us-east4

# Watch logs
gcloud logging read "resource.type=cloud_run_job AND resource.labels.job_name=database-image-build" \
  --limit=100 \
  --format=json | jq .
```

## Command Examples

### Build with MySQL
```bash
export DATABASE_TYPE=mysql
gcloud builds submit --config=phase2/cloudbuild2.yaml

gcloud beta run jobs execute database-image-build \
  --set-env-vars="DATABASE_TYPE=mysql" \
  --region=us-east4
```

### Build with Oracle
```bash
export DATABASE_TYPE=oracle
gcloud builds submit --config=phase2/cloudbuild2.yaml

gcloud beta run jobs execute database-image-build \
  --set-env-vars="DATABASE_TYPE=oracle" \
  --region=us-east4
```

### Build with No Database
```bash
export DATABASE_TYPE=none
gcloud beta run jobs execute database-image-build \
  --set-env-vars="DATABASE_TYPE=none" \
  --region=us-east4
```

## Outputs

After successful execution:

### MySQL Image
- **Image family:** `pww-windows-2022-db`
- **Preset:** MySQL Server 8.0
- **Port:** 3306
- **Service:** MySQL80
- **Ready for:** Application deployment with MySQL backend

### Oracle Image
- **Image family:** `pww-windows-2022-db`
- **Preset:** Oracle Database Free (23c)
- **Port:** 1521 (Listener), 5500 (Enterprise Manager)
- **Services:** Various Oracle services
- **Ready for:** Oracle-based applications

## Troubleshooting

### Build Failed: WinRM Error
```
ERROR: Error reaching WinRM service
```
**Solution:**
1. Verify `packer-winrm-password` secret exists in Secret Manager
2. Check service account permissions
3. Ensure Phase 1 image exists in correct project

### Build Failed: Timeout
```
ERROR: Build timeout after 85 minutes
```
**Solution:**
1. Increase Cloud Run Job timeout to 2+ hours
2. Check Packer logs for stuck provisioners
3. For Oracle: ensure installer is pre-staged

### Database Service Not Running
```
Service failed to start after installation
```
**Solution:**
- For MySQL: Check port 3306 not in use
- For Oracle: Check ORACLE_HOME environment variable set
- Review Windows Event Viewer logs on the instance

## Architecture Diagram

```
┌─────────────────────────────────────┐
│  Phase 1: STIG Hardened Image       │
│  (pww-windows-2022-hardened)        │
├─────────────────────────────────────┤
│ • Windows Server 2022               │
│ • STIG Compliance                   │
│ • Security Agents                   │
│ • DoD Certs & Banner                │
└─────────────────┬───────────────────┘
                  │
                  ↓
        ┌─────────────────────┐
        │ Phase 2 Builder     │
        │ (Packer Job)        │
        └─────────────────────┘
                  │
      ┌───────────┼───────────┐
      │           │           │
      ↓           ↓           ↓
  ┌────────┐ ┌────────┐ ┌────────┐
  │ MySQL  │ │ Oracle │ │ None   │
  │ Image  │ │ Image  │ │ Image  │
  └────────┘ └────────┘ └────────┘
      │           │           │
      └───────────┴───────────┘
              ↓
    Artifact Registry
    (Ready for GCE)
```

## Files Reference

| File | Purpose |
|------|---------|
| `Dockerfile` | Linux container with Packer + Ansible |
| `docker-entrypoint-phase2.sh` | Entrypoint script (Packer orchestration) |
| `packer/customize_db.pkr.hcl` | Packer template (sources Phase 1) |
| `packer/scripts/database_orchestrator.ps1` | PowerShell orchestrator (routes to MySQL/Oracle) |
| `packer/scripts/install_mysql.ps1` | MySQL installation script |
| `packer/scripts/install_oracle.ps1` | Oracle installation script |
| `packer/database-builder.yml` | Ansible playbook (validation/prep) |
| `cloudbuild2.yaml` | GCP Cloud Build config |
| `README.md` | Detailed documentation |

## Next Steps

1. ✅ Phase 1 image ready
2. ➡️ **You are here:** Phase 2 setup
3. Post-Phase 2:
   - Test database connectivity
   - Validate application deployment
   - Consider database-specific hardening (CIS benchmarks)
   - Create automated testing pipeline

## Support

For issues:
1. Check Phase 2 logs: `gcloud logging read ...`
2. Review Packer logs in Cloud Run Job
3. Verify Phase 1 image availability
4. Consult main [README.md](README.md)
