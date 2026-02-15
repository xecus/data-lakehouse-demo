-- ============================================================
-- シナリオ01: Iceberg ACID操作
-- UPDATE / DELETE / MERGE INTO
--
-- 目的:
--   IcebergはただのParquetではなく、完全なACIDトランザクションを
--   サポートするテーブルフォーマットであることを体感する。
--
-- 前提: setup.sql を先に実行してください
--
-- ⚠️  再実行の注意:
--   このスクリプトは setup 直後のクリーンな状態を前提としています。
--   2回目以降の実行は期待通りの結果にならない場合があります。
--   再実行前に以下を実行してリセットしてください:
--     make reset && make up && make setup
--
-- 実行方法:
--   make scenario-01
--   または: docker exec demo1-trino trino --file /etc/trino/sql/scenarios/01_iceberg_acid.sql
-- ============================================================

-- ------------------------------------------------------------
-- 事前確認: 現在のデータ状態
-- ------------------------------------------------------------

-- [A0-1] 注文の現在のステータス一覧
SELECT order_id, customer_id, order_date, status, total_amount
FROM iceberg.ecommerce.orders
ORDER BY order_id;

-- [A0-2] 現在のスナップショット数（操作前）
SELECT COUNT(*) AS snapshot_count
FROM iceberg.ecommerce."orders$snapshots";

-- ============================================================
-- Step 1: UPDATE — 注文ステータスの更新
-- ============================================================
-- ビジネスシナリオ: 配送処理が完了し、processing → shipped に変更する

UPDATE iceberg.ecommerce.orders
SET status = 'shipped'
WHERE status = 'processing';

-- 確認: 更新されたことを確認
SELECT order_id, status
FROM iceberg.ecommerce.orders
WHERE order_id = 1005;

-- 確認: スナップショットが追加されたことを確認（UPDATEはoverwrite操作）
SELECT snapshot_id, committed_at, operation, element_at(summary, 'changed-partition-count') AS changed_partitions
FROM iceberg.ecommerce."orders$snapshots"
ORDER BY committed_at;

-- ============================================================
-- Step 2: DELETE — キャンセル注文データの削除
-- ============================================================
-- ビジネスシナリオ: キャンセルされた注文を物理削除する前に、
--                  まずテスト用のキャンセルデータを追加して削除を試す

-- キャンセルデータを1件追加
INSERT INTO iceberg.ecommerce.orders VALUES
    (1006, 2, DATE '2024-03-01', TIMESTAMP '2024-03-01 09:00:00', 'cancelled', 15000.00);

-- 追加確認
SELECT order_id, status FROM iceberg.ecommerce.orders ORDER BY order_id;

-- キャンセル注文を削除
DELETE FROM iceberg.ecommerce.orders
WHERE status = 'cancelled';

-- 確認: キャンセル注文が消えていること
SELECT order_id, status FROM iceberg.ecommerce.orders ORDER BY order_id;

-- ============================================================
-- Step 3: MERGE INTO — 新規注文データのUpsert
-- ============================================================
-- ビジネスシナリオ: 外部システムから送られてきた注文データを
--                  「あれば更新、なければ挿入」でロードする (ETLパターン)

-- Upsert対象データ（既存order_id=1001の更新 + 新規order_id=1007の追加）
MERGE INTO iceberg.ecommerce.orders AS target
USING (
    VALUES
        (1001, 1, DATE '2024-01-15', TIMESTAMP '2024-01-15 10:30:00', 'returned',  96500.00),
        (1007, 3, DATE '2024-03-05', TIMESTAMP '2024-03-05 14:00:00', 'completed', 30000.00)
) AS source (order_id, customer_id, order_date, order_timestamp, status, total_amount)
ON target.order_id = source.order_id
WHEN MATCHED THEN
    UPDATE SET status = source.status, total_amount = source.total_amount
WHEN NOT MATCHED THEN
    INSERT (order_id, customer_id, order_date, order_timestamp, status, total_amount)
    VALUES (source.order_id, source.customer_id, source.order_date, source.order_timestamp, source.status, source.total_amount);

-- 確認: order_id=1001 が returned に更新、order_id=1007 が追加されていること
SELECT order_id, customer_id, order_date, status, total_amount
FROM iceberg.ecommerce.orders
ORDER BY order_id;

-- ============================================================
-- Step 4: スナップショット履歴で全操作を振り返る
-- ============================================================
-- 各DML操作がスナップショットとして記録されていることを確認

SELECT
    snapshot_id,
    committed_at,
    operation,
    element_at(summary, 'added-records')   AS added_records,
    element_at(summary, 'deleted-records') AS deleted_records
FROM iceberg.ecommerce."orders$snapshots"
ORDER BY committed_at;

-- ポイント:
--   - INSERT  → operation: 'append'
--   - UPDATE  → operation: 'overwrite'（削除+追加として記録）
--   - DELETE  → operation: 'overwrite'
--   - MERGE   → operation: 'overwrite'
--   各操作が独立したスナップショットとして残り、後からタイムトラベルで参照できる
