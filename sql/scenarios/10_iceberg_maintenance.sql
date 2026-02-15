-- ============================================================
-- シナリオ10: Iceberg テーブルメンテナンス
--
-- 目的:
--   本番運用で必要になるIcebergテーブルのメンテナンス操作を体験する。
--   スナップショットの期限切れ処理、孤立ファイルの削除、
--   小さなファイルのコンパクション（最適化）を通じて、
--   ストレージ効率とクエリ性能を維持する方法を理解する。
--
-- 前提: setup.sql を先に実行してください
--
-- ⚠️  再実行の注意:
--   このスクリプトは setup 直後のクリーンな状態を前提としています。
--   再実行前に make restart を実行してリセットしてください。
--
-- 実行方法:
--   make scenario-10
--   または: docker exec demo1-trino trino --file /etc/trino/sql/scenarios/10_iceberg_maintenance.sql
-- ============================================================

-- ============================================================
-- Step 1: メンテナンス対象のデータを準備する
-- ============================================================
-- 複数回の小さなINSERTでデータファイルを意図的に断片化させる

-- 1回目
INSERT INTO iceberg.ecommerce.orders VALUES
    (2001, 1, DATE '2024-03-01', TIMESTAMP '2024-03-01 10:00:00', 'completed', 12000.00);

-- 2回目
INSERT INTO iceberg.ecommerce.orders VALUES
    (2002, 2, DATE '2024-03-02', TIMESTAMP '2024-03-02 11:00:00', 'completed', 25000.00);

-- 3回目
INSERT INTO iceberg.ecommerce.orders VALUES
    (2003, 3, DATE '2024-03-03', TIMESTAMP '2024-03-03 12:00:00', 'processing', 8000.00);

-- 4回目
INSERT INTO iceberg.ecommerce.orders VALUES
    (2004, 4, DATE '2024-03-04', TIMESTAMP '2024-03-04 13:00:00', 'completed', 35000.00);

-- 5回目
INSERT INTO iceberg.ecommerce.orders VALUES
    (2005, 5, DATE '2024-03-05', TIMESTAMP '2024-03-05 14:00:00', 'processing', 5500.00);

-- UPDATE操作でさらにスナップショットを増やす
UPDATE iceberg.ecommerce.orders
SET status = 'shipped'
WHERE status = 'processing' AND order_date >= DATE '2024-03-01';

-- DELETE操作
DELETE FROM iceberg.ecommerce.orders
WHERE order_id = 2001;

-- ============================================================
-- Step 2: メンテナンス前の状態を確認
-- ============================================================

-- スナップショット数（INSERT + setup で多数蓄積されているはず）
SELECT COUNT(*) AS snapshot_count
FROM iceberg.ecommerce."orders$snapshots";

-- スナップショットの詳細
SELECT
    snapshot_id,
    committed_at,
    operation,
    element_at(summary, 'added-records')      AS added,
    element_at(summary, 'deleted-records')     AS deleted,
    element_at(summary, 'added-data-files')    AS added_files,
    element_at(summary, 'deleted-data-files')  AS deleted_files
FROM iceberg.ecommerce."orders$snapshots"
ORDER BY committed_at;

-- データファイル数（小さなファイルが多数あるはず）
SELECT
    COUNT(*)                           AS file_count,
    SUM(record_count)                  AS total_records,
    SUM(file_size_in_bytes)            AS total_bytes,
    AVG(file_size_in_bytes)            AS avg_file_bytes
FROM iceberg.ecommerce."orders$files";

-- マニフェストファイル数
SELECT COUNT(*) AS manifest_count
FROM iceberg.ecommerce."orders$manifests";

-- ============================================================
-- Step 3: スナップショットの期限切れ処理（expire_snapshots）
-- ============================================================
-- 古いスナップショットを削除してメタデータを軽量化する。
-- 削除されたスナップショットへのタイムトラベルはできなくなる。
--
-- retain_last: 保持するスナップショット数（最新N個を残す）
-- ※ デフォルトの最小保持期間（7日）をデモ用に短縮する
SET SESSION iceberg.expire_snapshots_min_retention = '0s';

