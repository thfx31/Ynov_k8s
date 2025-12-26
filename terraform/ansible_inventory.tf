resource "local_file" "ansible_inventory" {
  content = templatefile("inventory.tftpl", {
    nodes = digitalocean_droplet.k8s_vm
  })
  filename = "../ansible/hosts.ini"
}