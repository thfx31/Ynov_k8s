## Quick Start : déployer la Forge en 10 minutes
Ce guide résume les étapes minimales pour instancier l'intégralité de la plateforme.

&nbsp;

### 1. Préparation du dépôt
- **Fork ou Clone** : récupère le projet sur ton compte GitHub.
- **Secrets GitHub** : configure les 9 secrets indispensables (voir Gestion des Secrets) dans Settings > Secrets and variables > Actions.

---

### 2. Configuration Terraform Cloud
- **Crée un Workspace** (CLI-driven) sur [Terraform Cloud](https://app.terraform.io/login).
- Modifie le bloc `cloud` dans ton fichier `main.tf` avec ton nom d'organisation et de workspace.
- Ajoute ton `TF_VAR_do_token` dans les variables de ton workspace sur Terraform Cloud.

---

### 3. Lancement du Déploiement
- Va dans l'onglet **Actions** de ton dépôt GitHub.
- Sélectionne le workflow **"Kubernetes platform deployment"**.
- Clique sur **Run workflow**.

---

### 4. Récupération des accès
Une fois le job terminé (environ 10-15 min) :
- Ouvre le résumé du build dans GitHub Actions
- Note l'IP du LoadBalancer et les mots de passe temporaires affichés

---

## Pilotage via GitHub CLI (Optionnel)

Cette section explique comment utiliser l'outil `gh` pour piloter tes déploiements directement depuis ton terminal, sans passer par l'interface web.

&nbsp;

### 1. Pourquoi utiliser la CLI ?
La **GitHub CLI (`gh`)** est particulièrement utile pour :
- **Vitesse** : Lancer un déploiement ou un nettoyage en une seule ligne.
- **Monitoring** : Suivre les logs de tes jobs en temps réel.
- **Automatisation** : Enchaîner des commandes locales et distantes.

---

### 2. Installer la CLI GH
Voir la page [Github officielle](https://github.com/cli/cli/blob/trunk/docs/install_linux.md).

---

### 3. Commandes Essentielles

| Action | Commande
|------------|------|
| **S'authentifier** | `gh auth login` |
| **Lister les workflows** | `gh workflow list` |
| **Lancer le déploiement** | `gh workflow run "Kubernetes platform deployment"`  |
| **Suivre le déploiement** | `gh run watch` | 
| **Télécharger le Kubeconfig** | `gh run download --name cluster-kubeconfig` |
| **Lancer le nettoyage** | `gh workflow run "Kubernetes platform cleanup"` |

