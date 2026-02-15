-- ============================================================
-- demo.sql
-- ECサイト売上分析 - 分析クエリ集
--
-- 実行方法:
--   docker exec demo1-trino trino --file /etc/trino/sql/demo.sql
--
-- 前提: setup.sql を先に実行してください
-- ============================================================

-- ============================================================
-- Section 1: 基本的な売上分析
-- ============================================================

-- [Q1] 日次売上集計
SELECT
    order_date,
    COUNT(*)              AS order_count,
    SUM(total_amount)     AS daily_revenue,
    AVG(total_amount)     AS avg_order_value
FROM iceberg.ecommerce.orders
WHERE status = 'completed'
GROUP BY order_date
ORDER BY order_date;

-- [Q2] 国別 顧客数・注文数・売上
SELECT
    c.country,
    COUNT(DISTINCT c.customer_id)    AS customer_count,
    COUNT(o.order_id)                AS order_count,
    COALESCE(SUM(o.total_amount), 0) AS total_revenue
FROM iceberg.ecommerce.customers c
LEFT JOIN iceberg.ecommerce.orders o ON c.customer_id = o.customer_id
GROUP BY c.country
ORDER BY total_revenue DESC;

-- [Q3] 商品カテゴリ別 売上ランキング
SELECT
    p.category,
    p.product_name,
    SUM(oi.quantity)  AS total_quantity_sold,
    SUM(oi.subtotal)  AS total_revenue
FROM iceberg.ecommerce.order_items oi
JOIN iceberg.ecommerce.products p ON oi.product_id = p.product_id
GROUP BY p.category, p.product_name
ORDER BY total_revenue DESC;

-- [Q4] 顧客別 購入履歴・LTV（顧客生涯価値）
SELECT
    c.customer_name,
    c.email,
    COUNT(o.order_id)      AS purchase_count,
    SUM(o.total_amount)    AS lifetime_value,
    MAX(o.order_date)      AS last_purchase_date
FROM iceberg.ecommerce.customers c
LEFT JOIN iceberg.ecommerce.orders o ON c.customer_id = o.customer_id
GROUP BY c.customer_name, c.email
ORDER BY lifetime_value DESC;

-- [Q5] 月次売上トレンド
--   NOTE: Trino では DATE_FORMAT ではなく date_trunc を使用します
SELECT
    date_trunc('month', order_date) AS month,
    COUNT(*)                        AS order_count,
    SUM(total_amount)               AS monthly_revenue,
    AVG(total_amount)               AS avg_order_value
FROM iceberg.ecommerce.orders
WHERE status = 'completed'
GROUP BY date_trunc('month', order_date)
ORDER BY month;

-- ============================================================
-- Section 2: Apache Iceberg 機能デモ
-- ============================================================

-- [I1] スナップショット履歴（タイムトラベルの起点）
SELECT
    snapshot_id,
    committed_at,
    operation,
    summary
FROM iceberg.ecommerce."orders$snapshots"
ORDER BY committed_at;

-- [I2] タイムトラベルクエリ
--   下記の <snapshot_id> を [I1] で確認した値に置き換えてください
-- SELECT * FROM iceberg.ecommerce.orders
-- FOR VERSION AS OF <snapshot_id>;

-- [I3] マニフェストファイル一覧（データファイルの管理情報）
SELECT * FROM iceberg.ecommerce."orders$manifests";

-- [I4] パーティション情報
SELECT * FROM iceberg.ecommerce."orders$partitions";

-- [I5] スキーマ進化: カラムの追加
--   既存データはエラーにならず NULL になります
-- ALTER TABLE iceberg.ecommerce.orders ADD COLUMN coupon_code VARCHAR;
-- SELECT order_id, total_amount, coupon_code FROM iceberg.ecommerce.orders LIMIT 3;
