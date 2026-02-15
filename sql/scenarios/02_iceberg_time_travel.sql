-- ============================================================
-- シナリオ02: Iceberg タイムトラベル
--
-- 目的:
--   スナップショットを使って過去の任意の時点のデータを参照・復元できる
--   ことを体感する。データを誤って更新・削除してしまった場合の
--   リカバリーシナリオとして理解する。
--
-- 前提: setup.sql を先に実行してください
--       （シナリオ01実行後でも動作します）
--
-- ⚠️  再実行の注意:
--   このスクリプトは setup 直後のクリーンな状態を前提としています。
--   2回目以降の実行はスナップショット数が増加し、タイムトラベルの
--   結果が変わる場合があります。
--   再実行前に以下を実行してリセットしてください:
--     make reset && make up && make setup
--
-- 実行方法:
--   make scenario-02
--   または: docker exec demo1-trino trino --file /etc/trino/sql/scenarios/02_iceberg_time_travel.sql
-- ============================================================

-- ============================================================
-- Step 1: スナップショットの作成（タイムトラベルの起点を増やす）
-- ============================================================

-- 現在の注文件数を確認
SELECT COUNT(*) AS order_count, 'Step1開始時点' AS label
FROM iceberg.ecommerce.orders;

-- 新規注文を追加（スナップショット作成）
INSERT INTO iceberg.ecommerce.orders VALUES
    (2001, 1, DATE '2024-03-10', TIMESTAMP '2024-03-10 10:00:00', 'completed', 25000.00),
    (2002, 3, DATE '2024-03-11', TIMESTAMP '2024-03-11 11:00:00', 'completed', 89000.00);

SELECT COUNT(*) AS order_count, 'INSERT後' AS label
FROM iceberg.ecommerce.orders;

-- さらにステータスを更新（別スナップショット作成）
UPDATE iceberg.ecommerce.orders
SET status = 'shipped'
WHERE order_id IN (2001, 2002);

SELECT COUNT(*) AS order_count, 'UPDATE後' AS label
FROM iceberg.ecommerce.orders;

-- ============================================================
-- Step 2: スナップショット履歴を確認
-- ============================================================
-- 操作ごとにスナップショットが作られていることを確認

SELECT
    snapshot_id,
    committed_at,
    operation
FROM iceberg.ecommerce."orders$snapshots"
ORDER BY committed_at;

-- ============================================================
-- Step 3: FOR VERSION AS OF — スナップショットIDで時点指定
-- ============================================================
-- 上のクエリで得たスナップショットIDを使って過去データを参照する
--
-- 手順:
--   1. 上記 Step2 の結果から、最初の INSERT 直後のスナップショットID（2行目）を確認する
--   2. 下記クエリの <最初のINSERT後のsnapshot_id> をその値に置き換えて実行
--
-- 例（IDは環境によって異なります）:
--   SELECT * FROM iceberg.ecommerce.orders
--   FOR VERSION AS OF 4843723319432220799;

-- ポイント: 下記はスナップショット履歴の「最初のINSERT（appendオペレーション）」を
--           サブクエリで取得できないため、手動でIDを確認して実行してください

-- ============================================================
-- Step 4: FOR TIMESTAMP AS OF — タイムスタンプで時点指定
-- ============================================================
-- スナップショットIDを調べなくても、時刻で過去を参照できる
--
-- 例: 30秒前のデータを参照（起動直後のデモ向け。本番では '1' HOUR 等に変更）
SELECT order_id, status, total_amount
FROM iceberg.ecommerce.orders
FOR TIMESTAMP AS OF (CURRENT_TIMESTAMP - INTERVAL '30' SECOND);

-- ============================================================
-- Step 5: タイムトラベルによるデータリカバリーシナリオ
-- ============================================================
-- ビジネスシナリオ: 誤ってデータを削除してしまった場合の復元

-- (1) 誤操作をシミュレート: 全注文を誤って削除
DELETE FROM iceberg.ecommerce.orders
WHERE order_date >= DATE '2024-03-01';

SELECT COUNT(*) AS order_count, '誤削除後' AS label
FROM iceberg.ecommerce.orders;

-- (2) 削除前のスナップショットIDを確認
SELECT
    snapshot_id,
    committed_at,
    operation,
    element_at(summary, 'deleted-records') AS deleted_records
FROM iceberg.ecommerce."orders$snapshots"
ORDER BY committed_at;

-- (3) タイムトラベルで削除前のデータを確認
--     ※ 下記の <削除前のsnapshot_id> を実際のIDに書き換えて実行
-- SELECT order_id, status FROM iceberg.ecommerce.orders
-- FOR VERSION AS OF <削除前のsnapshot_id>;

-- (4) タイムトラベルを使ってデータを復元
--     削除されたレコードを過去スナップショットからINSERT SELECT で戻す
--     ※ 下記の <削除前のsnapshot_id> を実際のIDに書き換えて実行
-- INSERT INTO iceberg.ecommerce.orders
-- SELECT * FROM iceberg.ecommerce.orders
-- FOR VERSION AS OF <削除前のsnapshot_id>
-- WHERE order_date >= DATE '2024-03-01';

-- ============================================================
-- Step 6: $history テーブルで履歴全体を俯瞰する
-- ============================================================

SELECT
    made_current_at,
    snapshot_id,
    parent_id,
    is_current_ancestor
FROM iceberg.ecommerce."orders$history"
ORDER BY made_current_at;

-- ポイント:
--   - is_current_ancestor = true  → 現在の最新スナップショットの祖先（有効な履歴）
--   - is_current_ancestor = false → 参照されなくなったスナップショット（EXPIRE後に削除される）
