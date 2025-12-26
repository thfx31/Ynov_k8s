#!/bin/bash
# bootstrap.sh - Provisioning Layer 0 & ArgoCD

set -eo pipefail

# Variables
INFRA_DIR="k8s/00-infra"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env-do"
TIMEOUT="300s"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

info() { echo -e "${CYAN}>> $1${NC}"; }

# Chargement des variables d'environnement
if [ -f "$ENV_FILE" ]; then
    set -a && source "$ENV_FILE" && set +a
    echo ""
    echo -e "${GREEN}Variables d'environnement chargées${NC}"
else
    echo -e "${RED}Erreur : Fichier .env absent.${NC}" && exit 1
fi

echo ""
echo -e "${BLUE}---------------------------------------${NC}"
echo "  Installation des composants"
echo -e "${BLUE}---------------------------------------${NC}"

# Création du secret DigitalOcean
echo "Création du secret DigitalOcean..."
kubectl create secret generic digitalocean -n kube-system \
  --from-literal=access-token="$DO_TOKEN" --dry-run=client -o yaml | kubectl apply -f -

# Installation des composants (CCM / CSI)
kubectl apply -f $INFRA_DIR/cni-calico.yaml
kubectl apply -f $INFRA_DIR/ccm-do.yaml
kubectl apply -f $INFRA_DIR/csi-crds-do.yaml
kubectl apply -f $INFRA_DIR/csi-driver-do.yaml

# Vérification du statut Ready des nodes
echo "Attente du statut READY des nodes..."
kubectl wait --for=condition=Ready nodes --all --timeout=$TIMEOUT

echo ""
echo -e "${BLUE}---------------------------------------${NC}"
echo "  Installation d'ArgoCD"
echo -e "${BLUE}---------------------------------------${NC}"

# Création du namespace ArgoCD
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Installation d'ArgoCD
echo "Installation d'ArgoCD dans le namespace 'argocd'..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Attente du serveur ArgoCD (cela peut prendre 2-3 min)..."
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=$TIMEOUT

# Récupération du mot de passe admin
ARGOCD_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo -e "${BLUE}---------------------------------------${NC}"
echo "  ETAT DU CLUSTER"
echo -e "${BLUE}---------------------------------------${NC}"
kubectl get nodes -o wide
echo ""
kubectl get pods -A -o wide
echo ""
echo -e "${GREEN}Bootstrap terminé avec succès !${NC}"
echo ""
echo -e "${BLUE}---------------------------------------${NC}"
echo "  Accès à l'interface ArgoCD"
echo -e "${BLUE}---------------------------------------${NC}"
echo "URL : localhost:8080 (via port-forward)"
info "kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "Login : admin"
echo -e Password : "${YELLOW}$ARGOCD_PWD${NC}"
echo ""