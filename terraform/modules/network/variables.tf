variable "project_id"        { type = string }
variable "region"            { type = string }
variable "network_name"      { type = string }
variable "app_subnet1_cidr"  { type = string }
variable "app_subnet2_cidr"  { type = string }
variable "db_subnet1_cidr"   { type = string }
variable "batch_subnet_cidr" { type = string }
variable "iap_source_range"  { type = string }
variable "cloud_router_asn"  { type = number }
variable "config" {
  type = object({
    dns_service_name  = string
    dns_policy_name   = string
    iap_ssh_ports     = list(string)
    iap_rdp_ports     = list(string)
    iap_winrm_ports   = list(string)
    user_vm_protocols = string
  })
}
