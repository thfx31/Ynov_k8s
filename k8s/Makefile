#!/usr/bin/make -f

SHELL := /bin/bash

# Scripts
DEPLOY_SCRIPT := ./deploy_manifests.sh
DESTROY_SCRIPT := ./destroy_manifests.sh

.PHONY: help apply delete recreate

help:
	@echo ""
	@echo "Commandes disponibles :"
	@echo "  make apply     → Applique tous les manifests Kubernetes"
	@echo "  make delete    → Supprime tous les manifests Kubernetes"
	@echo "  make recreate  → Supprime puis applique tous les manifests (reset complet)"
	@echo "  make help      → Affiche cette aide"
	@echo ""

apply:
	@echo "Déploiement des manifests..."
	$(DEPLOY_SCRIPT)

delete:
	@echo "Suppression des manifests..."
	$(DESTROY_SCRIPT)

recreate:
	@echo "Reset complet : delete + apply"
	$(DESTROY_SCRIPT)
	$(DEPLOY_SCRIPT)

