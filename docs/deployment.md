## Pipeline de déploiement (Workflow CI/CD)
Cette section détaille l'orchestration du déploiement automatisé, divisé en 4 Jobs au sein de GitHub Actions.

![GHA](/docs/sources/gha-workflow-deploy.png)

---

### 1. Principe du pipeline
Le déploiement suit une logique de **dépendance séquentielle** : chaque étape ne peut démarrer que si la précédente a réussi (`needs: ...`). Cela garantit qu'on ne tente pas de configurer un cluster si les machines n'existent pas encore.

---

### 2. Détail des 4 phases du déploiement

**Phase 1 : Provisioning (Terraform)**
- **Objectif** : créer l'infrastructure "physique"
- **Actions** : initialisation de Terraform Cloud, application du plan HCL pour créer les Droplets
- **Artefact produit** : le fichier `hosts.ini` (généré via un terraform output) est sauvegardé en tant qu'artefact GitHub pour être utilisé par le job suivant.

&nbsp;
**Phase 2 : Cluster Setup (Ansible)**
- **Objectif** : installer et configurer Kubernetes
- **Actions** : récupération de l'inventaire (`hosts.ini`), connexion SSH aux nodes, exécution du playbook `cluster.yml`.
- **Artefact produit** : le fichier `kubeconfig.yaml` est extrait du Master et sauvegardé comme artefact sécurisé.

&nbsp;
**Phase 3 : Infra & Secrets (Kubectl)**

- **Objectif** : préparer l'environnement Kubernetes et injecter la sécurité
- **Actions** :
    - Récupération du `kubeconfig.yaml`
    - Création du Namespace `rt`
    - Injection des secrets (DigitalOcean, Docker Hub, Postgres) avec les labels de tracking pour Argo CD
    - Déploiement des composants core : CNI (Calico) et drivers Cloud (CCM/CSI)

&nbsp;
**Phase 4 : GitOps (Argo CD)**
- **Objectif** : déployer la stack applicative et restituer les accès
- **Actions** :
    - Installation du serveur Argo CD
    - Lancement de la Root-App qui orchestre le déploiement des 4 couches (Layer 00 à 03)
    - Dashboarding : Extraction des adresses IP et mots de passe pour affichage dans le résumé GitHub Actions (Step Summary)

---

### 3. Gestion des artefacts
Le workflow utilise la commande `gh run download` ou l'action `upload-artifact` pour transmettre les informations critiques entre les jobs :
- **Terraform ➔ Ansible** : transmission des adresses IP via hosts.ini
- **Ansible ➔ Kubectl/Argo CD** : transmission des droits admin via kubeconfig.yaml

<p align="center">
  <img src="/docs/sources/gh-artifacts.png" width="500" alt="Workflow Deployment">
</p>

--- 

### 4. Github Step Summary
À la fin du déploiement, le workflow génère un **GitHub Step Summary**. Ce rapport dynamique contient :
- La liste des nœuds actifs avec leurs IPs externes
- L'IP du LoadBalancer d'entrée
- Les URLs d'accès (Argo CD, Jenkins, Gitea)
- Les identifiants de connexion Argo CD et Jenkins

<p align="center">
  <img src="/docs/sources/gh-step-summary.png" width="600" alt="Workflow Deployment">
</p>