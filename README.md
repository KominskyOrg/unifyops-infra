# UnifyOps GitOps (k3s + Argo CD)

Pure GitOps home cluster with branches mapped to environments:

- `dev` → namespace `uo-dev`
- `staging` → `uo-staging`
- `main` → `uo-prod`

Infra via Argo CD Applications (cert-manager, Longhorn, Harbor, metrics-server, external-dns). App delivery via ApplicationSet.

**Next steps:** see `docs/BOOTSTRAP.md`.
