# Phase 2: Ansible-Based Database Installation

## Architecture Update: PowerShell → Ansible

Your Phase 2 has been updated to use **Ansible** for database installation instead of direct PowerShell scripts.

## How It Works Now

```
┌──────────────────────────┐
│  Packer (Linux Container)│
├──────────────────────────┤
│  1. Upload Ansible files │
│  2. Create inventory      │
│  3. Run: ansible-playbook │
└────────────┬─────────────┘
             │
        WinRM (HTTPS)
        Port 5986
             │
             ↓
┌──────────────────────────┐
│  Windows VM (Target)     │
├──────────────────────────┤
│  - MySQL (if requested)  │
│  - Oracle (if requested) │
│  - Firewall Rules        │
│  - Services Running      │
└──────────────────────────┘
```

## Files Created

### Ansible Playbooks

| File | Purpose |
|------|---------|
| `database_installation.yml` | Main playbook - routes to MySQL/Oracle |
| `install_mysql_tasks.yml` | MySQL installation tasks |
| `install_oracle_tasks.yml` | Oracle installation tasks |

### Updated Files

| File | Changes |
|------|---------|
| `customize_db.pkr.hcl` | Now uses `provisioner "shell"` to run Ansible |
| Dockerfile | Already has Ansible installed ✓ |

## Key Improvements

✅ **Ansible-native:** Uses Ansible Windows modules (`win_package`, `win_service`, `win_firewall_rule`)
✅ **Better error handling:** Ansible's built-in error handling
✅ **Idempotent:** Can be re-run safely
✅ **Extensible:** Easy to add more tasks
✅ **Better logging:** Ansible provides detailed output

## Execution Flow

### Phase 2 Build Process

```
1. gcloud builds submit (builds Docker image)
                ↓
2. Cloud Run Job starts
                ↓
3. docker-entrypoint-phase2.sh runs
                ↓
4. packer build command executes
                ↓
5. Packer provisions Windows VM:
   a. PowerShell: Setup environment
   b. Upload: Ansible playbooks to Windows
   c. Create: Ansible inventory (targets 127.0.0.1)
   d. Shell: Run ansible-playbook command
                ↓
6. Ansible connects to Windows via WinRM (127.0.0.1:5986)
                ↓
7. Executes appropriate tasks:
   - install_mysql_tasks.yml (if DATABASE_TYPE=mysql)
   - install_oracle_tasks.yml (if DATABASE_TYPE=oracle)
   - neither (if DATABASE_TYPE=none)
                ↓
8. Packer captures output
                ↓
9. Image snapshot taken
```

## Parameter Passing (Updated)

```
DATABASE_TYPE (env var)
    ↓
Cloud Run Job
    ↓
docker-entrypoint-phase2.sh
    ↓
packer build -var "database_type=${DATABASE_TYPE}"
    ↓
customize_db.pkr.hcl receives var.database_type
    ↓
Packer passes to shell provisioner:
  shell: export DATABASE_TYPE=...
    ↓
Ansible playbook reads: lookup('env', 'DATABASE_TYPE')
    ↓
Routes to appropriate tasks
```

## Ansible Modules Used

### install_mysql_tasks.yml
- `win_file` - Create directories
- `win_get_url` - Download MySQL installer
- `win_package` - Install MSI package
- `win_service` - Create and manage Windows service
- `win_firewall_rule` - Configure firewall
- `win_telnet` - Verify connectivity

### install_oracle_tasks.yml
- `win_file` - Create directories
- `win_get_url` - Download Oracle installer
- `win_unzip` - Extract archive
- `win_command` - Run setup.exe
- `win_environment` - Set ORACLE_HOME
- `win_path` - Add to PATH
- `win_firewall_rule` - Configure firewall
- `win_service_info` - Check services

## Advantages Over PowerShell

| Aspect | PowerShell | Ansible |
|--------|-----------|---------|
| **Idempotency** | Manual implementation | Built-in |
| **Error handling** | Basic try/catch | Advanced error handling |
| **Logging** | Custom output | Standardized logging |
| **Modularity** | Scripts | Reusable tasks |
| **Windows support** | Native | Via WinRM ✓ |
| **State tracking** | Manual | Automatic |

## Usage Examples

