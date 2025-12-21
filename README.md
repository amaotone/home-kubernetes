# おうち Kubernetes

GitOps による自宅 Kubernetes クラスタ管理リポジトリ。ArgoCD で自動デプロイ・自己修復を実現。

## クイックリファレンス

### よく使うコマンド

```bash
# クラスタの状態確認
kubectl get pods -A
kubectl get applications -n argocd

# ArgoCD UI へのアクセス (初回のみパスワード取得)
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
kubectl port-forward svc/argocd-server -n argocd 8080:443

# アプリケーションの同期状態確認
kubectl get app -n argocd

# ログ確認
kubectl logs -n <namespace> <pod-name> --tail=100 -f
```

### シークレットの作成

**Bitwarden Secrets Manager を使用**

```bash
# 1. Bitwarden Web UI でシークレット作成
# 2. Machine Accountに読み取り権限を付与
# 3. BitwardenSecret CRD を作成
kubectl apply -f manifests/<app-name>/<app>-bitwarden-secret.yaml

# 4. 自動同期を確認
kubectl get bitwardensecrets -A
kubectl get secrets -n <namespace>
```

**詳細なセットアップガイド**: [docs/bitwarden-secrets-manager-setup.md](docs/bitwarden-secrets-manager-setup.md)

## 前提条件

### 必要なツール

```bash
# kubectl (Kubernetes CLI)
brew install kubectl

# Bitwarden CLI (シークレット管理)
brew install bitwarden-cli

# Helm (Kubernetes パッケージマネージャー)
brew install helm

# ArgoCD CLI (オプション)
brew install argocd
```

### kubectl context の設定

クラスタに接続できるように context を設定してください:

```bash
kubectl config get-contexts
kubectl config use-context <your-cluster-context>
```

## 初回セットアップ

### 1. ArgoCD のインストール

```bash
# ArgoCD をクラスタにデプロイ
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# ArgoCD Server が起動するまで待機
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```

### 2. ルートアプリケーションのデプロイ

```bash
# App of Apps パターンのルートをデプロイ
kubectl apply -f manifests/applications/root.yaml

# または ArgoCD UI から root.yaml をデプロイ
```

### 3. ArgoCD UI へのアクセス

```bash
# 初期パスワードを取得
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# ポートフォワードで UI にアクセス
kubectl port-forward svc/argocd-server -n argocd 8080:443

# ブラウザで https://localhost:8080 を開く
# ユーザー名: admin
# パスワード: 上記で取得したパスワード
```

## よくある操作

### 新しいアプリケーションの追加

**1. Application マニフェストを作成**

```bash
# manifests/applications/ に新しい Application YAML を作成
cat > manifests/applications/my-app.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/amaotone/home-kubernetes.git
    targetRevision: HEAD
    path: manifests/my-app
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
```

**2. アプリケーション固有のマニフェストを配置**

```bash
mkdir -p manifests/my-app
# manifests/my-app/ 配下に Deployment, Service などを配置
```

**3. Git にコミット**

```bash
git add manifests/applications/my-app.yaml manifests/my-app/
git commit -m "feat: add my-app application"
git push
```

ArgoCD が自動的に検知してデプロイします。

### アプリケーションの状態確認

```bash
# すべてのアプリケーションの状態
kubectl get app -n argocd

# 特定のアプリケーションの詳細
kubectl describe app <app-name> -n argocd

# ArgoCD UI で視覚的に確認
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### 手動での同期実行

```bash
# kubectl 経由
kubectl patch app <app-name> -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'

# ArgoCD CLI 経由
argocd app sync <app-name>

# ArgoCD UI から Sync ボタンをクリック
```

### ログとトラブルシューティング

```bash
# Pod のログ確認
kubectl logs -n <namespace> <pod-name> --tail=100 -f

# Pod の状態確認
kubectl describe pod -n <namespace> <pod-name>

