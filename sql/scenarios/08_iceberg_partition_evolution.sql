-- ============================================================
-- シナリオ08: Iceberg パーティション進化
--
-- 目的:
--   Icebergではパーティション戦略を「後から変更」できることを体感する。
--   従来のHiveでは不可能だった「既存データを書き換えずに
--   パーティション構成を変える」ことが、メタデータ操作だけで実現できる。
--
-- 前提: setup.sql を先に実行してください
--
-- ⚠️  再実行の注意:
--   このスクリプトは setup 直後のクリーンな状態を前提としています。
--   再実行前に make restart を実行してリセットしてください。
--
-- 実行方法:
--   make scenario-08
--   または: docker exec trino trino --file /etc/trino/sql/scenarios/08_iceberg_partition_evolution.sql
-- ============================================================

-- ============================================================
-- Step 1: パーティションなしのテーブルを作成してデータ投入
-- ============================================================

-- 分析用のアクセスログテーブル（パーティションなし）
CREATE TABLE IF NOT EXISTS iceberg.ecommerce.access_logs (
    log_id       BIGINT,
    user_id      BIGINT,
    access_time  TIMESTAMP,
    page_url     VARCHAR,
    http_status  INTEGER,
    response_ms  INTEGER
) WITH (
    format = 'PARQUET'
);

-- 2024年1月〜3月のアクセスログを投入
INSERT INTO iceberg.ecommerce.access_logs VALUES
    (1,  1, TIMESTAMP '2024-01-10 08:30:00', '/products',       200, 120),
    (2,  2, TIMESTAMP '2024-01-10 09:15:00', '/products/101',   200,  85),
    (3,  3, TIMESTAMP '2024-01-15 14:20:00', '/cart',           200, 200),
    (4,  1, TIMESTAMP '2024-01-20 10:00:00', '/checkout',       200, 350),
    (5,  4, TIMESTAMP '2024-02-01 11:30:00', '/products',       200, 110),
    (6,  2, TIMESTAMP '2024-02-05 13:45:00', '/products/104',   200,  90),
    (7,  5, TIMESTAMP '2024-02-14 16:00:00', '/cart',           200, 180),
    (8,  3, TIMESTAMP '2024-02-20 09:30:00', '/checkout',       500, 5000),
    (9,  1, TIMESTAMP '2024-03-01 08:00:00', '/products',       200, 100),
    (10, 4, TIMESTAMP '2024-03-10 12:00:00', '/products/102',   200,  75),
    (11, 5, TIMESTAMP '2024-03-15 15:30:00', '/cart',           200, 160),
    (12, 2, TIMESTAMP '2024-03-25 17:00:00', '/checkout',       200, 300);

-- 現在のパーティション構成を確認（パーティションなし）
SELECT * FROM iceberg.ecommerce."access_logs$partitions";

-- データファイル数を確認
SELECT COUNT(*) AS data_file_count
FROM iceberg.ecommerce."access_logs$files";

-- ============================================================
-- Step 2: 月別パーティションを追加する（パーティション進化）
-- ============================================================
-- ポイント: ALTER TABLE でパーティションを追加しても、
--           既存のデータファイルは一切書き換わらない。
--           新しく書き込まれるデータだけが新しいパーティション構成に従う。

ALTER TABLE iceberg.ecommerce.access_logs
SET PROPERTIES partitioning = ARRAY['month(access_time)'];

-- パーティション仕様の変化をメタデータで確認
-- partition_spec_id が変わっていることがわかる
SELECT
    snapshot_id,
    committed_at,
    operation
FROM iceberg.ecommerce."access_logs$snapshots"
ORDER BY committed_at;

-- ============================================================
-- Step 3: 新しいデータを投入（新パーティション構成が適用される）
-- ============================================================

-- 4月のデータを追加（月別パーティションが適用される）
INSERT INTO iceberg.ecommerce.access_logs VALUES
    (13, 1, TIMESTAMP '2024-04-01 09:00:00', '/products',       200, 105),
    (14, 3, TIMESTAMP '2024-04-05 11:30:00', '/products/106',   200,  80),
    (15, 5, TIMESTAMP '2024-04-10 14:00:00', '/cart',           200, 170),
    (16, 2, TIMESTAMP '2024-04-15 16:30:00', '/checkout',       200, 280);

