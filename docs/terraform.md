## Provisioning avec Terraform
Cette section détaille la première étape du workflow : la création de la couche d'infrastructure et sa gestion centralisée via un backend distant.

![Terraform Cloud](/img/terraform-cloud.png)
---

### 1. L'Infrastructure as Code (IaC)
L'**Infrastructure as Code** est une pratique DevOps qui consiste à gérer et provisionner l'infrastructure via du code plutôt que par des processus manuels. Elle permet de garantir que l'environnement est identique à chaque déploiement.

**Le concept de "State" (l'état)**
Pour fonctionner, Terraform a besoin de savoir ce qu'il a déjà créé. Il stocke cette "mémoire" dans un fichier nommé `terraform.tfstate`.

- **Le problème du local** : dans un pipeline CI/CD (GitHub Actions), le runner est détruit après chaque exécution. Si le fichier state reste sur le runner, il est perdu. Au prochain build, Terraform tentera de recréer des ressources déjà existantes, provoquant des doublons ou des erreurs.
- **La solution cloud** : déporter ce fichier sur un serveur distant pour garantir la persistance et permettre le travail collaboratif.

---

### 2. Configuration de Terraform Cloud

Terraform Cloud sert de **Remote Backend**. Il assure la persistance du State, le verrouillage des ressources (State Locking) et la sécurité des données d'infrastructure.

#### A. Initialisation de la plateforme
- **URL** : créer un compte sur https://app.terraform.io
- **Organisation** : créer une organisation
- **Workspace** : créer un nouveau Workspace de type **"CLI-driven workflow"**. Ce mode permet à GitHub Actions de piloter Terraform tout en déléguant la gestion du State au cloud.

#### B. Liaison dans le code (HCL)
Pour que Terraform communique avec le Terraform Cloud, ajoutez le bloc suivant dans le fichier `main.tf` :

```bash
terraform {
  cloud {
    organization = "VOTRE_NOM_D_ORGANISATION"
    workspaces {
      name = "NOM_DE_VOTRE_WORKSPACE"
    }
  }
}
```
#### C. Configuration des Secrets Cloud

Terraform Cloud doit être autorisé à agir sur le compte DigitalOcean.

- Dans le Workspace, aller dans **Variables**.
- Ajoutez une **Environment Variable** nommée TF_VAR_do_token.
- Collez votre token API DigitalOcean et cochez la case **"Sensitive"** pour le masquer.

---

### 3. Interaction avec GitHub Actions
Le pipeline GitHub Actions joue le rôle d'orchestrateur. Il commande à Terraform Cloud d'exécuter les modifications.

- **Token d'API** : dans Terraform Cloud (User Settings > Tokens), générer un token d'accès.
- **Secret GitHub** : sur votre dépôt GitHub, créer un secret nommé `TF_API_TOKEN` et collez-y ce jeton.
- **Exécution** : lors de l'étape `terraform apply`, le runner s'authentifie via ce token, envoie le code à Terraform Cloud, qui lui-même ordonne à DigitalOcean de créer les ressources.

---

### 4. Implémentation du Projet (DigitalOcean)
**Ressources créées**

- **DigitalOcean Droplets** : provisioning de nodes Ubuntu 24.04 (1 Master et X Workers).
- **Clés SSH** : injection de votre clé publique SSH pour permettre l'accès ultérieur par Ansible.

**Gestion des Variables et Secrets**
Pour des raisons de sécurité, aucune donnée sensible n'est écrite en dur dans les fichiers .tf.

- **Input Variables** : Le token DigitalOcean (`DO_TOKEN`) et le nom de la clé SSH sont passés via des variables d'environnement.
- **GitHub Integration** : Ces variables sont stockées dans les GitHub Secrets et injectées lors de l'exécution du workflow terraform apply.

**Transition vers la configuration (Outputs)**

À la fin du provisioning, Terraform expose des **Outputs** (notamment les adresses IP publiques). Ces données sont récupérées dynamiquement par GitHub Actions pour générer l'inventaire Ansible de l'étape suivante.

---

### 5. Workflow de Destruction (Cleanup)

Le cycle de vie se termine par la commande `terraform destroy`.

- **Rôle** : Terraform Cloud identifie toutes les ressources rattachées au State et demande leur suppression à DigitalOcean.
- **Point de vigilance** : Terraform ne peut détruire que ce qu'il a créé (les VMs). Les ressources générées dynamiquement par Kubernetes (loadBalancer et volumes via le CCM/CSI) doivent être supprimées via le workflow de nettoyage `kubectl` avant de lancer la destruction Terraform.

---

### 6. Utilisation
Ces commandes sont directement jouées par les workflow GitHub Actions, voici leur description :

| Secret | Description
|------------|------|
| **`terraform init`** | Initialise le projet et télécharge le provider DigitalOcean |
| **`terraform plan`** | Affiche les modifications qui seront apportées sans les exécuter  |
| **`terraform apply`** | Crée l'infrastructure sur DigitalOcean | 
| **`terraform destroy`** | Supprime l'intégralité de l'infrastructure gérée |
