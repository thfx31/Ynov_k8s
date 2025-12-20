#!/bin/bash

# Configuration
INFRA_DIR="00-infra"
KUBE_NS="kube-system"
FORGE_NS="rt"

# Couleurs (Codes ANSI)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# --- FONCTIONS UTILITAIRES ---

log() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERR]${NC} $1"; }
info() { echo -e "${CYAN}>> $1${NC}"; }
header() { 
    echo ""
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo -e "${WHITE}   $1${NC}"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
}

# Vérifications préliminaires
check_prereqs() {
    local missing=0
    for cmd in kubectl kubeseal helm; do
        if ! command -v $cmd &> /dev/null; then
            error "$cmd n'est pas installé."
            missing=1
        fi
    done
    
    if [ ! -d "$INFRA_DIR" ]; then
        error "Le dossier $INFRA_DIR n'existe pas."
        missing=1
    fi

    if [ $missing -eq 1 ]; then exit 1; fi
}

# --- FONCTION STATUS ---

check_status() {
    header "ÉTAT DU CLUSTER"
    
    # Ici je garde les redirections car c'est pour l'affichage du tableau
    # Si on les enlève, le tableau sera cassé par les messages d'erreur techniques
    
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
}

# --- INSTALLATION INFRA ---

install_cni() {
    echo ""
    info "Installation du CNI (Calico)..."
    # Redirection supprimée
    kubectl apply -f "$INFRA_DIR/cni-calico.yaml"
    log "Fin de l'étape CNI."
}

install_sealed_controller() {
    echo ""
    info "Installation de Sealed Secrets via Helm..."
    # Redirections supprimées pour voir les updates de repo et l'install
    helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
    helm repo update

    helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
        --namespace "$KUBE_NS" \
        --set-string fullnameOverride=sealed-secrets-controller \
        --set tolerations[0].key="node.cloudprovider.kubernetes.io/uninitialized" \
        --set-string tolerations[0].value="true" \
        --set tolerations[0].effect="NoSchedule" \
        --wait
    log "Contrôleur installé."
}

setup_do_secret() {
    echo ""
    info "Configuration du Secret Digital Ocean..."
    
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
    
    # On affiche l'erreur si le pod n'existe pas, c'est pas grave
    kubectl delete pod -n $KUBE_NS -l k8s-app=digitalocean-cloud-controller-manager --ignore-not-found
    log "Secret appliqué."
}

install_ccm() {
    echo ""
    info "Installation du Cloud Controller Manager..."
    kubectl apply -f "$INFRA_DIR/ccm-do.yaml"
    log "CCM appliqué."
}

install_csi() {
    echo ""
    info "Installation du CSI (Stockage)..."
    log "Application des CRDs..."
    kubectl apply -f "$INFRA_DIR/csi-crds-do.yaml"
    
    log "Attente des CRDs..."
    # On laisse le '|| true' pour ne pas planter le script, mais on enlève la redirection
    kubectl wait --for=condition=established --timeout=60s crd/volumesnapshotclasses.snapshot.storage.k8s.io || true
    
    log "Application du Driver..."
    kubectl apply -f "$INFRA_DIR/csi-driver-do.yaml"
    log "Drivers CSI installés."
}

install_ingress() {
    echo ""
    info "Installation de l'Ingress Nginx..."
    kubectl apply -f "$INFRA_DIR/ingress-nginx.yaml"
    
    echo -e "${YELLOW}En attente de l'attribution de l'IP par DigitalOcean (ca peut prendre 1-2 min)...${NC}"
    echo -ne "Patience "
    
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
    
    echo "" # Retour à la ligne
    log "IP PUBLIQUE ATTRIBUÉE !"
    echo -e "${WHITE}Adresse du LoadBalancer : ${GREEN}$LB_IP${NC}"
    echo ""
}

# --- GESTION APPS ---

