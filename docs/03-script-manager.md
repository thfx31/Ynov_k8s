## Guide du Kubernetes Manager
Le script `k8s_manager.sh` est l'outil central de pilotage de la forge. Il permet d'automatiser l'installation des **composants** et le déploiement des **applications** sans manipulation manuelle complexe de fichiers YAML.

<p align="center">
  <img src="../img/script_manager.png" width="400" alt="Menu Manager">
</p>

### 1. Idempotence
Le manager est conçu pour être idempotent : chaque option peut être relancée plusieurs fois sans casser l'existant. Il assure la transition entre un cluster Kubernetes "nu" et une plateforme DevOps opérationnelle.

---

### 2. Structure du menu
Le menu est organisé en cinq sections logiques respectant l'ordre de déploiement :

#### A. Infrastructure
Cette section installe les composants du cluster :
- **CNI Calico** : configure le réseau interne entre les Pods
- **Storage CSI** : permet au cluster de commander dynamiquement des volumes de stockage (Block Storage) chez DigitalOcean
- **Bitnami Sealed Secrets** : permet au cluster de déchiffrer les secrets
- **Ingress Nginx** : expose le cluster sur internet. Le script inclut une boucle d'attente qui surveille l'attribution de l'IP publique par le Cloud Provider
- **Cert-Manager** : gère la demande et le renouvellement automatique des certificats SSL Let's Encrypt

#### B. Secrets
C'est ici que l'on configure la protection des données sensibles via Sealed Secrets :
- **Config DO API** : scelle votre token DigitalOcean pour que Cert-Manager puisse valider les domaines
- **Postgres Secrets** : lit votre fichier .env local, crée un secret Kubernetes puis le chiffre (scelle) dans un fichier YAML prêt pour Git
- **DockerHub Auth** : configure les identifiants nécessaires pour télécharger vos images privées depuis Docker Hub

#### C. Gestion de la forge
Cette section déploie les outils de développement :
- **Déploiement apps Forge** : orchestre la création du namespace, applique les secrets scellés, déploie Nginx, PostgreSQL, Gitea et Jenkins
- **Jenkins Password** : Affiche le mot de passe permettant d'initialiser Jenkins

#### D. Maintenance
Cette section permet la maintenance des déploiements
- **Check composants du cluster** : controle l'état de santé du cluster
- **Check état de la forge** : vérifie les objets nécessaires au fonctionnement de la forge (pod, ingress, etc.)

#### E. Danger Zone
Cette section permet de supprimer les objects du cluster
- **Suppression apps** : supprime tous les objets liés à la forge
- **Suppression cluster** : supprime tous les composants du cluster

---

### 3. Adaptable
Le script a été écrit avec des fonctions, ce qui permet de le personnaliser avec les composants dont on a besoin.
Il suffit d'écrire/modifier une fonction et d'adapter `main loop` et le `show_menu`
```bash
# CNI - Container Network Interface
install_cni() {
    echo ""
    info "Installation du CNI (Calico)"
    kubectl apply -f "$INFRA_DIR/cni-calico.yaml"
    log "Contrôleur Calico installé"
}
```