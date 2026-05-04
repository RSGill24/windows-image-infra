# Phase 2: Technical Implementation Details

## Parameter Flow: DATABASE_TYPE

Understanding how the `DATABASE_TYPE` parameter flows through the entire pipeline:

### 1. Cloud Build → Cloud Run Job
```
cloudbuild2.yaml
  └─ _DATABASE_TYPE substitution = "none" (default)
     (Override via --substitutions flag)
       ↓
Cloud Run Job Environment Variable
  └─ DATABASE_TYPE env var
```

**Example:**
```bash
gcloud builds submit \
  --substitutions=_DATABASE_TYPE=mysql \
  --config=phase2/cloudbuild2.yaml
```

### 2. Cloud Run Job → Docker Container
```
Cloud Run Job Environment
  └─ DATABASE_TYPE=mysql
       ↓
Docker Container Entrypoint
  └─ Receives env var via Docker
```

### 3. Docker Entrypoint → Packer
```
docker-entrypoint-phase2.sh
  └─ export DATABASE_TYPE="$DATABASE_TYPE"
       ↓
packer validate -var "database_type=${DATABASE_TYPE}"
  └─ Packer receives: database_type = "mysql"
       ↓
packer build -var "database_type=${DATABASE_TYPE}"
```

### 4. Packer → PowerShell Script
```
customize_db.pkr.hcl
  └─ variable "database_type" { ... }
       ↓
provisioner "powershell" {
  inline = [
    "& './database_orchestrator.ps1' -DatabaseType '${var.database_type}'"
  ]
}
```

### 5. PowerShell: Conditional Logic
```
database_orchestrator.ps1
  └─ switch ($DatabaseType.ToLower()) {
      "oracle" → call install_oracle.ps1
      "mysql"  → call install_mysql.ps1
      "none"   → skip database installation
    }
```

## Environment Variable Set Points

### Set 1: Cloud Build → substitutions
```yaml
# cloudbuild2.yaml
substitutions:
  _DATABASE_TYPE: "none"  # Default: no database
```

### Set 2: Cloud Run Job → Environment Variables
Pre-configured in Cloud Run Job definition:
```bash
DATABASE_TYPE=none  # Can override at execution time
```

### Set 3: Override at Execution
```bash
gcloud beta run jobs execute database-image-build \
  --set-env-vars="DATABASE_TYPE=mysql"  # Override to MySQL
```

## Validation Flow

```
┌─────────────────────────────┐
│  DATABASE_TYPE Parameter    │
├─────────────────────────────┤
│  Environment Variable Set   │
│  ↓                          │
│  cloudbuild2.yaml Receives  │
│  ↓                          │
│  Cloud Run Job Does         │
│  ↓                          │
│  docker-entrypoint reads    │
│  ↓                          │
│  Packer passes to HCL       │
│  ↓                          │
│  PowerShell validates       │
│  ↓                          │
│  Conditional routing        │
│  ↓                          │
│  Appropriate installer runs │
└─────────────────────────────┘
```

## Directory Structure Details

### Phase 2 Folder
```
phase2/
├── Dockerfile                  
│   └─ Installs: Packer, gcloud, Ansible
│   └─ COPY: packer/, scripts/, entrypoint
│   └─ RUN: packer init (validate HCL syntax)
│
├── docker-entrypoint-phase2.sh
│   └─ Parse env vars (DATABASE_TYPE, others)
│   └─ Fetch WinRM secret
│   └─ Call: packer validate & packer build
│   └─ Pass: -var "database_type=${DATABASE_TYPE}"
│   └─ Handle: image deprecation, logging
│
├── cloudbuild2.yaml
│   └─ Step 2: docker build (creates builder image)
│   └─ Step 3: docker push (to Artifact Registry)
│   └─ Default: _DATABASE_TYPE=none
│
└── packer/
    ├── customize_db.pkr.hcl
    │   ├─ Variable: database_type (string, default="none")
    │   ├─ Source: googlecompute + Phase 1 image
    │   ├─ Provisioner: Upload scripts
    │   └─ Provisioner: Call orchestrator.ps1
    │
    ├── scripts/
    │   ├─ database_orchestrator.ps1
    │   │   ├─ Accept: -DatabaseType parameter
    │   │   ├─ Validate: oracle|mysql|none
    │   │   ├─ Route: Call appropriate installer
    │   │   └─ Log: Failures and success
    │   │
    │   ├─ install_mysql.ps1
    │   │   ├─ Download: MySQL 8.0 MSI
    │   │   ├─ Install: via msiexec
    │   │   ├─ Config: Service MySQL80, port 3306
    │   │   └─ Firewall: Allow inbound 3306
    │   │
    │   └─ install_oracle.ps1
    │       ├─ Download: Oracle 23c Free
    │       ├─ Extract: ZIP archive
    │       ├─ Install: via setup.exe
    │       ├─ Config: Services, ports 1521/5500
    │       └─ Firewall: Allow inbound 1521 & 5500
    │
    └─ database-builder.yml
        └─ Ansible playbook (validation/prep)
        └─ Check: Packer version, GCloud, env vars
        └─ Validate: Database type, scripts present
```

