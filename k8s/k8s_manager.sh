#!/bin/bash

# ==============================================================================
# 1. CONFIGURATION ET VARIABLES GLOBAL
# ==============================================================================
INFRA_DIR="00-infra"
KUBE_NS="kube-system"
FORGE_NS="rt"
DOMAIN="yplank.fr"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# ==============================================================================
# 2. FONCTIONS UTILITAIRES (affichage + logs + vérifications)
# ==============================================================================
log() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERR]${NC} $1"; }
info() { echo -e "${CYAN}>> $1${NC}"; }
header() { 
    echo ""
    echo -e "${BLUE}----------------------------------${NC}"
    echo -e "${WHITE}   $1${NC}"
    echo -e "${BLUE}----------------------------------${NC}"
}

# Vérification prérequis
check_prereqs() {
    local missing=0
    for cmd in kubectl kubeseal helm; do
        if ! command -v $cmd &> /dev/null; then
            error "$cmd n'est pas installé."
            missing=1
        fi
    done
    
    # Vérification des fichiers indispensables
    for file in "$INFRA_DIR/cni-calico.yaml" "$INFRA_DIR/ccm-do.yaml" "$INFRA_DIR/cert-manager-issuer.yaml" "$INFRA_DIR/cert-manager.yaml"; do
        if [ ! -f "$file" ]; then
            error "Fichier manquant : $file"
            missing=1
        fi
    done

    if [ ! -d "$INFRA_DIR" ]; then
        error "Le dossier $INFRA_DIR n'existe pas."
        missing=1
    fi

    if [ $missing -eq 1 ]; then exit 1; fi
}

# ==============================================================================
# 3. INSTALLATION DES COMPOSANTS ET CREATION DES SECRETS
# ==============================================================================


# --- RESEAU ET INFRA CORE ---

# CNI - Container Network Interface
install_cni() {
    echo ""
    info "Installation du CNI (Calico)"
    kubectl apply -f "$INFRA_DIR/cni-calico.yaml"
    log "Contrôleur Calico installé"
}

# CCM - Cloud Controller Manager
install_ccm() {
    echo ""
    info "Installation du Cloud Controller Manager"
    kubectl apply -f "$INFRA_DIR/ccm-do.yaml"
    log "Cloud Controller Manager installé"
}

# CSI - Container Storage Interface
install_csi() {
    echo ""
    info "Installation du CSI (Stockage)"
    log "Application des CRDs"
    kubectl apply -f "$INFRA_DIR/csi-crds-do.yaml"
    
    log "Attente des CRDs"
    kubectl wait --for=condition=established --timeout=60s crd/volumesnapshotclasses.snapshot.storage.k8s.io || true
    
    log "Application du driver CSI"
    kubectl apply -f "$INFRA_DIR/csi-driver-do.yaml"
    log "Drivers CSI installés"
}

# INGRESS Controller
install_ingress() {
    echo ""
    info "Installation de l'Ingress Nginx"
    kubectl apply -f "$INFRA_DIR/ingress-nginx.yaml"
    
    echo -e "${YELLOW}Attente de l'IP LoadBalancer... (cela peut prendre 1 à 2 min)...${NC}"
     
    # Boucle infinie qui vérifie l'IP toutes les 5 secondes
    LB_IP=""
    while [ -z "$LB_IP" ]; do
        # On essaie de récupérer l'IP
        LB_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        
        # Si pas d'IP, on affiche un point et on attend
        if [ -z "$LB_IP" ]; then
            echo -ne "."
            sleep 5
        fi
    done
    
    echo ""
    log "IP PUBLIQUE ATTRIBUÉE !"
    echo -e "${WHITE}Adresse du LoadBalancer : ${GREEN}$LB_IP${NC}"
    echo ""
}

# TLS Certificate
install_cert_manager() {
    echo ""
    info "Application des manifestes Cert-Manager"
    kubectl apply -f "$INFRA_DIR/cert-manager.yaml"
    
    echo ""
    info "Attente du déploiement (cela peut prendre 1 à 2 min)..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s
    
    echo ""
    info "Configuration de l'Issuer Let's Encrypt..."
    kubectl apply -f "$INFRA_DIR/cert-manager-issuer.yaml"
    log "Cert-Manager est prêt"
}

