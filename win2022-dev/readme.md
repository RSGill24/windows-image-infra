# Windows Server 2022 Hardened Image Build

## Overview

This repository builds a Windows Server 2022 hardened image using:

- Packer
- PowerShell automation
- Security hardening (STIG-based)
- Audit configuration and validation
- Cloud Build pipeline automation

The image is designed to produce a secure, compliance-ready Windows Server 2022 base image for enterprise or regulated environments.

---

## Repo Structure

```
win2022-dev/
├── cloudbuild.yaml
└── packer/
    ├── harden_ww.pkr.hcl
    └── scripts/
        ├── WindowsServer-2022-MS-2.1.org.pamdata.xml
        ├── apply_mof.ps1
        ├── audit.ps1
        ├── audit_to_bq.bat
        ├── create_audit_task.ps1
        ├── create_mof.ps1
        ├── install_PowerSTIG.ps1
        ├── install_dsc_deps.ps1
        ├── run_all.ps1
        └── run_only_audit.ps1
```

---

## What This Build Produces

### 1. Windows Server 2022 Base Image
- Latest Windows Server 2022
- Automated provisioning via Packer

### 2. STIG Hardened Configuration
- Uses PowerSTIG
- Applies Windows Server 2022 STIG baseline
- Uses DSC (Desired State Configuration)
- Generates and applies MOF files

### 3. Audit Configuration
- Enables Windows auditing policies
- Creates scheduled audit task
- Exports audit results
- Optional: sends audit output to BigQuery (via `audit_to_bq.bat`)

### 4. Compliance-Ready Golden Image
- Hardened OS
- Security controls enforced
- Repeatable, automated build
- Pipeline-driven deployment

---

## Component Description

### Packer Template

**`harden_ww.pkr.hcl`** — Main Packer configuration file. Responsible for:
- Defining the Windows image source
- Running provisioning scripts
- Executing hardening workflow
- Producing final hardened image artifact

### Scripts

| Script | Description |
|--------|-------------|
| `install_dsc_deps.ps1` | Installs required DSC and PowerShell modules |
| `install_PowerSTIG.ps1` | Installs the PowerSTIG module required for STIG application |
| `create_mof.ps1` | Generates the MOF file from STIG configuration |
| `apply_mof.ps1` | Applies the generated MOF configuration to the system |
| `WindowsServer-2022-MS-2.1.org.pamdata.xml` | STIG baseline configuration for Windows Server 2022 |
| `audit.ps1` | Performs security audit validation checks |
| `create_audit_task.ps1` | Creates scheduled task to run recurring audits |
| `audit_to_bq.bat` | Optional — exports audit results to BigQuery |
| `run_all.ps1` | Master script: installs dependencies, applies STIG, configures audit, runs validation |
| `run_only_audit.ps1` | Executes only the audit validation portion |

---

## Cloud Build Substitutions

| Variable | Value | Notes |
|----------|-------|-------|
| `_PROJECT_ID` | `ggn-nmfs-placeholderdev--1` | # Update to your project ID |
| `_SOURCE_IMAGE_PROJECT_ID` | `windows-cloud` | |
| `_SOURCE_IMAGE_FAMILY` | `windows-2022` | |
| `_ZONE` | `us-east4-b` | |
| `_IMAGE_FAMILY` | `pww-windows-2022-hardened` | |
| `_SOURCE_IMAGE` | `ws2022` | |
| `_WINRM_SECRET` | `packer-winrm-password` | # Update Secret Manager secret name |
| `_PACKER_TEMPLATE` | `harden_ww.pkr.hcl` | |
| `_PACKER_VERSION` | `1.9.4` | |
| `_HARDENING_SOURCE_DIR` | `./scripts` | |
| `_HARDENING_TARGET_DIR` | `C:/Users/packer_user/hardening/` | |
| `_MACHINE_TYPE` | `e2-standard-8` | |
| `_TRIVY_VERSION` | `0.61.1` | |
| `_SEVERITY` | `HIGH,CRITICAL` | |

---

## Prerequisites

- The Cloud Build service account must have appropriate IAM roles to run the pipeline.
- A Secret Manager secret must be created for the WinRM password and referenced via `_WINRM_SECRET`.

