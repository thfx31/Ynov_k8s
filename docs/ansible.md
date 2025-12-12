# Création du cluster avec Ansible (Ubuntu only)

## Description des rôles

**k8s_prereqs**
```shell
- Installation des packages de base
- Installation de Helm
- Installation de kubeadm, kubelet, kubctl, containerd
- Configuration SystemdCgroup
- Configuration des modules
- Activation IP Forwarding
```

> La variable `k8s_prereqs_k8s_repo_version` permet de fixer la version de Kubernetes

&nbsp;
**k8s_init_master**
```shell
- Copie la config kubeadm
- Initialise le control plane
- Stocke le join token dans une variable
- Affiche le join token
```

> La variable `k8s_init_pod_network_cidr` fixe le CIDR pour le composant réseau (Calico par défaut)

&nbsp;
**k8s_join_worker**
```shell
- Récupère le join token
- Configure le node pour un external cloud provider
- Ajoute le node au cluster
```

## Set up droplets
Créer 2 droplets Ubuntu 24.04 (machines virtuelles) dans l'espace DigitalOcean.

## Virtualenv
Créer un virtualenv sur le controleur Ansible
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