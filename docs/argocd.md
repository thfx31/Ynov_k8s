## Orchestration GitOps avec Argo CD
Cette section détaille la phase finale du déploiement : l'utilisation d'Argo CD pour piloter l'état du cluster selon le modèle App-of-Apps et une architecture en couches.

---

### 1. Le GitOps et l'App-of-Apps

Le GitOps est une stratégie de déploiement où Git est **la seule source de vérité**.

- **Etat déclaratif** : tout ce qui doit être présent dans le cluster est décrit dans des fichiers YAML sur GitHub.
- **Réconciliation automatique** : Argo CD surveille en permanence le cluster. S'il détecte une différence (dérive/drift) entre Git et la réalité, il synchronise le cluster pour qu'il corresponde au code.

**Le modèle "App-of-Apps"**

Plutôt que de déployer chaque application manuellement, nous utilisons une Root-App (Application Racine).
- Cette application "mère" ne déploie pas de pods, mais d'autres objets "Application" d'Argo CD.
- Cela permet de déployer une stack entière (Infra + DB + Apps) en ne lançant qu'un seul manifest YAML.

---

### 2. Architecture en couche

| Couche | Nom | Rôle & Composants
|------------|------|--------|
| **Layer-00** | Infrastructure | Fondations techniques : Ingress-Nginx, Cert-Manager, CNI, CSI et CCM
| **Layer-01** | Initialisation | Préparation de l'environnement : création des Namespaces applicatifs
| **Layer-02** | Data | Couche donnée : déploiement du serveur PostgreSQL (nécessaire pour Gitea)
| **Layer-03** | Apps | Applications finales : Jenkins, Gitea et la page d'accueil Nginx-Front


### 3. Cycle de vie et synchronisation
**Synchronisation automatique**
Chaque couche est configurée avec des options de synchronisation spécifiques :
- **Self-Healing** : si quelqu'un modifie manuellement une ressource dans le cluster (via kubectl), Argo CD la remet immédiatement dans l'état défini dans Git.
- **Pruning** : si l'on supprime un fichier YAML dans Git, Argo CD supprime automatiquement la ressource correspondante dans le cluster.

**Tracking des Ressources**
Comme vu dans la documentation des secrets, Argo CD utilise le label `app.kubernetes.io/instance` pour savoir quelle application gère quelle ressource. C'est ce qui permet de lier les secrets créés par le Job 3 à la couche `layer-01-init`.

---

### 4. Interaction avec le Workflow (Job 4)
Dans le pipeline GitHub Actions, le job **GitOps** réalise les actions suivantes :
- **Installation d'Argo CD** : téléchargement et application des manifests officiels dans le namespace `argocd`.
- **Attente (Wait)** : le workflow attend que le serveur Argo CD soit opérationnel avant de continuer.
- **Lancement de la Root-App** : application du fichier `argocd-manager/root-app.yaml`. Argo CD prend le relais et commence à déployer les 4 couches dans l'ordre.
- **Extraction des accès** : le workflow récupère le mot de passe administrateur généré par Argo CD pour l'afficher dans le résumé du build.

---

### 5. Utilisation au quotidien
Pour faire évoluer la plateforme, il n'est plus nécessaire de toucher aux pipelines GitHub Actions :
- **Ajouter un outil** : ajouter le manifest YAML dans le dossier `k8s/03-apps/` et Argo CD le déploiera automatiquement.
- **Modifier un replica** : changez le nombre de `replicas` dans le YAML de Jenkins sur Git et Argo CD mettra à jour le déploiement en quelques secondes.
