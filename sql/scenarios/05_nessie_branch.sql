-- ============================================================
-- シナリオ05: Nessie ブランチワークフロー
--
-- 目的:
--   Gitと同じように「ブランチ上でデータを変更してmainに影響させない」
--   という分離されたデータ開発ワークフローを体感する。
--   本番データに影響を与えずにETL開発・テスト・実験ができることを示す。
--
-- 重要:
--   Nessie のブランチ操作は Nessie REST API で行います。
--   このSQLファイルは「Trinoでデータを確認する」部分を担当します。
--   ブランチの作成・マージは docs/scenario-05-nessie-branch.md の
--   curl コマンドと合わせて実行してください。
--
-- 前提: setup.sql を先に実行してください
--
-- ⚠️  再実行の注意:
--   このスクリプトは setup 直後のクリーンな状態を前提としています。
--   2回目以降の実行では products テーブルに重複データが追加されます。
--   再実行前に以下を実行してリセットしてください:
--     make reset && make up && make setup
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
-- Step 2: ブランチ操作は REST API で行う
-- ============================================================
-- 別ターミナルで以下を実行してください:
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
-- (3) ブランチ一覧を確認
--     curl -s http://localhost:19120/api/v2/trees | jq '[.references[] | {type, name}]'

-- ============================================================
-- Step 3: featureブランチ用のカタログ設定でデータを追加
-- ============================================================
-- Trinoでブランチを切り替えるには、別のカタログ設定（iceberg-dev等）が必要です。
-- ここでは「mainとは別の名前空間」でブランチの動作を模倣します。

-- featureブランチ相当の変更をステージング領域に加える（mainには影響しない別スキーマ）
CREATE SCHEMA IF NOT EXISTS iceberg.feature_add_books;

CREATE TABLE IF NOT EXISTS iceberg.feature_add_books.products (
    product_id   BIGINT,
    product_name VARCHAR,
    category     VARCHAR,
    price        DECIMAL(10,2),
    created_at   TIMESTAMP
) WITH (format = 'PARQUET');

-- featureブランチ相当: mainのデータ + 新商品
INSERT INTO iceberg.feature_add_books.products
SELECT * FROM iceberg.ecommerce.products;

INSERT INTO iceberg.feature_add_books.products VALUES
    (201, 'データエンジニアリングの基礎', 'Books', 3500.00, TIMESTAMP '2024-03-01 00:00:00'),
    (202, 'レイクハウスアーキテクチャ',   'Books', 4200.00, TIMESTAMP '2024-03-01 00:00:00'),
    (203, 'Apache Iceberg完全ガイド',     'Books', 5800.00, TIMESTAMP '2024-03-01 00:00:00');

-- ============================================================
-- Step 4: 「ブランチ」と「main」のデータを比較
-- ============================================================

-- featureブランチ相当（新商品が見える）
SELECT product_id, product_name, category, price
FROM iceberg.feature_add_books.products
ORDER BY product_id;

-- mainブランチ（変更されていない）
SELECT product_id, product_name, category, price
FROM iceberg.ecommerce.products
ORDER BY product_id;

-- 件数の比較
SELECT 'feature/add-books' AS branch, COUNT(*) AS product_count
FROM iceberg.feature_add_books.products
UNION ALL
SELECT 'main' AS branch, COUNT(*) AS product_count
FROM iceberg.ecommerce.products;

-- ============================================================
-- Step 5: featureブランチで検証クエリを実行
-- ============================================================

-- featureブランチでカテゴリ別商品数を確認
SELECT category, COUNT(*) AS product_count, AVG(price) AS avg_price
FROM iceberg.feature_add_books.products
GROUP BY category
ORDER BY category;

-- ============================================================
-- Step 6: 「マージ」— featureブランチの変更をmainに適用
-- ============================================================

-- featureブランチの新商品データのみをmainに追加（差分マージ）
INSERT INTO iceberg.ecommerce.products
SELECT * FROM iceberg.feature_add_books.products
WHERE product_id >= 201;

-- mainに変更が反映されたことを確認
SELECT product_id, product_name, category, price
FROM iceberg.ecommerce.products
ORDER BY product_id;

-- ============================================================
-- Step 7: featureブランチ相当のスキーマをクリーンアップ
-- ============================================================

DROP TABLE IF EXISTS iceberg.feature_add_books.products;
DROP SCHEMA IF EXISTS iceberg.feature_add_books;

-- 最終確認: mainにBooksが追加されている
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
