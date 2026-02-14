# テスト手順

このドキュメントは `docker compose up` 後の動作確認手順をまとめたものです。

## 前提条件

```bash
docker compose up -d
docker compose ps   # 全サービスが healthy になるまで待つ
```

全サービス (`minio`, `nessie`, `trino`) の STATUS が `(healthy)` であることを確認してください。

---

## Step 1: テーブルセットアップ

スキーマ・テーブルの作成とサンプルデータの投入を行います。

```bash
docker exec trino trino --file /etc/trino/sql/setup.sql
```

### 期待される出力

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

---

## Step 2: アナリティクスクエリ

売上分析クエリと Iceberg メタデータクエリを一括実行します。

```bash
docker exec trino trino --file /etc/trino/sql/demo.sql
```

### 確認項目

| クエリ | 内容 | 確認ポイント |
|--------|------|------------|
| Q1 | 日次売上集計 | `completed` ステータスの注文のみ集計されること |
| Q2 | 国別 顧客数・注文数・売上 | Japan / USA の2行が返ること |
| Q3 | 商品カテゴリ別売上ランキング | 売上降順で Electronics / Furniture が並ぶこと |
| Q4 | 顧客LTV | 購入0回の顧客（鈴木一郎）も LEFT JOIN で含まれること |
| Q5 | 月次売上トレンド | 2024-01 / 2024-02 の2行が返ること |
| I1 | スナップショット履歴 | CREATE TABLE と INSERT の2スナップショットが返ること |
| I3 | マニフェストファイル一覧 | 1件以上のマニフェストが返ること |
| I4 | パーティション情報 | `order_date` 別に5パーティションが返ること |

---

## Step 3: Iceberg 機能テスト

### 3-1. スキーマ進化（カラム追加）

```bash
docker exec trino trino --execute "
ALTER TABLE iceberg.ecommerce.orders ADD COLUMN coupon_code VARCHAR;
SELECT order_id, total_amount, coupon_code FROM iceberg.ecommerce.orders LIMIT 3;
"
```

**期待される結果:** 既存レコードの `coupon_code` カラムが空文字列（NULL）で返ること。

### 3-2. タイムトラベル

まずスナップショット ID を取得します。

```bash
docker exec trino trino --execute "
SELECT snapshot_id, committed_at, operation
FROM iceberg.ecommerce.\"orders\$snapshots\"
ORDER BY committed_at;
"
```

出力例:
```
"4927423714614925184","2026-02-11 17:15:40.104 UTC","append"   -- CREATE TABLE
"4843723319432220799","2026-02-11 17:15:43.589 UTC","append"   -- INSERT
```

INSERT 直後のスナップショット ID（2行目）を使ってタイムトラベルクエリを実行します。

```bash
docker exec trino trino --execute "
SELECT * FROM iceberg.ecommerce.orders FOR VERSION AS OF <snapshot_id>;
"
```

**期待される結果:** `coupon_code` カラムが存在しない状態（ADD COLUMN 前）の5行が返ること。

---

## Step 4: 疎通確認

### Nessie カタログ

```bash
curl -s http://localhost:19120/api/v2/trees
```

**期待される結果:** `main` ブランチが返ること。

```json
{
  "references": [{ "type": "BRANCH", "name": "main", "hash": "..." }]
}
```

### MinIO ストレージ

```bash
curl -s http://localhost:9000/minio/health/live && echo "OK"
```

**期待される結果:** `OK` が出力されること。

MinIO コンソール（http://localhost:9001）にブラウザでアクセスし、`warehouse/ecommerce/` 配下に各テーブルの Parquet ファイルとメタデータが格納されていることも確認できます。

---

## テーブル行数サマリー

```bash
docker exec trino trino --execute "
SELECT 'customers'   AS tbl, COUNT(*) AS cnt FROM iceberg.ecommerce.customers
UNION ALL SELECT 'products',    COUNT(*) FROM iceberg.ecommerce.products
UNION ALL SELECT 'orders',      COUNT(*) FROM iceberg.ecommerce.orders
UNION ALL SELECT 'order_items', COUNT(*) FROM iceberg.ecommerce.order_items;
"
```

| テーブル | 行数 |
|---------|-----|
| customers | 5 |
| products | 6 |
| orders | 5 |
| order_items | 7 |
