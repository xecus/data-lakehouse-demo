# Data Lakehouse Demo: Trino + Nessie + Apache Iceberg + MinIO

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Docker](https://img.shields.io/badge/Docker-Compose-blue)](./docker-compose.yml)
[![Trino](https://img.shields.io/badge/Trino-479-DD00A1)](https://trino.io/)
[![Iceberg](https://img.shields.io/badge/Apache%20Iceberg-latest-blue)](https://iceberg.apache.org/)
[![Nessie](https://img.shields.io/badge/Nessie-latest-green)](https://projectnessie.org/)

`docker compose up` だけで起動できる、モダンなデータレイクハウス構成のハンズオンデモです。

**ユースケース**: ECサイトの売上分析データ基盤

---

## 構成技術と役割

| コンポーネント | 役割 | アクセス先 |
|---|---|---|
| **Trino** | 分散SQLクエリエンジン。複数データソースを単一SQLで横断クエリ可能 | http://localhost:8080 |
| **Apache Iceberg** | テーブルフォーマット。ACID、タイムトラベル、スキーマ進化をサポート | — |
| **Nessie** | データカタログ。Gitライクなブランチ・コミットでテーブルのバージョン管理が可能 | http://localhost:19120 |
| **MinIO** | S3互換オブジェクトストレージ。IcebergのデータファイルとメタデータをParquet形式で保存 | http://localhost:9001 |

```
┌──────────────────────────────────────────────┐
│         Trino  :8080  (クエリエンジン)          │
└────────────────────┬─────────────────────────┘
                     │ Iceberg connector
         ┌───────────┴───────────┐
         ▼                       ▼
┌─────────────────┐   ┌──────────────────────┐
│  Nessie  :19120 │   │    MinIO  :9000/9001  │
│  (カタログ/      │   │  (データファイル格納)    │
│  バージョン管理)  │   │  s3://warehouse/      │
└─────────────────┘   └──────────────────────┘
         │                       │
         └───────── Iceberg ─────┘
                 (テーブルフォーマット)
```

---

## クイックスタート

### 前提条件

- Docker Desktop 4.x 以上
- Docker Compose v2.x 以上

### 起動

```bash
git clone <this-repo>
cd <repo-dir>
docker compose up -d
```

全サービスの起動まで約30秒かかります。

```bash
# 起動確認
docker compose ps
```

```
NAME      STATUS
minio     Up (healthy)
nessie    Up (healthy)
trino     Up (healthy)
```

### Trinoに接続

```bash
docker exec -it trino trino
```

起動できたら以下でカタログを確認します。

```sql
SHOW CATALOGS;
-- iceberg
-- system
```

---

## デモ手順

### Step 1: テーブルのセットアップ

`sql/setup.sql` を実行してスキーマとテーブルを作成します。

```bash
docker exec trino trino --file /etc/trino/sql/setup.sql
```

または、Trinoシェル上で `sql/setup.sql` の内容をコピペしても構いません。

作成されるテーブル:

```
iceberg.ecommerce
├── customers    (顧客マスタ   : country でパーティション)
├── products     (商品マスタ)
├── orders       (注文ヘッダ   : order_date でパーティション)
└── order_items  (注文明細)
```

### Step 2: 分析クエリの実行

`sql/demo.sql` に以下のクエリが含まれています。

```bash
docker exec trino trino --file /etc/trino/sql/demo.sql
```

| クエリ | 内容 |
|---|---|
| クエリ1 | 日次売上集計 |
| クエリ2 | 国別顧客数・売上 |
| クエリ3 | 商品カテゴリ別売上ランキング |
| クエリ4 | 顧客別購入履歴・LTV |
| クエリ5 | 月次売上トレンド |

実行例:

```
-- クエリ2: 国別売上
 country | customer_count | order_count | total_revenue
---------+----------------+-------------+---------------
 Japan   |              3 |           3 |     171500.00
 USA     |              2 |           2 |     119000.00
```

---

## Iceberg の主要機能デモ

### タイムトラベル（過去のスナップショットを参照）

```sql
-- スナップショット履歴を確認
SELECT snapshot_id, committed_at, operation
FROM iceberg.ecommerce."orders$snapshots"
ORDER BY committed_at;

-- 特定のスナップショット時点のデータを参照
SELECT * FROM iceberg.ecommerce.orders
FOR VERSION AS OF <snapshot_id>;
```

### スキーマ進化（ダウンタイムなしでカラム追加）

```sql
ALTER TABLE iceberg.ecommerce.orders ADD COLUMN coupon_code VARCHAR;
SELECT * FROM iceberg.ecommerce.orders LIMIT 3;
-- 既存レコードの coupon_code は NULL になる（エラーにならない）
```

### パーティション情報の確認

```sql
SELECT * FROM iceberg.ecommerce."orders$partitions";
```

---

## Nessie のブランチ機能デモ

データに対して Git と同じようなブランチ・マージ操作ができます。

### ブランチの作成と切り替え

```bash
# mainブランチの現在のhashを取得
HASH=$(curl -s http://localhost:19120/api/v2/trees/main | jq -r '.reference.hash')

# dev ブランチを作成
curl -s -X POST "http://localhost:19120/api/v2/trees" \
  -H "Content-Type: application/json" \
  -d "{\"type\": \"BRANCH\", \"name\": \"dev\", \"hash\": \"${HASH}\", \"reference\": {\"type\": \"BRANCH\", \"name\": \"main\"}}" | jq .

# ブランチ一覧を確認
curl -s http://localhost:19120/api/v2/trees | jq '[.references[] | {type, name}]'
```

### devブランチのデータを操作（mainには影響しない）

Trinoで `iceberg.ecommerce` のカタログ設定を `nessie-ref=dev` に切り替えることで、ブランチ分離が可能です。これにより**本番データに影響を与えずにデータ実験・ETLテスト**ができます。

---

## MinIO でのデータ確認

1. http://localhost:9001 にアクセス（`admin` / `password`）
2. `warehouse` バケットを開く
3. Iceberg が作成したフォルダ構造を確認:

```
warehouse/
└── ecommerce/
    ├── customers/
    │   └── data/            ← Parquet ファイル（country別パーティション）
    ├── orders/
    │   ├── data/            ← Parquet ファイル（date別パーティション）
    │   └── metadata/        ← Iceberg メタデータ（JSON/Avro）
    └── ...
```

---

## Trino Web UI でのクエリ監視

http://localhost:8080 にアクセスすると、実行中・完了済みクエリの詳細を確認できます。

- クエリの実行計画（Explain）
- ステージ別の処理時間・行数
- リソース使用量

---

## よく使うコマンド

```bash
# 起動
docker compose up -d

# 全ログをリアルタイム確認
docker compose logs -f

# Trino シェルに接続
docker exec -it trino trino

# セットアップSQLの実行
docker exec trino trino --file /etc/trino/sql/setup.sql

# サービスの停止（データは保持）
docker compose down

# 完全リセット（データも削除）
docker compose down -v
```

---

## トラブルシューティング

**Trinoが起動しない**

```bash
docker compose logs trino | grep ERROR
```

よくある原因: MinIO または Nessie がまだ起動していない。`docker compose ps` でヘルスチェックを確認してから再試行してください。

**MinIO の `warehouse` バケットが存在しない**

```bash
docker compose logs minio-setup
# "Bucket created successfully" が出ているか確認

# 手動でバケット作成する場合
docker exec minio-setup /usr/bin/mc mb minio/warehouse
```

**全てリセットしたい**

```bash
docker compose down -v && docker compose up -d
```

---

## ディレクトリ構成

```
.
├── docker-compose.yml        # 全サービスの定義
├── trino/
│   └── catalog/
│       └── iceberg.properties  # IcebergカタログのTrino設定
├── sql/
│   ├── setup.sql               # テーブル定義 + サンプルデータ投入
│   └── demo.sql                # 分析クエリ集
└── README.md
```

---

## 参考リンク

- [Apache Iceberg ドキュメント](https://iceberg.apache.org/docs/latest/)
- [Project Nessie ドキュメント](https://projectnessie.org/docs/)
- [Trino ドキュメント](https://trino.io/docs/current/)
- [Trino Iceberg Connector](https://trino.io/docs/current/connector/iceberg.html)
- [MinIO ドキュメント](https://min.io/docs/minio/linux/index.html)

---

## ライセンス

[MIT License](./LICENSE)
