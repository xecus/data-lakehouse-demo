# シナリオ05: Nessie ブランチワークフロー

**難易度**: ★★★★☆
**所要時間**: 約20分
**前提**: `make setup` 完了後

---

## 何を学ぶか

Project Nessie は**データカタログにGitの概念を持ち込んだ**ツールです。

テーブルの変更を「ブランチ」上で行い、問題なければ「マージ」、問題があれば「破棄」できます。

```
main  ──●──────────────────────────────●──► (マージ後)
         └──● feature/add-books ──────┘
```

**ユースケース:**
- ETLパイプラインの開発・テストを本番データから隔離
- データ変換ロジックの実験（壊しても安全）
- データエンジニアのレビューフロー（PRならぬDR: Data Request）
- 四半期レポート用の「スナップショットブランチ」

---

## 実行方法

```bash
make scenario-05
```

---

## Nessie のブランチ操作（REST API）

Nessie のブランチ操作は REST API で行います。Trino は Nessie のブランチ操作構文（`SHOW BRANCHES`、`CREATE BRANCH` 等）を直接サポートしていません。

| 操作 | curl コマンド |
|---|---|
| ブランチ一覧 | `curl -s http://localhost:19120/api/v2/trees` |
| ブランチ作成 | `curl -X POST http://localhost:19120/api/v2/trees -d {...}` |
| コミット履歴 | `curl -s http://localhost:19120/api/v2/trees/main/history` |
| ブランチ削除 | `curl -X DELETE http://localhost:19120/api/v2/trees/branch/<name>/<hash>` |

---

## ステップ解説

### Step 2: ブランチを作成（curl）

```bash
# mainブランチのハッシュを取得
HASH=$(curl -s http://localhost:19120/api/v2/trees/main | jq -r '.reference.hash')

# feature/add-books ブランチを作成
curl -s -X POST "http://localhost:19120/api/v2/trees" \
  -H "Content-Type: application/json" \
  -d "{\"type\":\"BRANCH\",\"name\":\"feature/add-books\",\"hash\":\"${HASH}\",\"reference\":{\"type\":\"BRANCH\",\"name\":\"main\"}}" | jq .

# ブランチ一覧を確認
curl -s http://localhost:19120/api/v2/trees | jq '[.references[] | {type, name}]'
```

### Step 3〜6: データ操作（Trino SQL）

シナリオ05のSQLでは、別スキーマ（`feature_add_books`）を使ってブランチの分離を模倣します。

```sql
-- 別スキーマ = featureブランチ相当
CREATE SCHEMA iceberg.feature_add_books;
INSERT INTO iceberg.feature_add_books.products VALUES (201, ...);

-- mainは影響を受けていない
SELECT COUNT(*) FROM iceberg.ecommerce.products;       -- 6件
SELECT COUNT(*) FROM iceberg.feature_add_books.products; -- 9件

-- マージ相当: mainに差分を追加
INSERT INTO iceberg.ecommerce.products
SELECT * FROM iceberg.feature_add_books.products WHERE product_id >= 201;
```

---

## Nessie REST API でブランチを確認

Trino 経由だけでなく、Nessie の Web UI やAPIでも確認できます。

```bash
# ブランチ一覧
curl -s http://localhost:19120/api/v2/trees | jq '[.references[] | {type, name}]'

# mainブランチのコミット履歴
curl -s "http://localhost:19120/api/v2/trees/main/history" | jq '.logEntries[].commitMeta | {commitTime, message}'
```

---

## Iceberg のスナップショット vs Nessie のコミット

| 概念 | 粒度 | 役割 |
|---|---|---|
| Iceberg スナップショット | テーブル単位 | テーブル内のデータ変更履歴 |
| Nessie コミット | カタログ全体 | 複数テーブルをまたいだ変更セット |

Nessie のブランチは「Icebergスナップショットへの参照の切り替え」として機能します。

---

## 次のステップ

Nessie のコミット履歴を監査ログとして活用する: [シナリオ06: Nessie 監査・コミット履歴](./scenario-06-nessie-audit.md)
