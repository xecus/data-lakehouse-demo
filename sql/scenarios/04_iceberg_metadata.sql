-- ============================================================
-- シナリオ04: Iceberg メタデータ探索
-- $snapshots / $manifests / $files / $partitions / $history
--
-- 目的:
--   Icebergが「どのようにデータを物理的に管理しているか」を可視化する。
--   メタデータの階層構造を理解することで、なぜIcebergが高速で信頼性が
--   高いのかが分かる。
--
-- Icebergのメタデータ階層:
--   スナップショット (snapshot)
--     └── マニフェストリスト (manifest list)
--           └── マニフェストファイル (manifest)
--                 └── データファイル (Parquet)
--
-- 前提: setup.sql を先に実行してください
--
-- 実行方法:
--   make scenario-04
--   または: docker exec trino trino --file /etc/trino/sql/scenarios/04_iceberg_metadata.sql
-- ============================================================

-- ============================================================
-- Step 1: $snapshots — コミット履歴
-- ============================================================

SELECT
    snapshot_id,
    parent_id,
    committed_at,
    operation,
    manifest_list,
    summary
FROM iceberg.ecommerce."orders$snapshots"
ORDER BY committed_at;

-- summary フィールドには各スナップショットの統計情報が入っている
SELECT
    snapshot_id,
    committed_at,
    operation,
    element_at(summary, 'added-data-files')   AS added_files,
    element_at(summary, 'deleted-data-files') AS deleted_files,
    element_at(summary, 'added-records')      AS added_records,
    element_at(summary, 'deleted-records')    AS deleted_records,
    element_at(summary, 'total-data-files')   AS total_files,
    element_at(summary, 'total-records')      AS total_records,
    element_at(summary, 'total-files-size')   AS total_size_bytes
FROM iceberg.ecommerce."orders$snapshots"
ORDER BY committed_at;

-- ============================================================
-- Step 2: $history — スナップショット変遷
-- ============================================================

SELECT
    made_current_at,
    snapshot_id,
    parent_id,
    is_current_ancestor
FROM iceberg.ecommerce."orders$history"
ORDER BY made_current_at;

-- ============================================================
-- Step 3: $manifests — マニフェストファイル一覧
-- ============================================================
-- マニフェストは「どのデータファイルが存在するか」を記録した中間インデックス

SELECT
    path,
    length             AS size_bytes,
    partition_spec_id,
    added_snapshot_id,
    added_data_files_count,
    added_rows_count,
    existing_data_files_count,
    deleted_data_files_count
FROM iceberg.ecommerce."orders$manifests";

-- ============================================================
-- Step 4: $files — 物理データファイル一覧
-- ============================================================
-- 実際に MinIO に格納されているParquetファイルの情報

SELECT
    file_path,
    file_format,
    record_count,
    file_size_in_bytes,
    column_sizes,
    value_counts,
    null_value_counts,
    lower_bounds,
    upper_bounds
FROM iceberg.ecommerce."orders$files";

-- ファイルパスだけをシンプルに確認
SELECT
    file_path,
    record_count,
    file_size_in_bytes
FROM iceberg.ecommerce."orders$files"
ORDER BY file_path;

-- ポイント: file_path の中にパーティション情報（order_date=2024-01-15/等）が
--          含まれていることを確認。パーティションごとにファイルが分かれている。

-- ============================================================
-- Step 5: $partitions — パーティション統計
-- ============================================================

SELECT
    partition,
    record_count,
    file_count,
    total_size
FROM iceberg.ecommerce."orders$partitions"
ORDER BY partition;

-- 顧客テーブルのパーティション（country別）も確認
SELECT
    partition,
    record_count,
    file_count,
    total_size
FROM iceberg.ecommerce."customers$partitions"
ORDER BY partition;

-- ============================================================
-- Step 6: EXPLAIN でパーティションプルーニングを確認
-- ============================================================
-- Icebergは WHERE 句のフィルタをメタデータで評価し、
-- 読む必要がないファイルをスキップする（パーティションプルーニング）

-- 特定日付の注文を検索（この日付のパーティションファイルだけ読む）
EXPLAIN
SELECT order_id, total_amount
FROM iceberg.ecommerce.orders
WHERE order_date = DATE '2024-01-15';

-- 範囲指定の場合
EXPLAIN
SELECT order_id, total_amount
FROM iceberg.ecommerce.orders
WHERE order_date BETWEEN DATE '2024-01-01' AND DATE '2024-01-31';

-- ポイント: EXPLAIN結果の "Split" 数や "files" 数を見ると、
--          条件に一致するパーティションのファイルだけが読まれることが分かる

-- ============================================================
-- Step 7: $entries — マニフェストエントリの詳細
-- ============================================================
-- NOTE: $entries テーブルは position delete ファイルが存在する場合、
--       Trino で "type is null" NPE が発生する既知の問題があるためスキップ。
--       代わりに $manifests の added_data_files_count / deleted_data_files_count
--       でファイルの追加/削除状況を確認してください。
