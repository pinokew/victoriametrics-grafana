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
