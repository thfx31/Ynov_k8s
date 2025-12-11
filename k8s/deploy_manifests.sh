#!/bin/bash

echo "APPLY : application de tous les manifests Kubernetes"
echo "------------------------------------------------------"

FILES=$(find . -type f \( -name "*.yaml" -o -name "*.yml" \) | sort)

if [ -z "$FILES" ]; then
    echo "Aucun fichier manifest trouvé."
    exit 1
fi

for file in $FILES; do
    echo "apply : $file"
    kubectl apply -f "$file"
    echo "------------------------------------------------------"
done

echo "✔️ Tous les manifests ont été appliqués."

