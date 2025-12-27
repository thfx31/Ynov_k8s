variable "do_token" {
  description = "Token API DigitalOcean"
  type        = string
  sensitive   = true
}

variable "region" {
  default = "fra1"
}

variable "ssh_key_name" {
  description = "Nom de la clé SSH déjà enregistrée sur DO"
  type        = string
}