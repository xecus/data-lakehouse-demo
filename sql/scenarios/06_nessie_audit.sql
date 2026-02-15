-- ============================================================
-- シナリオ06: Nessie 監査・コミット履歴
-- Iceberg スナップショット + Nessie REST API 監査ログ
--
-- 目的:
--   「誰が・いつ・どのテーブルを・どう変更したか」を追跡できる
--   監査ログとしてIceberg/Nessieの履歴を活用する。
--   データガバナンス・コンプライアンス要件への応用を理解する。
--
-- このシナリオは Trino SQL と curl コマンドの組み合わせです。
-- curl コマンドはコメント内に記載しており、別ターミナルで実行してください。
--
-- 前提: setup.sql を先に実行してください
--
-- ⚠️  再実行の注意:
--   このスクリプトは setup 直後のクリーンな状態を前提としています。
--   2回目以降の実行では価格が重ねて更新され、顧客・注文データが重複します。
--   再実行前に以下を実行してリセットしてください:
--     make reset && make up && make setup
--
-- 実行方法:
--   make scenario-06
--   または: docker exec demo1-trino trino --file /etc/trino/sql/scenarios/06_nessie_audit.sql
-- ============================================================

-- ============================================================
-- Step 1: 監査用の変更を複数回実行してログを積む
-- ============================================================

-- 変更1: 商品価格の更新（価格改定イベント）
UPDATE iceberg.ecommerce.products
SET price = price * 1.1
WHERE category = 'Electronics';

-- 変更後の確認
SELECT product_name, category, price
FROM iceberg.ecommerce.products
WHERE category = 'Electronics'
ORDER BY product_id;

-- 変更2: 新規顧客の追加
INSERT INTO iceberg.ecommerce.customers VALUES
    (6, '田中誠', 'tanaka@example.com', 'Japan', DATE '2024-03-01');

SELECT COUNT(*) AS customer_count FROM iceberg.ecommerce.customers;

-- 変更3: 注文ステータスの一括更新
UPDATE iceberg.ecommerce.orders
SET status = 'archived'
WHERE order_date < DATE '2024-02-01' AND status = 'completed';

SELECT order_id, order_date, status
FROM iceberg.ecommerce.orders
ORDER BY order_id;

-- ============================================================
-- Step 2: Iceberg スナップショットで変更履歴を確認（テーブル単位）
-- ============================================================

-- products テーブルの変更履歴
SELECT
    snapshot_id,
    committed_at,
    operation,
    element_at(summary, 'added-records')   AS added_records,
    element_at(summary, 'deleted-records') AS deleted_records,
    element_at(summary, 'total-records')   AS total_records
FROM iceberg.ecommerce."products$snapshots"
ORDER BY committed_at;

-- orders テーブルの変更履歴
SELECT
    snapshot_id,
    committed_at,
    operation,
    element_at(summary, 'added-records')   AS added_records,
    element_at(summary, 'deleted-records') AS deleted_records,
    element_at(summary, 'total-records')   AS total_records
FROM iceberg.ecommerce."orders$snapshots"
ORDER BY committed_at;

-- ============================================================
-- Step 3: タイムスタンプ指定で「イベント前後」のデータを比較
-- ============================================================
-- 価格改定前後の比較（FOR TIMESTAMP AS OF を使う）
-- 価格改定は直前のスナップショットIDを $snapshots から確認して
-- FOR VERSION AS OF で参照してください

-- 現在の Electronics 価格
SELECT product_name, price FROM iceberg.ecommerce.products
WHERE category = 'Electronics'
ORDER BY product_id;

-- 30秒前の価格（直近の変更前）
SELECT product_name, price FROM iceberg.ecommerce.products
FOR TIMESTAMP AS OF (CURRENT_TIMESTAMP - INTERVAL '30' SECOND)
WHERE category = 'Electronics'
ORDER BY product_id;

-- ============================================================
-- Step 4: 全テーブルのスナップショット件数をサマリ表示
-- ============================================================
-- 「どのテーブルが最も変更されているか」を監査観点で確認

SELECT 'customers'   AS table_name, COUNT(*) AS snapshot_count FROM iceberg.ecommerce."customers$snapshots"
UNION ALL
SELECT 'products',   COUNT(*) FROM iceberg.ecommerce."products$snapshots"
UNION ALL
SELECT 'orders',     COUNT(*) FROM iceberg.ecommerce."orders$snapshots"
UNION ALL
SELECT 'order_items',COUNT(*) FROM iceberg.ecommerce."order_items$snapshots";

-- ============================================================
-- Step 5: Nessie REST API でカタログ全体のコミット履歴を確認
-- ============================================================
-- 別ターミナルで以下を実行してください:
--
-- --- mainブランチのコミット履歴（全変更操作のログ） ---
-- curl -s "http://localhost:19120/api/v2/trees/main/history" | jq '
--   .logEntries[] | {
--     commitTime: .commitMeta.commitTime,
--     message:    .commitMeta.message,
--     hash:       .commitMeta.hash
--   }
-- '
--
-- --- コミット件数の確認 ---
-- curl -s "http://localhost:19120/api/v2/trees/main/history" | jq '.logEntries | length'
--
-- ポイント: 各SQL操作がNessieのコミットとして記録されている

-- ============================================================
-- Step 6: Nessie ブランチ・ハッシュを使ったバージョン固定
-- ============================================================
-- 別ターミナルで実行してください:
--
-- --- 現在のmainブランチのハッシュを取得（「今この瞬間」の固定点） ---
-- curl -s http://localhost:19120/api/v2/trees/main | jq '.reference.hash'
--
-- --- 特定ハッシュ時点のコミット情報を確認 ---
-- HASH=$(curl -s http://localhost:19120/api/v2/trees/main | jq -r '.reference.hash')
-- curl -s "http://localhost:19120/api/v2/trees/main@${HASH}/history?maxRecords=1" | jq .
--
-- --- このハッシュを「Q1-2024確定版」として記録しておくことで
--     いつでもこの時点のデータに戻れる（タグ相当の使い方）
--
-- ブランチ作成でバージョンを保存:
-- HASH=$(curl -s http://localhost:19120/api/v2/trees/main | jq -r '.reference.hash')
-- curl -s -X POST "http://localhost:19120/api/v2/trees" \
--   -H "Content-Type: application/json" \
--   -d "{\"type\":\"BRANCH\",\"name\":\"snapshot-q1-2024\",\"hash\":\"${HASH}\",\"reference\":{\"type\":\"BRANCH\",\"name\":\"main\"}}" | jq .

-- ============================================================
-- Step 7: さらに変更を加えて「確定版との差分」を確認
-- ============================================================

-- Q2のデータを追加（Q1確定後の変更）
INSERT INTO iceberg.ecommerce.orders VALUES
    (3001, 5, DATE '2024-04-01', TIMESTAMP '2024-04-01 10:00:00', 'completed', 89000.00);

-- 現在の件数
SELECT COUNT(*) AS order_count, 'Q2追加後（現在）' AS label
FROM iceberg.ecommerce.orders
UNION ALL
-- 30秒前の件数（Q1確定時点に近い）
SELECT COUNT(*), '30秒前'
FROM iceberg.ecommerce.orders
FOR TIMESTAMP AS OF (CURRENT_TIMESTAMP - INTERVAL '30' SECOND);
