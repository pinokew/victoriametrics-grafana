# Exporters Configuration (Phase 2)

## Мета
Описати конфігурацію P0 exporters для monitoring stack.

## P0 Exporters

### cAdvisor
- Сервіс: `cadvisor`
- Порт: внутрішній `:${CADVISOR_INTERNAL_PORT}` (без публікації на host)
- Метрики: `http://cadvisor:${CADVISOR_INTERNAL_PORT}/metrics`
- Безпека: тільки `:ro` маунти хоста

### MariaDB Exporter
- Сервіс: `mariadb-exporter`
- Порт: `127.0.0.1:${MARIADB_EXPORTER_HOST_PORT}`
- Метрики: `http://mariadb-exporter:${MARIADB_EXPORTER_INTERNAL_PORT}/metrics`
- Підключення:
	- `MARIADB_EXPORTER_TARGET`
	- `MARIADB_EXPORTER_USER`
	- `MARIADB_EXPORTER_PASSWORD`
- Для Docker Swarm використовуй DNS-ім'я сервісу/alias у мережі Koha (наприклад `db:3306`), а не container/task ім'я на кшталт `koha-deploy-db-1:3306`.
- Мережі: `monitoring_net` + `${KOHANET_NETWORK_NAME}`
- Профіль: `phase2-db`

### PostgreSQL Exporter
- Сервіс: `postgres-exporter`
- Порт: `127.0.0.1:${POSTGRES_EXPORTER_HOST_PORT}`
- Метрики: `http://postgres-exporter:${POSTGRES_EXPORTER_INTERNAL_PORT}/metrics`
- DSN: `POSTGRES_EXPORTER_DSN`
- Мережі: `monitoring_net` + `${DSPACENET_NETWORK_NAME}`
- Профіль: `phase2-db`

### Traefik Metrics
- Scrape job: `traefik`
- Target (у `scrape-config.yml`): `traefik:8082`
- Передумова: у Traefik має бути ввімкнений Prometheus metrics endpoint.
- Для job `traefik` увімкнено `honor_labels: true`.
- У labels для цього job залишаємо тільки `env: prod` (без статичного `service`).
- Причина: Traefik сам віддає label `service` (`dspace-api@docker`, `dspace-ui@docker` тощо). Якщо перезаписати його статичним `service: traefik`, панелі `KDI Traefik v3 Overview` будуть порожні або некоректні.

### Cloudflare Tunnel Metrics
- Scrape job: `cloudflare-tunnel`
- Target задається через `CLOUDFLARE_TUNNEL_METRICS_TARGET` у форматі `host:port` без `http://` або `https://`.
- Tunnel name задається через `CLOUDFLARE_TUNNEL_NAME` і потрапляє в label `tunnel`.
- Очікувана модель: `cloudflared` працює в зовнішньому edge stack, а monitoring stack дістається до його metrics endpoint через спільну Docker network або інший внутрішній маршрут.
- У цей репозиторій `cloudflared` контейнер не повертаємо.
- Labels:
	- `env: prod`
	- `service: cloudflare`
	- `component: tunnel`

### Blackbox Exporter (Phase 4)
- Сервіс: `blackbox-exporter`
- Порт: внутрішній `:9115` (без публікації на host)
- Конфіг: `blackbox/blackbox.yml`
- Модулі:
	- `http_2xx` — перевірка доступності (успіх тільки для HTTP 2xx)
	- `http_tls` — перевірка HTTPS/TLS
- Scrape jobs у `victoria-metrics/scrape-config.yml`:
	- `blackbox-koha-opac`
	- `blackbox-koha-staff`
	- `blackbox-matomo`
	- `blackbox-dspace-ui`
	- `blackbox-dspace-api`
- Env-змінні для render:
	- `KOHA_OPAC_URL`
	- `KOHA_STAFF_URL`
	- `MATOMO_URL`
	- `DSPACE_UI_URL`
	- `DSPACE_API_URL`
	- `CLOUDFLARE_TUNNEL_METRICS_TARGET`
	- `CLOUDFLARE_TUNNEL_NAME`

