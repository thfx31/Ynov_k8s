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

### 4. Maintenance et troubleshooting
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

### 5. Pruning (Nettoyage Automatique)
Une fonction clé de notre configuration Argo CD est le Pruning.
- Si l'on supprime un fichier YAML du dépôt Git, Argo CD comprend que cette ressource ne doit plus exister.
- Il va alors supprimer proprement les objets correspondants dans Kubernetes (Pods, Services, Ingress).
- **Attention** : les volumes persistants (PVC) sont souvent configurés pour être conservés même après suppression du pod pour éviter la perte de données (Gitea/Postgres).
