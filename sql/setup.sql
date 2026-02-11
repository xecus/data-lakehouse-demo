-- ============================================================
-- setup.sql
-- ECサイト売上分析 - スキーマ・テーブル定義 + サンプルデータ投入
--
-- 実行方法:
--   docker exec trino trino --file /etc/trino/sql/setup.sql
-- ============================================================

-- スキーマの作成
CREATE SCHEMA IF NOT EXISTS iceberg.ecommerce;

-- ------------------------------------------------------------
-- テーブル定義
-- ------------------------------------------------------------

-- 顧客マスタ（countryでパーティション）
CREATE TABLE IF NOT EXISTS iceberg.ecommerce.customers (
    customer_id       BIGINT,
    customer_name     VARCHAR,
    email             VARCHAR,
    country           VARCHAR,
    registration_date DATE
) WITH (
    format       = 'PARQUET',
    partitioning = ARRAY['country']
);

-- 商品マスタ
CREATE TABLE IF NOT EXISTS iceberg.ecommerce.products (
    product_id   BIGINT,
    product_name VARCHAR,
    category     VARCHAR,
    price        DECIMAL(10,2),
    created_at   TIMESTAMP
) WITH (
    format = 'PARQUET'
);

-- 注文ヘッダ（order_dateでパーティション）
CREATE TABLE IF NOT EXISTS iceberg.ecommerce.orders (
    order_id        BIGINT,
    customer_id     BIGINT,
    order_date      DATE,
    order_timestamp TIMESTAMP,
    status          VARCHAR,
    total_amount    DECIMAL(10,2)
) WITH (
    format       = 'PARQUET',
    partitioning = ARRAY['order_date']
);

-- 注文明細
CREATE TABLE IF NOT EXISTS iceberg.ecommerce.order_items (
    order_item_id BIGINT,
    order_id      BIGINT,
    product_id    BIGINT,
    quantity      INTEGER,
    unit_price    DECIMAL(10,2),
    subtotal      DECIMAL(10,2)
) WITH (
    format = 'PARQUET'
);

-- ------------------------------------------------------------
-- サンプルデータの投入
-- ------------------------------------------------------------

INSERT INTO iceberg.ecommerce.customers VALUES
    (1, '山田太郎',    'yamada@example.com', 'Japan', DATE '2023-01-15'),
    (2, '佐藤花子',    'sato@example.com',   'Japan', DATE '2023-02-20'),
    (3, 'John Smith',  'john@example.com',   'USA',   DATE '2023-03-10'),
    (4, 'Alice Johnson','alice@example.com', 'USA',   DATE '2023-04-05'),
    (5, '鈴木一郎',    'suzuki@example.com', 'Japan', DATE '2023-05-12');

INSERT INTO iceberg.ecommerce.products VALUES
    (101, 'ノートPC',         'Electronics', 89000.00, TIMESTAMP '2023-01-01 00:00:00'),
    (102, 'ワイヤレスマウス',  'Electronics',  2500.00, TIMESTAMP '2023-01-01 00:00:00'),
    (103, 'キーボード',        'Electronics',  5000.00, TIMESTAMP '2023-01-01 00:00:00'),
    (104, 'モニター',          'Electronics', 25000.00, TIMESTAMP '2023-01-01 00:00:00'),
    (105, 'デスクチェア',      'Furniture',   15000.00, TIMESTAMP '2023-01-01 00:00:00'),
    (106, 'デスク',            'Furniture',   30000.00, TIMESTAMP '2023-01-01 00:00:00');

INSERT INTO iceberg.ecommerce.orders VALUES
    (1001, 1, DATE '2024-01-15', TIMESTAMP '2024-01-15 10:30:00', 'completed',  96500.00),
    (1002, 2, DATE '2024-01-16', TIMESTAMP '2024-01-16 14:20:00', 'completed',  30000.00),
    (1003, 3, DATE '2024-01-17', TIMESTAMP '2024-01-17 09:15:00', 'completed', 114000.00),
    (1004, 1, DATE '2024-02-10', TIMESTAMP '2024-02-10 11:00:00', 'completed',  45000.00),
    (1005, 4, DATE '2024-02-15', TIMESTAMP '2024-02-15 16:45:00', 'processing',  5000.00);

INSERT INTO iceberg.ecommerce.order_items VALUES
    (1, 1001, 101, 1, 89000.00, 89000.00),
    (2, 1001, 102, 3,  2500.00,  7500.00),
    (3, 1002, 106, 1, 30000.00, 30000.00),
    (4, 1003, 101, 1, 89000.00, 89000.00),
    (5, 1003, 104, 1, 25000.00, 25000.00),
    (6, 1004, 105, 3, 15000.00, 45000.00),
    (7, 1005, 103, 1,  5000.00,  5000.00);
