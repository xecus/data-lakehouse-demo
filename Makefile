.PHONY: up down reset setup demo trino logs ps help

## デフォルトターゲット
help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  up      全サービスを起動"
	@echo "  down    全サービスを停止（データは保持）"
	@echo "  reset   全サービスを停止してデータも削除"
	@echo "  setup   テーブル作成とサンプルデータ投入"
	@echo "  demo    分析クエリを実行"
	@echo "  trino   Trinoシェルに接続"
	@echo "  logs    全サービスのログをリアルタイム表示"
	@echo "  ps      サービスの稼働状況を確認"

up:
	docker compose up -d
	@echo "起動完了。状態を確認するには: make ps"

down:
	docker compose down

reset:
	docker compose down -v
	@echo "データを含む全リソースを削除しました"

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
