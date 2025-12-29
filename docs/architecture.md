## Architecture du cluster & composants Kubernetes
Cette section décrit la structure logique et technique du cluster Kubernetes auto-géré, ainsi que les composants essentiels qui permettent l'exécution de la Forge DevOps sur DigitalOcean.

---

### 1. Fonctionnement de Kubernetes
Kubernetes (K8s) est un orchestrateur de conteneurs basée sur une architecture Control Plane / Workers.

**Le Control Plane**
Il prend les décisions pour le cluster et détecte/répond aux événements. Ses composants sont :
- **API Server** : le point d'entrée unique pour toutes les commandes (kubectl, Argo CD)
- **etcd** : la base de données clé-valeur du cluster qui stocke toute la configuration (état souhaité)
- **Scheduler** : il décide sur quel nœud Worker un nouveau Pod doit être lancé
- **Controller Manager** : il veille à ce que l'état réel corresponde à l'état souhaité (par exemple s'assurer qu'il y a bien 3 replicas)

**Les Worker Nodes**
Ce sont les machines qui font tourner les applications. Elles contiennent :
- **Kubelet** : l'agent qui s'assure que les conteneurs tournent dans les Pods
- **Kube-proxy** : gère les règles réseau pour permettre la communication entre services
- **Container Runtime (Containerd)** : le moteur qui lance réellement les conteneurs

---

### 2. Architecture du projet
Notre cluster est une installation **Self-Managed** (via `kubeadm`) sur des instances **DigitalOcean Droplets (Ubuntu 24.04)**. Contrairement à une offre managée (DOKS), nous maîtrisons l'intégralité de la configuration.

**Composants d'intégration Cloud**
Pour que Kubernetes puisse interagir avec les ressources de DigitalOcean, nous installons deux briques obligatoires :
- **CCM (Cloud Controller Manager)** : il fait le lien entre l'API K8s et l'API DigitalOcean. C'est lui qui crée un LoadBalancer externe dès qu'un service Ingress est déclaré.
- **CSI (Container Storage Interface)** : il permet de monter des Volumes Block Storage DigitalOcean sur les Pods PostgreSQL, Jenkins ou Gitea pour garantir que les données ne sont pas perdues si un Pod redémarre.

**Réseau et connectivité**
- **CNI (Calico)** : nous utilisons Calico pour gérer le réseau interne. Il attribue une adresse IP unique à chaque Pod et gère le routage entre les différents nodes du cluster.
- **Ingress Controller (Nginx)** : il sert de point d'entrée unique (port 80/443). Il reçoit le trafic depuis le LoadBalancer DigitalOcean et le redirige vers les services de la Forge (Jenkins, Gitea) en fonction du nom de domaine.

---

### 3. Organisation des Ressources (Namespaces)
Pour éviter les conflits et organiser la sécurité, le cluster est découpé en Namespaces :
- `kube-system` : composants internes de Kubernetes, CCM et CSI
- `argocd` : l'instance d'Argo CD qui pilote le déploiement GitOps
- `ingress-nginx` : le contrôleur d'entrée du cluster
- `rt` : notre namespace applicatif principal contenant la Forge (Jenkins, Gitea, Postgres, Nginx-Front)

---

### 4. Accès au Registry Docker avec ServiceAccount Patch
Pour simplifier le déploiement des applications, nous utilisons une méthode de "patch" sur le compte de service (`ServiceAccount`) par défaut du namespace `rt`.
- **Fichier** : `k8s/01-initialisation/sa-patch.yaml`
- **Rôle** : ce fichier injecte de manière permanente le secret `dockerhub-auth-secret` dans la configuration du `ServiceAccount` par défaut.
- **Avantage** : Kubernetes utilise le compte de service par défaut pour lancer les Pods. En y associant le secret d'authentification, tous les Pods du namespace héritent automatiquement de la capacité à télécharger des images privées depuis Docker Hub. Cela évite de devoir déclarer manuellement la section `imagePullSecrets` dans chaque fichier `deployment.yaml` de l'application, réduisant ainsi les risques d'erreur et la duplication de code.

---

### 5. Flux de données applicatif
- **Requête utilisateur** : l'utilisateur accède à `https://jenkins.yplank.fr`
- **LoadBalancer DO** : reçoit la requête et l'envoie vers l'un des nœuds du cluster
- **Ingress Nginx** : analyse le nom de domaine et redirige le flux vers le Service Jenkins
- **Pod Jenkins** : traite la requête. Si des données doivent être sauvegardées, elles sont écrites sur le volume persistant géré par le CSI
