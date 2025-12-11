#!/bin/bash

echo "DELETE : suppression de tous les manifests Kubernetes"
echo "------------------------------------------------------"

FILES=$(find . -type f \( -name "*.yaml" -o -name "*.yml" \) | sort -r)

if [ -z "$FILES" ]; then
    echo "Aucun fichier manifest trouvé."
    exit 1
fi

# Remarque : on supprime dans l'ordre inverse (-r)
# pour éviter les erreurs (ex : service supprimé avant deployment)
for file in $FILES; do
    echo "delete : $file"
    kubectl delete -f "$file" --ignore-not-found
    echo "------------------------------------------------------"
done

echo "✔️ Tous les manifests ont été supprimés."

