# シナリオ03: Iceberg スキーマ進化

**難易度**: ★★☆☆☆
**所要時間**: 約10分
**前提**: `make setup` 完了後

---

## 何を学ぶか

従来のデータレイク（生のParquet）ではスキーマ変更が問題になります。カラムを追加するだけでも既存ファイルとの互換性が崩れ、全ファイルの書き換えが必要になることがあります。

Iceberg ではスキーマ変更が**メタデータの更新だけで完結**します。

- 既存の Parquet ファイルは一切書き換えられない
- ダウンタイムなし
- クエリはスキーマの新旧に関係なく正常動作

**サポートされる変更操作:**

| 操作 | SQL |
|---|---|
| カラム追加 | `ADD COLUMN` |
| カラム名変更 | `RENAME COLUMN` |
| カラム削除 | `DROP COLUMN` |
| カラム型の安全な拡張 | `int` → `bigint` など |

---

## 実行方法

```bash
make scenario-03
```

---

## ステップ解説

### Step 1: ADD COLUMN

```sql
ALTER TABLE iceberg.ecommerce.orders ADD COLUMN coupon_code VARCHAR;
ALTER TABLE iceberg.ecommerce.orders ADD COLUMN discount_amount DECIMAL(10,2);
```

実行後、既存レコードを確認すると:

```sql
SELECT order_id, total_amount, coupon_code, discount_amount
FROM iceberg.ecommerce.orders LIMIT 3;
```

```
 order_id | total_amount | coupon_code | discount_amount
----------+--------------+-------------+-----------------
     1001 |     96500.00 | NULL        | NULL
     1002 |     30000.00 | NULL        | NULL
```

**注目ポイント**: 既存レコードの新カラムは `NULL` になります。エラーにならず、既存 Parquet ファイルも書き換えられません。

### Step 3: RENAME COLUMN

```sql
ALTER TABLE iceberg.ecommerce.orders RENAME COLUMN coupon_code TO promotion_code;
```

Iceberg はカラムを **ID** で追跡しているため、名前を変えても内部的には同じカラムとして扱います。既存のクエリが壊れないよう注意が必要ですが、データファイルは変更されません。

### Step 4: DROP COLUMN

```sql
ALTER TABLE iceberg.ecommerce.orders DROP COLUMN discount_amount;
```

カラムを削除しても既存ファイルはそのままです。その列のデータはメタデータから「存在しない」とマークされるだけです。

---

## タイムトラベルとスキーマ変更の組み合わせ

スキーマ変更をまたいだタイムトラベルも機能します。

```sql
-- coupon_code が存在した時代のスナップショットに戻ると
-- coupon_code カラムつきでデータが返ってくる
SELECT * FROM iceberg.ecommerce.orders
FOR VERSION AS OF <coupon_code追加後のsnapshot_id>;
```

これにより「このカラムが追加される前のデータはどうだったか」という分析が可能です。

---

## やってはいけない変更

Iceberg でも**非互換な型変換**はできません。

```sql
-- NG: BIGINT → INT（縮小方向の変換）
ALTER TABLE ... ALTER COLUMN order_id SET DATA TYPE INT;

-- OK: INT → BIGINT（拡大方向の変換）
ALTER TABLE ... ALTER COLUMN quantity SET DATA TYPE BIGINT;
```

---

## 次のステップ

スキーマ変更の内部がどう記録されているかをメタデータから確認する: [シナリオ04: メタデータ探索](./scenario-04-iceberg-metadata.md)
