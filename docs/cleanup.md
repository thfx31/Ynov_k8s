## Stratégie de nettoyage et gestion des coûts
Cette section détaille le workflow de destruction de l'infrastructure et la méthodologie utilisée pour garantir qu'aucune ressource facturable ne reste active sur DigitalOcean après la fin du projet.

---

### 1. Ressources orphelines
Dans un environnement Kubernetes "Self-Managed" intégré au Cloud (via CCM et CSI), Terraform ne connaît pas toutes les ressources :
- **Ressources Terraform** : les Droplets (VMs) et éventuellement un VPN custom. Terraform les a créés, il peut les détruire.
- **Ressources Kubernetes** : lorsque l'on déploie un service de type LoadBalancer ou un PersistentVolumeClaim (PVC), c'est Kubernetes qui demande directement à DigitalOcean de créer un LoadBalancer ou un Volume SSD.
- **Le risque** : si on lance terraform destroy en premier, les VMs sont supprimées, mais Kubernetes n'a pas le temps de dire au Cloud de supprimer les disques et les équilibreurs de charge. Ces ressources restent actives et continuent d'être facturées par DigitalOcean.

---

### 2. Stratégie de destruction ordonnée
Pour éviter ce scénario, nous avons mis en place un workflow de nettoyage (`k8s-cleanup.yml`) qui suit un ordre strict de dépendances :

### A. Nettoyage des objets Kubernetes
Avant de toucher à l'infrastructure, le pipeline se connecte au cluster et supprime les objets qui créent des coûts Cloud :
- **Services LoadBalancer** : libération des adresses IP publiques et des instances de LoadBalancer DigitalOcean.
- **PVC (Persistent Volume Claims)** : libération des volumes de stockage SSD associés à Gitea et PostgreSQL.

### B. Nettoyage Terraform
Une fois que le cluster Kubernetes est "vide" de ses ressources cloud, nous pouvons détruire les fondations :
- Suppression des Droplets (Master & Workers)
- Suppression du VPC (si VPN custom crée)
- Nettoyage du "State" sur Terraform Cloud

---

### 3. Implémentation dans le Workflow GitHub
Le workflow de nettoyage utilise les mécanismes suivants pour fonctionner même si le cluster est déja détruit :
- **Récupération du Kubeconfig** : le workflow télécharge l'artefact cluster-kubeconfig généré lors du déploiement pour pouvoir s'authentifier une dernière fois auprès du cluster.
- **Commande de suppression globale** : `kubectl delete namespace rt --wait=true`
> L'utilisation de `--wait=true` force le pipeline à attendre que DigitalOcean ait réellement confirmé la suppression physique des volumes et des LoadBalancers avant de passer à la suite.
- **Destruction Terraform** : Le runner utilise le `TF_API_TOKEN` pour demander à Terraform Cloud d'exécuter un apply avec une intention de destruction.

---

### 4. Comment détruire proprement ?
Ne jamais supprimer les VMs manuellement depuis l'interface DigitalOcean. Utiliser le workflow dédié :
- Aller dans l'onglet "Actions" du dépôt GitHub.
- Sélectionner le workflow "Kubernetes platform cleanup".
- Lancez le workflow sur la branche `main`.
- Surveillez le résumé (Step Summary) pour confirmer que :
    - Les services Kubernetes ont été supprimés
    - Le `terraform destroy` s'est terminé avec succès