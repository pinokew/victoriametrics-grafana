# Deployment: Monitoring Stack (Phase 1)

## Мета
Підняти базовий monitoring stack (VictoriaMetrics + Grafana + Node Exporter) у безпечному режимі, коли порти доступні тільки на `127.0.0.1`.

## Передумови
- Docker та Docker Compose встановлені
- У корені репозиторію є заповнений `.env`
- Значення `GRAFANA_ADMIN_PASSWORD` змінене з дефолтного
- `.env` містить всі змінні зі списку `.env.example` (image, ports, шляхи томів, memory limits)

## Кроки запуску
1. Перевірити поточний стан:

```bash
git status
docker compose ps
```

2. Запустити стек:

```bash
docker compose up -d
```

3. Перевірити health:

```bash
curl -s http://127.0.0.1:8428/health
curl -s http://127.0.0.1:3000/api/health
```

4. Перевірити targets:

```bash
curl -s http://127.0.0.1:8428/targets | python3 -m json.tool
```

5. Перевірити, що порти не публічні:

```bash
ss -tlnp | grep -E '8428|3000|9100'
```

Очікування: адреси прослуховування мають бути тільки `127.0.0.1:*`.

## Що покриває Phase 1 у репозиторії
- `docker-compose.yml`:
  - `victoriametrics` з retention через `VM_RETENTION_PERIOD`
  - `grafana` з `GF_AUTH_ANONYMOUS_ENABLED=false`
  - `node-exporter` як базовий host exporter
- `victoria-metrics/scrape-config.yml`:
  - `victoriametrics` self-scrape
  - `node-exporter` scrape
- `grafana/provisioning/datasources/victoriametrics.yml`:
  - datasource для VictoriaMetrics через provisioning

## Ручні дії поза цим репозиторієм

### Cloudflare Tunnel для Grafana

У репозиторії вже підготовлено сервіс `cloudflared` (profile `phase1-edge`) у `docker-compose.yml`.

1. У Cloudflare Zero Trust створити Tunnel та Public Hostname:
  - hostname: `${CLOUDFLARE_GRAFANA_HOSTNAME}`
  - service type: `HTTP`
  - service URL: `http://grafana:3000`
2. Скопіювати tunnel token у локальний `.env`:

```env
CLOUDFLARE_TUNNEL_TOKEN=<token_from_cloudflare>
```

3. Запустити tunnel-контейнер:

```bash
docker compose --profile phase1-edge up -d cloudflared
docker compose logs cloudflared --tail=100
```

Очікування в логах: є активне з'єднання з Cloudflare edge (рядки на кшталт `Registered tunnel connection`).

### Cloudflare Access policy (MS Entra ID SSO)

Зміна Access policy виконується у Cloudflare Zero Trust (не в цьому репозиторії).

Мінімальна policy для Phase 1:
- Application type: `Self-hosted`
- Domain: `${CLOUDFLARE_GRAFANA_HOSTNAME}`
- Identity provider: `Microsoft Entra ID`
- Rule: `Allow` тільки для потрібної групи (наприклад, `ops-team`)
- Rule: `Block` для всіх інших

### Перевірка DoD для Phase 1

1. Grafana доступна тільки через Tunnel + Access auth:

```bash
# локально Grafana лишається на 127.0.0.1, зовнішній доступ тільки через Cloudflare hostname
curl -I https://${CLOUDFLARE_GRAFANA_HOSTNAME}
```

Очікування: повертається сторінка/редирект Cloudflare Access login (до успішної SSO-автентифікації доступ до Grafana UI відсутній).

2. VictoriaMetrics не публічний:

```bash
EXTERNAL_IP=$(hostname -I | awk '{print $1}')
curl --connect-timeout 3 http://${EXTERNAL_IP}:8428/health
```

Очікування: `timeout` або `Failed to connect`.

## CI/CD деплой (GitHub Actions)

У репозиторій додано workflow: `.github/workflows/deploy-monitoring.yml`.

Що робить workflow:
- запускається вручну (`workflow_dispatch`) або при push у `main` для monitoring-файлів;
- використовує `ubuntu-latest` (GitHub-hosted runner);
- встановлює з'єднання через Tailscale;
- піднімає стек через `docker compose up -d`;
- перевіряє health endpoint-и, targets і localhost-only binding портів.

Що потрібно налаштувати у GitHub:
- додати secrets: `SERVER_HOST`, `SERVER_USER`, `SERVER_SSH_KEY`, `DEPLOY_PROJECT_DIR`, `TAILSCALE_EPHEMERAL_AUTH_KEY`;
- переконатися, що `DEPLOY_PROJECT_DIR` на цільовому сервері містить робочий клон репозиторію і коректний `.env`.

Підключення до сервера відбувається через Tailscale Auth Key (ephemeral) + SSH.

Ці кроки залежать від зовнішньої інфраструктури, тому виконуються окремо.