# Sealed Secrets Controller
install_sealed_controller() {
    echo ""
    info "Installation de Sealed Secrets via Helm..."
    helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
    helm repo update

    helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
        --namespace "$KUBE_NS" \
        --set-string fullnameOverride=sealed-secrets-controller \
        --set tolerations[0].key="node.cloudprovider.kubernetes.io/uninitialized" \
        --set-string tolerations[0].value="true" \
        --set tolerations[0].effect="NoSchedule" \
        --wait
    log "Contrôleur Sealed Secrets installé"
}

# --- SECRETS ---

# Digitalocean secret
setup_do_secret() {
    echo ""
    info "Configuration du secret Digital Ocean"
    
    if [ -f "$INFRA_DIR/sealed-secret-do.yaml" ]; then
        log "Fichier chiffré existant trouvé."
        kubectl apply -f "$INFRA_DIR/sealed-secret-do.yaml"
        return
    fi

    echo -e "${YELLOW}Token Digital Ocean requis (RW)${NC}"
    read -s -p "Token: " DO_TOKEN
    echo "" 

    kubectl create secret generic digitalocean \
        --namespace "$KUBE_NS" \
        --from-literal=access-token="$DO_TOKEN" \
        --dry-run=client -o yaml > secret-tmp.yaml

    kubeseal --controller-namespace $KUBE_NS \
             --controller-name sealed-secrets-controller \
             --format=yaml < secret-tmp.yaml > "$INFRA_DIR/sealed-secret-do.yaml"
             
    kubectl apply -f "$INFRA_DIR/sealed-secret-do.yaml"
    rm secret-tmp.yaml
    
    kubectl delete pod -n $KUBE_NS -l k8s-app=digitalocean-cloud-controller-manager --ignore-not-found
    log "Secret Digital Ocean configuré"
}

# Postgresql secret
setup_db_secrets() {
    echo ""
    info "Configuration des secrets PostgreSQL"
    
    # Vérification du fichier .env
    if [ -f ".env" ]; then
        echo "Chargement des identifiants depuis le fichier .env"
        # On utilise 'export' pour s'assurer que les variables sont visibles
        export $(grep -v '^#' .env | xargs)
    else
        error "Erreur : Le fichier .env est introuvable à la racine du projet"
        echo -e "${YELLOW}Conseil : Copiez .env.example vers .env et remplissez les valeurs.${NC}"
        return 1
    fi

    # Recherche d'éventuelles variables vides
    if [[ -z "$DB_PASSWORD" || -z "$DB_USER" || -z "$DB_NAME" ]]; then
        error "Erreur : Une ou plusieurs variables (DB_PASSWORD, DB_USER, DB_NAME) sont vides dans le .env"
        return 1
    fi

    # Nettoyage de l'ancien secret scellé s'il existe (pour éviter les conflits)
    if [ -f "02-database/postgresql/sealed-postgres-secret.yaml" ]; then
        rm "02-database/postgresql/sealed-postgres-secret.yaml"
    fi

    # Génération et scellage immédiat via kubeseal
    # On utilise 'dry-run' pour que le secret ne soit jamais créé en clair sur le cluster
    echo ""
    info "Génération du SealedSecret PostgresQL"
    kubectl create secret generic postgres-secret \
      --namespace "$FORGE_NS" \
      --from-literal=postgres-password="$DB_PASSWORD" \
      --from-literal=postgres-user="$DB_USER" \
      --from-literal=postgres-db="$DB_NAME" \
      --dry-run=client -o yaml | \
    kubeseal --controller-namespace "$KUBE_NS" \
             --controller-name sealed-secrets-controller \
             --format=yaml > 02-database/postgresql/sealed-secret-postgres.yaml

    if [ $? -eq 0 ]; then
        log "Secret PostgreSQL scellé avec succès"
    else
        error "Erreur lors du scellage du secret avec kubeseal"
        return 1
    fi
}

# Docker Hub secret
setup_docker_secret() {
info "Vérification des accès Docker Hub"

if kubectl get secret dockerhub-auth-secret -n "$FORGE_NS" > /dev/null 2>&1; then
    log "Secret 'dockerhub-auth-secret' déjà présent"
    read -p "Voulez-vous le recréer ? (y/n) : " confirm
    [[ "$confirm" != "y" ]] && return
    kubectl delete secret dockerhub-auth-secret -n "$FORGE_NS"
fi

info "Création du secret d'authentification Docker Hub"
read -p "User Docker Hub : " DOCKER_USER
read -s -p "Password/Token : " DOCKER_PASS
echo ""

kubectl create secret docker-registry dockerhub-auth-secret \
    --docker-server=https://index.docker.io/v1/ \
    --docker-username="$DOCKER_USER" \
    --docker-password="$DOCKER_PASS" \
    --namespace="$FORGE_NS"
    
log "Secret 'dockerhub-auth-secret' créé avec succès"
}