-- 5月のデータも追加
INSERT INTO iceberg.ecommerce.access_logs VALUES
    (17, 4, TIMESTAMP '2024-05-01 08:00:00', '/products',       200,  95),
    (18, 1, TIMESTAMP '2024-05-10 10:30:00', '/products/103',   200,  70),
    (19, 3, TIMESTAMP '2024-05-20 13:00:00', '/cart',           200, 150),
    (20, 5, TIMESTAMP '2024-05-25 15:30:00', '/checkout',       200, 260);

-- パーティション一覧を確認
-- 旧データ（1〜3月）はパーティションなし、新データ（4〜5月）は月別パーティション
SELECT * FROM iceberg.ecommerce."access_logs$partitions";

-- ============================================================
-- Step 4: データファイルの物理構造を比較
-- ============================================================

-- 各データファイルのパーティション情報を確認
-- 旧ファイルにはパーティション情報がなく、新ファイルには月情報がある
SELECT
    file_path,
    record_count,
    file_size_in_bytes
FROM iceberg.ecommerce."access_logs$files";

-- ============================================================
-- Step 5: パーティションプルーニングの効果を確認
-- ============================================================

-- 月別フィルタ付きクエリ（4月のみ）
-- 新パーティション構成のデータはプルーニングが効く
SELECT log_id, user_id, access_time, page_url
FROM iceberg.ecommerce.access_logs
WHERE access_time >= TIMESTAMP '2024-04-01 00:00:00'
  AND access_time <  TIMESTAMP '2024-05-01 00:00:00'
ORDER BY access_time;

-- 全期間のサマリ（パーティション進化前後のデータが透過的に結合される）
SELECT
    date_trunc('month', access_time) AS month,
    COUNT(*)                         AS access_count,
    AVG(response_ms)                 AS avg_response_ms
FROM iceberg.ecommerce.access_logs
GROUP BY date_trunc('month', access_time)
ORDER BY month;

-- ============================================================
-- Step 6: さらにパーティションを変更する（2回目の進化）
-- ============================================================
-- HTTPステータスコードも加えて複合パーティションにする

ALTER TABLE iceberg.ecommerce.access_logs
SET PROPERTIES partitioning = ARRAY['month(access_time)', 'http_status'];

-- 6月のデータを投入（新しい複合パーティション構成が適用）
INSERT INTO iceberg.ecommerce.access_logs VALUES
    (21, 2, TIMESTAMP '2024-06-01 09:00:00', '/products',       200, 100),
    (22, 4, TIMESTAMP '2024-06-05 11:00:00', '/checkout',       500, 8000),
    (23, 1, TIMESTAMP '2024-06-10 14:00:00', '/products/101',   200,  65),
    (24, 3, TIMESTAMP '2024-06-15 16:00:00', '/cart',           404, 50);

-- パーティション一覧の最終確認
-- 3種類のパーティション仕様が共存している:
--   1) パーティションなし（1〜3月）
--   2) month(access_time)（4〜5月）
--   3) month(access_time) + http_status（6月）
SELECT * FROM iceberg.ecommerce."access_logs$partitions";

-- 全期間を透過的にクエリできることを確認
SELECT
    date_trunc('month', access_time) AS month,
    http_status,
    COUNT(*) AS count
FROM iceberg.ecommerce.access_logs
GROUP BY date_trunc('month', access_time), http_status
ORDER BY month, http_status;

-- ============================================================
-- クリーンアップ
-- ============================================================

DROP TABLE IF EXISTS iceberg.ecommerce.access_logs;

-- ============================================================
-- まとめ
-- ============================================================
-- ポイント:
--   - ALTER TABLE SET PROPERTIES partitioning でパーティションを後から変更可能
--   - 既存のデータファイルは書き換えられない（メタデータのみ更新）
--   - 異なるパーティション仕様のデータが透過的に共存・結合される
--   - Hive では「テーブル再作成 + データ再ロード」が必要だった操作が
--     Iceberg ではダウンタイムなしで実現できる
--   - パーティション進化はスキーマ進化（シナリオ03）と同様に
--     Iceberg のメタデータレイヤーが実現する強力な機能