## Matomo DB Size Metric (Phase 6)
- Скрипт: `scripts/collect-matomo-db-size.sh`
- Джерело: `information_schema.tables` у контейнері `matomo-db`
- Механізм експорту: `node-exporter` textfile collector
- Prometheus-метрики:
	- `kdi_matomo_database_size_bytes`
	- `kdi_matomo_database_size_last_collect_timestamp_seconds`
	- `kdi_matomo_database_size_last_status`
- Labels у textfile:
	- `env="prod"`
	- `service="matomo"`
	- `component="db"`

### Ручний запуск
```bash
./scripts/collect-matomo-db-size.sh
```

### Cron (щоденний приклад)
```cron
15 2 * * * cd /opt/victoriametrics-grafana && ./scripts/collect-matomo-db-size.sh >> /var/log/matomo-db-size.log 2>&1
```

### Alert threshold
- `MatomoDatabaseSizeHigh` → warning, якщо `kdi_matomo_database_size_bytes > 5_000_000_000`

## Matomo Archiving Freshness Metric (Phase 6)
- Скрипт: `scripts/collect-matomo-archiving-metric.sh`
- Джерело: `docker logs --timestamps matomo-cron`
- Success marker: рядок `Done archiving!`
- Механізм експорту: `node-exporter` textfile collector
- Метрики:
	- `matomo_archiving_last_success_timestamp`
	- `matomo_archiving_last_collect_timestamp`
	- `matomo_archiving_last_status`

### Ручний запуск
```bash
./scripts/collect-matomo-archiving-metric.sh
```

### Cron (щогодинний приклад)
```cron
5 * * * * cd /opt/victoriametrics-grafana && ./scripts/collect-matomo-archiving-metric.sh >> /var/log/matomo-archiving-metric.log 2>&1
```

### Alert threshold
- `MatomoArchivingStale` → critical, якщо `time() - matomo_archiving_last_success_timestamp > 7200`

## Matomo Backup Freshness Metric (Phase 6)
- Джерело: `Matomo-analytics/scripts/backup.sh`
- Механізм експорту: `node-exporter` textfile collector
- Метрики:
	- `matomo_backup_last_run_timestamp`
	- `matomo_backup_last_success_timestamp`
	- `matomo_backup_last_status`

### Ручний запуск
```bash
cd /home/pinokew/Matomo-analytics && ./scripts/backup.sh --dry-run
```

### Cron (щоденний приклад)
```cron
30 2 * * * cd /home/pinokew/Matomo-analytics && ./scripts/backup.sh >> /var/log/matomo-backup.log 2>&1
```

### Alert threshold
- `MatomoBackupStale` → critical, якщо `time() - matomo_backup_last_success_timestamp > 93600` (26 годин)

## Matomo Restore Smoke Metric (Phase 6)
- Скрипт: `Matomo-analytics/scripts/test-restore.sh`
- Механізм експорту: `node-exporter` textfile collector
- Метрики:
	- `matomo_restore_smoke_last_run_timestamp`
	- `matomo_restore_smoke_last_success_timestamp`
	- `matomo_restore_smoke_last_status`

### Ручний запуск
```bash
cd /home/pinokew/Matomo-analytics && ./scripts/test-restore.sh --dry-run
```

### Cron (weekly приклад)
```cron
30 3 * * 1 cd /home/pinokew/Matomo-analytics && ./scripts/test-restore.sh >> /var/log/matomo-restore-smoke.log 2>&1
```

### Alert threshold
- `MatomoRestoreSmokeStale` → warning, якщо `time() - matomo_restore_smoke_last_success_timestamp > 691200` (8 діб)

## Команди запуску

1. Базовий стек + cAdvisor:

```bash
docker compose up -d
```

2. Додатково DB exporters:

```bash
docker compose --profile phase2-db up -d
```

3. Перевірка targets:

```bash
curl -s http://127.0.0.1:8428/targets | python3 -m json.tool
```

## Типові причини DOWN target
- Відсутня зовнішня мережа `${KOHANET_NETWORK_NAME}` або `${DSPACENET_NETWORK_NAME}`
- Неправильні credentials/target для exporter або користувач не має read-only прав
- Traefik metrics endpoint не ввімкнений або недоступний з `monitoring_net`