## Packer Variable Passing

### HCL Variables Definition
```hcl
# customize_db.pkr.hcl
variable "database_type" { 
  type    = string 
  default = "none" 
}
```

### HCL Variable Usage in Provisioner
```hcl
provisioner "powershell" {
  inline = [
    "& 'C:/Users/packer_user/installation/database_orchestrator.ps1' -DatabaseType '${var.database_type}'"
  ]
}
```

### Docker Entrypoint Passing to Packer
```bash
packer build \
  -var "database_type=${DATABASE_TYPE}" \
  customize_db.pkr.hcl
```

## PowerShell Orchestrator Logic

```powershell
switch ($DatabaseType.ToLower()) {
    "oracle" {
        Write-Host "Installing Oracle Database..."
        Invoke-Step -ScriptPath "$scriptDir\install_oracle.ps1" -Label "Oracle Installation"
    }
    "mysql" {
        Write-Host "Installing MySQL Database..."
        Invoke-Step -ScriptPath "$scriptDir\install_mysql.ps1" -Label "MySQL Installation"
    }
    "none" {
        Write-Host "No database installation requested."
    }
    default {
        Write-Error "Unknown database type: $DatabaseType"
        exit 1
    }
}
```

## WinRM Communication

Windows instance ← WinRM (Port 5986, HTTPS) → Packer (Linux)

1. Packer initiates connection via WinRM
2. Uploads PowerShell scripts via file provisioner
3. Executes provisioner "powershell" inline commands
4. Scripts execute in context of packer_user (admin)
5. Output streamed back to Packer logs

## Security Considerations

| Layer | Security |
|-------|----------|
| **Transport** | WinRM over HTTPS (5986), IAP |
| **Authentication** | WinRM password in Secret Manager |
| **Network** | Private subnet, internal IP only, no external IP |
| **VMs** | Secure Boot, vTPM, Integrity Monitoring enabled |
| **Scripts** | Encoding normalized (UTF-8 BOM), pre-upload validation |
| **Logging** | Cloud Logging configured, audit trail maintained |

## Testing the Parameter

### Test 1: Validate Syntax
```bash
export DATABASE_TYPE=mysql
cd phase2
packer validate \
  -var "database_type=${DATABASE_TYPE}" \
  packer/customize_db.pkr.hcl
```

### Test 2: Ansible Validation
```bash
cd phase2
ansible-playbook packer/database-builder.yml \
  -e "database_type=mysql"
```

### Test 3: PowerShell Logic (locally)
```powershell
$DatabaseType = "mysql"
$scriptDir = "C:\Scripts"

switch ($DatabaseType.ToLower()) {
    "mysql"  { Write-Host "MySQL selected" }
    "oracle" { Write-Host "Oracle selected" }
    "none"   { Write-Host "No database" }
}
```

## Troubleshooting Parameter Passing

### Problem: Parameter not reaching Packer
```
ERROR: undefined: database_type
```
**Solution:** Check env var is set in Cloud Run Job
```bash
# Verify
gcloud beta run jobs describe database-image-build \
  --region=us-east4 \
  --format="value(template.labels.database_type)"
```

### Problem: PowerShell not receiving parameter
```
ERROR: Cannot bind argument to parameter
```
**Solution:** Verify packer/customize_db.pkr.hcl inline syntax:
```hcl
inline = [
  "& 'path/script.ps1' -DatabaseType '${var.database_type}'"  # ✓ Correct
  # NOT: "& 'path/script.ps1' $DatabaseType"  # ✗ Wrong
]
```

### Problem: Database script not found
```
ERROR: Script not found: install_mysql.ps1
```
**Solution:** Check file provisioners in HCL:
```hcl
provisioner "file" {
  source      = "${var.installation_source_dir}/install_mysql.ps1"
  destination = "${var.installation_target_dir}/install_mysql.ps1"
}
```

## Performance Notes

- **Phase 1 Base:** ~30 min (hardening)
- **Phase 2 MySQL:** +15-20 min (download + install)
- **Phase 2 Oracle:** +30-40 min (larger footprint, more config)
- **Phase 2 None:** +5 min (skip database layer)

**Total build time:**
- MySQL: ~45-50 min
- Oracle: ~60-70 min
- None: ~35 min

## Next Steps

1. Test Phase 1 image accessibility
2. Deploy Phase 2 builder Docker image
3. Create Cloud Run Job
4. Execute with `--set-env-vars="DATABASE_TYPE=mysql"`
5. Monitor job execution and logs
6. Verify output image and database functionality
