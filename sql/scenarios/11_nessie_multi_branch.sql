-- ============================================================
-- シナリオ11: Nessie マルチブランチ並行開発
--
-- 目的:
--   複数チームが同時に異なるブランチでデータ開発を行う
--   ワークフローを体験する。チームAはスキーマ変更、
--   チームBはデータバックフィルを並行して行い、
--   それぞれの変更が互いに影響しないことを確認した後、
--   順次mainにマージする。
--
-- カタログ構成:
--   iceberg     → Nessie の main ブランチ（本番）
--   iceberg_dev → ブランチ切替で各チームのブランチを参照
--
-- 前提: setup.sql を先に実行してください
--
-- ⚠️  再実行の注意:
--   このスクリプトは setup 直後のクリーンな状態を前提としています。
--   再実行前に make restart を実行してリセットしてください。
--
-- 実行方法:
--   make scenario-11
--   または: docker exec trino trino --file /etc/trino/sql/scenarios/11_nessie_multi_branch.sql
-- ============================================================

-- ============================================================
-- Step 1: 現在の本番環境を確認
-- ============================================================

-- 本番の商品データ
SELECT product_id, product_name, category, price
FROM iceberg.ecommerce.products
ORDER BY product_id;

-- 本番の注文データ
SELECT COUNT(*) AS order_count FROM iceberg.ecommerce.orders;

