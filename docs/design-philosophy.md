# Home Kubernetes - 設計思想

## 概要

このリポジトリは、自宅（おうち）Kubernetes 環境の構成を管理するためのものです。GitOps の原則に従い、Kubernetes クラスタの状態をコード（マニフェスト）として管理しています。

## 主要な設計原則

### 1. GitOps による管理

- [ArgoCD](https://argoproj.github.io/cd/)を採用し、GitOps ワークフローを実現
- Git リポジトリが唯一の信頼できる情報源（Single Source of Truth）
- クラスタの状態が Git リポジトリの内容と自動的に同期される

### 2. 宣言的な構成

- すべてのリソースを Kubernetes マニフェストとして宣言的に記述
- `manifests/`ディレクトリ下にアプリケーションごとにマニフェストを整理
- App of Apps パターンを採用し、マニフェスト間の依存関係を管理
  - `manifests/applications/root.yaml`がルートアプリケーションとなり、他のアプリケーションを管理
  - 新しいアプリケーションを追加する場合は、対応する Application CR を作成するだけで良い

### 3. セキュリティの確保

- [SealedSecrets](https://github.com/bitnami-labs/sealed-secrets)を利用した機密情報の暗号化
- 暗号化されたシークレットを Git リポジトリで安全に管理
- Cloudflare Tunnels を利用した安全な外部アクセス
  - Ingress リソースは不要
  - 代わりに、cloudflared の Service リソースを参照する設定
  - Cloudflare Dashboard で対応するトンネルを設定する必要あり

### 4. 自動化とセルフヒーリング

- ArgoCD によるマニフェストの自動同期
- 自己修復（selfHeal）機能を有効化し、手動変更の防止
- Renovate による依存関係の自動更新
  - `renovate.json5`で Renovate の設定を管理
  - コンテナイメージや Helm chart の更新を自動化

### 5. 可観測性の確保

- Prometheus + Grafana によるモニタリング体制
- メトリクスの可視化とアラート
- （計画中）ログ収集の仕組み

### 6. インフラストラクチャのコード化

- クラスタ環境自体もコードとして管理
- 必要に応じてインフラ変更をコードで表現
- 再現性と一貫性の確保

## リポジトリ構造

```
.
├── manifests/         # Kubernetesマニフェスト
│   ├── applications/  # ArgoCD Application定義
│   │   ├── root.yaml  # ルートアプリケーション（App of Appsパターン）
│   │   ├── cloudflared.yaml # Cloudflare Tunnels用アプリケーション
│   │   ├── sealed-secrets.yaml # SealedSecrets用アプリケーション
│   │   └── n8n.yaml   # n8nワークフロー用アプリケーション
│   ├── cloudflared/   # Cloudflare Tunnels関連設定
│   └── n8n/           # n8nワークフロー関連設定
├── src/               # アプリケーションソースコード
│   └── kotatsu-news/  # Slackボットアプリケーション
└── docs/              # ドキュメント
```

## AI agent によるコーディング支援のためのポイント

### アーキテクチャ上の重要事項

1. **App of Apps パターン**

   - 新規アプリケーションを追加する場合は、`manifests/applications/`に Application CR を作成
   - アプリケーション固有のマニフェストは`manifests/<アプリ名>/`ディレクトリに配置

2. **Cloudflare Tunnels によるサービス公開**

   - Ingress リソースは不要
   - 代わりに、cloudflared の Service リソースを参照する設定
   - Cloudflare Dashboard で対応するトンネルを設定する必要あり

3. **シークレット管理**

   - 通常の Secret リソースは直接コミットしない
   - kubeseal を使用して SealedSecret リソースを生成
   - 既存の SealedSecret パターンを参考にする

4. **アプリケーション開発**
   - `src/`ディレクトリにアプリケーションコードを配置
   - Dockerfile でコンテナイメージをビルド
   - 対応するマニフェストを`manifests/`に配置

### コントリビューションワークフロー

1. 機能追加/変更の場合:

   - マニフェストを作成/編集
   - ArgoCD による自動同期を確認
   - 必要に応じてアプリケーションコードを`src/`に追加

2. シークレット管理:
   - kubeseal を使用して機密情報を暗号化
   - SealedSecret リソースをコミット

## ロードマップ

現在計画中または進行中の機能拡張:

1. ログ収集の仕組みの構築
2. n8n ワークフローエンジンのセットアップ
3. 監視・アラート体制の強化
4. バックアップ/リストア戦略の確立

このリポジトリは継続的に進化し、ホームラボ環境に新しい機能や改善を取り入れていきます。
