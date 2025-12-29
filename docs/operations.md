## Opérations et maintenance du Cluster
Cette section explique comment gérer le cycle de vie du cluster une fois le déploiement initial terminé : mise à l'échelle, ajout de services et mises à jour de configuration.

---

### 1. Les Opérations de "Jour 2"
**Infrastructure immuable vs changements dynamiques**

Dans un modèle traditionnel, pour modifier un serveur, on s'y connecte en SSH. En GitOps****, on pratique l'**infrastructure immuable** au niveau des nodes, mais dynamique au niveau des applications :
- **Dérive (Drift)** : c'est l'écart entre ce qui est écrit dans Git et ce qui tourne réellement.
- **Réconciliation** : c'est le processus par lequel Argo CD détecte une modification dans Git et l'applique au cluster pour supprimer la dérive.

**Le cycle de modification**
Le flux de travail pour toute modification suit systématiquement ce schéma : `Modification du Code (Git)` ➔ `Commit / Push` ➔ `Détection Argo CD` ➔ `Application (Sync)` ➔ `Vérification`

---

### 2. Mise à l'échelle (Scaling)
Le scaling consiste à ajuster les ressources pour répondre à la charge. Grâce à Kubernetes, cela se fait en modifiant une seule ligne de code.

**Scaling des Replicas**
Pour augmenter le nombre d'instances de Jenkins ou de Nginx-Front :
- Allez dans le dossier `k8s/03-apps/`
- Ouvrez le fichier YAML du déploiement, par exemple`jenkins.yaml`
- Modifiez la valeur `replicas: 1` par `replicas: 3`.
- Pushez sur GitHub.
- Argo CD détecte le changement et demande à Kubernetes de créer 2 nouveaux Pods.

**Ressources CPU/RAM**
De la même manière, on ajuste les `resources.limits` et `resources.requests` dans les manifests pour garantir les performances sans gaspiller les ressources des Droplets DigitalOcean.

---

### 3. Ajout d'une nouvelle application
Pour ajouter un nouvel outil comme du monitoring ou un micro-service : 
- **Manifests** : créer un nouveau fichier YAML dans `k8s/03-apps/mon-app.yaml`.
- **Référencement** : s'assurer que le dossier `k8s/03-apps/` est bien scanné par l'application layer-03-apps dans Argo CD.
- **Secrets (si besoin)** : si l'app nécessite un mot de passe, l'ajouter dans GitHub Secrets et vérifier que le workflow `infra-secrets` (Job 3) crée le secret K8s correspondant avec le bon label de tracking.
- **Validation** : une fois le push effectué, surveiller l'interface Argo CD pour voir l'application apparaître et passer au vert.

---

### 4. Maintenance
Même avec Argo CD, il est parfois nécessaire d'inspecter manuellement l'état pour comprendre un échec de déploiement.

**Commandes utiles via la CLI**
Puisque le pipeline GitHub Actions fournit le `kubeconfig.yaml` en artefact, vous pouvez l'utiliser sur votre machine locale en le copiant dans `~/.kube/***`

| Action | Commande
|------------|------|
| **Vérifier l'état des nodes** | `kubectl get nodes -A` |
| **Vérifier l'état des pods** | `kubectl get pods -n rt` |
| **Consulter les logs** | `kubectl logs -l app=gitea -n rt`  |
| **Décrire une erreur** | `kubectl describe pod <nom-du-pod> -n rt` | 
| **Accès temporaire** | `kubectl port-forward svc/jenkins-svc 8080:80 -n rt` |

---

### 5. Troubleshooting : problème de téléchargement d'images
Si un Pod affiche un statut `ImagePullBackOff` ou `ErrImagePull`, suivez ces étapes pour diagnostiquer si le problème vient du mécanisme de `ServiceAccount Patch` ou des identifiants eux-mêmes.

**Vérification de l'injection du secret**
La première chose à vérifier est de savoir si Kubernetes a bien "injecté" le secret dans le Pod au moment de sa création.

```bash
kubectl get pod <nom-du-pod> -n rt -o jsonpath='{.spec.imagePullSecrets}'
```
- **Résultat attendu** : `[{"name":"dockerhub-auth-secret"}]`
- **Si vide** `[]` : le Pod a été créé avant l'application du patch ou le `ServiceAccount` n'est pas correctement configuré
- **Action** : redémarrez le déploiement (`kubectl rollout restart deployment <nom> -n rt`) pour forcer la création d'un nouveau Pod qui bénéficiera de l'injection


**Vérification de l'état du Secret**
Si le secret est bien présent dans le Pod mais que l'image ne descend pas, vérifiez que le secret lui-même existe dans le bon namespace.
```bash
kubectl get secret dockerhub-auth-secret -n rt
```
- **Si absent** : relancez le workflow GitHub Actions (Job 3) ou recréez le secret manuellement
- **Note** : le secret doit impérativement se trouver dans le **même namespace** que le Pod pour être utilisé

**Test de validité des identifiants**
Il est possible que le token Docker Hub ait expiré ou soit erroné. Pour tester les identifiants stockés dans le cluster :

- Récupérez le contenu du secret (encodé en base64) :
```bash
kubectl get secret dockerhub-auth-secret -n rt -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d
```
- Vérifiez que le JSON affiché contient bien vos identifiants valides

**Analyse des événements du Pod**
Pour obtenir le message d'erreur exact renvoyé par le registre (ex: *Unauthorized*, *Manifest not found*, *Rate limit exceeded*), consultez les logs système du cluster.
```bash
kubectl describe pod <nom-du-pod> -n rt
```
Regarder la section Events tout en bas et Chercher les lignes de type `Warning Failed`.

| Erreur | Cause probable | Résolution
|------------|------|------|
| **`Unauthorized`** |Token Docker Hub expiré ou erroné | Mettre à jour le secret GitHub `DOCKER_PASSWORD` |
| **`Forbidden`** | Le Pod tente d'accéder à un repo privé non autorisé | Vérifier les droits du compte Docker Hub  |
| **`Not Found`** |Erreur de frappe dans le nom de l'image ou tag inexistant | Vérifier le champ `image:` dans le Deployment |
| **`imagePullSecrets`** | ServiceAccount non patché au moment du spawn | Relancer le rollout du déploiement |

---


### 5. Pruning (Nettoyage Automatique)
Une fonction clé de notre configuration Argo CD est le Pruning.
- Si l'on supprime un fichier YAML du dépôt Git, Argo CD comprend que cette ressource ne doit plus exister.
- Il va alors supprimer proprement les objets correspondants dans Kubernetes (Pods, Services, Ingress).
- **Attention** : les volumes persistants (PVC) sont souvent configurés pour être conservés même après suppression du pod pour éviter la perte de données (Gitea/Postgres).
