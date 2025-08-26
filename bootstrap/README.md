# Bootstrap

## 0) Prereqs

- k3s single-node cluster is Ready
- `kubectl` context points at the cluster
- Domain: `unifyops.io` in Route53 (or adjust manifests)

## 1) Install Argo CD

```bash
cd bootstrap
./argo-install.sh
```
