# シナリオ02: Iceberg タイムトラベル

**難易度**: ★★☆☆☆
**所要時間**: 約15分
**前提**: `make setup` 完了後

---

## 何を学ぶか

Iceberg はデータを変更するたびに**スナップショット**を作成します。これにより、過去の任意の時点のデータを参照・復元できます。

**ユースケース:**
- 誤ってデータを削除・更新してしまったときの復元
- 「先月末時点」「バッチ処理前」など特定時点のデータを分析
- データパイプラインのデバッグ（どの処理でデータが変わったかを追跡）

---

## 実行方法

```bash
make scenario-02
```

---

## タイムトラベルの2つの構文

### パターン1: スナップショットID指定

```sql
SELECT * FROM iceberg.ecommerce.orders
FOR VERSION AS OF 4843723319432220799;
```

スナップショットIDを `$snapshots` テーブルで確認してから指定します。

### パターン2: タイムスタンプ指定

```sql
SELECT * FROM iceberg.ecommerce.orders
FOR TIMESTAMP AS OF TIMESTAMP '2024-01-20 10:00:00 UTC';
```

時刻を直接指定できます。IDを調べる手間がなく、使いやすい形式です。

---

## ステップ解説

### Step 1-2: スナップショットを複数作る

タイムトラベルを体感するには、まず複数の変更操作でスナップショットを積みます。

```sql
-- INSERT でスナップショット1を作成
INSERT INTO iceberg.ecommerce.orders VALUES (2001, ...);

-- UPDATE でスナップショット2を作成
UPDATE iceberg.ecommerce.orders SET status = 'shipped' WHERE ...;
```

### Step 2: スナップショット履歴の確認

```sql
SELECT snapshot_id, committed_at, operation
FROM iceberg.ecommerce."orders$snapshots"
ORDER BY committed_at;
```

**実行例:**
```
 snapshot_id          | committed_at                    | operation
----------------------+---------------------------------+-----------
 4927423714614925184  | 2024-01-15 17:15:40.104 UTC     | append     ← 初期INSERT
 4843723319432220799  | 2024-01-15 17:15:43.589 UTC     | append     ← 追加INSERT
 3912847651023847519  | 2024-01-15 17:15:50.201 UTC     | overwrite  ← UPDATE
```

### Step 5: リカバリーシナリオ

最も実用的なパターン: データを誤削除してしまった場合の復元

```sql
-- 1. 誤って削除
DELETE FROM iceberg.ecommerce.orders WHERE order_date >= DATE '2024-03-01';

-- 2. スナップショット確認（削除前のIDを特定）
SELECT snapshot_id, committed_at, operation FROM iceberg.ecommerce."orders$snapshots";

-- 3. タイムトラベルで復元
INSERT INTO iceberg.ecommerce.orders
SELECT * FROM iceberg.ecommerce.orders
FOR VERSION AS OF <削除前のsnapshot_id>
WHERE order_date >= DATE '2024-03-01';
```

---

## タイムスタンプ指定の注意事項

`FOR TIMESTAMP AS OF` に指定する時刻は **UTC** で評価されます。

```sql
-- 1時間前のデータを参照（推奨形式）
SELECT * FROM iceberg.ecommerce.orders
FOR TIMESTAMP AS OF (CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
```

---

## `$history` テーブルとの違い

| テーブル | 役割 |
|---|---|
| `$snapshots` | 各スナップショットの詳細（統計情報含む） |
| `$history` | スナップショットの親子関係・有効性 |

`$history` の `is_current_ancestor` フラグで、現在有効な履歴チェーンかどうかが分かります。

---

## 次のステップ

スキーマも変化させてタイムトラベルがどう振る舞うかを確認する: [シナリオ03: スキーマ進化](./scenario-03-iceberg-schema-evolution.md)
