.PHONY: up down reset setup demo trino logs ps help \
        seed restart \
        scenario-01 scenario-02 scenario-03 scenario-04 scenario-05 scenario-06 \
        scenario-07 scenario-08 scenario-09 scenario-10 scenario-11 \
        scenario-all

## デフォルトターゲット
help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "--- 基本操作 ---"
	@echo "  up            全サービスを起動"
	@echo "  down          全サービスを停止（データは保持）"
	@echo "  reset         全サービスを停止してデータも削除"
	@echo "  setup         テーブル作成とサンプルデータ投入"
	@echo "  seed          大量サンプルデータ投入（パーティション効果確認用）"
	@echo "  restart       データを削除して起動・セットアップまで一発実行"
	@echo "  demo          基本分析クエリを実行"
	@echo "  trino         Trinoシェルに接続"
	@echo "  logs          全サービスのログをリアルタイム表示"
	@echo "  ps            サービスの稼働状況を確認"
	@echo ""
	@echo "--- シナリオ（setup 実行後に使用） ---"
	@echo "  scenario-01   Iceberg ACID操作 (UPDATE / DELETE / MERGE)"
	@echo "  scenario-02   Iceberg タイムトラベル"
	@echo "  scenario-03   Iceberg スキーマ進化"
	@echo "  scenario-04   Iceberg メタデータ探索"
	@echo "  scenario-05   Nessie ブランチワークフロー"
	@echo "  scenario-06   Nessie 監査・コミット履歴"
	@echo ""
	@echo "--- 応用シナリオ ---"
	@echo "  scenario-07   Nessie コンフリクト解決"
	@echo "  scenario-08   Iceberg パーティション進化"
	@echo "  scenario-09   Nessie タグによるリリース管理"
	@echo "  scenario-10   Iceberg テーブルメンテナンス"
	@echo "  scenario-11   Nessie マルチブランチ並行開発"
	@echo ""
	@echo "  scenario-all  基本シナリオ(01-06)を順番に実行"

up:
	docker compose up -d
	@echo "起動完了。状態を確認するには: make ps"

down:
	docker compose down

reset:
	docker compose down -v
	@echo "データを含む全リソースを削除しました"

restart:
	docker compose down -v
	@echo "サービスが healthy になるまで待機中..."
	docker compose up -d --wait minio nessie trino
	docker compose up minio-setup
	$(MAKE) setup

setup:
	docker exec demo1-trino trino --file /etc/trino/sql/setup.sql
	@echo "セットアップ完了"

demo:
	docker exec demo1-trino trino --file /etc/trino/sql/demo.sql

trino:
	docker exec -it demo1-trino trino

logs:
	docker compose logs -f

ps:
	docker compose ps

seed:
	docker exec demo1-trino trino --file /etc/trino/sql/seed/large_dataset.sql
	@echo "大量サンプルデータ投入完了"

scenario-01:
	@echo "=== シナリオ01: Iceberg ACID操作 ==="
	docker exec demo1-trino trino --file /etc/trino/sql/scenarios/01_iceberg_acid.sql

scenario-02:
	@echo "=== シナリオ02: Iceberg タイムトラベル ==="
	docker exec demo1-trino trino --file /etc/trino/sql/scenarios/02_iceberg_time_travel.sql

scenario-03:
	@echo "=== シナリオ03: Iceberg スキーマ進化 ==="
	docker exec demo1-trino trino --file /etc/trino/sql/scenarios/03_iceberg_schema_evolution.sql

scenario-04:
	@echo "=== シナリオ04: Iceberg メタデータ探索 ==="
	docker exec demo1-trino trino --file /etc/trino/sql/scenarios/04_iceberg_metadata.sql

scenario-05:
	@echo "=== シナリオ05: Nessie ブランチワークフロー ==="
	docker exec demo1-trino trino --file /etc/trino/sql/scenarios/05_nessie_branch.sql

scenario-06:
	@echo "=== シナリオ06: Nessie 監査・コミット履歴 ==="
	docker exec demo1-trino trino --file /etc/trino/sql/scenarios/06_nessie_audit.sql

scenario-07:
	@echo "=== シナリオ07: Nessie コンフリクト解決 ==="
	docker exec demo1-trino trino --file /etc/trino/sql/scenarios/07_nessie_conflict.sql

scenario-08:
	@echo "=== シナリオ08: Iceberg パーティション進化 ==="
	docker exec demo1-trino trino --file /etc/trino/sql/scenarios/08_iceberg_partition_evolution.sql

scenario-09:
	@echo "=== シナリオ09: Nessie タグによるリリース管理 ==="
	docker exec demo1-trino trino --file /etc/trino/sql/scenarios/09_nessie_tag.sql

scenario-10:
	@echo "=== シナリオ10: Iceberg テーブルメンテナンス ==="
	docker exec demo1-trino trino --file /etc/trino/sql/scenarios/10_iceberg_maintenance.sql

scenario-11:
	@echo "=== シナリオ11: Nessie マルチブランチ並行開発 ==="
	docker exec demo1-trino trino --file /etc/trino/sql/scenarios/11_nessie_multi_branch.sql

scenario-all: scenario-01 scenario-02 scenario-03 scenario-04 scenario-05 scenario-06
	@echo "=== 基本シナリオ(01-06)完了 ==="
