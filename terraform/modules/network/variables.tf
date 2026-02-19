variable "project_id" { type = string }
variable "region" { type = string }
variable "network_name" { type = string }
variable "router_name" { type = string }
variable "nat_name" { type = string }
variable "subnet_app1" { type = string }
variable "subnet_app2" { type = string }
variable "subnet_db1" { type = string }
variable "subnet_batch" { type = string }
variable "app_subnet1_cidr" { type = string }
variable "app_subnet2_cidr" { type = string }
variable "db_subnet1_cidr" { type = string }
variable "batch_subnet_cidr" { type = string }
variable "iap_source_range" { type = string }
variable "cloud_router_asn" { type = number }
variable "dns_service_name" {
  type    = string
  default = "dns.googleapis.com"
}

variable "dns_policy_name" {
  type    = string
  default = "dns-logging"
}

variable "iap_ssh_ports" {
  type    = list(string)
  default = ["22"]
}

variable "iap_rdp_ports" {
  type    = list(string)
  default = ["3389"]
}

variable "iap_winrm_ports" {
  type    = list(string)
  default = ["5986"]
}

variable "user_vm_protocols" {
  type    = string
  default = "all"
}
