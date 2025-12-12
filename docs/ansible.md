## Set up droplets
Créer 2 droplets Ubuntu 24.04 (machines virtuelles) dans l'espace DigitalOcean.

## Virtualenv
Créer un virtialenv sur le controleur Ansible
```shell
# Prerequisites
sudo apt-get install python3-venv

# Create your virtualenv
python3 -m venv ~/.virtualenvs/ansible

# Source your virtualenv
source ~/.virtualenvs/ansible/bin/activate
```

## Host file
Ajouter le hostname et l'IP des serveurs dans le fichier /etc/hosts du controleur Ansible.
```shell
sudo vim /etc/hosts
```

## Inventory
Editer le fichier inventory.yml et ajouter les droptlets
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