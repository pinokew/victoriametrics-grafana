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

2. Ініціалізувати директорії томів згідно `.env` та виставити права:

```bash
./scripts/init-monitoring-volumes.sh
```

3. Згенерувати `victoria-metrics/scrape-config.yml` із шаблону (для private Koha URL):

```bash
./scripts/render-scrape-config.sh
```

4. Запустити стек:

```bash
docker compose up -d
```

5. Перевірити health:

```bash
curl -s http://127.0.0.1:8428/health
curl -s http://127.0.0.1:3000/api/health
```

6. Перевірити targets:

```bash
curl -s http://127.0.0.1:8428/targets | python3 -m json.tool
```

7. Перевірити, що порти не публічні:

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

## Шаблонізація scrape-config (Phase 4)

- `victoria-metrics/scrape-config.tmpl.yml` зберігається в Git без приватних URL.
- `scripts/render-scrape-config.sh` підставляє `KOHA_OPAC_URL` і `KOHA_STAFF_URL` з `.env` у робочий `victoria-metrics/scrape-config.yml`.
- VictoriaMetrics не інтерполює `${VAR}` всередині scrape-config, тому генерація файлу перед запуском є обов'язковою.
- `grafana/provisioning/datasources/victoriametrics.yml`:
  - datasource для VictoriaMetrics через provisioning

## Ручні дії поза цим репозиторієм

### Cloudflare Tunnel для Grafana

Cloudflare Tunnel працює в окремому зовнішньому edge stack. У цьому репозиторії `cloudflared` контейнер не запускається і не повертається в `docker-compose.yml`.

1. У зовнішньому edge stack має бути налаштований Tunnel та Public Hostname:
  - hostname: `${CLOUDFLARE_GRAFANA_HOSTNAME}`
  - service type: `HTTP`
  - service URL: route до Grafana через central Traefik / `proxy-net`

2. Monitoring stack не зберігає tunnel token. Для Grafana потрібен тільки public hostname:

```env
CLOUDFLARE_GRAFANA_HOSTNAME=grafana.example.com
```

3. Для моніторингу зовнішнього tunnel metrics endpoint вказати target у decrypted env:

```env
CLOUDFLARE_TUNNEL_METRICS_TARGET=cf_tunnel_tunnel:2000
CLOUDFLARE_TUNNEL_NAME=grafana
```

Очікування: VictoriaMetrics бачить target `cloudflare-tunnel`, а dashboard `KDI Cloudflare Tunnel Overview` отримує метрики `cloudflared_tunnel_*`.

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

## Backup і перевірка відновлення (Phase 5)

Після стабільного запуску стеку виконай backup VictoriaMetrics volume:

```bash
./scripts/backup-victoriametrics-volume.sh
```

Перевір відновлення на тимчасовому контейнері (smoke test):

```bash
./scripts/test-victoriametrics-restore.sh
```

Повне відновлення з backup (destructive, перезаписує `VM_DATA_DIR`):

```bash
./scripts/restore-victoriametrics-backup.sh --yes
```

Очікування:
- створено архів `vmdata-*.tar.gz` у `VM_BACKUP_DIR`;
- створено checksum-файл `.sha256`;
- restore smoke test повертає `Restore smoke test passed`.