-- ============================================================
-- Step 2: 2つのチーム用ブランチを作成
-- ============================================================
-- ⚠️  別ターミナルで以下を実行してください:
--
-- (1) mainブランチのハッシュを取得
--     HASH=$(curl -s http://localhost:19120/api/v2/trees/main | jq -r '.reference.hash')
--
-- (2) チームA用ブランチ: スキーマ変更担当
--     curl -s -X POST \
--       -H "Content-Type: application/json" \
--       -d "{\"name\":\"main\",\"type\":\"BRANCH\",\"hash\":\"${HASH}\"}" \
--       "http://localhost:19120/api/v2/trees?name=team-a/add-columns&type=BRANCH" | jq .
--
-- (3) チームB用ブランチ: データバックフィル担当
--     curl -s -X POST \
--       -H "Content-Type: application/json" \
--       -d "{\"name\":\"main\",\"type\":\"BRANCH\",\"hash\":\"${HASH}\"}" \
--       "http://localhost:19120/api/v2/trees?name=team-b/backfill-orders&type=BRANCH" | jq .
--
-- (4) ブランチ一覧を確認
--     curl -s http://localhost:19120/api/v2/trees | jq '[.references[] | {type, name}]'

-- ============================================================
-- Step 3: チームA — productsテーブルにカラムを追加
-- ============================================================
-- ⚠️  iceberg_dev.properties の ref を team-a/add-columns に設定して
--     Trino を再起動してから実行してください。
--     iceberg.nessie-catalog.ref=team-a/add-columns

-- チームA: 商品テーブルに在庫数と重量カラムを追加
ALTER TABLE iceberg_dev.ecommerce.products ADD COLUMN stock_quantity INTEGER;
ALTER TABLE iceberg_dev.ecommerce.products ADD COLUMN weight_kg DECIMAL(6,2);

-- 在庫データを設定
UPDATE iceberg_dev.ecommerce.products SET stock_quantity = 50,  weight_kg = 1.80 WHERE product_id = 101;
UPDATE iceberg_dev.ecommerce.products SET stock_quantity = 200, weight_kg = 0.08 WHERE product_id = 102;
UPDATE iceberg_dev.ecommerce.products SET stock_quantity = 150, weight_kg = 0.50 WHERE product_id = 103;
UPDATE iceberg_dev.ecommerce.products SET stock_quantity = 30,  weight_kg = 5.00 WHERE product_id = 104;
UPDATE iceberg_dev.ecommerce.products SET stock_quantity = 20,  weight_kg = 12.00 WHERE product_id = 105;
UPDATE iceberg_dev.ecommerce.products SET stock_quantity = 15,  weight_kg = 25.00 WHERE product_id = 106;

-- チームAのブランチで確認（新カラムが見える）
SELECT product_id, product_name, stock_quantity, weight_kg
FROM iceberg_dev.ecommerce.products
ORDER BY product_id;

-- mainには影響していない（新カラムがまだない）
SELECT *
FROM iceberg.ecommerce.products
ORDER BY product_id;

-- ============================================================
-- Step 4: チームB — 過去の注文データをバックフィル
-- ============================================================
-- ⚠️  iceberg_dev.properties の ref を team-b/backfill-orders に設定して
--     Trino を再起動してから実行してください。
--     iceberg.nessie-catalog.ref=team-b/backfill-orders

-- チームB: 2023年の過去注文データを大量追加
INSERT INTO iceberg_dev.ecommerce.orders VALUES
    (501, 1, DATE '2023-06-15', TIMESTAMP '2023-06-15 10:00:00', 'completed',  45000.00),
    (502, 2, DATE '2023-07-20', TIMESTAMP '2023-07-20 11:30:00', 'completed',  28000.00),
    (503, 3, DATE '2023-08-10', TIMESTAMP '2023-08-10 14:00:00', 'completed',  92000.00),
    (504, 4, DATE '2023-09-05', TIMESTAMP '2023-09-05 09:15:00', 'completed',  15000.00),
    (505, 5, DATE '2023-10-12', TIMESTAMP '2023-10-12 16:45:00', 'completed',  67000.00),
    (506, 1, DATE '2023-11-01', TIMESTAMP '2023-11-01 13:00:00', 'completed', 120000.00),
    (507, 2, DATE '2023-11-25', TIMESTAMP '2023-11-25 10:30:00', 'completed',  33000.00),
    (508, 3, DATE '2023-12-10', TIMESTAMP '2023-12-10 15:00:00', 'completed',  55000.00),
    (509, 4, DATE '2023-12-20', TIMESTAMP '2023-12-20 11:00:00', 'completed',  78000.00),
    (510, 5, DATE '2023-12-31', TIMESTAMP '2023-12-31 23:59:00', 'completed',  41000.00);

-- チームBのブランチで確認（過去データが追加されている）
SELECT COUNT(*) AS order_count, 'team-b branch' AS source
FROM iceberg_dev.ecommerce.orders;

-- 年別の注文件数
SELECT YEAR(order_date) AS year, COUNT(*) AS order_count
FROM iceberg_dev.ecommerce.orders
GROUP BY YEAR(order_date)
ORDER BY year;

-- mainには影響していない
SELECT COUNT(*) AS order_count, 'main' AS source
FROM iceberg.ecommerce.orders;

-- ============================================================
-- Step 5: 各ブランチの独立性を確認
-- ============================================================

-- ⚠️  別ターミナルで各ブランチのコミット履歴を比較:
--
-- チームAのコミット:
-- curl -s "http://localhost:19120/api/v2/trees/team-a%2Fadd-columns/history" \
--   | jq '.logEntries[0:5] | .[] | {commitTime: .commitMeta.commitTime, message: .commitMeta.message}'
--
-- チームBのコミット:
-- curl -s "http://localhost:19120/api/v2/trees/team-b%2Fbackfill-orders/history" \
--   | jq '.logEntries[0:5] | .[] | {commitTime: .commitMeta.commitTime, message: .commitMeta.message}'
--
-- mainのコミット（変更なし）:
-- curl -s "http://localhost:19120/api/v2/trees/main/history" \
--   | jq '.logEntries[0:3] | .[] | {commitTime: .commitMeta.commitTime, message: .commitMeta.message}'

-- ============================================================
-- Step 6: チームAの変更をmainにマージ
-- ============================================================
-- ⚠️  別ターミナルで以下を実行してください:
--
-- (1) ハッシュを取得
--     MAIN_HASH=$(curl -s http://localhost:19120/api/v2/trees/main | jq -r '.reference.hash')
--     TEAM_A_HASH=$(curl -s "http://localhost:19120/api/v2/trees/team-a%2Fadd-columns" | jq -r '.reference.hash')
--
-- (2) チームAのブランチをmainにマージ
--     curl -s -X POST \
--       -H "Content-Type: application/json" \
--       -d "{\"fromRefName\":\"team-a/add-columns\",\"fromHash\":\"${TEAM_A_HASH}\"}" \
--       "http://localhost:19120/api/v2/trees/main@${MAIN_HASH}/history/merge" | jq .

-- マージ後: mainに新カラムが反映されている
SELECT product_id, product_name, stock_quantity, weight_kg
FROM iceberg.ecommerce.products
ORDER BY product_id;

-- 注文データはまだ元のまま（チームBの変更は未マージ）
SELECT COUNT(*) AS order_count FROM iceberg.ecommerce.orders;

-- ============================================================
-- Step 7: チームBの変更をmainにマージ
-- ============================================================
-- ⚠️  別ターミナルで以下を実行してください:
--
-- (1) ハッシュを取得（mainはチームAマージ後の最新）
--     MAIN_HASH=$(curl -s http://localhost:19120/api/v2/trees/main | jq -r '.reference.hash')
--     TEAM_B_HASH=$(curl -s "http://localhost:19120/api/v2/trees/team-b%2Fbackfill-orders" | jq -r '.reference.hash')
--
-- (2) チームBのブランチをmainにマージ
--     curl -s -X POST \
--       -H "Content-Type: application/json" \
--       -d "{\"fromRefName\":\"team-b/backfill-orders\",\"fromHash\":\"${TEAM_B_HASH}\"}" \
--       "http://localhost:19120/api/v2/trees/main@${MAIN_HASH}/history/merge" | jq .

-- 両チームの変更が統合された最終状態
-- 商品: 新カラム付き
SELECT product_id, product_name, category, price, stock_quantity, weight_kg
FROM iceberg.ecommerce.products
ORDER BY product_id;

-- 注文: 過去データが追加されている
SELECT YEAR(order_date) AS year, COUNT(*) AS order_count, SUM(total_amount) AS total_revenue
FROM iceberg.ecommerce.orders
GROUP BY YEAR(order_date)
ORDER BY year;

-- ============================================================
-- Step 8: クリーンアップ — featureブランチを削除
-- ============================================================
-- ⚠️  別ターミナルで以下を実行してください:
--
-- (1) チームAのブランチを削除
--     HASH=$(curl -s "http://localhost:19120/api/v2/trees/team-a%2Fadd-columns" | jq -r '.reference.hash')
--     curl -s -X DELETE "http://localhost:19120/api/v2/trees/team-a%2Fadd-columns@${HASH}" | jq .
--
-- (2) チームBのブランチを削除
--     HASH=$(curl -s "http://localhost:19120/api/v2/trees/team-b%2Fbackfill-orders" | jq -r '.reference.hash')
--     curl -s -X DELETE "http://localhost:19120/api/v2/trees/team-b%2Fbackfill-orders@${HASH}" | jq .
--
-- (3) ブランチ一覧を確認（mainのみに戻っていればOK）
--     curl -s http://localhost:19120/api/v2/trees | jq '[.references[] | {type, name}]'

-- ============================================================
-- まとめ
-- ============================================================
-- ポイント:
--   - 複数のブランチで並行してスキーマ変更とデータ変更を行っても互いに影響しない
--   - マージ順序を制御することで、依存関係のある変更も安全に統合できる
--   - 実際のチーム開発では:
--     * データエンジニアがスキーマ変更を feature ブランチで開発・テスト
--     * データアナリストが別ブランチでデータ品質の検証
--     * レビュー後に main へマージして本番反映
--   - Git Flow / GitHub Flow と同じ開発プラクティスをデータにも適用できる
