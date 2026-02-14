# シナリオ04: Iceberg メタデータ探索

**難易度**: ★★★☆☆
**所要時間**: 約20分
**前提**: `make setup` 完了後（`make seed` 実行後だとより多くのファイルが見えます）

---

## 何を学ぶか

Iceberg の高速性・信頼性の根拠となる**メタデータ階層構造**を実際に目で確認します。

```
スナップショット (snapshot)
  └─ マニフェストリスト (manifest list)  ← MinIO上のAvroファイル
       └─ マニフェストファイル (manifest) ← どのデータファイルが存在するか
            └─ データファイル (Parquet)   ← 実際のレコード
```

この階層のおかげで、Iceberg はクエリ実行時に「読む必要がないファイル」をメタデータだけで判断してスキップできます（パーティションプルーニング・データスキッピング）。

---

## 実行方法

```bash
make scenario-04
```

---

## メタデータテーブル一覧

Trino から `テーブル名$サフィックス` 形式でアクセスできます。

| テーブル | 内容 |
|---|---|
| `$snapshots` | コミット履歴・統計情報 |
| `$history` | スナップショットの変遷・親子関係 |
| `$manifests` | マニフェストファイル一覧 |
| `$files` | 物理データファイル一覧 |
| `$partitions` | パーティション別統計 |
| `$entries` | マニフェストエントリ詳細 |

---

## ステップ解説

### Step 1: $snapshots — 変更の歴史

```sql
SELECT
    snapshot_id,
    committed_at,
    operation,
    summary['total-data-files'] AS total_files,
    summary['total-records']    AS total_records
FROM iceberg.ecommerce."orders$snapshots"
ORDER BY committed_at;
```

`summary` マップには以下のキーが含まれます:
- `added-data-files` / `deleted-data-files`: 今回の操作で追加/削除されたファイル数
- `added-records` / `deleted-records`: 今回の操作で追加/削除されたレコード数
- `total-data-files` / `total-records`: このスナップショット時点の合計

### Step 4: $files — 物理ファイルを見る

```sql
SELECT file_path, record_count, file_size_in_bytes
FROM iceberg.ecommerce."orders$files"
ORDER BY file_path;
```

**実行例（order_date パーティション）:**
```
 file_path                                                     | record_count | file_size_in_bytes
---------------------------------------------------------------+--------------+--------------------
 s3://warehouse/ecommerce/orders/data/order_date=2024-01-15/.. |            1 |               1234
 s3://warehouse/ecommerce/orders/data/order_date=2024-01-16/.. |            1 |               1189
 s3://warehouse/ecommerce/orders/data/order_date=2024-02-10/.. |            1 |               1198
```

**注目ポイント**: ファイルパスに `order_date=2024-01-15` というパーティション情報が入っています。これにより、特定日付のフィルタをかけたクエリはそのパーティションのファイルだけを読みます。

### Step 5: $partitions — パーティション統計

```sql
SELECT partition, record_count, file_count, total_size
FROM iceberg.ecommerce."orders$partitions"
ORDER BY partition;
```

データ分散の偏りを確認するのに便利です。

### Step 6: EXPLAIN でパーティションプルーニングを確認

```sql
EXPLAIN
SELECT order_id, total_amount
FROM iceberg.ecommerce.orders
WHERE order_date = DATE '2024-01-15';
```

EXPLAIN の出力で `TableScan` 部分に `files=1` と表示されれば、その日付のファイル1つだけを読むことを示しています。全ファイルを読む `TABLE FULL SCAN` との違いを確認してください。

---

## MinIO での確認

メタデータの実体は MinIO 上の JSON/Avro ファイルです。

1. http://localhost:9001 にアクセス（`admin` / `password`）
2. `warehouse/ecommerce/orders/` を開く
3. `data/` ディレクトリ: Parquet ファイル（パーティションごとにフォルダ分け）
4. `metadata/` ディレクトリ: スナップショットJSON・マニフェストAvroファイル

---

## 次のステップ

メタデータの理解を活かして、ブランチによる安全なデータ変更を体験する: [シナリオ05: Nessie ブランチワークフロー](./scenario-05-nessie-branch.md)
