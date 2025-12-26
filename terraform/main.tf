# Création du réseau privé
resource "digitalocean_vpc" "forge_vpc" {
  name   = "vpc-forge-rt"
  region = var.region
}

# Création d'une VM (Droplet)
resource "digitalocean_droplet" "k8s_vm" {
  for_each = toset(["kube-master", "kube-worker1"])   
  name     = each.key
  size     = "s-2vcpu-2gb"
  image    = "ubuntu-24-04-x64"
  region   = var.region
  vpc_uuid = digitalocean_vpc.forge_vpc.id
  ssh_keys = [data.digitalocean_ssh_key.my_key.id]
}

# On récupère l'ID de la clé SSH existante par son nom
data "digitalocean_ssh_key" "my_key" {
  name = var.ssh_key_name
}