# ==============================================================================
# 4. FONCTIONS DE WORKFLOW (Orchestration)
# ==============================================================================

# Install de l'infra K8S
install_full_infra() {
    install_cni
    install_ccm
    install_csi
    install_sealed_controller
    install_ingress
    install_cert_manager
}

# Install des applications
install_apps() {
    header "DÉPLOIEMENT DE LA FORGE CI/CD"

    # Namespace
    echo ""
    info "Vérification du namespace $FORGE_NS"
    if ! kubectl get namespace "$FORGE_NS" > /dev/null 2>&1; then
        echo -e "${YELLOW}Création du namespace $FORGE_NS${NC}"
        kubectl apply -f 01-initialisation/namespace.yaml
        log "Namespace $FORGE_NS créé"
    else
        log "Namespace $FORGE_NS déjà présent"
    fi
    
    # Secret PostgresQL : génère le fichier yaml scellé via le .env    
    setup_db_secrets    
    echo ""
    info "Création du secret sealed secret PostgreSQL"
    kubectl apply -f 02-database/postgresql/sealed-secret-postgres.yaml
    log "Secret PostgreSQL appliqué"

    # Secret Docker Hub
    setup_docker_secret  


    # IP check
    LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [ -z "$LB_IP" ]; then
        error "Ingress IP introuvable. L'Ingress est-il prêt ?"
        return 1
    fi
    echo ""
    info "Vérification de l'IP du LoadBalancer"
    log "IP Cluster détectée : $LB_IP"

    # Install PostgreSQL, Jenkins, Gitea et Nginx
    echo ""
    info "Déploiement de la base de données Postgresql"
    kubectl apply -f 02-database/postgresql/

    echo ""
    info "Déploiement des services Nginx, Jenkins et Gitea"
    find 03-apps -name "*.yaml" | while read file; do
        # On affiche la sortie de kubectl apply
        sed "s/IP_LB_PLACEHOLDER/$DOMAIN/g" "$file" | kubectl apply -f -
    done
    
    echo ""
    echo -e "${GREEN}ACCÈS APPLICATIONS :${NC}"
    echo -e "  - Forge   : https://forge.${DOMAIN}"
    echo -e "  - Jenkins : https://jenkins.${DOMAIN}"
    echo -e "  - Gitea   : https://gitea.${DOMAIN}"
}

# Affichage du password admin Jenkins après la création du pod
show_jenkins_password() {
    echo ""
    info "Récupération mot de passe Jenkins"
    
    if ! kubectl get pod -n "$FORGE_NS" -l app=jenkins --no-headers > /dev/null 2>&1; then
        warn "Pod Jenkins introuvable. Est-il installé ?"
        return
    fi

    echo -e "Initialisation de l'instance Jenkins"
    kubectl wait --for=condition=ready pod -l app=jenkins -n "$FORGE_NS" --timeout=300s
    sleep 10

    POD_NAME=$(kubectl get pod -n "$FORGE_NS" -l app=jenkins -o jsonpath='{.items[0].metadata.name}')
    
    PASSWORD=$(kubectl exec -n "$FORGE_NS" "$POD_NAME" -- cat /var/jenkins_home/secrets/initialAdminPassword)

    if [ -n "$PASSWORD" ]; then
        echo ""
        echo -e "${WHITE}JENKINS ADMIN PASSWORD :${NC}"
        echo -e "${CYAN}----------------------------------------${NC}"
        echo -e "${GREEN}$PASSWORD${NC}"
        echo -e "${CYAN}----------------------------------------${NC}"
        echo ""
    else
        error "Mot de passe indisponible (Jenkins initialise encore ?)"
    fi
}

# ==============================================================================
# 5. MAINTENANCE
# ==============================================================================

