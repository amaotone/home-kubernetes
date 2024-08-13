# おうち Kubernetes

## Setup

ArgoCD 自体のデプロイ

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

ArgoCD の UI から `manifests/applications/root.yaml` をデプロイする

## TODO

- [x] ArgoCD を利用する
  - [x] Bootstrap
  - [x] Cloudflare Tunnels 経由でアクセス
  - [x] App of Apps パターンの利用
- [x] SealedSecrets を導入する
- [x] cloudflared をクラスタに載せる
- [x] クラスタのモニタリング
  - [x] Prometheus + Grafana のデプロイ
  - [x] Cloudflare Tunnels 経由で Grafana にアクセス
- [x] Slack Bot のデプロイ
- [x] renovate の設定
- [ ] ログ収集の仕組みを作る
- [ ] 
