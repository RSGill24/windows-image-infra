# Database Configuration Guide

This guide explains how to use the config-driven database installation system.

## Configuration File

The database type is defined in `config.yaml` (located in `phase2/` directory):

```yaml
# ============================================================
# Phase 2: Database Configuration
# ============================================================

# Database type to install
# Valid values: mysql, oracle, none
database_type: mysql

# Optional build metadata
build_metadata:
  description: "Windows Server 2022 with MySQL database layer"
  version: "1.0"
  environment: "production"
```

### Valid Values

- `mysql` - Install MySQL Server 8.0 on Windows VM
- `oracle` - Install Oracle Database 23c Free on Windows VM  
- `none` - No database installation (base OS only)

## Workflow

### 1. Edit Configuration Locally

```bash
cd phase2/
```

Edit `config.yaml` and change the `database_type` value:

```yaml
database_type: oracle
```

### 2. Commit and Push to GitHub

```bash
git add config.yaml
git commit -m "Configure database type for Phase 2 build: oracle"
git push origin main
```

### 3. Cloud Build Executes

When you push, Cloud Build automatically:

1. ✅ **Step 0** - Reads `config.yaml` and validates the `database_type`
2. ✅ **Step 1** - Builds the Docker image
3. ✅ **Step 2-3** - Configures auth and pushes to Artifact Registry
4. ✅ **Step 4** - Displays configuration summary with next steps

### 4. Execute Cloud Run Job

After Cloud Build completes, execute the database image build job:

**Option A: Via GCP Console**
1. Go to GCP Console → Cloud Run → Jobs
2. Select `database-image-build` job
3. Click **Execute**
4. The job will:
   - Pull the Docker image from Artifact Registry
   - Read `config.yaml` from the entrypoint script
   - Install the specified database on Windows VM
   - Create the final image in the image family specified

**Option B: Via gcloud CLI**

```bash
gcloud run jobs execute database-image-build \
  --project=big-mender-473219-r2 \
  --region=us-east4
```

## How It Works

### Configuration Loading Flow

```
config.yaml (in GitHub repo)
    ↓
Cloud Build reads it (Step 0)
    ↓
Docker image built with all scripts
    ↓
Cloud Run Job executes
    ↓
docker-entrypoint-phase2.sh runs
    ↓
Reads config.yaml from mounted volume
    ↓
Sets DATABASE_TYPE environment variable
    ↓
Packer selects appropriate installation scripts
    ↓
MySQL/Oracle installed on Windows VM
    ↓
Final image created in GCE
```
    ↓
Sets DATABASE_TYPE environment variable
    ↓
Packer selects appropriate installation scripts
    ↓
MySQL/Oracle installed on Windows VM
    ↓
Final image created in GCE
```

### No Runtime Prompts

- The `database_type` is **NOT** asked at runtime
- It comes from the committed `config.yaml` file
- You decide the database when you edit the file before pushing

## Example Scenarios

### Scenario 1: Build with MySQL

```bash
# Edit config.yaml - Option 1: Using cat
cat << 'EOF' > phase2/config.yaml
database_type: mysql

build_metadata:
  description: "Windows Server 2022 with MySQL"
  version: "1.0"
EOF

# Or Option 2: Edit with your editor
vim phase2/config.yaml

# Push to trigger Cloud Build
git add phase2/config.yaml
git commit -m "Build with MySQL"
git push
```

### Scenario 2: Build Base OS Only (No Database)

```bash
# Edit config.yaml
cat << 'EOF' > phase2/config.yaml
database_type: none

build_metadata:
  description: "Windows Server 2022 - Base OS only"
  version: "1.0"
EOF

# Push and execute
git add phase2/config.yaml
git commit -m "Build base OS without database"
git push
```

## Troubleshooting

### Invalid Database Type Error

```
ERROR: Invalid database_type 'postgresql'. Must be 'mysql', 'oracle', or 'none'
```

**Solution**: Edit `config.yaml` and use a valid value.

### Config File Not Found

```
ERROR: ./phase2/config.yaml not found
```

**Solution**: Ensure `config.yaml` exists in the `phase2/` directory and is committed to GitHub.

### Database Installation Fails

Check the Cloud Run Job logs in GCP Console to see the full error output.

## Environment Variable Override (Advanced)

If needed, you can override the config via environment variables when running Cloud Run manually:

```bash
gcloud run jobs execute database-image-build \
  --project=big-mender-473219-r2 \
  --region=us-east4 \
  --set-env-vars=OVERRIDE_DATABASE_TYPE=oracle
```

This overrides the `config.yaml` value for that specific execution.

## File Locations

- **Config file**: `phase2/config.yaml`
- **Entry script**: `phase2/docker-entrypoint-phase2.sh`
- **Cloud Build config**: `phase2/cloudbuild2.yaml`
- **Database playbooks**: `phase2/packer/ansible-playbook/`
