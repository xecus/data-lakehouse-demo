-- ============================================================
-- シナリオ09: Nessie タグによるデータリリース管理
--
-- 目的:
--   Nessie のタグ機能を使って「データのバージョンリリース」を管理する。
--   Git のタグと同じように、特定時点のデータに名前を付けて
--   再現性のあるアクセスを可能にする。
--   月次レポートや監査用スナップショットとしての実用例を理解する。
--
-- 前提: setup.sql を先に実行してください
--
-- ⚠️  再実行の注意:
--   このスクリプトは setup 直後のクリーンな状態を前提としています。
--   再実行前に make restart を実行してリセットしてください。
--
-- 実行方法:
--   make scenario-09
--   または: docker exec trino trino --file /etc/trino/sql/scenarios/09_nessie_tag.sql
-- ============================================================

-- ============================================================
-- Step 1: 現在の状態を確認（初期データ = v1.0.0 相当）
-- ============================================================

SELECT product_id, product_name, category, price
FROM iceberg.ecommerce.products
ORDER BY product_id;

SELECT COUNT(*) AS product_count FROM iceberg.ecommerce.products;

SELECT COUNT(*) AS order_count FROM iceberg.ecommerce.orders;

-- ============================================================
-- Step 2: v1.0.0 タグを作成（初期リリース）
-- ============================================================
-- ⚠️  別ターミナルで以下を実行してください:
--
-- (1) mainブランチのハッシュを取得
--     HASH=$(curl -s http://localhost:19120/api/v2/trees/main | jq -r '.reference.hash')
--
-- (2) v1.0.0 タグを作成
--     curl -s -X POST \
--       -H "Content-Type: application/json" \
--       -d "{\"name\":\"main\",\"type\":\"BRANCH\",\"hash\":\"${HASH}\"}" \
--       "http://localhost:19120/api/v2/trees?name=v1.0.0&type=TAG" | jq .
--
-- (3) リファレンス一覧を確認（TAG として v1.0.0 が表示される）
--     curl -s http://localhost:19120/api/v2/trees | jq '[.references[] | {type, name}]'

-- ============================================================
-- Step 3: データを更新する（v1.0.0 → v2.0.0 の変更）
-- ============================================================

-- 新商品を追加
INSERT INTO iceberg.ecommerce.products VALUES
    (107, 'USBハブ',        'Electronics', 3500.00, TIMESTAMP '2024-04-01 00:00:00'),
    (108, 'Webカメラ',      'Electronics', 8000.00, TIMESTAMP '2024-04-01 00:00:00');

-- 既存商品の価格改定（10%値上げ）
UPDATE iceberg.ecommerce.products
SET price = price * 1.10
WHERE category = 'Furniture';

-- 新規注文を追加
INSERT INTO iceberg.ecommerce.orders VALUES
    (1006, 3, DATE '2024-04-01', TIMESTAMP '2024-04-01 10:00:00', 'completed',  11500.00),
    (1007, 5, DATE '2024-04-15', TIMESTAMP '2024-04-15 14:30:00', 'processing', 8000.00);

-- 更新後の確認
SELECT product_id, product_name, category, price
FROM iceberg.ecommerce.products
ORDER BY product_id;

SELECT COUNT(*) AS order_count FROM iceberg.ecommerce.orders;

-- ============================================================
-- Step 4: v2.0.0 タグを作成（価格改定 + 新商品追加後）
-- ============================================================
-- ⚠️  別ターミナルで以下を実行してください:
--
-- (1) mainブランチの最新ハッシュを取得
--     HASH=$(curl -s http://localhost:19120/api/v2/trees/main | jq -r '.reference.hash')
--
-- (2) v2.0.0 タグを作成
--     curl -s -X POST \
--       -H "Content-Type: application/json" \
--       -d "{\"name\":\"main\",\"type\":\"BRANCH\",\"hash\":\"${HASH}\"}" \
--       "http://localhost:19120/api/v2/trees?name=v2.0.0&type=TAG" | jq .
--
-- (3) リファレンス一覧を確認（v1.0.0 と v2.0.0 の2つのタグ）
--     curl -s http://localhost:19120/api/v2/trees | jq '[.references[] | {type, name}]'

-- ============================================================
-- Step 5: タグを使ってバージョン間のデータを比較
-- ============================================================
-- タグ指定でデータにアクセスするには、タグを参照するカタログが必要です。
-- ここでは Iceberg スナップショットのタイムトラベル機能で
-- 「タグ作成前後」のデータの違いを確認します。

-- 現在（v2.0.0 相当）の商品数
SELECT COUNT(*) AS product_count, 'v2.0.0 (現在)' AS version
FROM iceberg.ecommerce.products;

-- 初期状態（v1.0.0 相当）の商品数
-- ※ setup直後のスナップショットIDを使ってアクセス
SELECT snapshot_id, committed_at, operation
FROM iceberg.ecommerce."products$snapshots"
ORDER BY committed_at;

-- ============================================================
-- Step 6: REST API でタグの詳細を確認
-- ============================================================
-- ⚠️  別ターミナルで以下を実行してください:
--
-- --- v1.0.0 タグの詳細（ハッシュとメタデータ） ---
-- curl -s http://localhost:19120/api/v2/trees/v1.0.0 | jq .
--
-- --- v2.0.0 タグの詳細 ---
-- curl -s http://localhost:19120/api/v2/trees/v2.0.0 | jq .
--
-- --- v1.0.0 時点のコミット履歴 ---
-- curl -s "http://localhost:19120/api/v2/trees/v1.0.0/history" \
--   | jq '.logEntries[] | {commitTime: .commitMeta.commitTime, message: .commitMeta.message}'
--
-- --- v2.0.0 時点のコミット履歴（v1.0.0よりコミットが多い） ---
-- curl -s "http://localhost:19120/api/v2/trees/v2.0.0/history" \
--   | jq '.logEntries[] | {commitTime: .commitMeta.commitTime, message: .commitMeta.message}'
--
-- --- v1.0.0 と v2.0.0 のコミット数の違い ---
-- echo "v1.0.0: $(curl -s http://localhost:19120/api/v2/trees/v1.0.0/history | jq '.logEntries | length') commits"
-- echo "v2.0.0: $(curl -s http://localhost:19120/api/v2/trees/v2.0.0/history | jq '.logEntries | length') commits"

-- ============================================================
-- Step 7: さらに変更を加えてもタグは不変であることを確認
-- ============================================================

-- v2.0.0 タグ作成後にさらにデータを変更
INSERT INTO iceberg.ecommerce.products VALUES
    (109, 'ゲーミングマウス', 'Electronics', 12000.00, TIMESTAMP '2024-05-01 00:00:00');

-- main（最新）では 9 商品
SELECT COUNT(*) AS product_count, 'main (最新)' AS ref
FROM iceberg.ecommerce.products;

-- ⚠️  別ターミナルで確認:
-- v2.0.0 タグのハッシュは変わっていない（タグは不変）
-- curl -s http://localhost:19120/api/v2/trees/v2.0.0 | jq '.reference.hash'

-- ============================================================
-- Step 8: タグの削除
-- ============================================================
-- 不要になったタグは削除できます。
--
-- ⚠️  別ターミナルで以下を実行してください:
--
-- (1) v1.0.0 タグを削除
--     TAG_HASH=$(curl -s http://localhost:19120/api/v2/trees/v1.0.0 | jq -r '.reference.hash')
--     curl -s -X DELETE "http://localhost:19120/api/v2/trees/v1.0.0@${TAG_HASH}" | jq .
--
-- (2) リファレンス一覧を確認（v1.0.0 が消えている）
--     curl -s http://localhost:19120/api/v2/trees | jq '[.references[] | {type, name}]'
--
-- (3) v2.0.0 も削除する場合
--     TAG_HASH=$(curl -s http://localhost:19120/api/v2/trees/v2.0.0 | jq -r '.reference.hash')
--     curl -s -X DELETE "http://localhost:19120/api/v2/trees/v2.0.0@${TAG_HASH}" | jq .

-- ============================================================
-- まとめ
-- ============================================================
-- ポイント:
--   - Nessie タグはブランチと異なり「不変」— 一度作成したら指すハッシュは変わらない
--   - Git タグと同じく、リリースポイントやスナップショットとして利用できる
--   - 実用例:
--     * 月次・四半期レポート用のデータスナップショット（report-2024-Q1 等）
--     * データパイプラインのリリースバージョン管理
--     * 監査・コンプライアンス要件での「確定時点のデータ」の保持
--   - タグはブランチと同じ REST API パターンで作成・参照・削除できる
