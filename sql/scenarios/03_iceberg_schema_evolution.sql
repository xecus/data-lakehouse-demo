-- ============================================================
-- シナリオ03: Iceberg スキーマ進化
-- ADD COLUMN / RENAME COLUMN / DROP COLUMN / 型変更
--
-- 目的:
--   通常のRDBMSと異なり、Icebergではスキーマ変更が
--   「メタデータの更新だけ」で完結し、既存のParquetファイルは
--   書き換えられない（= ダウンタイムなし・データ安全）ことを体感する。
--
-- 前提: setup.sql を先に実行してください
--
-- 実行方法:
--   make scenario-03
--   または: docker exec demo1-trino trino --file /etc/trino/sql/scenarios/03_iceberg_schema_evolution.sql
-- ============================================================

-- ------------------------------------------------------------
-- 事前確認: 現在のスキーマ
-- ------------------------------------------------------------

DESCRIBE iceberg.ecommerce.orders;

-- ============================================================
-- Step 1: ADD COLUMN — カラム追加
-- ============================================================
-- ビジネスシナリオ: クーポン機能を追加するため、注文テーブルに
--                  クーポンコードと割引額カラムを追加する

ALTER TABLE iceberg.ecommerce.orders ADD COLUMN coupon_code VARCHAR;
ALTER TABLE iceberg.ecommerce.orders ADD COLUMN discount_amount DECIMAL(10,2);

-- 確認: 既存データはエラーにならず NULL になる
SELECT order_id, total_amount, coupon_code, discount_amount
FROM iceberg.ecommerce.orders
LIMIT 3;

-- ポイント: 既存Parquetファイルは一切書き換えられていない
--          スキーマ定義（メタデータ）だけが更新された

-- ============================================================
-- Step 2: 追加したカラムにデータを入れてみる
-- ============================================================

UPDATE iceberg.ecommerce.orders
SET coupon_code = 'WINTER2024', discount_amount = 1000.00
WHERE order_id = 1001;

UPDATE iceberg.ecommerce.orders
SET coupon_code = 'NEWUSER', discount_amount = 500.00
WHERE order_id = 1005;

SELECT order_id, total_amount, coupon_code, discount_amount
FROM iceberg.ecommerce.orders
ORDER BY order_id;

-- ============================================================
-- Step 3: RENAME COLUMN — カラム名の変更
-- ============================================================
-- ビジネスシナリオ: 命名規約の変更で coupon_code → promotion_code にリネーム

ALTER TABLE iceberg.ecommerce.orders RENAME COLUMN coupon_code TO promotion_code;

-- 確認: データはそのままで名前だけ変わっている
SELECT order_id, promotion_code, discount_amount
FROM iceberg.ecommerce.orders
ORDER BY order_id;

-- ============================================================
-- Step 4: DROP COLUMN — カラム削除
-- ============================================================
-- ビジネスシナリオ: discount_amount は total_amount に内包することになったため削除

ALTER TABLE iceberg.ecommerce.orders DROP COLUMN discount_amount;

-- 確認: カラムが消えていること
DESCRIBE iceberg.ecommerce.orders;

SELECT order_id, total_amount, promotion_code
FROM iceberg.ecommerce.orders
ORDER BY order_id;

-- ============================================================
-- Step 5: スキーマ変更履歴をスナップショットで確認
-- ============================================================
-- スキーマ変更もスナップショットとして記録される

SELECT
    snapshot_id,
    committed_at,
    operation,
    element_at(summary, 'changed-partition-count') AS changed_partitions
FROM iceberg.ecommerce."orders$snapshots"
ORDER BY committed_at;

-- ============================================================
-- Step 6: タイムトラベルで「coupon_codeが存在した時代」のスキーマを確認
-- ============================================================
-- スキーマ変更前のスナップショットIDを Step5 の結果から確認し、
-- 下記クエリのIDを置き換えて実行する

-- 例:
-- SELECT order_id, coupon_code FROM iceberg.ecommerce.orders
-- FOR VERSION AS OF <coupon_code追加後のsnapshot_id>;

-- ポイント: タイムトラベルはスキーマ変更をまたいでも有効
--          過去のスナップショット時点のスキーマでデータが返ってくる

-- ============================================================
-- クリーンアップ: このシナリオの追加カラムをリセット
-- ============================================================
-- 他のシナリオに影響しないよう promotion_code を削除

ALTER TABLE iceberg.ecommerce.orders DROP COLUMN promotion_code;

DESCRIBE iceberg.ecommerce.orders;
