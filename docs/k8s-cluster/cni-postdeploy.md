# Kubespray CNI Post-Deploy (Cilium + Multus + Kube-OVN)

This replaces the old bash scripts with Ansible roles and a single playbook.

## Image
- Build: `cd v0.2.0/k8s-cluster && docker build -t ghcr.io/proficientnowtech/kubespray-pncp:v2.28.1 .`
- Contains: Ansible 10.7.0, Kubespray v2.28.1 checkout in `/opt/kubespray`, kubectl v1.31.4. (Helm is already installed by Kubespray on the cluster.)

## Playbook
- Location: `v0.2.0/k8s-cluster/playbooks/cni.yml`
- Roles:
  - `cilium` (Helm install + applies L2 IPPool/L2Announcements from `v0.2.0/k8s-cluster/cilium/`)
  - `multus` (applies upstream multus daemonset)
  - `kube_ovn` (Helm install from kube-ovn repo; default state is **present** so it is installed as a secondary CNI. Set `KUBE_OVN_STATE=absent` to skip.)

## Run
Prereqs: `KUBECONFIG` exported for the target cluster (or use `v0.2.0/k8s-cluster/run.sh` which copies kubeconfig automatically); kubespray deploy already done.
```bash
cd v0.2.0/k8s-cluster
docker run --rm -it \
  -v $KUBECONFIG:/root/.kube/config \
  -v $(pwd):/workspace \
  ghcr.io/proficientnowtech/kubespray-pncp:v2.28.1 \
  ansible-playbook -i localhost, -c local /workspace/playbooks/cni.yml
```
Only localhost is targeted (using provided kubeconfig). Defaults: Cilium + Multus + Kube-OVN install; Kube-OVN is installed but used as a secondary CNI (for vCluster use). Override with `CILIUM_STATE`/`MULTUS_STATE`/`KUBE_OVN_STATE`.

## Notes
- Cilium values come from `v0.2.0/k8s-cluster/cilium-values.yaml`; L2 resources from `v0.2.0/k8s-cluster/cilium/`.
- Multus uses the upstream thick daemonset manifest.
- Kube-OVN installs with default chart values (customize via role vars) and remains secondary; Cilium stays primary.
- Old markdown in `v0.2.0/k8s-cluster` was removed; refer here instead.