check_cluster_status() {
    header "ÉTAT DU CLUSTER"
    
    printf "${WHITE}%-25s${NC} : " "CNI (Calico)"
    if kubectl get pods -n "$KUBE_NS" -l k8s-app=calico-node --no-headers 2>/dev/null | grep -q "Running"; then
        echo -e "${GREEN}Running${NC}"
    else
        echo -e "${RED}Not Found / Error${NC}"
    fi

    printf "${WHITE}%-25s${NC} : " "Sealed Secrets"
    if kubectl get pods -n "$KUBE_NS" -l app.kubernetes.io/name=sealed-secrets --no-headers 2>/dev/null | grep -q "Running"; then
        echo -e "${GREEN}Running${NC}"
    else
        echo -e "${RED}Not Found / Error${NC}"
    fi

    printf "${WHITE}%-25s${NC} : " "Cloud Controller"
    if kubectl get pods -n "$KUBE_NS" -l app=digitalocean-cloud-controller-manager --no-headers 2>/dev/null | grep -q "Running"; then
        echo -e "${GREEN}Running${NC}"
    else
        echo -e "${RED}Not Found${NC}"
    fi

    printf "${WHITE}%-25s${NC} : " "Storage Class (CSI)"
    if kubectl get sc --no-headers 2>/dev/null | grep -q "do-block-storage"; then
        echo -e "${GREEN}Active${NC}"
    else
        echo -e "${RED}Missing${NC}"
    fi

    printf "${WHITE}%-25s${NC} : " "Ingress Controller"
    INGRESS_IP=$(kubectl get svc -n ingress-nginx -o jsonpath='{.items[*].status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    if [ -n "$INGRESS_IP" ]; then
        echo -e "${GREEN}Ready ($INGRESS_IP)${NC}"
    else
        echo -e "${YELLOW}Pending IP${NC}"
    fi

    printf "${WHITE}%-25s${NC} : " "Cert Manager"
    CERT_MANAGER_NS="cert-manager"
    if kubectl get pods -n "$CERT_MANAGER_NS" -l app.kubernetes.io/name=cert-manager --no-headers 2>/dev/null | grep -q "Running"; then
        echo -e "${GREEN}Running${NC}"
    else
        echo -e "${RED}Not Found / Error${NC}"
    fi
}

check_forge_status() {
    header "ETAT DE LA FORGE"

    # Santé des nodes
    info "--- Etat des nodes ---"
    kubectl get nodes
    echo ""

    # Etat des pods dans le namespace de la Forge
    info "--- Pods dans le namespace $FORGE_NS ---"
    kubectl get pods -n "$FORGE_NS" -o wide
    echo ""

    # Etat des services
    info "--- Services ---"
    kubectl get services -n "$FORGE_NS"
    echo ""

    # Etat des déploiements
    info "--- Déploiements ---"
    kubectl get deploy -n "$FORGE_NS"
    echo ""    

    # Etat des replicasets
    info "--- Replicasets ---"
    kubectl get services -n "$FORGE_NS"
    echo ""

    # Etat des PVC
    info "--- PVC ---"
    kubectl get pvc -n "$FORGE_NS"
    echo ""    

    #  Etat des accès réseau (Ingress)
    info "--- Routes Ingress & IPs ---"
    kubectl get ingress -n "$FORGE_NS"
    echo ""

    # Etat des certificats SSL
    info "--- Certificats SSL (Cert-Manager) ---"
    kubectl get certificate -n "$FORGE_NS"
    
    echo -e "\n${CYAN}Astuce :${NC} Si un certificat est à 'READY: False', vérifiez les logs de cert-manager."
}


# ==============================================================================
# 6. DANGER ZONE
# ==============================================================================

# Suppression des composants du cluster
destroy_infra() {
    header "DESTRUCTION INFRASTRUCTURE"
    echo -e "${RED}!!! ATTENTION : ACTION IRRÉVERSIBLE !!!${NC}"
    echo "Cela détruira TOUT le cluster (LoadBalancer, Volumes, Réseau)."
    
    echo -e "${RED}Écrivez 'destroy' pour confirmer : ${NC}\c"
    read confirm

    if [ "$confirm" != "destroy" ]; then echo "Annulé."; return; fi

    echo ""
    info "Nettoyage Ingress"
    kubectl delete -f "$INFRA_DIR/ingress-nginx.yaml" --ignore-not-found
    
    echo ""
    info "Nettoyage Storage (CSI)"
    kubectl delete -f "$INFRA_DIR/csi-driver-do.yaml" --ignore-not-found
    kubectl delete -f "$INFRA_DIR/csi-crds-do.yaml" --ignore-not-found
    
    echo ""
    info "Nettoyage Cloud Controller (CCM)"
    kubectl delete -f "$INFRA_DIR/ccm-do.yaml" --ignore-not-found
    
    echo ""
    info "Nettoyage Secrets"
    helm uninstall sealed-secrets -n "$KUBE_NS" --ignore-not-found
    
    read -p "Supprimer le fichier local 'sealed-secret-do.yaml' ? (o/n) " del_local
    if [[ "$del_local" =~ ^[oO]$ ]]; then
        rm -f "$INFRA_DIR/sealed-secret-do.yaml"
        log "Fichier secret local supprimé"
    fi

    echo ""
    info "Nettoyage Réseau (CNI)"
    kubectl delete -f "$INFRA_DIR/cni-calico.yaml" --ignore-not-found

    header "CLUSTER NETTOYÉ"
}

# Suppression des apps
destroy_apps() {
    header "SUPPRESSION DES APPLICATIONS"
    echo -e "${YELLOW}Ceci supprimera Jenkins, Gitea, Nginx et la DB Postgres.${NC}"
    
    read -p "Supprimer aussi les volumes (Données perdues) ? (o/n) " del_data
    
    echo ""
    info "Suppression des applications"
    
    find 03-apps -name "*.yaml" | while read file; do
        sed "s/IP_LB_PLACEHOLDER/$DOMAIN/g" "$file" | kubectl delete -f - --ignore-not-found
    done

    kubectl delete -f 02-database/postgresql/ --recursive --ignore-not-found
    
    if [[ "$del_data" =~ ^[oO]$ ]]; then
        echo ""
        info "Suppression des PVC (Données)"
        kubectl delete pvc --all -n "$FORGE_NS" --ignore-not-found
        log "Données supprimées."
    else
        log "Volumes (PVC) conservés"
    fi
    
    log "Applications désinstallées"
}

# ==============================================================================
# 7. MENU ET BOUCLE PRINCIPALE
# ==============================================================================

show_menu() {
    clear
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${WHITE}              KUBERNETES FORGE MANAGER v1.0${NC}"
    echo -e "${BLUE}============================================================${NC}"
    
    echo -e "\n${CYAN}[ CLUSTER INFRASTRUCTURE ]${NC}"
    echo -e "  1.   ${GREEN}DEPLOIEMENT COMPOSANTS (étape 2 à 6)${NC}"
    echo    "  2.   Calico (CNI)"
    echo    "  3.   Cloud Controller Manager (CCM DigitalOcean)"
    echo    "  4.   Storage (CSI DigitalOcean)"
    echo    "  5.   Sealed Secrets Controller"
    echo    "  6.   Ingress Controller (Nginx)"
    echo    "  7.   Cert Manager (SSL Let's Encrypt)"     

    echo -e "\n${CYAN}[ SECURITE & SECRETS ]${NC}"
    echo    "  8.   Configuration DigitalOcean API Secret"
    echo    "  9.   Génère/Update Postgres Sealed Secret (.env)"
    echo    "  10.  Configuration DockerHub Auth Secret"

    echo -e "\n${CYAN}[ GESTION FORGE ]${NC}"
    echo -e "  11.  ${GREEN}DEPLOIEMENT APPS FORGE${NC}"
    echo    "  12.  Affiche le password Jenkins (fresh install)"

    echo -e "\n${CYAN}[ MAINTENANCE ]${NC}"
    echo    "  13.  Check composants du cluster"    
    echo    "  14.  Check état de la forge"

    echo -e "\n${RED}[ DANGER ZONE ]${NC}"
    echo -e "  99.  ${YELLOW}Suppression de toutes les applications${NC}"
    echo -e "  666. ${YELLOW}DESTRUCTION DU CLUSTER${NC}"
    echo    "  Q.  Quit manager"
    echo -e "${BLUE}============================================================${NC}"
    echo -n "Select : "
}

# Main Loop
check_prereqs

while true; do
    show_menu
    read choix

    case $choix in
        1)   install_full_infra ;;
        2)   install_cni ;;
        3)   install_ccm ;;
        4)   install_csi ;;
        5)   install_sealed_controller ;;
        6)   install_ingress ;;
        7)   install_cert_manager ;;

        8)   setup_do_secret ;;
        9)   setup_db_secrets ;;
        10)  setup_docker_secret ;;
        
        11)  install_apps ;;
        12)  show_jenkins_password ;;

        13)  check_cluster_status ;;
        14)  check_forge_status ;;

        99)  destroy_apps ;;
        666) destroy_infra ;;
        q|Q) echo "Au revoir !"; exit 0 ;;      
      
        *)  echo -e "${RED}Choix invalide.${NC}" ; sleep 1 ;;
    esac
    
    echo -e "\n${YELLOW}Appuyez sur Entrée pour revenir au menu...${NC}"
    read
done