install_apps() {
    header "DÉPLOIEMENT DES APPLICATIONS"

    # Namespace
    echo ""
    info "Vérification du namespace $FORGE_NS..."
    if ! kubectl get namespace "$FORGE_NS" > /dev/null 2>&1; then
        echo -e "${YELLOW}Création du namespace $FORGE_NS${NC}"
        kubectl apply -f 01-initialisation/namespace.yaml
        log "Namespace créé."
    else
        log "Namespace déjà présent."
    fi

    # 1. Secret Docker
    echo ""
    info "Vérification des accès DockerHub..."
    # Ici on garde la redirection car c'est un check silencieux (if)
    if ! kubectl get secret regcred -n "$FORGE_NS" > /dev/null 2>&1; then
        echo -e "${YELLOW}Création du secret 'regcred' dans le namespace $FORGE_NS${NC}"
        read -p "User: " DOCKER_USER
        read -s -p "Password: " DOCKER_PASS
        echo ""
           
        # On affiche le résultat de la création
        kubectl create secret docker-registry regcred \
          --docker-server=https://index.docker.io/v1/ \
          --docker-username="$DOCKER_USER" \
          --docker-password="$DOCKER_PASS" \
          --namespace="$FORGE_NS"
        log "Secret créé."
    else
        log "Secret Docker déjà présent."
    fi

    # 2. IP check
    LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [ -z "$LB_IP" ]; then
        error "Ingress IP introuvable. L'Ingress est-il prêt ?"
        return 1
    fi
    log "IP Cluster détectée : $LB_IP"

    # 3. Deploy
    echo ""
    info "Déploiement Base de Données..."
    kubectl apply -f 02-database/postgresql/

    echo ""
    info "Déploiement Services (Nginx, Jenkins, Gitea)..."
    find 03-apps -name "*.yaml" | while read file; do
        # On affiche la sortie de kubectl apply
        sed "s/IP_LB_PLACEHOLDER/$LB_IP/g" "$file" | kubectl apply -f -
    done
    
    echo ""
    echo -e "${GREEN}ACCÈS APPLICATIONS :${NC}"
    echo -e "  - Forge   : http://forge.${LB_IP}.nip.io"
    echo -e "  - Jenkins : http://jenkins.${LB_IP}.nip.io"
    echo -e "  - Gitea   : http://gitea.${LB_IP}.nip.io"
}

show_jenkins_password() {
    echo ""
    info "Récupération mot de passe Jenkins..."
    
    if ! kubectl get pod -n "$FORGE_NS" -l app=jenkins --no-headers > /dev/null 2>&1; then
        warn "Pod Jenkins introuvable. Est-il installé ?"
        return
    fi

    echo -e "En attente du statut Ready..."
    # On enlève la redirection pour voir si le wait timeout ou autre
    kubectl wait --for=condition=ready pod -l app=jenkins -n "$FORGE_NS" --timeout=300s
    sleep 10

    POD_NAME=$(kubectl get pod -n "$FORGE_NS" -l app=jenkins -o jsonpath='{.items[0].metadata.name}')
    
    # On enlève la redirection des erreurs (2>/dev/null) pour voir si le fichier n'existe pas
    PASSWORD=$(kubectl exec -n "$FORGE_NS" "$POD_NAME" -- cat /var/jenkins_home/secrets/initialAdminPassword)

    if [ -n "$PASSWORD" ]; then
        echo ""
        echo -e "${WHITE}JENKINS ADMIN PASSWORD :${NC}"
        echo -e "${CYAN}----------------------------------------${NC}"
        echo -e "${GREEN}$PASSWORD${NC}"
        echo -e "${CYAN}----------------------------------------${NC}"
        echo ""
    else
        error "Mot de passe indisponible (Jenkins initialise encore ?)."
    fi
}    

destroy_apps() {
    header "SUPPRESSION DES APPLICATIONS"
    echo -e "${YELLOW}Ceci supprimera Jenkins, Gitea, Nginx et la DB Postgres.${NC}"
    
    read -p "Supprimer aussi les Volumes (Données perdues) ? (o/n) " del_data
    
    echo ""
    info "Suppression des applications..."
    
    # On affiche les suppressions
    find 03-apps -name "*.yaml" | while read file; do
        sed "s/IP_LB_PLACEHOLDER/1.1.1.1/g" "$file" | kubectl delete -f - --ignore-not-found
    done

    kubectl delete -f 02-database/postgresql/ --recursive --ignore-not-found
    
    if [[ "$del_data" =~ ^[oO]$ ]]; then
        echo ""
        info "Suppression des PVC (Données)..."
        kubectl delete pvc --all -n "$FORGE_NS" --ignore-not-found
        log "Données supprimées."
    else
        log "Volumes (PVC) conservés."
    fi
    
    log "Applications désinstallées."
}


