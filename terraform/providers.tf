terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.72.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.6.1"
    }       
  }
}

provider "digitalocean" {
  token = var.do_token
}