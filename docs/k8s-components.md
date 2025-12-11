# Install components on Kubernetes cluster

## HELm (temporaire, à basculer côté ansible)
```shell
sudo apt-get install curl gpg apt-transport-https --yes
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm
```
curl https://raw.githubusercontent.com/projectcalico/calico/refs/heads/master/manifests/calico.yaml -o cni-calico.yaml
kubectl apply -f k8s/00-infra/cni-calico.yaml

## Sealed Secret
```shell
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install sealed-secrets bitnami/sealed-secrets --namespace kube-system
```