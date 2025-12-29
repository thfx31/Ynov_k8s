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

---

### 5. Troubleshooting
Il arrive que les certificats restent bloqués en état `False` ou `Pending`. Voici comment diagnostiquer et résoudre les blocages liés au DNS ou aux conflits internes.

#### A. Identifier le blocage

Si la commande `kubectl get certificate -n rt` affiche `READY: False` pendant plus de 10 minutes, il faut descendre dans la pile des ressources ACME :

**Vérifier l'état des challenges**
```bash
kubectl get challenges -n rt

NAME                                         STATE     DOMAIN              AGE
forge-tls-secret-1-3776914928-3521478564     pending   forge.yplank.fr     2m55s
gitea-tls-secret-1-449151209-2789355816      pending   gitea.yplank.fr     2m57s
jenkins-tls-secret-1-3563542937-2321201427   pending   jenkins.yplank.fr   2m52s
```


**Analyser l'erreur précise sur un challenge**
```bash
kubectl describe challenge jenkins-tls-secret-1-3563542937-2321201427 -n rt
...
Events:
  Type     Reason        Age   From                     Message
  ----     ------        ----  ----                     -------
  Normal   Started       33m   cert-manager-challenges  Challenge scheduled for processing
  Warning  PresentError  33m   cert-manager-challenges  Error presenting challenge: Internal error occurred: failed calling webhook "validate.nginx.ingress.kubernetes.io": failed to call webhook: Post "https://ingress-nginx-controller-admission.ingress-nginx.svc:443/networking/v1/ingresses?timeout=29s": dial tcp 10.96.3.248:443: connect: connection refused
  Normal   Presented     33m   cert-manager-challenges  Presented challenge using HTTP-01 challenge mechanism
```

&nbsp;
#### B. Incident 1 : blocage par le Webhook d'Admission Nginx
**Symptôme** : l'erreur dans le challenge indique : `failed calling webhook "validate.nginx.ingress.kubernetes.io": connection refused`
- **Cause** : le contrôleur Ingress-Nginx possède un "validateur" interne (Admission Webhook) qui empêche Cert-Manager de créer l'Ingress temporaire nécessaire pour le challenge ACME
- **Correction** : supprimer la configuration de validation qui bloque les requêtes :

```bash
kubectl delete validatingwebhookconfigurations ingress-nginx-admission
```

&nbsp;
#### C. Incident 2 : propagation DNS et cache

**Symptôme** : le challenge reste en `pending` et le "self-check" de Cert-Manager affiche une ancienne adresse IP au lieu de la nouvelle IP du LoadBalancer
**Cause** : Les enregistrements DNS n'ont pas fini de se propager ou Cert-Manager a mis en cache l'ancienne résolution DNS.
**Correction** : forcer le rafraîchissement du cache DNS de Cert-Manager :
```bash
kubectl rollout restart deployment cert-manager -n cert-manager
```

&nbsp;
#### D. Procédure de "Reset" Global (Clean Slate)
Si les DNS sont corrects mais que le challenge reste bloqué en "Backoff" (attente exponentielle), voici la procédure pour forcer une nouvelle tentative immédiate :

**Nettoyer les ressources en échec :**
```bash
kubectl delete challenges --all -n rt
kubectl delete orders --all -n rt
```

**Supprimer les secrets TLS corrompus  ou incomplets**

```bash
kubectl delete secret <nom-du-secret> -n rt
```

**Vider le cache DNS en redémarrant le controlleur Cert-Manager :**
```bash
kubectl rollout restart deployment cert-manager -n cert-manager
```

**Relancer la synchronisation Argo CD**
Via l'interface d'Argo CD : Sync + Prune