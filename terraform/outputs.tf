output "hosts_ini" {
  value = <<EOF
[master]
${digitalocean_droplet.k8s_vm["kube-master"].ipv4_address}

[workers]
${digitalocean_droplet.k8s_vm["kube-worker01"].ipv4_address}
EOF
}

output "node_ips" {
  value = {
    for name, vm in digitalocean_droplet.k8s_vm : name => vm.ipv4_address
  }
}