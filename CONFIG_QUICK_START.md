# Quick Start: YAML Configuration

## 📝 Current Config

**File**: `phase2/config.yaml`

```yaml
# ============================================================
# Phase 2: Database Configuration
# ============================================================
# This configuration file controls which database is installed
# during the Phase 2 Windows image customization build.
#
# VALID VALUES:
#   - mysql   : Installs MySQL Server 8.0 on Windows VM
#   - oracle  : Installs Oracle Database 23c Free on Windows VM
#   - none    : No database installation (base OS only)
#
# DEFAULT: none (if config file is missing)
# ============================================================

# Database type to install
# Change this value to switch databases before pushing to GitHub
# Examples:
#   database_type: mysql
#   database_type: oracle
#   database_type: none
database_type: mysql

# Optional: Build metadata (for reference)
# These are informational only and don't affect the build
build_metadata:
  # Description of this build configuration
  description: "Windows Server 2022 with MySQL database layer"
  
  # Version of this configuration
  version: "1.0"
  
  # Last updated
  last_updated: "2026-05-04"
  
  # Build target environment
  environment: "production"
```

---

## ✨ How To Use

### To Install MySQL:
```yaml
database_type: mysql
```

### To Install Oracle:
```yaml
database_type: oracle
```

### To Build Base OS Only:
```yaml
database_type: none
```

### With Metadata:
```yaml
database_type: mysql

build_metadata:
  description: "Production MySQL build for IT-DISA"
  version: "2.0"
  last_updated: "2026-05-04"
  environment: "production"
```

---

## 🚀 Workflow

1. **Edit** `phase2/config.yaml` (change `database_type` value)
2. **Commit** to git: `git add phase2/config.yaml`
3. **Push** to GitHub: `git push origin main`
4. **Cloud Build** automatically runs (no manual action needed)
5. **Execute** Cloud Run Job: `gcloud run jobs execute database-image-build --region=us-east4`
6. **Result**: Windows image with specified database installed

---

## ✅ Validation Status

All files have been validated:

```
✅ config.yaml - Valid YAML format
✅ docker-entrypoint-phase2.sh - Bash syntax OK
✅ Dockerfile - References config.yaml correctly
✅ cloudbuild2.yaml - All 6 steps configured
✅ All required files found
```

---

## 📋 Files Changed

1. ✅ `config.yaml` - Created (new YAML config)
2. ✅ `docker-entrypoint-phase2.sh` - Updated to parse YAML
3. ✅ `Dockerfile` - Added COPY config.yaml
4. ✅ `cloudbuild2.yaml` - Updated cloud build steps
5. ✅ `DATABASE_CONFIG.md` - Updated documentation

---

## 🎯 No More Errors!

The new YAML format:
- ✅ Supports proper comments
- ✅ Is more readable and maintainable
- ✅ Parses correctly in all scripts
- ✅ Validates database_type values
- ✅ Ready for production deployment

**Status**: **READY TO PUSH** 🚀
