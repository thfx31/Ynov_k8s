output "hosts_ini" {
  value = templatefile("inventory.tftpl", {
    nodes = digitalocean_droplet.k8s_vm
  })
}

output "node_ips" {
  value = {
    for name, vm in digitalocean_droplet.k8s_vm : name => vm.ipv4_address
  }
}