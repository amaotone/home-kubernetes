# PostgreSQLメジャーバージョンアップグレード手順（ArgoCD環境）

このドキュメントでは、ArgoCD + GitOps環境でn8nのPostgreSQLをメジャーバージョンアップする際の安全な手順を説明します。

## 前提条件

- GitOpsリポジトリ: すべての変更はGitにコミットしてArgoCDで適用
- 現在のバージョン: PostgreSQL 15
- 対象バージョン: PostgreSQL 16 or 17
- データの完全性を保つため、短時間のダウンタイムを伴います

## 自動化の仕組み

### Renovateの設定

`renovate.json5`で以下のように設定されています:

```json5
packageRules: [
  {
    // PostgreSQLメジャーバージョン更新を無効化
    matchPackageNames: ["postgres"],
    matchUpdateTypes: ["major"],
    enabled: false
  },
  {
    // マイナー・パッチは自動マージ
    matchPackageNames: ["postgres"],
    matchUpdateTypes: ["minor", "patch"],
    automerge: true
  }
]
```

**効果:**

- `postgres:15.1` → `15.2`: 自動でPR作成・マージ → ArgoCDが自動適用 ✅
- `postgres:15.x` → `16.0`: PRが作成されない → 手動アップグレードが必要 ⚠️

### なぜメジャーバージョンを無効化するのか

PostgreSQLのメジャーバージョンアップグレードでは:

1. データディレクトリの形式が変わる（互換性なし）
2. 単純なイメージ変更だけでは起動しない
3. データのマイグレーションが必要

そのため、**自動適用を防ぎ、計画的なアップグレードを実施**します。

## アップグレード手順（ArgoCD + GitOps）

### 全体の流れ

```
1. バックアップ作成（安全のため）
2. アップグレードJobを実行（kubectl apply、GitOpsの外で実行）
3. Deploymentマニフェストを更新してGitにコミット
4. ArgoCDで適用
5. 動作確認
6. 古いPVCを削除
```

### ステップ0: 事前準備

メンテナンスウィンドウを確保し、以下を確認:

```bash
# 現在のPostgreSQLバージョンを確認
kubectl get deployment -n n8n postgres -o jsonpath='{.spec.template.spec.containers[0].image}'

# n8nが正常に動作していることを確認
kubectl get pods -n n8n
```

### ステップ1: クラスタ外でバックアップを取得（推奨）

```bash
# PostgreSQL Podからバックアップをエクスポート
kubectl exec -n n8n deployment/postgres -- \
  pg_dump -U postgres -Fc n8n > ./backups/n8n_backup_$(date +%Y%m%d_%H%M%S).dump

# バックアップファイルを確認
ls -lh ./backups/

# 別の場所にもコピー（安全のため）
cp ./backups/n8n_backup_*.dump /path/to/safe/location/
```

### ステップ2: アップグレードJobの準備

**重要: このファイルはGitOpsリポジトリにありますが、ArgoCD管理外で実行します**

```bash
# ローカルでファイルを編集（まだコミットしない）
vim manifests/n8n/postgres-upgrade-job.yaml
```

以下の箇所を更新:

```yaml
containers:
  - name: restore
    image: postgres:16  # ← 対象バージョンに更新（例: 16, 17）
```

### ステップ3: n8nを一時停止

データの一貫性を保つため、n8nをスケールダウン:

```bash
# n8nをスケールダウン
kubectl scale deployment -n n8n n8n --replicas=0

# Podが停止したことを確認
kubectl get pods -n n8n -w
```

### ステップ4: アップグレードJobを実行

**ArgoCDの外で直接実行**（GitOpsリポジトリにコミットしない）:

```bash
# Jobを直接適用
kubectl apply -f manifests/n8n/postgres-upgrade-job.yaml

# 実行状況を確認
kubectl get jobs -n n8n

# ログを監視（重要: エラーがないか確認）
kubectl logs -n n8n job/postgres-upgrade -f

# Jobの完了を待つ
kubectl wait --for=condition=complete --timeout=10m job/postgres-upgrade -n n8n
```

**期待される出力:**

```
Starting backup of PostgreSQL database...
Backup completed successfully
Starting PostgreSQL 16 for restore...
Restoring backup...
Verifying restore...
Upgrade completed successfully!
```

### ステップ5: Deploymentマニフェストを更新してコミット

Jobが成功したら、GitOpsリポジトリを更新:

```bash
# postgres-deployment.yaml を編集
vim manifests/n8n/postgres-deployment.yaml
```

以下を変更:

```yaml
spec:
  template:
    spec:
      containers:
        - name: postgres
          image: postgres:16  # ← 新しいバージョンに更新
      volumes:
        - name: postgresql-pv
          persistentVolumeClaim:
            claimName: postgresql-pv-upgrade  # ← 新しいPVCに変更
```

変更をコミット:

```bash
git add manifests/n8n/postgres-deployment.yaml
git commit -m "feat: upgrade PostgreSQL from 15 to 16

- Migrated data using postgres-upgrade-job
- Updated PVC to postgresql-pv-upgrade
- Completed upgrade on $(date +%Y-%m-%d)"
git push origin main
```

### ステップ6: ArgoCDで適用

```bash
# ArgoCDが自動的に変更を検出（autoSync有効の場合）
# または、手動でSync
kubectl get applications -n argocd

# 手動Syncの場合
argocd app sync n8n
# または
kubectl patch application n8n -n argocd --type merge -p '{"operation": {"initiatedBy": {"username": "manual"}, "sync": {}}}'

# デプロイメントの進捗を監視
kubectl get pods -n n8n -w
```

### ステップ7: n8nを再起動して動作確認

```bash
# n8nをスケールアップ
kubectl scale deployment -n n8n n8n --replicas=2

# Podが起動してReadyになることを確認
kubectl get pods -n n8n -w

# n8nのログを確認（データベース接続エラーがないか）
kubectl logs -n n8n deployment/n8n --tail=50

# PostgreSQLに接続して確認
kubectl exec -n n8n deployment/postgres -- psql -U postgres -d n8n -c "\dt"
kubectl exec -n n8n deployment/postgres -- psql -U postgres -c "SELECT version();"
```

### ステップ8: 動作確認と後片付け

n8nが正常に動作することを確認したら:

```bash
# 動作確認（実際のワークフローを実行）
# ブラウザでn8nにアクセスして確認

# 問題なければ、アップグレードJobを削除
kubectl delete job -n n8n postgres-upgrade

# 古いPVCを削除（慎重に！）
kubectl get pvc -n n8n
kubectl delete pvc -n n8n postgresql-pv

# オプション: 新しいPVCを正式名称にリネームする場合
# 1. Deploymentを一時停止
# 2. PVCをクローン
# 3. Deploymentを更新
# 複雑なため、そのまま postgresql-pv-upgrade を使用することを推奨
```

## トラブルシューティング

### アップグレードJobが失敗した場合

```bash
# Jobのログを確認
kubectl logs -n n8n job/postgres-upgrade

# よくあるエラー:
# - "pg_dump: error: connection to database failed": PostgreSQLに接続できない
#   → postgres Serviceが正常か確認
# - "permission denied": 権限の問題
#   → securityContextとPVC権限を確認
# - "out of memory": メモリ不足
#   → Jobのresource limitsを増やす

# Jobを削除して再試行
kubectl delete job -n n8n postgres-upgrade
# 問題を修正してから再度実行
kubectl apply -f manifests/n8n/postgres-upgrade-job.yaml
```

### アップグレード後にn8nが起動しない

```bash
# n8nのログを確認
kubectl logs -n n8n deployment/n8n

# PostgreSQLに接続できるか確認
kubectl exec -n n8n deployment/postgres -- psql -U postgres -d n8n -c "SELECT 1;"

# データベースユーザーの権限を確認
kubectl exec -n n8n deployment/postgres -- psql -U postgres -d n8n -c "\du"

# 必要に応じて権限を再付与
kubectl exec -n n8n deployment/postgres -- psql -U postgres -d n8n -c "
  GRANT ALL PRIVILEGES ON DATABASE n8n TO <n8n_user>;
  GRANT ALL ON SCHEMA public TO <n8n_user>;
  GRANT ALL ON ALL TABLES IN SCHEMA public TO <n8n_user>;
  GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO <n8n_user>;
"
```

## ロールバック手順

### アップグレードJob実行前の失敗

Jobが完了していない場合は簡単にロールバック可能:

```bash
# Jobを削除
kubectl delete job -n n8n postgres-upgrade

# 新しいPVCを削除
kubectl delete pvc -n n8n postgresql-pv-upgrade

# n8nをスケールアップして元の状態に戻す
kubectl scale deployment -n n8n n8n --replicas=2

# 古いPostgreSQLはそのまま稼働し続ける
```

### Deploymentを更新した後の失敗

GitOpsリポジトリを元に戻す:

```bash
# 1. Gitを以前のコミットに戻す
git revert HEAD  # または
git reset --hard <previous-commit>
git push origin main --force  # 注意: force pushは慎重に

# 2. ArgoCDで同期
argocd app sync n8n

# 3. n8nをスケールアップ
kubectl scale deployment -n n8n n8n --replicas=2

# 4. バックアップから復元が必要な場合
kubectl exec -n n8n deployment/postgres -- psql -U postgres -d n8n < /path/to/backup.sql
```

### 完全な災害復旧

最悪の場合（データが壊れた場合）:

```bash
# 1. PostgreSQL Deploymentを削除
kubectl delete deployment -n n8n postgres

# 2. 新しいPVCを削除
kubectl delete pvc -n n8n postgresql-pv-upgrade

# 3. 古いPVCで再デプロイ
# postgres-deployment.yaml を元のバージョン・PVCに戻す
git checkout HEAD~1 -- manifests/n8n/postgres-deployment.yaml
git commit -m "revert: rollback PostgreSQL upgrade"
git push

# 4. ArgoCDで適用
argocd app sync n8n

# 5. バックアップから復元
kubectl cp ./backups/n8n_backup_*.dump n8n/<postgres-pod>:/tmp/
kubectl exec -n n8n deployment/postgres -- pg_restore -U postgres -d n8n /tmp/n8n_backup_*.dump
```

## ArgoCD固有の注意点

### postgres-upgrade-job.yaml の扱い

このファイルはGitOpsリポジトリに含まれていますが、**ArgoCDで管理しない**ことを推奨:

**方法1: ArgoCD Applicationから除外**

```yaml
# manifests/applications/n8n.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: n8n
spec:
  source:
    repoURL: https://github.com/amaotone/home-kubernetes
    targetRevision: main
    path: manifests/n8n
    directory:
      exclude: 'postgres-upgrade-job.yaml'  # この行を追加
```

**方法2: 手動適用のみ**

- Jobは `kubectl apply` で直接実行
- アップグレード完了後にJobを削除
- ArgoCDは無視（Out of Sync状態でも問題なし）

### autoSync との共存

n8n Applicationで `autoSync` が有効になっている場合:

```yaml
spec:
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

postgres-deployment.yaml をコミットすると、**数秒〜数分で自動適用**されます。

**重要:**

- アップグレードJobが完全に成功してからコミット
- コミット前にローカルで内容を再確認
- 必要に応じて一時的に autoSync を無効化

```bash
# autoSyncを一時的に無効化
kubectl patch application n8n -n argocd --type=json \
  -p='[{"op": "remove", "path": "/spec/syncPolicy/automated"}]'

# アップグレード完了後に再度有効化
kubectl patch application n8n -n argocd --type=merge \
  -p='{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
```

## チェックリスト

### アップグレード前

- [ ] 現在のPostgreSQLバージョンを確認
- [ ] クラスタ外にバックアップを作成
- [ ] バックアップファイルを安全な場所に保存
- [ ] メンテナンスウィンドウを確保
- [ ] 必要に応じてユーザーに通知
- [ ] アップグレード手順を再確認

### アップグレード中

- [ ] n8nをスケールダウン（replicas=0）
- [ ] postgres-upgrade-job.yaml のバージョンを更新
- [ ] Jobを実行して完了を待つ
- [ ] Jobログでエラーがないことを確認
- [ ] postgres-deployment.yaml を更新
- [ ] 変更をコミット・プッシュ
- [ ] ArgoCDで同期（または自動同期を待つ）

### アップグレード後

- [ ] PostgreSQLが新バージョンで起動
- [ ] n8nをスケールアップ（replicas=2）
- [ ] n8nがデータベースに接続できる
- [ ] n8nのUIにアクセスできる
- [ ] 既存のワークフローが正常に動作
- [ ] ログにエラーがない
- [ ] パフォーマンスに問題がない
- [ ] アップグレードJobを削除
- [ ] 古いPVCを削除（慎重に）

## まとめ

### GitOps環境でのポイント

1. **Renovateで自動PR作成を防止**: メジャーバージョンは `enabled: false`
2. **Jobは手動実行**: ArgoCDの外で直接 `kubectl apply`
3. **マニフェストはGitで管理**: アップグレード後の状態をコミット
4. **ArgoCDで適用**: autoSyncまたは手動Sync
5. **ロールバック可能**: Git revert + バックアップで安全に戻せる

この手順により、GitOpsの原則を守りつつ、安全にPostgreSQLをアップグレードできます。

## 参考リンク

- [PostgreSQL公式アップグレードガイド](https://www.postgresql.org/docs/current/upgrading.html)
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [Renovate Package Rules](https://docs.renovatebot.com/configuration-options/#packagerules)