-- 古いスナップショットを期限切れにする
ALTER TABLE iceberg.ecommerce.orders EXECUTE expire_snapshots(retention_threshold => '0s');

-- スナップショット数を再確認（減少しているはず）
SELECT COUNT(*) AS snapshot_count_after_expire
FROM iceberg.ecommerce."orders$snapshots";

SELECT
    snapshot_id,
    committed_at,
    operation
FROM iceberg.ecommerce."orders$snapshots"
ORDER BY committed_at;

-- ============================================================
-- Step 4: 孤立ファイルの削除（remove_orphan_files）
-- ============================================================
-- スナップショット期限切れや失敗した書き込みで参照されなくなった
-- データファイル（孤立ファイル）をストレージから物理削除する。
SET SESSION iceberg.remove_orphan_files_min_retention = '0s';

ALTER TABLE iceberg.ecommerce.orders EXECUTE remove_orphan_files(retention_threshold => '0s');

-- ファイル数を再確認
SELECT
    COUNT(*)                AS file_count_after_cleanup,
    SUM(file_size_in_bytes) AS total_bytes_after_cleanup
FROM iceberg.ecommerce."orders$files";

-- ============================================================
-- Step 5: ファイルコンパクション（optimize）
-- ============================================================
-- 小さなデータファイルを統合して、クエリ性能を改善する。
-- Icebergの小さなファイル問題（small file problem）への対処。

-- コンパクション前のファイル状態
SELECT
    COUNT(*)                AS file_count_before,
    SUM(record_count)       AS total_records_before,
    SUM(file_size_in_bytes) AS total_bytes_before
FROM iceberg.ecommerce."orders$files";

-- コンパクションを実行
ALTER TABLE iceberg.ecommerce.orders EXECUTE optimize;

-- コンパクション後のファイル状態
SELECT
    COUNT(*)                AS file_count_after,
    SUM(record_count)       AS total_records_after,
    SUM(file_size_in_bytes) AS total_bytes_after
FROM iceberg.ecommerce."orders$files";

-- データの整合性確認（レコード数が変わっていないこと）
SELECT COUNT(*) AS order_count FROM iceberg.ecommerce.orders;

SELECT order_id, customer_id, order_date, status, total_amount
FROM iceberg.ecommerce.orders
ORDER BY order_id;

-- ============================================================
-- Step 6: products テーブルでもメンテナンスを実演
-- ============================================================

-- products の現状
SELECT COUNT(*) AS snapshot_count FROM iceberg.ecommerce."products$snapshots";
SELECT COUNT(*) AS file_count FROM iceberg.ecommerce."products$files";

-- 一括メンテナンス（セッションプロパティは Step 3, 4 で設定済み）
ALTER TABLE iceberg.ecommerce.products EXECUTE expire_snapshots(retention_threshold => '0s');
ALTER TABLE iceberg.ecommerce.products EXECUTE remove_orphan_files(retention_threshold => '0s');
ALTER TABLE iceberg.ecommerce.products EXECUTE optimize;

-- メンテナンス後
SELECT COUNT(*) AS snapshot_count FROM iceberg.ecommerce."products$snapshots";
SELECT COUNT(*) AS file_count FROM iceberg.ecommerce."products$files";

-- ============================================================
-- まとめ
-- ============================================================
-- ポイント:
--   - expire_snapshots: 古いスナップショットのメタデータを削除
--     * タイムトラベルの範囲が狭まるトレードオフがある
--     * 本番では retention_threshold で保持期間を指定（例: '7d'）
--
--   - remove_orphan_files: 参照されなくなったデータファイルを物理削除
--     * ストレージコストの削減に直結
--     * expire_snapshots の後に実行するのが一般的
--
--   - optimize (compaction): 小さなファイルを統合して大きなファイルにまとめる
--     * クエリ性能の改善（I/O回数の削減）
--     * ストリーミングINSERTや頻繁な小バッチ処理後に特に有効
--
--   - 本番運用では、これらを定期的なジョブとしてスケジューリングする
--     （例: 日次で expire + orphan 削除、週次で optimize）
