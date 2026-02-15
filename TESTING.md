# 環境確認チェックリスト

`make up` 後にこのチェックリストを上から順に実行して、環境が正常に動いているかを確認してください。

---

## 1. サービスの起動確認

```bash
make ps
```

**期待される結果:** 全サービスが `(healthy)` であること。

```
NAME      STATUS
minio     Up (healthy)
nessie    Up (healthy)
trino     Up (healthy)
```

`health: starting` が続く場合は30秒ほど待ってから再実行してください。

---

## 2. 疎通確認

### Trino

```bash
curl -s http://localhost:8080/v1/info | jq .starting
```

**期待される結果:** `false`（起動完了）

### Nessie

```bash
curl -s http://localhost:19120/api/v2/trees | jq '[.references[] | {type, name}]'
```

**期待される結果:** `main` ブランチが返ること。

```json
[{ "type": "BRANCH", "name": "main" }]
```

### MinIO

```bash
curl -s http://localhost:9000/minio/health/live && echo "OK"
```

**期待される結果:** `OK` が出力されること。

MinIO コンソール（http://localhost:9001、`admin` / `password`）にブラウザでアクセスし、`warehouse` バケットが存在することも確認できます。

---

## 3. テーブルセットアップの確認

```bash
make setup
```

**期待される出力:**

```
CREATE SCHEMA
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE TABLE
INSERT: 5 rows
INSERT: 6 rows
INSERT: 5 rows
INSERT: 7 rows
```

セットアップ後の行数確認:

```bash
docker exec demo1-trino trino --execute "
SELECT 'customers'   AS tbl, COUNT(*) AS cnt FROM iceberg.ecommerce.customers
UNION ALL SELECT 'products',    COUNT(*) FROM iceberg.ecommerce.products
UNION ALL SELECT 'orders',      COUNT(*) FROM iceberg.ecommerce.orders
UNION ALL SELECT 'order_items', COUNT(*) FROM iceberg.ecommerce.order_items;
"
```

| テーブル | 期待行数 |
|---|---|
| customers | 5 |
| products | 6 |
| orders | 5 |
| order_items | 7 |

---

## 4. 基本クエリの動作確認

```bash
make demo
```

**確認ポイント:**

| クエリ | 確認内容 |
|---|---|
| Q1 日次売上 | `completed` の注文のみ、4行返ること |
| Q2 国別売上 | `Japan` / `USA` の2行が返ること |
| Q3 カテゴリ別 | `Electronics` / `Furniture` が売上降順で並ぶこと |
| Q4 顧客LTV | 購入0回の鈴木一郎も含む5行が返ること（LEFT JOIN） |
| Q5 月次トレンド | `2024-01` / `2024-02` の2行が返ること |

---

## 5. MinIO にデータが格納されていることを確認

```bash
docker exec minio /usr/bin/mc ls minio/warehouse/ecommerce/ --recursive | head -20
```

**期待される結果:** `orders/`, `customers/` 等のディレクトリ配下に `.parquet` ファイルが存在すること。

---

## シナリオの動作確認

各シナリオの詳細な確認手順は `docs/` を参照してください。

| コマンド | ドキュメント |
|---|---|
| `make scenario-01` | [docs/scenario-01-iceberg-acid.md](./docs/scenario-01-iceberg-acid.md) |
| `make scenario-02` | [docs/scenario-02-iceberg-time-travel.md](./docs/scenario-02-iceberg-time-travel.md) |
| `make scenario-03` | [docs/scenario-03-iceberg-schema-evolution.md](./docs/scenario-03-iceberg-schema-evolution.md) |
| `make scenario-04` | [docs/scenario-04-iceberg-metadata.md](./docs/scenario-04-iceberg-metadata.md) |
| `make scenario-05` | [docs/scenario-05-nessie-branch.md](./docs/scenario-05-nessie-branch.md) |
| `make scenario-06` | [docs/scenario-06-nessie-audit.md](./docs/scenario-06-nessie-audit.md) |

---

## トラブルシューティング

**Trino が healthy にならない**

```bash
make logs
# または
docker compose logs trino | grep -E "ERROR|WARN" | tail -20
```

よくある原因: MinIO または Nessie がまだ起動していない。`make ps` でヘルスチェックを確認してから再試行してください。

**setup が失敗する（テーブルが既に存在する）**

```bash
make reset   # データを含む全リソースを削除
make up      # 再起動
make setup
```

**Nessie の `main` ブランチが返らない**

```bash
docker compose logs nessie | tail -20
```

RocksDB の初期化に失敗している場合は `make reset` で volume ごと削除して再起動してください。
