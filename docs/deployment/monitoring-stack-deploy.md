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
- Налаштувати Cloudflare Tunnel для Grafana
- Налаштувати Cloudflare Access policy (MS Entra ID)

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
