# Windows Server 2022 Hardened Image Build

## Overview

This repository builds a Windows Server 2022 hardened image using:

- Packer  
- PowerShell automation  
- Security hardening (STIG-based)  
- Audit configuration and validation  
- Security agent installation (FireEye/Trellix, Nessus, BigFix)  
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
        ├── Certificates_PKCS7_v5_14_D...
        ├── InstallRoot.msi
        ├── WindowsServer-2022-MS-2.1.org.pamdata.xml
        ├── account_policy.ps1
        ├── apply_mof.ps1
        ├── remaining-fixes.ps1
        ├── audit.ps1
        ├── create_mof.ps1
        ├── dod_banner.ps1
        ├── install_PowerSTIG.ps1
        ├── install_bigfix.ps1
        ├── install_dod_certs.ps1
        ├── install_dsc_deps.ps1
        ├── install_nessus.ps1
        ├── install_trellix.ps1
        ├── registry_stig.ps1
        ├── repair_winrm_for_packer.ps1
        ├── run_all.ps1
        ├── services_stig.ps1
        └── stig_remediation_fixes.ps1
```
## What This Build Produces

### 1. Windows Server 2022 Base Image
- Latest Windows Server 2022  
- Automated provisioning via Packer
- Customized DOD consent Banner

---

### 2. STIG Hardened Configuration
- Uses PowerSTIG  
- Applies Windows Server 2022 STIG baseline  
- Uses DSC (Desired State Configuration)  
- Generates and applies MOF files  
- Includes additional hardening:
  - Account policies
  - Registry settings
  - Services hardening
  - DoD banner enforcement
  - Remediation fixes  

---

### 3. Security Agent Installation

The image includes automated installation of the following enterprise security agents:

- **FireEye (Trellix Agent)**  
- **Nessus Agent**  
- **BigFix Agent**  

These are installed during the build process using dedicated scripts:

| Script | Description |
|--------|-------------|
| `install_trellix.ps1` | Installs FireEye/Trellix security agent |
| `install_nessus.ps1` | Installs Nessus vulnerability scanning agent |
| `install_bigfix.ps1` | Installs BigFix compliance and patching agent |

> Note:  
> Agent binaries, and configuration parameters are securely provided via:
> - Secure storage (GCS- Google Cloud Storage)

---

### 4. Audit Configuration
- Enables Windows auditing policies  
- Performs compliance validation  

---

### 5. Compliance-Ready Golden Image
- Hardened OS  
- Security controls enforced  
- Security agents pre-installed  
- Repeatable, automated build  
- Pipeline-driven deployment  

---

## Scripts

| Script | Description |
|--------|-------------|
| `install_dsc_deps.ps1` | Installs required DSC and PowerShell modules |
| `install_PowerSTIG.ps1` | Installs the PowerSTIG module |
| `create_mof.ps1` | Generates MOF from STIG configuration |
| `apply_mof.ps1` | Applies MOF configuration |
| `account_policy.ps1` | Configures account-related STIG policies |
| `registry_stig.ps1` | Applies registry-based STIG settings |
| `services_stig.ps1` | Applies service-level hardening |
| `dod_banner.ps1` | Configures DoD login banner |
| `install_dod_certs.ps1` | Installs DoD certificates |
| `remaining-fixes.ps1` | Applies additional fixes not covered by STIG |
| `stig_remediation_fixes.ps1` | Applies remediation fixes |
| `install_trellix.ps1` | Installs FireEye/Trellix agent |
| `install_nessus.ps1` | Installs Nessus agent |
| `install_bigfix.ps1` | Installs BigFix agent |
| `audit.ps1` | Performs security audit validation |
| `repair_winrm_for_packer.ps1` | Fixes WinRM issues during build |
| `run_all.ps1` | Master orchestration script |
| `run_only_audit.ps1` | Runs only audit validation |

---

## Cloud Build Substitutions

| Variable | Value | Notes |
|----------|-------|-------|
| `_PROJECT_ID` | `ggn-nmfs-placeholderdev--1` | Update to your project ID |
| `_SOURCE_IMAGE_PROJECT_ID` | `windows-cloud` | |
| `_SOURCE_IMAGE_FAMILY` | `windows-2022` | |
| `_ZONE` | `us-east4-b` | |
| `_IMAGE_FAMILY` | `pww-windows-2022-hardened` | |
| `_SOURCE_IMAGE` | `ws2022` | |
| `_WINRM_SECRET` | `packer-winrm-password` | Secret Manager reference |
| `_PACKER_TEMPLATE` | `harden_ww.pkr.hcl` | |
| `_PACKER_VERSION` | `1.9.4` | |
| `_HARDENING_SOURCE_DIR` | `./scripts` | |
| `_HARDENING_TARGET_DIR` | `C:/Users/packer_user/hardening/` | |
| `_MACHINE_TYPE` | `e2-standard-8` | |
| `_TRIVY_VERSION` | `0.61.1` | |
| `_SEVERITY` | `HIGH,CRITICAL` | |

---

## Prerequisites

- Cloud Build service account with required IAM roles  
- Secret Manager configured for WinRM password  
- Access to agent installation binaries:
  - Trellix (FireEye)
  - Nessus Agent
  - BigFix Agent  
- Network access to:
  - Agent management servers (e.g., Nessus Manager, BigFix Root Server, Trellix ePO)

---

## Notes / Best Practices

- Keep agent installers version-controlled or stored securely  
- Do not hardcode credentials or activation keys  
- Use secure parameter injection (Secret Manager / environment variables)  
- Validate agent connectivity post-installation  
- Consider adding health checks in `run_all.ps1`
