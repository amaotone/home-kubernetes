# PostgreSQLメジャーバージョンアップグレード手順

このドキュメントでは、n8nのPostgreSQLをメジャーバージョンアップする際の安全な手順を説明します。

## 前提条件

- 現在のバージョン: PostgreSQL 15
- 対象バージョン: PostgreSQL 16 or 17
- データの完全性を保つため、ダウンタイムを伴う手順です

## Renovate と ArgoCD との統合

### 自動化の設定

`renovate.json5`で以下のように設定されています:

- **PostgreSQLのメジャーバージョン更新**: 無効化（手動での対応が必要）
- **PostgreSQLのマイナー・パッチ更新**: 自動マージ（安全に自動適用）

これにより、PostgreSQL 15.x → 15.y のような安全な更新は自動で行われますが、
15.x → 16.x のようなメジャーバージョンアップは手動での介入が必要になります

## 方法1: Kubernetes Jobを使用した自動アップグレード（推奨）

ArgoCD環境で最も適した方法。Kubernetes Jobでアップグレードを自動化します。

### ステップ1: アップグレードJobの準備

`manifests/n8n/postgres-upgrade-job.yaml`を確認し、新しいバージョンを設定:

```yaml
containers:
  - name: restore
    image: postgres:16  # ← ここを更新
```

### ステップ2: n8nを一時停止（オプション）

```bash
# n8nをスケールダウンして、データベースへの書き込みを停止
kubectl scale deployment -n n8n n8n --replicas=0
```

### ステップ3: アップグレードJobを実行

```bash
# Jobを適用
kubectl apply -f manifests/n8n/postgres-upgrade-job.yaml

# 進捗を監視
kubectl logs -n n8n job/postgres-upgrade -f
```

### ステップ4: Deploymentを更新

Jobが成功したら、postgres-deployment.yamlを更新:

```yaml
# manifests/n8n/postgres-deployment.yaml
spec:
  template:
    spec:
      containers:
        - image: postgres:16  # ← バージョンを更新
      volumes:
        - name: postgresql-pv
          persistentVolumeClaim:
            claimName: postgresql-pv-upgrade  # ← 新しいPVCを使用
```

```bash
# 変更をコミット
git add manifests/n8n/postgres-deployment.yaml
git commit -m "feat: upgrade PostgreSQL to version 16"
git push

# ArgoCDが自動的に適用（または手動でSync）
kubectl get pods -n n8n -w
```

### ステップ5: 動作確認と後片付け

```bash
# n8nを再起動
kubectl scale deployment -n n8n n8n --replicas=2

# 動作確認
kubectl logs -n n8n deployment/n8n

# 確認後、古いPVCを削除
kubectl delete pvc -n n8n postgresql-pv

# 新しいPVCを正式名称にリネーム（オプション）
# または、そのまま postgresql-pv-upgrade を使用し続ける
```

## 方法2: 手動での pg_dump/pg_restore

Jobを使わず、手動でバックアップ・復元を行う方法。

### ステップ1: 現在のデータをバックアップ

```bash
# PostgreSQL Podに接続
kubectl exec -n n8n deployment/postgres -it -- bash

# データベース全体をダンプ
pg_dump -U postgres n8n > /tmp/n8n_backup.sql

# Podからローカルにバックアップをコピー
kubectl cp n8n/postgres:/tmp/n8n_backup.sql ./n8n_backup_$(date +%Y%m%d).sql
```

### ステップ2: PVCをバックアップ（オプションだが推奨）

```bash
# 現在のPVCのスナップショットを取得（ストレージクラスがサポートしている場合）
# または、PVCの内容を別の場所にコピー
kubectl get pvc -n n8n postgresql-pv -o yaml > postgresql-pvc-backup.yaml
```

### ステップ3: 新しいバージョン用のPVCを作成

既存のPVCとは別に、新しいPVCを作成します:

```yaml
# manifests/n8n/postgres-pvc-v16.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgresql-pv-v16
  namespace: n8n
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: local-path  # 既存のPVCと同じストレージクラスを使用
```

### ステップ4: 一時的なPostgreSQL 16インスタンスを起動

```bash
# 新しいバージョンのPostgreSQLを一時的に起動
kubectl run -n n8n postgres-v16-temp --image=postgres:16 \
  --env="POSTGRES_USER=postgres" \
  --env="POSTGRES_PASSWORD=<パスワード>" \
  --env="POSTGRES_DB=n8n" \
  -- sleep infinity

# バックアップファイルを新しいPodにコピー
kubectl cp ./n8n_backup_*.sql n8n/postgres-v16-temp:/tmp/n8n_backup.sql

# 新しいPodでデータを復元
kubectl exec -n n8n postgres-v16-temp -it -- bash
psql -U postgres n8n < /tmp/n8n_backup.sql
```

### ステップ5: Deploymentを更新

```bash
# 既存のDeploymentを削除（PVCは削除されません）
kubectl delete deployment -n n8n postgres

# postgres-deployment.yamlのimageをpostgres:16に更新
# PVCも新しいものに変更
```

### ステップ6: 動作確認

```bash
# n8nが正常に接続できることを確認
kubectl logs -n n8n deployment/n8n

# データベースに接続してデータを確認
kubectl exec -n n8n deployment/postgres -it -- psql -U postgres n8n
```

### ステップ7: 古いPVCを削除

動作確認が完了したら、古いPVCを削除:

```bash
kubectl delete pvc -n n8n postgresql-pv
```

## ArgoCD での注意点

### Sync Policy

postgres-upgrade-job.yaml は ArgoCD で管理しない方が安全です:

```yaml
# manifests/applications/n8n.yaml に追加
spec:
  ignoreDifferences:
    - group: batch
      kind: Job
      name: postgres-upgrade
```

または、アップグレード時のみ手動で kubectl apply する方法を推奨します。

### ロールバック

アップグレードが失敗した場合:

```bash
# Jobを削除
kubectl delete job -n n8n postgres-upgrade

# 新しいPVCを削除
kubectl delete pvc -n n8n postgresql-pv-upgrade

# 古いバージョンのまま継続
# postgres-deployment.yaml は変更しない
```

## ロールバック手順

アップグレード失敗時のロールバック:

```bash
# Deploymentを元のバージョンに戻す
kubectl apply -f manifests/n8n/postgres-deployment.yaml  # image: postgres:15

# または、バックアップから復元
kubectl exec -n n8n deployment/postgres -it -- bash
psql -U postgres n8n < /tmp/n8n_backup.sql
```

## チェックリスト

アップグレード前:
- [ ] 現在のデータベースを完全にバックアップ
- [ ] バックアップからの復元をテスト
- [ ] ダウンタイムのスケジュールをユーザーに通知
- [ ] n8nのワークフローが停止することを確認

アップグレード後:
- [ ] PostgreSQLが正常に起動することを確認
- [ ] n8nが接続できることを確認
- [ ] 既存のワークフローが正常に動作することを確認
- [ ] パフォーマンスに問題がないことを確認

## 参考リンク

- [PostgreSQL公式アップグレードガイド](https://www.postgresql.org/docs/current/upgrading.html)
- [pg_upgrade documentation](https://www.postgresql.org/docs/current/pgupgrade.html)
