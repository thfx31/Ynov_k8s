# Setup des composants du cluster Kubernetes

## Install kubectl sur le PC d'admin
Copier la configuration kubeconfig vers la machine d'administration
```shell
scp root@kube-master:/etc/kubernetes/admin.conf ~/.kube/do-kubeconfig
```
Exporter la config
```shell
export KUBECONFIG=~/.kube/do-kubeconfig
```
---
## Cloner le projet
```shell
git clone git@github.com:thfx31/Ynov_k8s.git
cd Ynov_k8s/k8s
```
---
## Configuration du cluster (automatique)
Utiliser le script install_infra_k8s.sh
```shell
chmod +x install_infra_k8s.sh

./install_infra.sh
```
---
## Configuration du cluster (manuel)

### CNI Calico
**Installation**
```shell
kubectl apply -f 00-infra/cni-calico.yaml
```
**Validation**
```shell
 kubectl get pods -n kube-system | grep calico
calico-kube-controllers-5b97c7b9dd-tfclm                 1/1     Running   1 (88m ago)   7h50m
calico-node-6kxbd                                        1/1     Running   0             7h50m
calico-node-jfbh2                                        1/1     Running   1 (88m ago)   7h50m
```
&nbsp;

### Sealed Secret

**Installation controller sur le cluster**
```shell
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install sealed-secrets bitnami/sealed-secrets --namespace kube-system
```
Vérifier l'état du pod
```shell
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets
NAME                             READY   STATUS    RESTARTS      AGE
sealed-secrets-c5b4f946c-dvsbp   1/1     Running   2 (13m ago)   6h32m
```
&nbsp;
**Installation client sur la machine d'administration**
L'outil kubeseal permet de chiffrer les fichiers

```shell
# Télécharger la release
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.33.1/kubeseal-0.33.1-darwin-amd64.tar.gz

# Extraire et installer
tar -xvzf kubeseal-0.33.1-darwin-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

# Vérifier la version
kubeseal --version

# Validation
kubectl get pods -n kube-system
```
&nbsp;

**Workflow de création**
A faire pour chaque secret

**Générer le secret en clair localement**
Créer un fichier temporaire, à ne jamais commit
```shell
vim secret-do-local.yaml
```

```shell
apiVersion: v1
kind: Secret
metadata:
  name: digitalocean
  namespace: kube-system
stringData:
  access-token: "dop_v1_API_TOKEN"
```
&nbsp;

**Chiffrer le secret**
```shell
kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system --format=yaml < secret-do-local.yaml > sealed-secret-do.yaml
```
&nbsp;
**Appliquer le secret et supprimer le secret local**
```shell
kubectl apply -f sealed-secret-do.yaml

rm secret-do-local.yaml
```
&nbsp;
**Validation**
```shell
kubectl get sealedsecret digitalocean -n kube-system
NAME           STATUS   SYNCED   AGE
digitalocean            True     6h45m

kubectl -n kube-system get secret digitalocean -o jsonpath='{.data.access-token}' | base64 --decode
<dop_v1_API_TOKEN_en_clair>
```
&nbsp;

### CSI DigitalOcean

**Installer les définitions**
```shell
kubectl apply -f 00-infra/csi-crds.yaml
```
**Installer le driver**
```shell
kubectl apply -f 00-infra/csi-driver.yaml
```
**Vérification**
Les storages :
```shell
kubectl get sc
NAME                          PROVISIONER                 RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
do-block-storage (default)    dobs.csi.digitalocean.com   Delete          Immediate           true                   12s
do-block-storage-retain       dobs.csi.digitalocean.com   Retain          Immediate           true                   12s
do-block-storage-xfs          dobs.csi.digitalocean.com   Delete          Immediate           true                   12s
do-block-storage-xfs-retain   dobs.csi.digitalocean.com   Retain          Immediate           true                   12s
```

Les pods :
```shell
kubectl get pods -n kube-system -l app=csi-do-node
NAME                READY   STATUS    RESTARTS   AGE
csi-do-node-xfbnd   2/2     Running   0          19s
```
&nbsp;
### Ingress Nginx
**Installation**
```shell
kubectl apply -f 00-infra/ingress-nginx.yaml
```
**Validation**
```shell
kubectl get svc -n ingress-nginx -w
NAME                                 TYPE           CLUSTER-IP     EXTERNAL-IP       PORT(S)                      AGE
ingress-nginx-controller             LoadBalancer   10.108.59.98   146.190.176.247   80:31184/TCP,443:32657/TCP   13m
ingress-nginx-controller-admission   ClusterIP      10.98.36.100   <none>            443/TCP                      13m
```