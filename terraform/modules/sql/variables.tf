variable "project_id" { type = string }
variable "region1" { type = string }
variable "zone1" { type = string }
variable "environment" { type = string }
variable "application_id" { type = string }
variable "lineoffice" { type = string }
variable "system_id" { type = string }
variable "taskorder" { type = string }

variable "cloudsql_psc_service_attachment" { type = string }
variable "allowed_consumer_projects" { type = list(string) }
variable "app_network_id" { type = string }
variable "db_subnet1_id" { type = string }
variable "psc_endpoint_ip_name" { type = string }
variable "psc_forwarding_rule_name" { type = string }
