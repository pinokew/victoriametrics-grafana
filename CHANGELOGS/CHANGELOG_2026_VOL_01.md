# CHANGELOG 2026 VOL 01

## [2026-03-07] — Phase 0 старт: структура та ADR база

- **Context:** Старт `Phase 0 — Pre-Flight`, підготовка репозиторію до подальшого deployment етапу.
- **Change:** Створено каркас monitoring stack у корені репо (`docker-compose.yml`, `victoria-metrics/`, `grafana/`, `alerting/`, `exporters/`), додано `ADR-001..003`, створено `docs/architecture/monitoring-architecture.md` та `docs/architecture/ports-map.md`, ініціалізовано changelog-том.
- **Verification:** Перевірено наявність структури директорій та файлів; перевірено disk space (`df -h .`) — доступно 27G.
- **Risks:** Конфігураційні файли поки placeholder; фактичний deploy не виконано (очікується у Phase 1).
- **Rollback:** `git revert <commit>` після коміту змін.

## [2026-03-07] — Phase 1: Core Stack (VictoriaMetrics + Grafana + Node Exporter)

- **Context:** Початок `Phase 1 — Core Stack Deployment`, перехід від placeholder конфігів до робочого базового стеку.
- **Change:**
	- Заповнено `docker-compose.yml` сервісами `victoriametrics`, `grafana`, `node-exporter` з портами тільки `127.0.0.1`.
	- Додано retention через `VM_RETENTION_PERIOD` (з дефолтом `90d`) і `restart: unless-stopped` для ключових сервісів.
	- Увімкнено базові security-параметри Grafana (`GF_AUTH_ANONYMOUS_ENABLED=false`, admin credentials через `.env`).
	- Оновлено `victoria-metrics/scrape-config.yml` (self-scrape + node-exporter) з label schema `env/service`.
	- Додано provisioning datasource: `grafana/provisioning/datasources/victoriametrics.yml`.
	- Додано `docs/deployment/monitoring-stack-deploy.md` та каталог `grafana/provisioning/plugins/`.
- **Verification:**
	- `docker compose -f docker-compose.yml config --quiet`
	- `docker compose -f docker-compose.yml up -d`
	- `docker compose -f docker-compose.yml ps` → сервіси `Up`
	- `curl -s http://127.0.0.1:8428/health` → `OK`
	- `curl -s http://127.0.0.1:3000/api/health` → `database: ok`
	- `curl -s http://127.0.0.1:8428/targets` → `victoriametrics` і `node-exporter` у стані `up`
	- `ss -tlnp | grep -E '8428|3000|9100|9104|9187|8081|9114|15692|5001'` → тільки `127.0.0.1`
	- `docker compose -f docker-compose.yml logs --since=2m | grep -Ei "error|fatal|panic"` → нових критичних помилок не виявлено
- **Risks:** Cloudflare Tunnel/Access та CI/CD інтеграція ще не налаштовані в межах цього кроку; перевірка доступності Grafana через SSO лишається відкритою.
- **Rollback:** `git revert <commit>` + `docker compose -f docker-compose.yml up -d`.

## [2026-03-07] — Phase 1 refactor: env-driven compose + rename

- **Context:** Уніфікація конфігурації стека: прибрати хардкод image/ports/paths і перейти на `docker-compose.yml`.
- **Change:**
	- `docker-compose.monitoring.yml` перейменовано в `docker-compose.yml`.
	- У `docker-compose.yml` винесено в `.env`:
	  - образи (`VICTORIAMETRICS_IMAGE`, `GRAFANA_IMAGE`, `NODE_EXPORTER_IMAGE`)
	  - порти та bind IP (`MONITORING_BIND_IP`, `*_HOST_PORT`, `*_INTERNAL_PORT`)
	  - шляхи постійних томів (`VM_DATA_DIR`, `GRAFANA_DATA_DIR`, `GRAFANA_LOGS_DIR`)
	  - мережа (`MONITORING_NETWORK_NAME`)
	- Додано обмеження пам'яті для VictoriaMetrics (`VM_MEMORY_LIMIT`, `VM_MEMORY_SWAP_LIMIT`).
	- Для node-exporter додано `pid: "host"`.
	- Додано явну мережу `monitoring_net` (через env-параметр).
	- `grafana/provisioning/datasources/victoriametrics.yml` переведено на env URL (`VM_DATASOURCE_URL`).
	- `.env.example` доповнено всіма новими змінними.
	- `.gitignore` доповнено `/.data` для локальних persistent volume директорій.
- **Verification:**
	- `docker compose --env-file .env.example -f docker-compose.yml config --quiet`
	- Перевірено відсутність прямого хардкоду image/ports у YAML сервіс-конфігах.
- **Risks:** Якщо локальний `.env` не містить нових змінних, `docker compose` не стартує; перед запуском потрібно синхронізувати `.env` з `.env.example`.
- **Rollback:** `git revert <commit>` + `docker compose -f docker-compose.yml up -d`.

## [2026-03-07] — Phase 1: CD pipeline + Grafana Explore verification

- **Context:** Закриття залишку задач `Phase 1` після базового запуску Core Stack.
- **Change:**
	- Додано workflow `/.github/workflows/deploy-monitoring.yml` для автоматичного деплою monitoring stack через GitHub Actions на `self-hosted` runner.
	- Workflow покриває: `docker compose pull`, `docker compose up -d`, health-check, targets-check, перевірку localhost-only портів.
	- Оновлено `docs/deployment/monitoring-stack-deploy.md` секцією CI/CD з вимогою локального `.env` на runner.
	- Оновлено `docs/ROADMAP.md`: відмічено виконаними пункти про CD pipeline та видимість метрик Node Exporter у Grafana Explore.
- **Verification:**
	- `curl -s -u admin:change_me_before_deploy http://127.0.0.1:3000/api/datasources/uid/victoriametrics`
	- `curl -s -u admin:change_me_before_deploy -H 'Content-Type: application/json' -X POST http://127.0.0.1:3000/api/ds/query -d '{... "expr":"node_uname_info" ...}'` → повертаються series з `job="node-exporter"`.
- **Risks:** Автодеплой у GitHub Actions працює тільки після підключення self-hosted runner і наявності коректного `.env` на runner.
- **Rollback:** `git revert <commit>` + видалення workflow файлу.

## [2026-03-07] — CD strategy update: Tailscale Ephemeral Auth Key

- **Context:** Оновлення стратегії CD: відмова від `self-hosted` execution у GitHub Actions на користь підключення до target host через Tailscale ephemeral auth key.
- **Change:**
	- Переписано `.github/workflows/deploy-monitoring.yml` за еталоном `archive/ci-cd.yml` (CD-only логіка):
	  - `runs-on: ubuntu-latest`
	  - `tailscale/github-action@v4`
	  - deploy через `appleboy/ssh-action@v1.2.5`
	  - валідація deploy secrets + SemVer для tag deploy
	  - remote `docker compose pull && up -d --remove-orphans` + health/targets/ports checks
	- Оновлено `docs/deployment/monitoring-stack-deploy.md` та `docs/ROADMAP.md` під нову модель CD.
- **Verification:**
	- Локально перевірено синтаксис workflow та відсутність compile errors.
	- Логіка deploy кроків узгоджена зі структурою та business flow еталонного `archive/ci-cd.yml`.
- **Risks:** Пайплайн залежить від коректних GitHub secrets і доступності target host через Tailscale/SSH.
- **Rollback:** `git revert <commit>` для workflow і документації.
