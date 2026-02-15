-- ============================================================
-- シナリオ07: Nessie コンフリクト解決
--
-- 目的:
--   2つのブランチが同じテーブルを変更した場合にマージコンフリクトが
--   発生することを体験し、解決方法を理解する。
--   実際のチーム開発で起こりうる競合シナリオを再現する。
--
-- カタログ構成:
--   iceberg     → Nessie の main ブランチ（本番）
--   iceberg_dev → Nessie の feature/add-books ブランチ（開発）
--   ※ 本シナリオでは2つのブランチを順番に操作するため、
--     iceberg_dev のブランチ参照先を途中で切り替えます。
--
-- 前提: setup.sql を先に実行してください
--
-- ⚠️  再実行の注意:
--   このスクリプトは setup 直後のクリーンな状態を前提としています。
--   再実行前に make restart を実行してリセットしてください。
--
-- 実行方法:
--   make scenario-07
--   または: docker exec demo1-trino trino --file /etc/trino/sql/scenarios/07_nessie_conflict.sql
-- ============================================================

-- ============================================================
-- Step 1: 現在の状態を確認
-- ============================================================

SELECT product_id, product_name, category, price
FROM iceberg.ecommerce.products
ORDER BY product_id;

-- ============================================================
-- Step 2: 2つのfeatureブランチを作成する
-- ============================================================
-- ⚠️  別ターミナルで以下を実行してください:
--
-- (1) mainブランチのハッシュを取得
--     HASH=$(curl -s http://localhost:19120/api/v2/trees/main | jq -r '.reference.hash')
--
-- (2) feature/update-prices ブランチを作成
--     curl -s -X POST \
--       -H "Content-Type: application/json" \
--       -d "{\"name\":\"main\",\"type\":\"BRANCH\",\"hash\":\"${HASH}\"}" \
--       "http://localhost:19120/api/v2/trees?name=feature/update-prices&type=BRANCH" | jq .
--
-- (3) feature/add-discounts ブランチを作成
--     curl -s -X POST \
--       -H "Content-Type: application/json" \
--       -d "{\"name\":\"main\",\"type\":\"BRANCH\",\"hash\":\"${HASH}\"}" \
--       "http://localhost:19120/api/v2/trees?name=feature/add-discounts&type=BRANCH" | jq .
--
-- (4) ブランチ一覧を確認（3つのブランチが存在するはず）
--     curl -s http://localhost:19120/api/v2/trees | jq '[.references[] | {type, name}]'

-- ============================================================
-- Step 3: ブランチAで価格を値上げ
-- ============================================================
-- ⚠️  iceberg_dev カタログを feature/update-prices に向けてください。
--     trino/catalog/iceberg_dev.properties の ref を変更して Trino を再起動:
--       iceberg.nessie-catalog.ref=feature/update-prices
--     または docker exec demo1-trino trino で以下を実行:

-- feature/update-prices ブランチ: Electronics を10%値上げ
-- ⚠️  iceberg_dev.properties の ref を feature/update-prices に設定後に実行
UPDATE iceberg_dev.ecommerce.products
SET price = price * 1.10
WHERE category = 'Electronics';

-- 値上げ後の確認
SELECT product_id, product_name, price
FROM iceberg_dev.ecommerce.products
WHERE category = 'Electronics'
ORDER BY product_id;

-- mainは変更されていない
SELECT product_id, product_name, price
FROM iceberg.ecommerce.products
WHERE category = 'Electronics'
ORDER BY product_id;

-- ============================================================
-- Step 4: ブランチBで同じテーブルに割引フラグを追加
-- ============================================================
-- ⚠️  iceberg_dev カタログを feature/add-discounts に向けてください。
--     trino/catalog/iceberg_dev.properties の ref を変更して Trino を再起動:
--       iceberg.nessie-catalog.ref=feature/add-discounts

-- feature/add-discounts ブランチ: Electronics を20%値下げ
-- ⚠️  iceberg_dev.properties の ref を feature/add-discounts に設定後に実行
UPDATE iceberg_dev.ecommerce.products
SET price = price * 0.80
WHERE category = 'Electronics';

-- 値下げ後の確認
SELECT product_id, product_name, price
FROM iceberg_dev.ecommerce.products
WHERE category = 'Electronics'
ORDER BY product_id;

-- ============================================================
-- Step 5: ブランチAを先にマージ（成功する）
-- ============================================================
-- ⚠️  別ターミナルで以下を実行してください:
--
-- (1) 各ハッシュを取得
--     MAIN_HASH=$(curl -s http://localhost:19120/api/v2/trees/main | jq -r '.reference.hash')
--     PRICES_HASH=$(curl -s "http://localhost:19120/api/v2/trees/feature%2Fupdate-prices" | jq -r '.reference.hash')
--
-- (2) feature/update-prices を main にマージ（これは成功する）
--     curl -s -X POST \
--       -H "Content-Type: application/json" \
--       -d "{\"fromRefName\":\"feature/update-prices\",\"fromHash\":\"${PRICES_HASH}\"}" \
--       "http://localhost:19120/api/v2/trees/main@${MAIN_HASH}/history/merge" | jq .

-- マージ後のmainを確認（値上げが反映されている）
SELECT product_id, product_name, price
FROM iceberg.ecommerce.products
WHERE category = 'Electronics'
ORDER BY product_id;

-- ============================================================
-- Step 6: ブランチBをマージ（コンフリクト発生）
-- ============================================================
-- ⚠️  別ターミナルで以下を実行してください:
--
-- (1) 最新のハッシュを取得
--     MAIN_HASH=$(curl -s http://localhost:19120/api/v2/trees/main | jq -r '.reference.hash')
--     DISCOUNTS_HASH=$(curl -s "http://localhost:19120/api/v2/trees/feature%2Fadd-discounts" | jq -r '.reference.hash')
--
-- (2) feature/add-discounts を main にマージ（コンフリクトが発生する可能性）
--     curl -s -X POST \
--       -H "Content-Type: application/json" \
--       -d "{\"fromRefName\":\"feature/add-discounts\",\"fromHash\":\"${DISCOUNTS_HASH}\"}" \
--       "http://localhost:19120/api/v2/trees/main@${MAIN_HASH}/history/merge" | jq .
--
-- コンフリクトが発生した場合、レスポンスに conflicts が含まれます。
-- Nessie はデフォルトで同じキーへの変更を検出しコンフリクトとして報告します。

-- ============================================================
-- Step 7: コンフリクトの手動解決
-- ============================================================
-- コンフリクトが発生した場合の解決方法:
--
-- 方法A: ブランチBを破棄してmain上で直接変更する
--   → ブランチBを削除し、main上で改めて割引を適用
--
-- 方法B: ブランチBをmainの最新状態から作り直す
--   → 新しいブランチを作成し、マージ後のmainから分岐して変更を再適用
--
-- ここでは方法Aを実演します。main上で割引を適用:

-- mainの現在の状態（ブランチAのマージ済み = 値上げ後の価格）
SELECT product_id, product_name, price
FROM iceberg.ecommerce.products
WHERE category = 'Electronics'
ORDER BY product_id;

-- ============================================================
-- Step 8: クリーンアップ — featureブランチを削除
-- ============================================================
-- ⚠️  別ターミナルで以下を実行してください:
--
-- (1) 各ブランチを削除
--     PRICES_HASH=$(curl -s "http://localhost:19120/api/v2/trees/feature%2Fupdate-prices" | jq -r '.reference.hash')
--     curl -s -X DELETE "http://localhost:19120/api/v2/trees/feature%2Fupdate-prices@${PRICES_HASH}" | jq .
--
--     DISCOUNTS_HASH=$(curl -s "http://localhost:19120/api/v2/trees/feature%2Fadd-discounts" | jq -r '.reference.hash')
--     curl -s -X DELETE "http://localhost:19120/api/v2/trees/feature%2Fadd-discounts@${DISCOUNTS_HASH}" | jq .
--
-- (2) ブランチ一覧を確認（mainのみに戻っていればOK）
--     curl -s http://localhost:19120/api/v2/trees | jq '[.references[] | {type, name}]'

-- ============================================================
-- まとめ
-- ============================================================
-- ポイント:
--   - Nessie は同じテーブル（キー）への並行変更をコンフリクトとして検出する
--   - Git と同様に「先にマージした方が勝つ」
--   - コンフリクト解決は手動で行う必要がある（ブランチの作り直し or main上で直接変更）
--   - チーム開発ではブランチの寿命を短くし、こまめにマージすることでコンフリクトを減らせる
