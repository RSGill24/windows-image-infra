################################################################################
# variables.tf
#
# Root-module variables for the parameterized Windows image builder.
# Override at plan/apply time:
#   terraform apply -var="install_oracle=true" -var="install_rstudio=true"
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

# ── Component flags ────────────────────────────────────────────────────────────

variable "install_oracle" {
  type        = bool
  default     = false
  description = "Install Oracle Instant Client + SQL*Plus on the Windows image"
}

variable "install_rstudio" {
  type        = bool
  default     = false
  description = "Install R + RStudio Desktop (via Chocolatey) on the Windows image"
}

variable "install_conda" {
  type        = bool
  default     = false
  description = "Install Miniconda3 / conda + Python (via Chocolatey) on the Windows image"
}