### Example 1: Build with MySQL (Ansible)
```bash
export DATABASE_TYPE=mysql
gcloud beta run jobs execute database-image-build \
  --set-env-vars="DATABASE_TYPE=mysql" \
  --region=us-east4
```

Output: MySQL Server 8.0 installed via Ansible

### Example 2: Build with Oracle (Ansible)
```bash
export DATABASE_TYPE=oracle
gcloud beta run jobs execute database-image-build \
  --set-env-vars="DATABASE_TYPE=oracle" \
  --region=us-east4
```

Output: Oracle 23c Free installed via Ansible

### Example 3: No Database
```bash
gcloud beta run jobs execute database-image-build \
  --set-env-vars="DATABASE_TYPE=none" \
  --region=us-east4
```

Output: Phase 1 hardened image only

## Monitoring Ansible Execution

Check Packer logs for Ansible output:

```bash
# Watch real-time logs
gcloud logging read "resource.type=cloud_run_job" \
  --limit=100 \
  --format='value(textPayload)' \
  --grep='ansible'

# Look for Ansible task execution:
[windows_target] Windows VM via WinRM ← Ansible connecting
TASK [Install MySQL] ← Task output
ok: [127.0.0.1] ← Success indicator
```

## Ansible Inventory (Auto-created)

Packer automatically creates `/installation_target_dir/windows_inventory.ini`:

```ini
[windows_target]
127.0.0.1 ansible_user=packer_user ansible_password=... ansible_port=5986

[windows_target:vars]
ansible_connection=winrm
ansible_winrm_scheme=https
ansible_winrm_server_cert_validation=ignore
ansible_winrm_operation_timeout_sec=300
ansible_winrm_read_timeout_sec=300
```

This allows Ansible on the Linux container to connect to the Windows VM using WinRM.

## Troubleshooting

### Ansible can't connect to Windows
```
ERROR! Unexpected failure during execution of Ansible playbook
```
**Solution:**
1. Verify WinRM is running on Windows VM
2. Check firewall rule allows port 5986
3. Verify packer_user password is correct
4. Check `ANSIBLE_WINRM_OPERATION_TIMEOUT_SEC` is sufficient

### Ansible task fails mid-execution
```
FAILED - [windows_target]: Failed to install MySQL
```
**Solution:**
1. Check Windows Event Viewer for errors
2. Verify internet connectivity for MSI download
3. Check disk space (250GB allocated)
4. Review Ansible output for specific error

### MySQL/Oracle service won't start
```
Service failed with exit code 1
```
**Solution:**
1. Check Event Viewer on Windows VM
2. Verify port not already in use
3. For Oracle: Ensure ORACLE_HOME is set correctly
4. Run `ansible -vvv` for verbose output

## Deployment Checklist

- [ ] Phase 1 hardened image exists in `pww-windows-2022-hardened` family
- [ ] Ansible is installed in Docker image (already done) ✓
- [ ] Ansible playbooks present in `phase2/packer/`
- [ ] WinRM secret configured in Secret Manager
- [ ] Cloud Run Job environment variables set
- [ ] `DATABASE_TYPE` parameter set correctly
- [ ] Test: `ansible -i inventory.ini -m ping all` (from container)

## Next Steps

1. **Test Ansible Connectivity:**
   ```bash
   ansible -i phase2/packer/windows_inventory.ini \
     -m win_ping all
   ```

2. **Build Docker Image:**
   ```bash
   gcloud builds submit --config=phase2/cloudbuild2.yaml
   ```

3. **Execute Cloud Run Job:**
   ```bash
   gcloud beta run jobs execute database-image-build \
     --set-env-vars="DATABASE_TYPE=mysql"
   ```

4. **Monitor Ansible Output:**
   ```bash
   gcloud logging read ... --grep='Ansible\|TASK\|ok:'
   ```

## Migration from PowerShell

If you had previous PowerShell scripts, they're still available but not used:
- `install_mysql.ps1` - No longer used
- `install_oracle.ps1` - No longer used
- `database_orchestrator.ps1` - No longer used

These can be deleted or kept as reference.

---

**Updated:** May 1, 2026
**Architecture:** Packer + Ansible + Windows WinRM
**Status:** Ready for deployment
