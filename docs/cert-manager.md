## Gestion des certificats avec Cert-Manager
Cette section explique comment le cluster automatise la génération et le renouvellement des certificats SSL/TLS pour sécuriser les accès à Jenkins, Gitea et à la page d'accueil.

---

### 1. L'automatisation du HTTPS
Dans une infrastructure moderne, gérer manuellement les certificats (achat, installation, renouvellement tous les 90 jours) est source d'erreurs et d'interruptions de service.
- **Cert-Manager** est un contrôleur Kubernetes qui automatise tout le cycle de vie des certificats.
- Il communique avec une autorité de certification (CA), dans notre cas Let's Encrypt, via le protocole ACME (Automated Certificate Management Environment).

**Le challenge HTTP-01**
Pour prouver à Let's Encrypt que nous possédons bien le domaine (ex: jenkins.yplank.fr), Cert-Manager utilise le challenge HTTP-01 :
- Let's Encrypt envoie un jeton.
- Cert-Manager crée un petit fichier temporaire sur notre serveur Nginx.
- Let's Encrypt vérifie la présence du fichier via internet.
- Si c'est validé, le certificat est délivré.

---

### 2. Implémentation dans le Cluster
**Installation (Layer-00)**
Cert-Manager est déployé dans la première couche d'Argo CD car tous les services supérieurs dépendent de lui pour le HTTPS.

**Composant : le ClusterIssuer**
C'est la ressource définissant "qui" délivre les certificats pour tout le cluster. Nous utilisons Let's Encrypt.
- **Configuration** : Il contient l'adresse email de contact (pour les alertes d'expiration) et l'URL du serveur ACME de Let's Encrypt.

**Composant : le Certificate**
Une fois l'Issuer prêt, Kubernetes crée des objets Certificate. Ces objets déclenchent la création de Secrets Kubernetes de type TLS contenant :
- La clé privée (`tls.key`)
- Le certificat public (`tls.crt`)

---

### 3. Intégration avec Ingress-Nginx
L'intégration fonctionne grâce aux annotations dans les fichiers Ingress des applications (Jenkins, Gitea, etc.).

Dans chaque fichier `ingress.yaml`, il suffit d'ajouter :

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod" # On pointe vers notre Issuer
spec:
  tls:
  - hosts:
    - jenkins.yourdomain.com
    secretName: jenkins-tls-secret # Nom du secret où Cert-Manager stockera le certif
```
&nbsp;

**Flux d'automatisation :**
- L'Ingress est déployé
- Cert-Manager voit l'annotation et demande un certificat
- Le challenge est résolu
- Le secret `jenkins-tls-secret` est créé
- Ingress-Nginx détecte le secret et active le HTTPS sur le port 443

---

### 4. Vérification et Maintenance

**Commandes utiles**
| Action | Commande
|------------|------|
| **Vérifier l'Issuer** | `kubectl get clusterissuer` |
| **Voir l'état des certificats** | `kubectl get certificate -n rt`  |
| **Suivre un challenge en cours** | `kubectl get challenges -n rt` | 

**Renouvellement automatique**
Let's Encrypt délivre des certificats valides **90 jours**. Cert-Manager est configuré pour les renouveler automatiquement environ **30 jours** avant leur expiration, sans aucune intervention manuelle.