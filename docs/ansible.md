## Configuration du Cluster avec Ansible
Cette section détaille la transformation des instances virtuelles "vierges" en un cluster Kubernetes fonctionnel grâce à l'automatisation de la configuration.

---

### 1. Gestion de Configuration & Bootstrapping
**Pourquoi Ansible ?**

Alors que Terraform s'occupe de "l'**infrastructure**", Ansible gère la "**configuration**".

- **Agentless** : Ansible n'a pas besoin d'être installé sur les nœuds cibles. Il communique via SSH.
- **Idempotence** : comme Terraform, Ansible vérifie l'état actuel avant d'agir. Si un paquet est déjà installé, il ne fait rien.
- **Inventaire dynamique** : dans ce projet, l'inventaire (la liste des machines) est généré à la volée à partir des adresses IP fournies par Terraform.

**Qu'est-ce que kubeadm ?**
`kubeadm` est l'outil officiel de la communauté Kubernetes pour instancier un cluster. Il automatise les étapes complexes comme la génération des certificats, la configuration du Control Plane et la jonction des nodes.

--- 

### 2. Structure des Rôles Ansible
Le déploiement est découpé en rôles pour séparer les responsabilités :

| Rôle | Description | Machines cibles
|------------|------|----------|
| **`k8s_prerequis`** | Installe les packages et outils nécéssaires (`kubeadm`, `kubelet`, `kubectl`) et configure les modules kernel, systemdCgroup et le runtime de container (`containerd`) | master + workers
| **`k8s_init_master`** | Lance `kubeadm init`, configure le fichier `admin.conf` et génère le token de jonction.  | master (Control Plane)
| **`k8s_join_master`** | Utilise le token du master pour rejoindre le cluster (`kubeadm join`). | workers

---
### 3. Interaction avec le Workflow GitHub
- **Injection SSH key** : le pipeline GitHub Actions injecte une clé privée SSH (stockée en secret) pour qu'Ansible puisse se connecter aux Droplets.
- **Génération de l'inventaire** : un script récupère les adresses IP des Outputs Terraform et crée un fichier `hosts.ini` temporaire.
- **Exécution du playbook** : Ansible parcourt les rôles dans l'ordre défini.
- **Extraction du Kubeconfig** : à la fin, Ansible récupère le fichier de configuration du cluster sur le Master pour le transmettre aux étapes suivantes (Argo CD et Cleanup).

**Playbook cluster.yml**
```bash
---
- hosts: master
  roles:
    - k8s_prereqs
    - k8s_init_master

- hosts: workers
  vars:
    master_host: "{{ groups['master'][0] }}"
  roles:
    - k8s_prereqs
    - k8s_join_worker
```

---

### 4. Utilisation (Commandes clés)
Ces commandes sont directement jouées par les workflow GitHub Actions, voici leur description :

| Commandes | Description
|------------|------|
| **`ansible-playbook -i hosts.ini cluster.yml`** | Lance l'intégralité du déploiement du cluster |
| **`ansible all -m ping`** | Vérifie la connectivité SSH avec tous les nodes  |
