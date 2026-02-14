# シナリオ06: Nessie 監査・コミット履歴

**難易度**: ★★★★☆
**所要時間**: 約20分
**前提**: `make setup` + シナリオ05 完了後

---

## 何を学ぶか

Nessie はすべてのデータ変更を**Gitのコミットログ**として記録します。これにより:

- **監査**: 「誰が・いつ・どのテーブルを・どう変更したか」を追跡できる
- **コンプライアンス**: データ変更の完全な証跡を保持
- **タグ管理**: 特定時点に名前をつけて保存（例: 「Q1決算確定データ」）

---

## 実行方法

```bash
make scenario-06
```

---

## Nessie のタグ機能

ブランチと似ていますが、タグは**変更できない参照点**です。

```
コミット履歴: ──●──●──●──●──●──► (main)
                        ↑
                    "Q1-2024-snapshot" タグ
```

タグを作成した時点のデータは、その後どれだけデータが変わっても「Q1-2024-snapshot」として参照できます。

---

## ステップ解説

### Step 1: ブランチ・タグ一覧

```sql
SHOW BRANCHES IN iceberg;
SHOW TAGS IN iceberg;
```

### Step 2: 変更を積んで監査ログを作る

```sql
-- 変更1: 価格改定
UPDATE iceberg.ecommerce.products SET price = price * 1.1 WHERE category = 'Electronics';

-- 変更2: 新規顧客追加
INSERT INTO iceberg.ecommerce.customers VALUES (6, ...);

-- 変更3: ステータス更新
UPDATE iceberg.ecommerce.orders SET status = 'archived' WHERE ...;
```

### Step 3: Nessie API で監査ログを確認

```bash
# mainブランチのコミット履歴を確認
curl -s "http://localhost:19120/api/v2/trees/main/history" | jq '
  .logEntries[] | {
    commitTime: .commitMeta.commitTime,
    message:    .commitMeta.message,
    hash:       .commitMeta.hash
  }
'
```

各SQLの実行がコミットとして記録されています。本番環境では `author` フィールドにユーザー名が入るため、「誰が変更したか」まで追跡できます。

### Step 4: タグを作成

```sql
-- 現時点に "Q1-2024-snapshot" タグを付ける
CREATE TAG "Q1-2024-snapshot" IN iceberg;
SHOW TAGS IN iceberg;
```

### Step 6: タグを使った時点クエリ

```sql
-- Q1タグ時点のデータ
SELECT COUNT(*) AS order_count
FROM iceberg.ecommerce.orders AT TAG "Q1-2024-snapshot";

-- 現在のデータ
SELECT COUNT(*) AS order_count
FROM iceberg.ecommerce.orders;
```

---

## Nessie REST API リファレンス（主要エンドポイント）

| エンドポイント | 内容 |
|---|---|
| `GET /api/v2/trees` | ブランチ・タグ一覧 |
| `GET /api/v2/trees/{ref}/history` | コミット履歴 |
| `GET /api/v2/trees/{ref}/diff/{other}` | ブランチ間差分 |
| `GET /api/v2/config` | サーバー設定 |

```bash
# コミット履歴（件数確認）
curl -s "http://localhost:19120/api/v2/trees/main/history" | jq '.logEntries | length'

# 2つのブランチ間の差分
curl -s "http://localhost:19120/api/v2/trees/main/diff/feature/add-books" | jq .
```

---

## ブランチ vs タグの使い分け

| | ブランチ | タグ |
|---|---|---|
| 変更可能 | はい（新コミットを追加できる） | いいえ（不変） |
| 主な用途 | 開発作業・ETLテスト | リリース記念・スナップショット保存 |
| 例 | `feature/add-books`、`dev` | `v1.0.0`、`Q1-2024-snapshot` |

---

## 本番環境での活用シナリオ

1. **バッチETLのデプロイフロー**
   - `dev` ブランチでETLを開発
   - `staging` ブランチでQA
   - `main` にマージして本番反映

2. **決算・レポートのデータ固定**
   - 四半期末にタグを作成
   - 「2024年Q1確定値」として永続的に参照可能

3. **規制対応の監査証跡**
   - Nessieのコミット履歴をSIEMやログ管理ツールにエクスポート
   - いつ・誰が・どのデータを変更したかを証明
