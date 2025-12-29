## Gestion de la sécurité et des secrets
Cette section détaille la stratégie de sécurisation du projet : comment les données sensibles sont stockées, injectées et protégées à chaque étape du déploiement automatisé.

---

### 1. Principe de la gestion des secrets
Le projet repose sur une **injection par le runner CI/CD**. Au lieu de laisser Ansible ou Argo CD créer les secrets, c'est le workflow GitHub Actions qui utilise directement `kubectl` pour créer les objets "Secret" juste avant le déploiement applicatif.

- **Pas de secret dans Git** : aucun mot de passe, clé ou token n'est écrit en dur dans le code source.
- **Injection au Runtime** : les secrets sont stockés dans le coffre-fort de GitHub (Secrets Actions) et injectés uniquement lors de l'exécution du pipeline.
- **Idempotence & Tracking** : utilisation des labels et dry-run pour permettre des mises à jour sans erreurs de doublons.

---

### 2. Référentiels des secrets Github

Tous les secrets suivants doivent être configurés dans GitHub (`Settings > Secrets and variables > Actions`).

| Nom du Secret | Cible | Usage
|------------|------|------|
| **`TF_API_TOKEN`** |Terraform & K8S | Authentification pour la gestion du State distant |
| **`DO_TOKEN`** | Terraform CLoud | Provisioning des VMs et pilotage des LoadBalancers DigitalOcean  |
| **`DO_SSH_KEY_NAME`** |Terraform | Référence de la clé publique pour l'accès aux Droplets |
| **`SSH_PRIVATE_KEY`** | Ansible | Clé privée pour la configuration initiale du cluster |
| **`DOCKER_USERNAME`** | K8s (Registry) | Identifiant pour le pull des images (Docker Hub) |
| **`DOCKER_PASSWORD`** | K8s (Registry)| Token/Mot de passe Docker Hub |
| **`POSTGRES_DB`** | K8s (App)| Nom de DB créée pour Gitea |
| **`POSTGRES_USERNAME`** | K8s (App)| Login de la DB Gitea  |
| **`POSTGRES_PASSWORD`** | K8s (App)| Mot de passe de la DB |

---

### 3. Workflow des secrets

#### JOB 1 : PROVISIONING (Terraform)

Terraform prépare le terrain cloud avec :
- **`DO_TOKEN & DO_SSH_KEY_NAME`** : ces deux secrets permettent au provider DigitalOcean d'instancier les machines et d'y injecter la clé publique.

- **`TF_API_TOKEN`**  : permet de verrouiller et sauvegarder le "State" de l'infrastructure sur Terraform Cloud.

#### JOB 2 : CLUSTER SETUP (Ansible)

Pour transformer les VMs en cluster Kubernetes :
- **`SSH_PRIVATE_KEY`** : chargée dans un agent SSH éphémère, elle permet à Ansible de se connecter aux nodes pour installer kubeadm et créer le cluster

#### JOB 3 : INFRA & SECRETS (Kubectl)
C'est ici que l'on connecte le cluster au monde extérieur avant l'arrivée d'Argo CD :
- **`Secret DigitalOcean`** : le `DO_TOKEN` est injecté dans le namespace `kube-system`pour le Cloud Controller Manager
- **`Secret Docker Hub`** : les identifiants sont créés sous forme de secret `docker-registry` dans le namespace `rt` avec le label de tracking Argo CD.
- **`Secret Postgres`** : les identifiants de la base de données sont injectés et étiquetés pour être consommés par Gitea.

#### JOB 4 : GITOPS (Argo CD)
C'est l'étape finale de restitution et de déploiement :

- **`Consommation du Kubeconfig`** : ce job télécharge l'artefact `cluster-kubeconfig` (généré au Job 2) pour piloter le cluster.
- **`Déploiement Root-App`** : Argo CD est installé et lance la `root-app`. Celle-ci détecte les secrets étiquetés au Job 3 et les utilise pour démarrer Jenkins, Gitea, Posgresql et Nginx.
- **`Extraction des accès`** : le workflow extrait les mots de passe générés par le cluster (ex: `argocd-initial-admin-secret`) pour les afficher de manière sécurisée dans le **résumé GitHub**.

---

### 4. L'idempotence et le tracking
Pour garantir que le pipeline peut être relancé sans erreur :
- **Dry-Run & Apply** : `kubectl create ... --dry-run=client -o yaml | kubectl apply -f -`. Cette méthode permet de mettre à jour un secret (ex: changement de mot de passe dans GitHub) sans bloquer le pipeline avec une erreur "AlreadyExists".
- **Labels de tracking** : `app.kubernetes.io/instance=layer-01-init`. Ce label "fédère" les secrets créés par le script de CI au sein de la gestion GitOps d'Argo CD, empêchant leur suppression accidentelle.

---

### 5. Résumé du workflow des secrets
`GitHub` ➔ `Terraform (VMs)` ➔ `Ansible (K8s Setup)` ➔ `Kubectl (Cloud & Apps Secrets)` ➔ `Argo CD (Deployment)`