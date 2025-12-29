# Kubernetes – Environnement DevOps Cloud (DigitalOcean)

Ce projet met en place une **infrastructure DevOps** sur un cluster Kubernetes auto-géré (`kubeadm`), déployé de manière automatisée sur DigitalOcean.

Réalisation dans le cadre d'un TP **Orchestration Kubernetes** 
(Mastère **Expert en cloud, sécurité & infrastructure 2024/2026**)

![Argo CD Dashboard](/docs/sources/argocd-dashboard.png)

---

## Architecture Layered GitOps
Le projet est organisé en couches pilotées par **Argo CD**. Chaque composant est déployé selon une hiérarchie précise via le modèle **App-of-Apps** :

| Couche | Rôle | Composants
|------------|------|--------|
| **Layer-00** | Fondations cloud | CNI, CSI, CCM, Ingress-Nginx, Cert manager
| **Layer-01** | Environnement | Namespace
| **Layer-02** | Data | PostgreSQL (database pour Gitea)
| **Layer-03** | Apps | Gitea, Jenkins, Nginx-Front

---
## Architecture de la forge CI/CD
![Argo CD Dashboard](/docs/sources/diagram-rt.png)
*Représentation des objects du namespace applicatif RT*

---

##  Quick Start

### 1. Prérequis GitHub
Pour que les workflows fonctionnent, configurez les Secrets suivants dans votre dépôt GitHub (`Settings > Secrets and variables > Actions`) :

| Secret | Description
|------------|------|
| **`TF_API_TOKEN`** | Token Terraform Cloud (si utilisé pour le State) |
| **`DO_TOKEN`** | Token API DigitalOcean pour le provisionnement  |
| **`DO_SSH_KEY_NAME`** | Nom de votre clé SSH publique déjà présente sur DigitalOcean | 
| **`SSH_PRIVATE_KEY`** | Clé privée SSH (utilisée par Ansible pour configurer les nodes) |
| **`DOCKER_USERNAME`** | User DockerHub |
| **`DOCKER_PASSWORD`** | Token API DockerHub |
| **`POSTGRES_DB`** | Nom de la DB Gitea |
| **`POSTGRES_USERNAME`** | user de la DB Gitea  |
| **`POSTGRES_PASSWORD`** | Mot de passe de la DB Gitea |

### 2. Déploiement
- Allez dans l'onglet **Actions** du dépôt
- Sélectionnez le workflow **"Kubernetes platform deployment"**
- Cliquez sur Run workflow

### 3. Nettoyage des ressources
Pour détruire l'infrastructure sans laisser de ressources facturées :
- Lancer le workflow **"Kubernetes platform cleanup"**
- Ce script supprimera le loadbalancer et volumes avant de détruire les VMs

### 4. Accès aux services
| Appli | URL |
|------------|------|
| **Argo CD** | https://argocd.yourdomain |
| **Nginx** | https://forge.yourdomain |
| **Jenkins** | https://jenkins.yourdomain  |
| **Gitea** | https://gitea.yourdomain |
| **Postgresql** | N/A |

---
## Documentation technique
L'infrastructure est documentée par étapes, de la création des ressources Cloud jusqu'à la maintenance applicative.

### Infrastructure
- **[Architecture globale](docs/architecture.md)** : composants du cluster (Master/Workers), le réseau (Calico) et l'intégration Cloud (CCM/CSI)
- **[Provisionning avec Terraform](docs/terraform.md)** : création des Droplets sur DigitalOcean et la gestion du State via **Terraform Cloud**
- **[Configuration avec Ansible](docs/ansible.md)** : processus de "bootstrapping" du cluster via `kubeadm` et la configuration du cluster

### Sécurité
- **[Gestion des secrets](docs/secrets.md)** : injection sécurisée des identifiants (Docker, Postgres, SSH) sans stockage dans Git
- **[Sécurisation HTTPS avec Cert-Manager](docs/cert-manager.md)** : automatisation des certificats TLS avec **Let's Encrypt** pour tous les services de la forge logicielle

### GitOps
- **[Workflow du déploiement](docs/deployment.md)** : explication du pipeline GitHub Actions en 4 étapes
- **[Orchestration avec Argo CD](docs/argocd.md)** : détails du modèle Layered GitOps (L0 à L3) et de la structure **App-of-Apps**

### Opérations & cycle de vie
- **[Quick Start et pilotage via GitHub CLI](docs/quickstart.md)** : procédure pour préparer le setup et utilisation de l'outil `gh` pour commander l'infrastructure depuis le terminal
- **[Opérations de maintenance](docs/operations.md)** : guide pour le scaling, la mise à jour des applications et le troubleshooting
- **[Cleanup des ressources](docs/cleanup.md)** : procédure de destruction ordonnée pour éviter les coûts orphelins (LoadBalancer/Volumes)


---
## Auteurs
- Projet réalisé par **Thomas FAUROUX** et **Robin THIRIET** 
- Mastère Expert en cloud, sécurité & infrastructure (2024-2026)

---
## Licence
Ce projet est distribué sous licence **MIT**.  
Vous pouvez librement le réutiliser et le modifier avec attribution.
