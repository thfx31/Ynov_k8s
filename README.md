---

# 📘 README.md

## 🚀 Installation et configuration d’un cluster Kubernetes avec containerd, kubeadm, Calico, tests d’exposition, et intégration DigitalOcean

Ce document décrit toutes les étapes réalisées pour mettre en place un cluster Kubernetes basé sur **containerd**, initialisé avec **kubeadm**, configuré avec **Calico**, et enrichi d’un **Cloud Controller Manager (CCM) DigitalOcean**, ainsi que des tests avec un PVC et un Pod.

---

# 🟦 1. Installation de containerd

### Mise à jour du système

```bash
sudo apt update && sudo apt upgrade -y
```

### Installation des dépendances

```bash
sudo apt install -y ca-certificates curl gnupg lsb-release
```

### Installation de containerd

```bash
sudo apt install -y containerd.io
```

### Configuration

```bash
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
```

---

# 🟦 2. Installation de kubeadm, kubelet et kubectl

### Ajouter la clé Kubernetes

```bash
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

### Ajouter le dépôt

```bash
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

### Installation

```bash
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

---

# 🟦 3. Initialisation du cluster Kubernetes

Désactiver swap :

```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```

Initialiser le cluster :

```bash
kubeadm init --pod-network-cidr=192.168.0.0/16
```

Configurer kubectl :

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

---

# 🟦 4. Installation de crictl

```bash
VERSION="v1.30.0"
curl -LO https://github.com/kubernetes-sigs/cri-tools/releases/download/${VERSION}/crictl-${VERSION}-linux-amd64.tar.gz
sudo tar zxvf crictl-${VERSION}-linux-amd64.tar.gz -C /usr/local/bin
```

Configuration :

```bash
sudo tee /etc/crictl.yaml <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint:  unix:///run/containerd/containerd.sock
timeout: 10
debug: false
pull-image-on-create: false
EOF
```

---

# 🟦 5. Installation du CNI Calico

### Télécharger et appliquer le manifeste :

```bash
curl -O https://raw.githubusercontent.com/projectcalico/calico/refs/heads/master/manifests/calico.yaml
kubectl apply -f calico.yaml
```

---

# 🟦 6. Test d'un déploiement Kubernetes : whoami

### Création du déploiement

```bash
kubectl create deployment whoami --image=traefik/whoami
```

### Exposition en LoadBalancer (nécessite un CCM)

```bash
kubectl expose deployment whoami \
  --port=80 \
  --target-port=80 \
  --type=LoadBalancer
```

### Exposition en NodePort

```bash
kubectl expose deployment whoami \
  --name=whoami-nodeport \
  --port=80 \
  --target-port=80 \
  --type=NodePort
```

---

# 🟦 7. Installation du Cloud Controller Manager DigitalOcean (CCM)

### Téléchargement du manifeste

```bash
curl -LO https://raw.githubusercontent.com/digitalocean/digitalocean-cloud-controller-manager/master/releases/digitalocean-cloud-controller-manager/v0.1.64.yml
kubectl apply -f v0.1.64.yml
```

---

# 🟦 8. Création du token API DigitalOcean

Créer un token ici :
👉 [https://cloud.digitalocean.com/account/api/tokens](https://cloud.digitalocean.com/account/api/tokens)

Puis créer le secret :

```bash
kubectl -n kube-system create secret generic digitalocean --from-literal=access-token=xxxxxxxxxxxxx
```

---

# 🟦 9. Création d’un PVC

### pvc.yaml

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: myclaim
spec:
  accessModes:
    - ReadWriteOnce
  volumeMode: Filesystem
  resources:
    requests:
      storage: 8Gi
```

Appliquer :

```bash
kubectl apply -f pvc.yaml
```

---

# 🟦 10. Pod utilisant le PVC

### pod.yaml

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: sample-pod
spec:
  containers:
  - name: sample-container
    image: nginx:latest
    ports:
      - containerPort: 80
    volumeMounts:
      - name: myapp-volume
        mountPath: /data
  volumes:
  - name: myapp-volume
    persistentVolumeClaim:
      claimName: myclaim
```

Appliquer :

```bash
kubectl apply -f pod.yaml
```

Vérifier :

```bash
kubectl exec -it sample-pod -- sh
ls /data
```

---

# 🎉 Résultat

Vous avez maintenant :

✔ Un cluster Kubernetes fonctionnant avec containerd
✔ kubeadm + kubelet + kubectl installés
✔ crictl configuré pour containerd
✔ Calico installé pour le réseau Pod
✔ Un déploiement whoami exposé en LoadBalancer & NodePort
✔ Le Cloud Controller Manager DigitalOcean actif
✔ Un secret DigitalOcean pour l’intégration API
✔ Un PVC fonctionnel + Pod utilisant un volume persistant

---