# --- DESTRUCTION TOTALE ---

destroy_infra() {
    header "DESTRUCTION INFRASTRUCTURE"
    echo -e "${RED}!!! ATTENTION : ACTION IRRÉVERSIBLE !!!${NC}"
    echo "Cela détruira TOUT le cluster (LoadBalancer, Volumes, Réseau)."
    
    echo -e "${RED}Écrivez 'destroy' pour confirmer : ${NC}\c"
    read confirm

    if [ "$confirm" != "destroy" ]; then echo "Annulé."; return; fi

    echo ""
    info "Nettoyage Ingress..."
    kubectl delete -f "$INFRA_DIR/ingress-nginx.yaml" --ignore-not-found
    
    echo ""
    info "Nettoyage Storage (CSI)..."
    kubectl delete -f "$INFRA_DIR/csi-driver-do.yaml" --ignore-not-found
    kubectl delete -f "$INFRA_DIR/csi-crds-do.yaml" --ignore-not-found
    
    echo ""
    info "Nettoyage Cloud Controller (CCM)..."
    kubectl delete -f "$INFRA_DIR/ccm-do.yaml" --ignore-not-found
    
    echo ""
    info "Nettoyage Secrets..."
    helm uninstall sealed-secrets -n "$KUBE_NS" --ignore-not-found
    
    read -p "Supprimer le fichier local 'sealed-secret-do.yaml' ? (o/n) " del_local
    if [[ "$del_local" =~ ^[oO]$ ]]; then
        rm -f "$INFRA_DIR/sealed-secret-do.yaml"
        log "Fichier local supprimé."
    fi

    echo ""
    info "Nettoyage Réseau (CNI)..."
    kubectl delete -f "$INFRA_DIR/cni-calico.yaml" --ignore-not-found

    header "CLUSTER NETTOYÉ"
}

# --- MENU ---

show_menu() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${WHITE}      KUBERNETES DO MANAGER v1.0      ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${CYAN}INSTALLATION INFRA${NC}"
    echo "  1. Installation Complète (1-7)"
    echo "  2. Réseau (CNI)"
    echo "  3. Secrets (Sealed)"
    echo "  4. Config Digital Ocean"
    echo "  5. Cloud Controller"
    echo "  6. Storage (CSI)"
    echo "  7. Ingress Controller"
    echo ""
    echo -e "${CYAN}GESTION${NC}"
    echo "  8. Vérifier État"
    echo "  9. Installer Apps + DB"
    echo " 10. Afficher Password Jenkins"
    echo " 11. Désinstaller Apps"
    echo "  q. Quitter"
    echo ""
    echo -e "${RED}DANGER ZONE${NC}"
    echo -e " 666. ${YELLOW}DESTROY ALL INFRA${NC}"  
    echo -e "${BLUE}========================================${NC}"
}

# Main Loop
check_prereqs

while true; do
    show_menu
    read -p "Choix : " choice
    case $choice in
        1)
            install_cni
            install_sealed_controller
            setup_do_secret
            install_ccm
            install_csi
            install_ingress
            ;;
        2) install_cni ;;
        3) install_sealed_controller ;;
        4) setup_do_secret ;;
        5) install_ccm ;;
        6) install_csi ;;
        7) install_ingress ;;
        8) check_status ;;
        9) install_apps; show_jenkins_password ;;
        10) show_jenkins_password ;;
        11) destroy_apps ;;
        666) destroy_infra ;;
        q) exit 0 ;;
        *) error "Option invalide." ;;
    esac
    echo ""
    read -p "Appuyez sur Entrée..."
done