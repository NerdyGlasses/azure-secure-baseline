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

variable "cmk_expiration_date" {
  type        = string
  description = "Expiration date (RFC3339) for the storage CMK. A real rotation process would renew/reissue before this date rather than let the key simply expire."
  default     = "2027-12-31T23:59:59Z"
}
