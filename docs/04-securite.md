# Sécurité & Automatisation des Certificats

Cette page détaille le fonctionnement interne des deux piliers de notre sécurité : Bitnami Sealed Secrets pour la protection des données sensibles et Cert-Manager pour l'automatisation du HTTPS.

## Schéma des Secrets
Le diagramme suivant montre la répartition des secrets (TLS, DB, Docker) dans le namespace de production :

![Sécurité et Secrets](../img/rt-secrets.png)
---

## 1. Bitnami Sealed Secrets (secrets persistants)

### Théorie
Le principe repose sur le chiffrement asymétrique (clé publique / clé privée)

- **La clé privée (le secret du cluster)** : elle est générée par le contrôleur sealed-secrets lors de son installation. Elle ne quitte jamais le cluster. Elle seule peut déchiffrer les données
- **La clé publique (l'outil du développeur)** : elle est accessible via l'utilitaire `kubeseal`. Elle permet de chiffrer (sceller) des données, mais elle ne permet pas de les lire

### Workflow
- **Chiffrement** : on prend un secret Kubernetes classique (en clair localement) et on le passe à `kubeseal`
- **Scellage** : `kubeseal` utilise la clé publique du cluster pour transformer ce secret en un objet de type SealedSecret (fichier YAML)
- **Stockage** : ce fichier YAML est chiffré. Même si un attaquant le lit sur GitHub, il ne peut rien en faire
- **Déchiffrement** : quand on applique ce fichier sur le cluster (kubectl apply), le contrôleur détecte l'objet, utilise sa clé privée pour le déchiffrer et crée instantanément un Secret Kubernetes standard dans le namespace cible

### Secret API DigitalOcean (DO_TOKEN)
- **Nature** : Token d'accès Cloud (Read/Write)
- **Méthode** : Saisi une seule fois lors de la configuration initiale
- **Flux** : Le token est chiffré par `kubeseal` et stocké dans `00-infra/sealed-secret-do.yaml`
- **Usage** : Permet à `cert-manager` de modifier vos DNS pour valider les certificats SSL

### Secret PostgreSQL (Base de données)
- **Nature** : Identifiants de la base de données de la Forge.
- **Méthode** : Lu automatiquement depuis le fichier local `.env`
- **Flux** : Génère un fichier `02-database/postgresql/sealed-secret-postgres.yaml`
- **Usage** : Injecté dans le Pod Postgres et les applications clientes (Gitea/Jenkins)

> Les fichiers `.yaml` commençant par `sealed-` sont chiffrés. Ils peuvent être poussés sur GitHub sans risque

---

## 2. Secrets interactifs (secrets de déploiement)

### Secret Docker Hub (Pull Secret)
- **Nature** : Identifiants de votre registre privé Docker Hub
- **Méthode** : Saisi via un prompt interactif lors du déploiement
- **Type** : `docker-registry` (Opaque)
- **Usage** : Permet à Kubernetes de s'authentifier auprès de Docker Hub pour télécharger vos images privées (`thfx31/ynov:...`)

---

## 3. Cert-Manager

### Théorie
**Cert-Manager** est un "opérateur" Kubernetes dont le rôle est de gérer le cycle de vie des certificats (création, renouvellement avant expiration).
Il utilise le protocole ACME (Automated Certificate Management Environment) pour communiquer avec une autorité de certification, principalement Let's Encrypt.

### La Pratique
Pour fonctionner, Cert-Manager a besoin d'un `Issuer` (ou `ClusterIssuer` s'il est disponible pour tout le cluster). C'est le fichier qui définit "qui" délivre le certificat et "comment" prouver que nous possédons bien le domaine.

Le fichier `cert-manager-issuer.yaml` contient deux informations importantes :
- **L'autorité** : L'URL de Let's Encrypt
- **Le Challenge (la preuve)** : pour obtenir un certificat, Let's Encrypt doit vérifier que l'on contrôle le domaine déclaré
    - **HTTP-01** : Cert-Manager crée un petit fichier temporaire sur le serveur web. Let's Encrypt tente de le lire via Internet. S'il y parvient, le domaine est validé
    - **DNS-01** (utilisé pour les wildcards ou si le port 80 est fermé) : Cert-Manager crée un enregistrement TXT temporaire dans le DNS DigitalOcean (via l'API Token que nous avons scellé). Let's Encrypt vérifie le DNS

### Cycle de vie d'un certificat dans la forge
- **Demande** : dans nos fichiers d'apps, nous ajoutons une annotation `cert-manager.io/cluster-issuer: letsencrypt-prod`
- **Création** : Cert-Manager voit cette annotation, crée un objet `Certificate` et lance le challenge
- **Réception** : une fois le challenge réussi, il récupère le certificat et le stocke dans un Secret Kubernetes (ex: `gitea-tls-secret`)
- **Utilisation** : l'Ingress Nginx utilise ce secret pour chiffrer la connexion
- **Renouvellement** : 30 jours avant l'expiration, Cert-Manager relance tout seul le processus