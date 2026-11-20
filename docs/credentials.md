# Lab credentials

Every secret in the lab is a fixed default stored in Git, so every copy of the lab behaves the same. This is safe only because nothing listens outside your machine. The table says where each one lives and how to change it.

| Secret | Value | Defined in | To change it |
|---|---|---|---|
| Grafana `admin` | `k8s-lab-admin` | `manifests/base/03-lab-credentials.yaml` (Secret `observability/grafana-admin`) | Edit it there and in `helm/kiali-values.yaml` (`external_services.grafana.auth.password`) |
| ArgoCD `admin` | `k8s-lab-admin` | `helm/argocd-values.yaml`, as a bcrypt hash | Generate a hash with the command in that file's comment, and update `argocdServerAdminPasswordMtime` |
| Redis | `k8s-lab-redis` | `manifests/base/03-lab-credentials.yaml` (Secret `shop/redis-auth`) | Edit it there, then restart Redis and the backends |
| Kiali token signing key | `k8s-lab-kiali-signing-key-32chrs` | `helm/kiali-values.yaml` (`login_token.signing_key`) | Any 16, 24 or 32 characters; keep it fixed or Kiali restarts on every sync ([problem 16](troubleshooting.md#16-kiali-restarts-every-few-minutes)) |
| Gitea `lab` (module 22 only) | `lab-gitops-pass` | the `gitea admin user create` command in [module 22](../platform-engineering/2-intermediate/22-gitops-with-argocd.md) | Use another password there and in your `git push` URL |
