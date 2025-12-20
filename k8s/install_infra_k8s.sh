#!/bin/bash

# Configuration
INFRA_DIR="00-infra"
KUBE_NS="kube-system"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction de log
log() { echo -e "${GREEN}[INFO] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}"; }
info() { echo -e "${BLUE}[CTX] $1${NC}"; }

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

# --- STATUS CHECK FUNCTION ---
check_status() {
    echo ""
    echo "=========================================="
    echo "   VÉRIFICATION DE L'ÉTAT DU CLUSTER"
    echo "=========================================="
    
    # 1. CNI (Calico)
    if kubectl get pods -n "$KUBE_NS" -l k8s-app=calico-node --no-headers 2>/dev/null | grep -q "Running"; then
        echo -e "[CNI] Calico             : ${GREEN}OK${NC}"
    else
        echo -e "[CNI] Calico             : ${RED}NOK (Pas de pods Running)${NC}"
    fi

    # 2. Sealed Secrets
    if kubectl get pods -n "$KUBE_NS" -l app.kubernetes.io/name=sealed-secrets --no-headers 2>/dev/null | grep -q "Running"; then
        echo -e "[SEC] Sealed Secrets     : ${GREEN}OK${NC}"
    else
        echo -e "[SEC] Sealed Secrets     : ${RED}NOK${NC}"
    fi

    # 3. CCM (Cloud Controller) - Check Pod Only
    if kubectl get pods -n "$KUBE_NS" -l app=digitalocean-cloud-controller-manager --no-headers 2>/dev/null | grep -q "Running"; then
        echo -e "[CCM] Cloud Controller   : ${GREEN}OK${NC}"
    else
        echo -e "[CCM] Cloud Controller   : ${RED}NOK${NC}"
    fi

    # 4. CSI (Stockage)
    if kubectl get sc --no-headers 2>/dev/null | grep -q "do-block-storage"; then
        echo -e "[CSI] Storage Class      : ${GREEN}OK${NC}"
    else
        echo -e "[CSI] Storage Class      : ${RED}NOK${NC}"
    fi

    # 5. Ingress Nginx
    INGRESS_IP=$(kubectl get svc -n ingress-nginx -o jsonpath='{.items[*].status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    if [ -n "$INGRESS_IP" ]; then
        echo -e "[ING] Ingress IP         : ${GREEN}OK ($INGRESS_IP)${NC}"
    else
        echo -e "[ING] Ingress IP         : ${YELLOW}PENDING ou NOK (Pas d'IP externe)${NC}"
    fi
    
    echo "=========================================="
}

# --- INSTALLATION FUNCTIONS ---

# CNI (Réseau)
install_cni() {
    info "Installation du CNI (Calico)..."
    kubectl apply -f "$INFRA_DIR/cni-calico.yaml"
    log "En attente que les noeuds soient Ready..."
    sleep 5
    kubectl get nodes
}

# Sealed Secrets (Via HELM)
install_sealed_controller() {
    info "Installation de Sealed Secrets via Helm..."
    helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
    helm repo update > /dev/null

    helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
        --namespace "$KUBE_NS" \
        --set-string fullnameOverride=sealed-secrets-controller \
        --set tolerations[0].key="node.cloudprovider.kubernetes.io/uninitialized" \
        --set-string tolerations[0].value="true" \
        --set tolerations[0].effect="NoSchedule" \
        --wait
    log "Contrôleur Sealed Secrets installé."
}

# Secret Digital Ocean
setup_do_secret() {
    info "Configuration du Secret Digital Ocean..."
    
    if [ -f "$INFRA_DIR/sealed-secret-do.yaml" ]; then
        read -p "Fichier sealed-secret-do.yaml trouvé. Le réutiliser ? (o/n) " response
        if [[ "$response" =~ ^[oO]$ ]]; then
            kubectl apply -f "$INFRA_DIR/sealed-secret-do.yaml"
            return
        fi
    fi

    echo -e "${YELLOW}Entrez votre Token Digital Ocean (RW mandatory) :${NC}"
    read -s DO_TOKEN
    echo "" # Retour à la ligne après le read -s

    # Création du fichier temporaire
    # Note : --dry-run=client est plus sûr que le heredoc manuel pour gérer l'encodage
    kubectl create secret generic digitalocean \
        --namespace "$KUBE_NS" \
        --from-literal=access-token="$DO_TOKEN" \
        --dry-run=client -o yaml > secret-tmp.yaml

    
#     cat <<EOF > secret-tmp.yaml
# apiVersion: v1
# kind: Secret
# metadata:
#   name: digitalocean
#   namespace: $KUBE_NS
# stringData:
#   access-token: "$DO_TOKEN"
# EOF

    log "Chiffrement du secret..."
    kubeseal --controller-namespace $KUBE_NS \
             --controller-name sealed-secrets-controller \
             --format=yaml < secret-tmp.yaml > "$INFRA_DIR/sealed-secret-do.yaml"
             
    kubectl apply -f "$INFRA_DIR/sealed-secret-do.yaml"
    rm secret-tmp.yaml
    
    # Refresh CCM pod
    kubectl delete pod -n $KUBE_NS -l k8s-app=digitalocean-cloud-controller-manager --ignore-not-found
    log "Secret appliqué."
}

# CCM
install_ccm() {
    info "Installation du Cloud Controller Manager..."
    kubectl apply -f "$INFRA_DIR/ccm-do.yaml"
    sleep 2
    kubectl get pods -n $KUBE_NS -l app=digitalocean-cloud-controller-manager
}

# CSI
install_csi() {
    info "Installation du CSI (Stockage)..."
    log "1/3 CRDs..."
    kubectl apply -f "$INFRA_DIR/csi-crds-do.yaml"
    
    log "2/3 Wait..."
    kubectl wait --for=condition=established --timeout=60s crd/volumesnapshotclasses.snapshot.storage.k8s.io || true

    log "3/3 Driver..."
    kubectl apply -f "$INFRA_DIR/csi-driver-do.yaml"
    kubectl get sc
}

# Ingress
install_ingress() {
    info "Installation de l'Ingress Nginx..."
    kubectl apply -f "$INFRA_DIR/ingress-nginx.yaml"
    log "Watch IP (Ctrl+C pour quitter)..."
    kubectl get svc -n ingress-nginx -w
}

# --- DESTROY FUNCTION ---

destroy_infra() {
    echo -e "${RED}!!! ATTENTION DESTRUCTION TOTALE !!!${NC}"
    read -p "Confirmer (écrire 'destroy') : " confirm

    if [ "$confirm" != "destroy" ]; then return; fi

    info "Suppression Ingress..."
    kubectl delete -f "$INFRA_DIR/ingress-nginx.yaml" --ignore-not-found

    info "Suppression CSI..."
    kubectl delete -f "$INFRA_DIR/csi-driver-do.yaml" --ignore-not-found
    kubectl delete -f "$INFRA_DIR/csi-crds-do.yaml" --ignore-not-found

    info "Suppression CCM..."
    kubectl delete -f "$INFRA_DIR/ccm-do.yaml" --ignore-not-found

    info "Désinstallation Sealed Secrets..."
    helm uninstall sealed-secrets -n "$KUBE_NS" --ignore-not-found
    
    read -p "Supprimer sealed-secret-do.yaml local ? (o/n) " del_local
    if [[ "$del_local" =~ ^[oO]$ ]]; then
        rm -f "$INFRA_DIR/sealed-secret-do.yaml"
    fi

    info "Suppression CNI..."
    kubectl delete -f "$INFRA_DIR/cni-calico.yaml" --ignore-not-found

    log "Terminé."
}

# Menu Principal
show_menu() {
    echo ""
    echo "=========================================="
    echo "   INFRA KUBERNETES DO (MANAGER)"
    echo "=========================================="
    echo "1. TOUT INSTALLER"
    echo "------------------------------------------"
    echo "2. Install CNI (Calico)"
    echo "3. Install Sealed Secrets (Helm)"
    echo "4. Config Secret DO"
    echo "5. Install CCM"
    echo "6. Install CSI"
    echo "7. Install Ingress"
    echo "------------------------------------------"
    echo "8. VÉRIFIER L'ÉTAT (Check Status)"
    echo "------------------------------------------"
    echo -e "${RED}666. DESTROY ALL${NC}"
    echo "q. Quitter"
    echo "=========================================="
}

# Main Loop
check_prereqs

while true; do
    show_menu
    read -p "Votre choix: " choice
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
        666) destroy_infra ;;
        q) exit 0 ;;
        *) error "Choix invalide" ;;
    esac
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
done