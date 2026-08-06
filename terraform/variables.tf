################################################################################
# variables.tf
#
# Root-module variables for the parameterized Windows image builder.
#
# Usage (ENV mode):
#   terraform apply -var="install_chrome=true" -var="install_git=true"
#
# Usage (JSON mode via Eventarc):
#   Upload a JSON to gs://<project>-image-builder-requests/requests/
################################################################################

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region (e.g. us-east4)"
  default     = "us-east4"
}

# ── Component flags (used in ENV mode / Cloud Scheduler) ──────────────────────

variable "install_oracle" {
  type        = bool
  default     = false
  description = "Install Oracle Instant Client + SQL*Plus"
}

variable "install_rstudio" {
  type        = bool
  default     = false
  description = "Install R + RStudio Desktop (OSS) via Chocolatey"
}

variable "install_conda" {
  type        = bool
  default     = false
  description = "Install Miniconda3 / conda + Python via Chocolatey"
}

variable "install_chrome" {
  type        = bool
  default     = false
  description = "Install Google Chrome"
}

variable "install_git" {
  type        = bool
  default     = false
  description = "Install Git + GitHub Desktop"
}

variable "install_python" {
  type        = bool
  default     = false
  description = "Install standalone Python"
}

variable "install_jupyterlab" {
  type        = bool
  default     = false
  description = "Install JupyterLab via pip"
}

variable "install_powershell_core" {
  type        = bool
  default     = false
  description = "Install PowerShell 7+"
}

variable "install_pycharm" {
  type        = bool
  default     = false
  description = "Install PyCharm Community Edition"
}

variable "install_visual_studio" {
  type        = bool
  default     = false
  description = "Install Visual Studio 2022 Community"
}

variable "install_paraview" {
  type        = bool
  default     = false
  description = "Install ParaView"
}

variable "install_echoview" {
  type        = bool
  default     = false
  description = "Install Echoview v16+ (binary from GCS)"
}

variable "install_matlab" {
  type        = bool
  default     = false
  description = "Install MATLAB (binary from GCS)"
}

variable "install_rstudio_pro" {
  type        = bool
  default     = false
  description = "Install RStudio Pro / Posit Workbench (binary from GCS)"
}

variable "install_positron" {
  type        = bool
  default     = false
  description = "Install Positron IDE (binary from GCS)"
}

variable "install_anaconda" {
  type        = bool
  default     = false
  description = "Install full Anaconda distribution"
}

variable "install_gpu_drivers" {
  type        = bool
  default     = false
  description = "Install NVIDIA GPU/vGPU GRID drivers (binary from GCS)"
}

variable "install_aalibrary" {
  type        = bool
  default     = false
  description = "Install AA-SI aalibrary Developer & ML"
}

variable "install_echosms" {
  type        = bool
  default     = false
  description = "Install EchoSMs"
}

variable "install_echostack" {
  type        = bool
  default     = false
  description = "Install EchoStack"
}

variable "install_gcp_utilities" {
  type        = bool
  default     = false
  description = "Install/update GCP Cloud Utilities (Google Cloud SDK)"
}

variable "install_excel" {
  type        = bool
  default     = false
  description = "Install Microsoft Excel via Office Deployment Tool"
}

# ── Email Notification (Gmail SMTP) ─────────────────────────────────────────

variable "gmail_sender_email" {
  type        = string
  description = "Gmail address used to send build notification emails"
  default     = ""
}

# ── Shared VPC / VM Network ────────────────────────────────────────────────

variable "vm_network" {
  type        = string
  description = "VPC network name for VM creation"
  default     = "app-network"
}

variable "vm_subnet" {
  type        = string
  description = "Subnet name for VM creation"
  default     = "app-subnet1"
}

variable "shared_vpc_host_project" {
  type        = string
  description = "Shared VPC host project ID (leave empty if not using Shared VPC)"
  default     = ""
}
