# シナリオ01: Iceberg ACID操作

**難易度**: ★★☆☆☆
**所要時間**: 約10分
**前提**: `make setup` 完了後

---

## 何を学ぶか

Apache Iceberg は「ただのParquetの上に乗ったテーブルフォーマット」ではなく、完全な **ACID トランザクション**をサポートします。

- `UPDATE` — 既存レコードの部分的な更新
- `DELETE` — 条件に一致するレコードの削除
- `MERGE INTO` — Upsert（あれば更新、なければ挿入）

通常のデータレイク（生のParquetファイル）ではこれらが不可能ですが、Iceberg ではできます。

---

## 実行方法

```bash
make scenario-01
```

または対話的に試したい場合:

```bash
make trino
# Trinoシェルが起動したら、以下を1ステップずつコピペして実行
```

---

## ステップ解説

### Step 1: UPDATE

```sql
UPDATE iceberg.ecommerce.orders
SET status = 'shipped'
WHERE status = 'processing';
```

**注目ポイント**: Iceberg の UPDATE は内部的に「対象レコードを削除した新ファイルを作成 + 更新後レコードを追加した新ファイルを作成」という形で実現されます。これが `$snapshots` の `operation` が `overwrite` になる理由です。

### Step 2: DELETE

```sql
DELETE FROM iceberg.ecommerce.orders
WHERE status = 'cancelled';
```

**注目ポイント**: 物理ファイルはすぐに削除されません。新しいスナップショットが作られ、古いファイルは「不要マーク」がつきます。`VACUUM` （Icebergでは `expire_snapshots`）を実行するまで物理ファイルは残ります。これがタイムトラベルを可能にする仕組みです。

### Step 3: MERGE INTO

```sql
MERGE INTO iceberg.ecommerce.orders AS target
USING ( VALUES (...) ) AS source (...)
ON target.order_id = source.order_id
WHEN MATCHED THEN UPDATE SET ...
WHEN NOT MATCHED THEN INSERT ...;
```

**注目ポイント**: ETLパイプラインで最もよく使われるパターンです。「差分データを受け取って既存テーブルに適用する」という処理を1クエリで実現できます。

### Step 4: スナップショット確認

```sql
SELECT snapshot_id, committed_at, operation,
       summary['added-records']   AS added,
       summary['deleted-records'] AS deleted
FROM iceberg.ecommerce."orders$snapshots"
ORDER BY committed_at;
```

**注目ポイント**: 各DML操作が独立したスナップショットとして記録されています。この履歴があるからこそ、シナリオ02のタイムトラベルが機能します。

---

## 確認すべき結果

| 操作 | `operation` 値 | 説明 |
|---|---|---|
| INSERT | `append` | データ追加 |
| UPDATE | `overwrite` | 削除+追加として記録 |
| DELETE | `overwrite` | 削除として記録 |
| MERGE  | `overwrite` | 削除+追加として記録 |

---

## 次のステップ

このシナリオで作られたスナップショット履歴を使って、[シナリオ02: タイムトラベル](./scenario-02-iceberg-time-travel.md) でデータの過去状態を参照してみましょう。
