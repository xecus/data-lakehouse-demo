.PHONY: up down reset setup demo trino logs ps help \
        seed restart \
        scenario-01 scenario-02 scenario-03 scenario-04 scenario-05 scenario-06 \
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
	@echo "  scenario-all  全シナリオを順番に実行"

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
	docker compose up -d
	@echo "サービスが healthy になるまで待機中..."
	docker compose wait trino
	$(MAKE) setup

setup:
	docker exec trino trino --file /etc/trino/sql/setup.sql
	@echo "セットアップ完了"

demo:
	docker exec trino trino --file /etc/trino/sql/demo.sql

trino:
	docker exec -it trino trino

logs:
	docker compose logs -f

ps:
	docker compose ps

seed:
	docker exec trino trino --file /etc/trino/sql/seed/large_dataset.sql
	@echo "大量サンプルデータ投入完了"

scenario-01:
	@echo "=== シナリオ01: Iceberg ACID操作 ==="
	docker exec trino trino --file /etc/trino/sql/scenarios/01_iceberg_acid.sql

scenario-02:
	@echo "=== シナリオ02: Iceberg タイムトラベル ==="
	docker exec trino trino --file /etc/trino/sql/scenarios/02_iceberg_time_travel.sql

scenario-03:
	@echo "=== シナリオ03: Iceberg スキーマ進化 ==="
	docker exec trino trino --file /etc/trino/sql/scenarios/03_iceberg_schema_evolution.sql

scenario-04:
	@echo "=== シナリオ04: Iceberg メタデータ探索 ==="
	docker exec trino trino --file /etc/trino/sql/scenarios/04_iceberg_metadata.sql

scenario-05:
	@echo "=== シナリオ05: Nessie ブランチワークフロー ==="
	docker exec trino trino --file /etc/trino/sql/scenarios/05_nessie_branch.sql

scenario-06:
	@echo "=== シナリオ06: Nessie 監査・コミット履歴 ==="
	docker exec trino trino --file /etc/trino/sql/scenarios/06_nessie_audit.sql

scenario-all: scenario-01 scenario-02 scenario-03 scenario-04 scenario-05 scenario-06
	@echo "=== 全シナリオ完了 ==="
