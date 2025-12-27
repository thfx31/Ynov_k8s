# Forge Kubernetes – Environnement DevOps Cloud (DigitalOcean)

Ce projet met en place une **infrastructure DevOps** sur un cluster Kubernetes déployé sur DigitalOcean. 

---

## Contexte
Projet réalisé dans le cadre d'un TP **Orchestration Kubernetes**
Mastère **Expert en cloud, sécurité & infrastructure 2024/2026**

---

## Applications de la forge

| Couche | Technologie |
|------------|------|
| **Nginx** | Web Front Page |
| **Jenkins** | Serveur d'automatisation CI/CD |
| **Gitea** | Forge Git |
| **PostgreSQL** | Base de données pour Gitea |

--- 
Voici le rendu des ressources déployées dans le namespace `rt` :
<p align="center">
  <img src="./img/rt-namespace.png" width="800" alt="Namespace RT">
</p>

---

##  Stack Technique & Composants

| Couche | Technologie |
|------------|------|
| **Infrastructure** | DigitalOcean Droplets (Ubuntu 24.04) |
| **Configuration** | Ansible  |
| **Orchestration** | Kubernetes (kubadm) |
| **Réseau** | Calico + Ingress-Nginx  |
| **Cloud Controller Manager** | CCM DigitalOcean  |
| **Storage** | CSI DigitalOcean  |
| **Sécurité** | Bitnami Sealed Secrets + Cert-Manager  |
| **Applications** | Nginx, Gitea, Jenkins, PostgreSQL |

---

##  Workflow de déploiement

---

##  Quick Start

```bash
# 1. Cloner le projet
git clone https://github.com/thfx31/Ynov_k8s.git
```

---
## Accès aux services
| Appli | URL |
|------------|------|
| **Nginx** | https://forge.yourdomain |
| **Jenkins** | https://jenkins.yourdomain  |
| **Gitea** | https://gitea.yourdomain |
| **Postgresql** | N/A |


---
## Documentation détaillée
Retrouvez les détails techniques et les schémas dans le dossier [`docs/`](docs/).
)


---
## Auteurs
- Projet réalisé par **Thomas FAUROUX** et **Robin THIRIET** 
- Mastère Expert en cloud, sécurité & infrastructure (2024-2026)
- Dépôt : https://github.com/thfx31/Ynov_k8s/

---
## Licence

Ce projet est distribué sous licence **MIT**.  
Vous pouvez librement le réutiliser et le modifier avec attribution.
