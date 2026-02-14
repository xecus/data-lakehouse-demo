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

## クイックデモ（基本の分析クエリ）

### Step 1: テーブルのセットアップ

```bash
make setup
```

作成されるテーブル:

```
iceberg.ecommerce
├── customers    (顧客マスタ   : country でパーティション)
├── products     (商品マスタ)
├── orders       (注文ヘッダ   : order_date でパーティション)
└── order_items  (注文明細)
```

### Step 2: 基本分析クエリの実行

```bash
make demo
```

| クエリ | 内容 |
|---|---|
| Q1 | 日次売上集計 |
| Q2 | 国別顧客数・売上 |
| Q3 | 商品カテゴリ別売上ランキング |
| Q4 | 顧客別購入履歴・LTV |
| Q5 | 月次売上トレンド |

---

## ハンズオン シナリオ

Iceberg と Nessie の機能を段階的に体験できる6つのシナリオを用意しています。

| シナリオ | テーマ | 難易度 | ドキュメント |
|---|---|---|---|
| [01](./sql/scenarios/01_iceberg_acid.sql) | **Iceberg ACID操作** — UPDATE / DELETE / MERGE | ★★☆☆☆ | [解説](./docs/scenario-01-iceberg-acid.md) |
| [02](./sql/scenarios/02_iceberg_time_travel.sql) | **タイムトラベル** — 過去データの参照・復元 | ★★☆☆☆ | [解説](./docs/scenario-02-iceberg-time-travel.md) |
| [03](./sql/scenarios/03_iceberg_schema_evolution.sql) | **スキーマ進化** — ダウンタイムなしのカラム変更 | ★★☆☆☆ | [解説](./docs/scenario-03-iceberg-schema-evolution.md) |
| [04](./sql/scenarios/04_iceberg_metadata.sql) | **メタデータ探索** — $files / $snapshots / EXPLAIN | ★★★☆☆ | [解説](./docs/scenario-04-iceberg-metadata.md) |
| [05](./sql/scenarios/05_nessie_branch.sql) | **Nessieブランチ** — Gitライクなデータ開発ワークフロー | ★★★★☆ | [解説](./docs/scenario-05-nessie-branch.md) |
| [06](./sql/scenarios/06_nessie_audit.sql) | **Nessie監査** — タグ管理とコミット履歴 | ★★★★☆ | [解説](./docs/scenario-06-nessie-audit.md) |

### 学習パス

```
基礎                                                       応用
 │                                                          │
setup → demo → [01 ACID] → [02 TimTravel] → [03 Schema] → [04 Metadata] → [05 Branch] → [06 Audit]
               └─── Icebergを「使う」 ───┘  └─── Icebergを「理解する」 ──┘  └── Nessieを「活かす」 ──┘
```

### シナリオの実行方法

```bash
# 個別実行
make scenario-01   # ACID操作
make scenario-02   # タイムトラベル
make scenario-03   # スキーマ進化
make scenario-04   # メタデータ探索
make scenario-05   # Nessieブランチ
make scenario-06   # Nessie監査

# 全シナリオを順番に実行
make scenario-all

# 大量データを投入してパーティション効果を体感（オプション）
make seed
```

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
├── docker-compose.yml            # 全サービスの定義
├── Makefile                      # 操作コマンド集
├── trino/
│   └── catalog/
│       └── iceberg.properties    # IcebergカタログのTrino設定
├── sql/
│   ├── setup.sql                 # テーブル定義 + サンプルデータ投入
│   ├── demo.sql                  # 基本分析クエリ集
│   ├── scenarios/                # ハンズオンシナリオSQL
│   │   ├── 01_iceberg_acid.sql
│   │   ├── 02_iceberg_time_travel.sql
│   │   ├── 03_iceberg_schema_evolution.sql
│   │   ├── 04_iceberg_metadata.sql
│   │   ├── 05_nessie_branch.sql
│   │   └── 06_nessie_audit.sql
│   └── seed/
│       └── large_dataset.sql     # 大量サンプルデータ（パーティション効果確認用）
└── docs/                         # 各シナリオの解説ドキュメント
    ├── scenario-01-iceberg-acid.md
    ├── scenario-02-iceberg-time-travel.md
    ├── scenario-03-iceberg-schema-evolution.md
    ├── scenario-04-iceberg-metadata.md
    ├── scenario-05-nessie-branch.md
    └── scenario-06-nessie-audit.md
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
