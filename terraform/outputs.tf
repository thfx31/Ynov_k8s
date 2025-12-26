output "node_ips" {
  value = {
    for name, node in digitalocean_droplet.k8s_vm : name => node.ipv4_address
  }
  description = "IPs des noeuds indexées par leur nom"
}