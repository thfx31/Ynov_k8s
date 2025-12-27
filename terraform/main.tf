# Création d'une VM (Droplet)
resource "digitalocean_droplet" "k8s_vm" {
  for_each = toset(["kube-master", "kube-worker01", "kube-worker02"])   
  name     = each.key
  size     = "s-2vcpu-2gb"
  image    = "ubuntu-24-04-x64"
  region   = var.region
  ssh_keys = [data.digitalocean_ssh_key.my_key.id]
}

# On récupère l'ID de la clé SSH existante par son nom
data "digitalocean_ssh_key" "my_key" {
  name = var.ssh_key_name
}