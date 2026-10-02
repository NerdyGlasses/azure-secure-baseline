variable "subscription_id" {
  type    = string
  default = "00000000-0000-0000-0000-000000000000"
}

variable "tenant_id" {
  type    = string
  default = "00000000-0000-0000-0000-000000000000"
}

variable "location" {
  type    = string
  default = "centralindia"
}

variable "prefix" {
  type    = string
  default = "secbase"
}

variable "trusted_admin_cidr" {
  type        = string
  description = "CIDR allowed to reach SSH (e.g. your office/VPN range). Never use 0.0.0.0/0."
  default     = "203.0.113.0/24" # placeholder - replace with a real trusted range
}
