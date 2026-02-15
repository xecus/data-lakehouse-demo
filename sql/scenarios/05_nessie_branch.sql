-- ============================================================
-- シナリオ05: Nessie ブランチワークフロー
--
-- 目的:
--   Gitと同じように「ブランチ上でデータを変更してmainに影響させない」
--   という分離されたデータ開発ワークフローを体感する。
--   本番データに影響を与えずにETL開発・テスト・実験ができることを示す。
--
-- カタログ構成:
--   iceberg     → Nessie の main ブランチ（本番）
--   iceberg_dev → Nessie の feature/add-books ブランチ（開発）
--
-- 前提: setup.sql を先に実行してください
--
-- ⚠️  再実行の注意:
--   このスクリプトは setup 直後のクリーンな状態を前提としています。
--   再実行前に make restart を実行してリセットしてください。
--
-- 実行方法:
--   make scenario-05
--   または: docker exec trino trino --file /etc/trino/sql/scenarios/05_nessie_branch.sql
-- ============================================================

-- ============================================================
-- Step 1: 現在の状態を確認（mainブランチ）
-- ============================================================

-- mainブランチの商品一覧
SELECT product_id, product_name, category, price
FROM iceberg.ecommerce.products
ORDER BY product_id;

-- 現在の商品件数
SELECT COUNT(*) AS product_count FROM iceberg.ecommerce.products;

-- ============================================================
-- Step 2: feature/add-books ブランチを作成する
-- ============================================================
-- ⚠️  以下のSQLを実行する前に、別ターミナルで curl コマンドを実行して
--     ブランチを作成してください。ブランチが存在しない状態で iceberg_dev
--     カタログを参照するとエラーになります。
--
-- (1) mainブランチのハッシュを取得
--     curl -s http://localhost:19120/api/v2/trees/main \
--       | jq -r '.reference.hash'
--
-- (2) feature/add-books ブランチを作成
--     HASH=$(curl -s http://localhost:19120/api/v2/trees/main | jq -r '.reference.hash')
--     curl -s -X POST \
--       -H "Content-Type: application/json" \
--       -d "{\"name\":\"main\",\"type\":\"BRANCH\",\"hash\":\"${HASH}\"}" \
--       "http://localhost:19120/api/v2/trees?name=feature/add-books&type=BRANCH" | jq .
--
-- (3) ブランチ一覧を確認（feature/add-books が表示されればOK）
--     curl -s http://localhost:19120/api/v2/trees | jq '[.references[] | {type, name}]'
-- ============================================================

-- ============================================================
-- Step 3: featureブランチにデータを追加（iceberg_dev カタログを使用）
-- ============================================================
-- iceberg_dev は feature/add-books ブランチを参照しており、
-- ここへの変更は iceberg（main）には一切影響しない。

-- featureブランチに新商品（Books カテゴリ）を追加
INSERT INTO iceberg_dev.ecommerce.products VALUES
    (201, 'データエンジニアリングの基礎', 'Books', 3500.00, TIMESTAMP '2024-03-01 00:00:00'),
    (202, 'レイクハウスアーキテクチャ',   'Books', 4200.00, TIMESTAMP '2024-03-01 00:00:00'),
    (203, 'Apache Iceberg完全ガイド',     'Books', 5800.00, TIMESTAMP '2024-03-01 00:00:00');

-- ============================================================
-- Step 4: ブランチ間のデータ分離を確認
-- ============================================================

-- featureブランチ（新商品が見える）
SELECT product_id, product_name, category, price
FROM iceberg_dev.ecommerce.products
ORDER BY product_id;

-- mainブランチ（変更されていない）
SELECT product_id, product_name, category, price
FROM iceberg.ecommerce.products
ORDER BY product_id;

-- 件数の比較
SELECT 'feature/add-books' AS branch, COUNT(*) AS product_count
FROM iceberg_dev.ecommerce.products
UNION ALL
SELECT 'main' AS branch, COUNT(*) AS product_count
FROM iceberg.ecommerce.products;

-- ============================================================
-- Step 5: featureブランチで検証クエリを実行
-- ============================================================

-- featureブランチでカテゴリ別商品数を確認
SELECT category, COUNT(*) AS product_count, AVG(price) AS avg_price
FROM iceberg_dev.ecommerce.products
GROUP BY category
ORDER BY category;

-- ============================================================
-- Step 6: 「マージ」— featureブランチの変更をmainに適用
-- ============================================================
-- ⚠️  Nessie のマージは REST API で行います。
--     別ターミナルで以下を実行してください:
--
-- (1) 各ブランチのハッシュを取得
--     MAIN_HASH=$(curl -s http://localhost:19120/api/v2/trees/main | jq -r '.reference.hash')
--     DEV_HASH=$(curl -s "http://localhost:19120/api/v2/trees/feature%2Fadd-books" | jq -r '.reference.hash')
--
-- (2) feature/add-books を main にマージ
--     ※ v2 API は ?expectedHash= ではなく URL パスに @hash 形式で埋め込む
--     curl -s -X POST \
--       -H "Content-Type: application/json" \
--       -d "{\"fromRefName\":\"feature/add-books\",\"fromHash\":\"${DEV_HASH}\"}" \
--       "http://localhost:19120/api/v2/trees/main@${MAIN_HASH}/history/merge" | jq .
--
-- または Nessie UI (http://localhost:19120) から操作することも可能です。

-- ============================================================
-- Step 7: マージ後にmainブランチへの反映を確認
-- ============================================================
-- REST APIでマージを実行した後に以下を実行してください

-- mainにBooksカテゴリが追加されているはず
SELECT product_id, product_name, category, price
FROM iceberg.ecommerce.products
ORDER BY product_id;

-- カテゴリ別の最終確認
SELECT category, COUNT(*) AS product_count
FROM iceberg.ecommerce.products
GROUP BY category
ORDER BY category;

-- ============================================================
-- Nessie REST API でブランチ管理を確認
-- ============================================================
-- 別ターミナルで実行してください:
--
-- ブランチ一覧
--   curl -s http://localhost:19120/api/v2/trees | jq '[.references[] | {type, name}]'
--
-- mainブランチのコミット履歴
--   curl -s "http://localhost:19120/api/v2/trees/main/history" \
--     | jq '.logEntries[0:5] | .[] | {commitTime: .commitMeta.commitTime, message: .commitMeta.message}'
--
-- feature/add-books ブランチのコミット履歴（/ を %2F にURLエンコード）
--   curl -s "http://localhost:19120/api/v2/trees/feature%2Fadd-books/history" \
--     | jq '.logEntries[0:5] | .[] | {commitTime: .commitMeta.commitTime, message: .commitMeta.message}'
