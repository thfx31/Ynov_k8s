## Set up droplets
Create 2 Ubuntu 24.04 droplets (virtual machines) on DigitalOcean tenant.

## Virtualenv
Create a virtualenv on yout Ansible Controler
```shell
# Prerequisites
sudo apt-get install python3-venv

# Create your virtualenv
python3 -m venv ~/.virtualenvs/ansible

# Source your virtualenv
source ~/.virtualenvs/ansible/bin/activate
```

## Host file
Add IP and hostname in /etc/hosts on Ansible controler machine
```shell
sudo vim /etc/hosts
```

## Inventory.yml
Edit inventory.yml and add these droplets

## Run cluster.yml playbook
```shell
ansible-playbook -i inventory.yml cluster.yml
```

## Check your Kubernetes cluster
```shell
ssh root@kube-master

root@kube-master:~# kubectl get nodes
NAME          STATUS     ROLES           AGE   VERSION
kube-master   NotReady   control-plane   12m   v1.34.3
kube-worker   NotReady   <none>          10m   v1.34.3
```