# イベント確認
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# ArgoCD アプリケーションのステータス
kubectl get app -n argocd <app-name> -o yaml
```

## アーキテクチャ概要

### 主要コンポーネント

- **ArgoCD**: GitOps による継続的デリバリー
- **Bitwarden Secrets Manager**: 中央集権的なシークレット管理
- **Cloudflare Tunnels**: Ingress なしでの外部アクセス
- **Prometheus + Grafana**: モニタリング
- **n8n**: ワークフロー自動化

### ディレクトリ構成

```
.
├── manifests/
│   ├── applications/      # ArgoCD Application 定義 (App of Apps)
│   │   ├── root.yaml      # ルートアプリケーション
│   │   ├── bitwarden-operator.yaml  # Secrets Manager Operator
│   │   ├── cloudflared.yaml
│   │   └── n8n.yaml
│   ├── bitwarden-operator/  # Bitwarden Operator 設定
│   ├── cloudflared/       # Cloudflare Tunnels 設定
│   ├── n8n/              # n8n ワークフロー設定
│   └── <app-name>/       # 各アプリケーションのマニフェスト
├── src/
│   └── kotatsu-news/     # カスタムアプリケーションのソースコード
├── docs/
│   ├── design-philosophy.md
│   ├── postgres-upgrade-procedure.md
│   ├── bitwarden-secrets-manager-setup.md  # Bitwarden完全ガイド
│   └── security-checklist.md
├── scripts/
│   └── rotate-secrets.sh
└── renovate.json5        # 依存関係自動更新設定
```

### 設計原則

1. **GitOps**: Git が唯一の信頼できる情報源（設定のみ、シークレットは除く）
2. **宣言的管理**: すべてのリソースを YAML で定義
3. **自動化**: ArgoCD の auto-sync と self-heal を活用
4. **セキュリティ**: Bitwarden Secrets Manager で中央集権的なシークレット管理
5. **シンプルさ**: Ingress の代わりに Cloudflare Tunnels を使用

詳細は [docs/design-philosophy.md](docs/design-philosophy.md) を参照。

## トラブルシューティング

### ArgoCD が同期しない

```bash
# アプリケーションの状態確認
kubectl get app -n argocd <app-name> -o yaml

# ArgoCD Server のログ確認
kubectl logs -n argocd deployment/argocd-server

# 手動で同期を試行
argocd app sync <app-name> --force
```

### BitwardenSecret が同期しない

```bash
# BitwardenSecret の状態確認
kubectl get bitwardensecrets -A
kubectl describe bitwardensecret <secret-name> -n <namespace>

# Bitwarden Operator のログ確認
kubectl logs -n sm-operator-system deployment/bw-sm-operator-controller-manager --tail=100

# bw-auth-token が存在するか確認
kubectl get secret bw-auth-token -n <namespace>
```

### Pod が起動しない

```bash
# Pod の詳細確認
kubectl describe pod -n <namespace> <pod-name>

# イベント確認
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# リソース制限の確認
kubectl top nodes
kubectl top pods -n <namespace>
```

## ドキュメント

### 運用ガイド

- **[Bitwardenセットアップガイド](docs/bitwarden-secrets-manager-setup.md)**: Bitwarden Secrets Managerの完全ガイド
- **[PostgreSQLアップグレード手順](docs/postgres-upgrade-procedure.md)**: 安全なメジャーバージョンアップグレード
- **[セキュリティチェックリスト](docs/security-checklist.md)**: セキュリティベストプラクティスの確認項目

### 設計ドキュメント

- **[設計思想](docs/design-philosophy.md)**: クラスタ設計の原則と判断基準

## 参考リンク

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Bitwarden Secrets Manager](https://bitwarden.com/help/secrets-manager-kubernetes-operator/)
- [Cloudflare Tunnels](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)

## TODO

- [x] ArgoCD を利用する
  - [x] Bootstrap
  - [x] Cloudflare Tunnels 経由でアクセス
  - [x] App of Apps パターンの利用
- [x] Bitwarden Secrets Manager を導入する
- [x] cloudflared をクラスタに載せる
- [x] クラスタのモニタリング
  - [x] Prometheus + Grafana のデプロイ
  - [x] Cloudflare Tunnels 経由で Grafana にアクセス
- [x] Slack Bot のデプロイ
- [x] renovate の設定
- [ ] ログ収集の仕組みを作る
- [ ] n8n をセットアップする
