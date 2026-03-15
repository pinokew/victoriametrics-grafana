# VictoriaMetrics + Grafana — Observability Stack (KDI)

> **Основне джерело правди.** Цей документ описує архітектуру стеку, призначення кожного компонента та директорії, де шукати код і документацію до кожного модуля.

**Стек:** VictoriaMetrics single-node + Grafana + 6 exporters  
**Ціль:** Production observability для KDI (Koha + DSpace + KDV Integrator)  
**Статус:** Phase 5 — Security & Production Readiness Gate ✅

---

## Зміст

1. [Архітектура стеку](#1-архітектура-стеку)
2. [Сервіси та порти](#2-сервіси-та-порти)
3. [Топологія репозиторію](#3-топологія-репозиторію)
4. [Швидкий старт](#4-швидкий-старт)
5. [Конфігурація (.env)](#5-конфігурація-env)
6. [Scrape-конфігурація VictoriaMetrics](#6-scrape-конфігурація-victoriametrics)
7. [Grafana: provisioning](#7-grafana-provisioning)
8. [Alerting](#8-alerting)
9. [Backup / Restore](#9-backup--restore)
10. [CI/CD pipeline](#10-cicd-pipeline)
11. [Безпека](#11-безпека)
12. [Операційні перевірки](#12-операційні-перевірки)
13. [Індекс документації](#13-індекс-документації)
14. [Поточний статус проекту](#14-поточний-статус-проекту)

---

## 1. Архітектура стеку

```
┌─────────────────────────────────────────────────────────────────┐
│  HOST VM (production server)                                    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Docker network: monitoring_net (bridge)                │   │
│  │                                                         │   │
│  │  VictoriaMetrics :8428  ←── scrapes ──────────┐        │   │
│  │         │                                      │        │   │
│  │         ▼                                      │        │   │
│  │  Grafana :3000  ──────── datasource ───────────┘        │   │
│  │         │                                               │   │
│  │         └── proxy-net ───► Central Traefik ──► Cloudflare│   │
│  │                                               (external) │   │
│  │  Node Exporter :9100 (host metrics)     │               │   │
│  │  cAdvisor      :8081 (container metrics)│               │   │
│  │  Blackbox Exp. :9115 (HTTP probes)      ▼               │   │
│  │  MariaDB Exp.  :9104 ─ koha-deploy_kohanet (external)   │   │
│  │  Postgres Exp. :9187 ─ dspace9_dspacenet (external)     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Зовнішні мережі: proxy-net, koha-deploy_kohanet, dspace9_dspacenet │
└─────────────────────────────────────────────────────────────────┘

CI/CD: GitHub Actions ──► Tailscale VPN ──► HOST VM
```

**Принцип доступу:** всі порти прив'язані на `127.0.0.1` (недоступні ззовні).  
Grafana доступна ззовні через центральний Traefik (`proxy-net`) і зовнішній edge-доступ, який керується в repo Traefik.

---

## 2. Сервіси та порти

| Сервіс | Порт (host) | Bind | Призначення |
|--------|-------------|------|-------------|
| `victoriametrics` | `8428` | `127.0.0.1` | TSDB: зберігання метрик, PromQL API, `/targets` |
| `grafana` | `3000` | `127.0.0.1` | Dashboards + Unified Alerting (провізіонується з Git) |
| `node-exporter` | `9100` | `127.0.0.1` | Host-метрики (CPU, RAM, диск, мережа) |
| `cadvisor` | `8081` | `127.0.0.1` | Per-container ресурсні метрики |
| `blackbox-exporter` | `9115` | `127.0.0.1` | HTTP/HTTPS probe-и (Koha OPAC, Staff, DSpace) |
| `mariadb-exporter` | `9104` | `127.0.0.1` | MySQL/MariaDB метрики (Koha DB через `koha-deploy_kohanet`) |
| `postgres-exporter` | `9187` | `127.0.0.1` | PostgreSQL метрики (DSpace DB через `dspace9_dspacenet`) |

> Повна таблиця портів (включно з P1-компонентами): [docs/architecture/ports-map.md](docs/architecture/ports-map.md)

---

## 3. Топологія репозиторію

```
victoriametrics-grafana/
│
├── docker-compose.yml              # Головний runtime: всі сервіси, мережі, volume-маунти
├── .env.example                    # Шаблон змінних оточення (копіювати в .env)
├── .env                            # Секрети і конфіг (НЕ в Git — у .gitignore)
├── .gitignore                      # Виключення: .env, .data/, .backups/
├── .gitleaks-local.json            # Виключення для Gitleaks (CI secret scanning)
│
├── victoria-metrics/               # Конфіг scrape-ing'у для VictoriaMetrics
│   ├── scrape-config.tmpl.yml      # Шаблон scrape-config (Jinja/envsubst)
│   └── scrape-config.yml           # Робочий scrape-config (генерується скриптом)
│
├── grafana/
│   ├── provisioning/               # Grafana config-as-code (монтується в контейнер :ro)
│   │   ├── datasources/
│   │   │   └── victoriametrics.yml # VictoriaMetrics як Prometheus datasource
│   │   ├── dashboards/
│   │   │   └── dashboards.yml      # Вказує Grafana де шукати JSON dashboards
│   │   ├── alerting/
│   │   │   ├── alert-rules.yml     # P0 alert rules: CPU, RAM, диск, контейнери, DB
│   │   │   ├── backup-alerts.yml   # Alert: VictoriaMetricsBackupStale
│   │   │   ├── synthetic-alerts.yml# Alert: SyntheticEmailSmoke (перевірка email delivery)
│   │   │   ├── website-alerts.yml  # Alerts для HTTP probe-ів (Koha, DSpace)
│   │   │   ├── contact-points.yml  # Email-точки доставки сповіщень
│   │   │   └── notification-policies.yml # Маршрутизація: critical → email+Telegram
│   │   └── plugins/
│   │       └── README.md           # Де встановлювати Grafana plugins
│   └── dashboards/                 # JSON-файли дашбордів (завантажуються при старті)
│       ├── host-overview-node-exporter-1860.json  # Node Exporter Full (id:1860)
│       ├── docker-containers-cadvisor-14282.json  # cAdvisor containers (id:14282)
│       ├── mariadb-overview-7362.json             # MariaDB overview (id:7362)
│       ├── postgresql-overview-9628.json          # PostgreSQL overview (id:9628)
│       └── traefik-v3-official-17346.json         # Traefik v3 (id:17346)
│
├── alerting/
│   └── rules/                      # Prometheus-style alert rules (reference catalog)
│       ├── host.yml                # Host-level alerts (CPU, RAM, диск, uptime)
│       ├── containers.yml          # Container alerts (OOM, restart loops)
│       ├── databases.yml           # DB alerts (connections, replication)
│       ├── monitoring.yml          # Self-monitoring: VictoriaMetricsDown
│       ├── traefik.yml             # Traefik-специфічні alerts
│       └── README.md               # Опис catalog та naming convention
│
├── blackbox/
│   └── blackbox.yml                # Конфіг Blackbox Exporter: HTTP probe modules
│
├── scripts/                        # Операційна автоматизація
│   ├── init-monitoring-volumes.sh  # Ініціалізація .data/ директорій перед першим запуском
│   ├── render-scrape-config.sh     # Генерація scrape-config.yml з шаблону + .env
│   ├── backup-victoriametrics-volume.sh   # Бекап VM volume → .backups/vmdata-*.tar.gz
│   ├── restore-victoriametrics-backup.sh  # Destructive restore (потребує --yes)
│   ├── test-victoriametrics-restore.sh    # Smoke-тест restore в ізольованому контейнері
│   └── check-internal-ports-policy.sh     # CI: перевіряє що порти не на 0.0.0.0
│
├── docs/                           # Вся проектна документація
│   ├── ROADMAP.md                  # Фазований план; поточний статус; Go-Live checklist
│   ├── PRD.md                      # Product Requirements Document
│   ├── AGENTS.md                   # Інструкції для AI-агентів (Copilot)
│   ├── NOTES.md                    # Робочі нотатки та quick-ref
│   ├── RELEASE.md                  # Процес релізу та versioning
│   ├── system-architecture-document.md   # SAD: повна системна архітектура
│   ├── tech-stack-infrastructure-overview.md # Огляд стеку та інфраструктури
│   ├── adr/                        # Architecture Decision Records
│   │   ├── ADR-001-victoriametrics-choice.md  # Чому VM, а не Prometheus
│   │   ├── ADR-002-vm-topology.md             # Single-node vs cluster
│   │   └── ADR-003-label-schema.md            # Label taxonomy (env/service/component)
│   ├── architecture/
│   │   ├── monitoring-architecture.md  # Детальна архітектура + data flow
│   │   └── ports-map.md                # Всі порти, bind-адреси, призначення
│   ├── alerting/
│   │   └── alert-rules-catalog.md  # Каталог усіх alert rules; семантика noDataState
│   ├── configuration/
│   │   ├── exporters-config.md     # Конфіг кожного exporter'а; env-змінні
│   │   └── retention-policy.md     # Retention policy VM; backup schedule
│   ├── dashboards/
│   │   ├── dashboard-catalog.md    # Перелік дашбордів; Grafana ID; призначення
│   │   └── how-to-update-dashboards.md  # Процес оновлення JSON через Git
│   ├── deployment/
│   │   └── monitoring-stack-deploy.md  # Step-by-step деплой; prerequisites
│   ├── runbooks/                   # Операційні runbook'и (що робити при алерті)
│   │   ├── container-down.md
│   │   ├── database-connections-high.md
│   │   ├── disk-space-low.md
│   │   ├── high-cpu.md
│   │   ├── high-memory.md
│   │   ├── monitoring-down.md
│   │   ├── vm-backup-restore.md
│   │   └── website-probe.md
│   └── security/
│       ├── monitoring-security-notes.md  # Загальна security baseline
│       └── db-exporter-users.md          # Мінімальні DB-юзери для exporters
│
├── .github/
│   └── workflows/
│       └── deploy-monitoring.yml   # CI/CD: lint → scan → deploy через Tailscale
│
├── archive/                        # Застарілі артефакти (не використовуються)
│
├── CHANGELOG.md                    # Зведений індекс змін (посилання на VOL-файли)
└── CHANGELOGS/
    ├── CHANGELOG_2026_VOL_01.md    # Детальний лог: Phase 0–1
    ├── CHANGELOG_2026_VOL_02.md    # Детальний лог: Phase 2–3
    └── CHANGELOG_2026_VOL_03.md    # Детальний лог: Phase 4–5 (поточний)
```

---

## 4. Швидкий старт

### Передумови

- Docker Engine + Docker Compose v2
- Файл `.env` заповнений на базі `.env.example`
- Зовнішні Docker-мережі існують: `proxy-net`, `koha-deploy_kohanet`, `dspace9_dspacenet`

### Кроки

```bash
# 1. Скопіювати та заповнити секрети
cp .env.example .env
# відредагувати .env: паролі, SMTP, адреси DB, hostname для Grafana ingress

# 2. Ініціалізувати директорії даних (.data/grafana, .data/victoriametrics, тощо)
./scripts/init-monitoring-volumes.sh

# 3. Згенерувати робочий scrape-config із шаблону
./scripts/render-scrape-config.sh

# 4. Запустити стек
docker compose up -d

# 5. Перевірити health
curl -s http://127.0.0.1:8428/health   # {"status":"ok"}
curl -s http://127.0.0.1:3000/api/health
```

> Детальний покроковий деплой: [docs/deployment/monitoring-stack-deploy.md](docs/deployment/monitoring-stack-deploy.md)

---

## 5. Конфігурація (.env)

Весь runtime-конфіг передається через `.env` (не комітиться в Git).  
Шаблон з описом всіх змінних: `.env.example`.

**Ключові групи змінних:**

| Група | Приклад змінних | Призначення |
|-------|----------------|-------------|
| **Networking** | `MONITORING_BIND_IP`, `MONITORING_NETWORK_NAME` | Bind-адреса та ім'я Docker-мережі |
| **Images** | `VICTORIAMETRICS_IMAGE`, `GRAFANA_IMAGE`, … | Версії образів (pin за digest для P0) |
| **VictoriaMetrics** | `VM_RETENTION_PERIOD`, `VM_DATA_DIR` | Retention, шлях до volume |
| **Grafana** | `GRAFANA_ADMIN_PASSWORD`, `GRAFANA_AUTO_ASSIGN_ORG_ROLE` | Адмін-доступ, дефолтна роль |
| **SMTP** | `MS365_SMTP_HOST`, `MS365_ALERT_EMAIL_TO` | Email-alerts через MS365 |
| **Ingress** | `CLOUDFLARE_GRAFANA_HOSTNAME`, `PROXY_NET_NETWORK_NAME` | Ім'я домену Grafana і зовнішня мережа Traefik |
| **DB Exporters** | `MARIADB_EXPORTER_PASSWORD`, `POSTGRES_EXPORTER_DSN` | Credentials для DB |

> Докладний опис кожної змінної: [docs/configuration/exporters-config.md](docs/configuration/exporters-config.md)

---

## 6. Scrape-конфігурація VictoriaMetrics

**Файли:** `victoria-metrics/`

| Файл | Призначення |
|------|-------------|
| `scrape-config.tmpl.yml` | Шаблон (envsubst) — редагувати тут |
| `scrape-config.yml` | Результат генерації — монтується в контейнер VM `:ro` |

**Активні scrape jobs:**

| Job | Ціль | Labels |
|-----|------|--------|
| `victoriametrics` | `victoriametrics:8428` | `service=monitoring` |
| `node-exporter` | `node-exporter:9100` | `service=host` |
| `cadvisor` | `cadvisor:8081` | `service=host` |
| `mariadb-exporter` | `mariadb-exporter:9104` | `service=koha, component=db` |
| `postgres-exporter` | `postgres-exporter:9187` | `service=dspace, component=db` |
| `traefik` | `traefik:8082` | `service=traefik` |
| `blackbox-koha-opac` | `https://biblio.fby.com.ua` | `service=koha, website=opac` |
| `blackbox-koha-staff` | staff-URL | `service=koha, website=staff` |

Всі метрики мають глобальний label `env=prod`.  
Перегенерація конфігу: `./scripts/render-scrape-config.sh`  
Перевірка активних targets: `curl -s http://127.0.0.1:8428/targets`

---

## 7. Grafana: provisioning

**Директорія:** `grafana/provisioning/` — монтується в Grafana як `:ro`.  
Вся конфігурація Grafana живе в Git. Ручні зміни через UI не зберігаються після рестарту.

### Datasources (`provisioning/datasources/`)
- `victoriametrics.yml` — реєструє VictoriaMetrics як Prometheus-сумісний datasource з UID `victoriametrics`; читає URL із `VM_DATASOURCE_URL` (env)

### Dashboards (`provisioning/dashboards/` + `grafana/dashboards/`)
- `dashboards.yml` — вказує Grafana де шукати JSON-файли (`/var/lib/grafana/dashboards`)
- JSON-файли в `grafana/dashboards/` монтуються як `:ro`; щоб оновити дашборд — замінити JSON в Git

> Процес оновлення дашбордів: [docs/dashboards/how-to-update-dashboards.md](docs/dashboards/how-to-update-dashboards.md)  
> Каталог дашбордів: [docs/dashboards/dashboard-catalog.md](docs/dashboards/dashboard-catalog.md)

### Alerting (`provisioning/alerting/`)

| Файл | Вміст |
|------|-------|
| `alert-rules.yml` | P0 alert rules: CPU, RAM, диск, контейнери, DB, VictoriaMetricsDown |
| `backup-alerts.yml` | Alert `VictoriaMetricsBackupStale` (якщо backup > 26 год) |
| `synthetic-alerts.yml` | Alert `SyntheticEmailSmoke` (перевірка email delivery) |
| `website-alerts.yml` | HTTP probe alerts для Koha та DSpace |
| `contact-points.yml` | Email contact points: `critical-email-telegram`, `warning-email` |
| `notification-policies.yml` | Маршрутизація: `severity=critical` → `critical-email-telegram`; `warning` → `warning-email` |

---

## 8. Alerting

### Catalog правил

Визначені в `alerting/rules/` (Prometheus формат, reference), провізіоновані через `grafana/provisioning/alerting/`.

| Файл rules | Alerts |
|-----------|--------|
| `host.yml` | HostHighCPU, HostHighMemory, HostDiskSpaceLow, HostDiskInodesLow |
| `containers.yml` | ContainerDown, ContainerHighCPU, ContainerHighMemory |
| `databases.yml` | MariaDBDown, PostgreSQLDown, MariaDBConnectionsHigh, PGConnectionsHigh |
| `monitoring.yml` | VictoriaMetricsDown (critical, `for=2m`) |
| `traefik.yml` | TraefikDown, TraefikHighErrorRate |

### Семантика alert rules

- `noDataState: NoData` — відсутність даних ≠ алерт (не генерує false-positive)
- `execErrState: Alerting` — якщо datasource недоступний → алерт спрацьовує
- `for: 2m` — витримка перед переходом у `Alerting` (фільтрує флуктуації)
- `severity=critical` → `critical-email-telegram` contact point  
- `severity=warning` → `warning-email` contact point

> Повний каталог з описом кожного правила: [docs/alerting/alert-rules-catalog.md](docs/alerting/alert-rules-catalog.md)  
> Runbooks (що робити при алерті): [docs/runbooks/](docs/runbooks/)

---

## 9. Backup / Restore

VictoriaMetrics volume бекапиться в `.backups/vmdata-<timestamp>.tar.gz`.

```bash
# Виконати бекап вручну
./scripts/backup-victoriametrics-volume.sh

# Smoke-тест відновлення (безпечний, ізольований контейнер)
./scripts/test-victoriametrics-restore.sh

# Повне відновлення (DESTRUCTIVE — знищує поточні дані)
./scripts/restore-victoriametrics-backup.sh --yes
```

**Скрипти:**

| Скрипт | Дія | Небезпечність |
|--------|-----|---------------|
| `backup-victoriametrics-volume.sh` | Зупиняє VM, tar-архівує volume, стартує VM | Короткий downtime (~30 сек) |
| `test-victoriametrics-restore.sh` | Розпаковує архів у тимчасовий контейнер, перевіряє `/health` | Безпечно |
| `restore-victoriametrics-backup.sh` | Зупиняє VM, видаляє поточний volume, розпаковує архів | **DESTRUCTIVE** |

> Retention policy та schedule: [docs/configuration/retention-policy.md](docs/configuration/retention-policy.md)  
> Runbook відновлення: [docs/runbooks/vm-backup-restore.md](docs/runbooks/vm-backup-restore.md)

---

## 10. CI/CD pipeline

**Файл:** `.github/workflows/deploy-monitoring.yml`

**Кроки pipeline:**

1. **ShellCheck** — статичний аналіз усіх bash-скриптів у `scripts/`
2. **Gitleaks** — сканування на витік секретів (конфіг: `.gitleaks-local.json`)
3. **Trivy** — сканування Docker-образів на вразливості
4. **Port Policy Check** — `scripts/check-internal-ports-policy.sh` перевіряє що `docker-compose.yml` не використовує `0.0.0.0` bind
5. **Deploy** — `docker compose pull && docker compose up -d` через Tailscale VPN

**Доступ до сервера з CI:** GitHub Actions підключається через Tailscale ephemeral key (не відкриває SSH-порт публічно).

---

## 11. Безпека

| Принцип | Реалізація |
|---------|-----------|
| Network isolation | Всі порти bind на `127.0.0.1`; зовні не доступні |
| Controlled external access | Grafana публікується через central Traefik (`proxy-net`) з edge-доступом на стороні Traefik stack |
| No anonymous access | `GF_AUTH_ANONYMOUS_ENABLED=false` в Grafana |
| Secrets management | Всі credentials у `.env` (у `.gitignore`, не в Git) |
| CI secret scanning | Gitleaks у кожному PR/push |
| Least privilege DB users | Окремі read-only юзери для MariaDB та PostgreSQL exporters |
| Image pinning | Критичні образи закріплені за digest (`sha256:…`) |
| Внутрішній CI-доступ | Tailscale VPN (не відкритий SSH-порт) |

> Детальний security baseline: [docs/security/monitoring-security-notes.md](docs/security/monitoring-security-notes.md)  
> Мінімальні DB-юзери: [docs/security/db-exporter-users.md](docs/security/db-exporter-users.md)

---

## 12. Операційні перевірки

```bash
# Статус всіх контейнерів
docker compose ps

# Health VictoriaMetrics
curl -s http://127.0.0.1:8428/health

# Активні scrape targets
curl -s http://127.0.0.1:8428/targets | python3 -m json.tool | grep '"health"'

# Health Grafana
curl -s http://127.0.0.1:3000/api/health

# Перевірка що всі порти тільки на 127.0.0.1
ss -tlnp | grep -E '8428|3000|9100|9104|9187|8081|9115'

# Перегляд логів конкретного сервісу
docker compose logs --tail=50 victoriametrics
docker compose logs --tail=50 grafana

# Ручна перевірка port-policy (як у CI)
./scripts/check-internal-ports-policy.sh
```

---

## 13. Індекс документації

### Архітектура та дизайн

| Документ | Зміст |
|----------|-------|
| [docs/system-architecture-document.md](docs/system-architecture-document.md) | **SAD** — повне системне архітектурне рішення |
| [docs/tech-stack-infrastructure-overview.md](docs/tech-stack-infrastructure-overview.md) | Огляд стеку та інфраструктури |
| [docs/architecture/monitoring-architecture.md](docs/architecture/monitoring-architecture.md) | Детальна архітектура та data flow |
| [docs/architecture/ports-map.md](docs/architecture/ports-map.md) | Всі порти та bind-адреси |
| [docs/adr/ADR-001-victoriametrics-choice.md](docs/adr/ADR-001-victoriametrics-choice.md) | Чому VictoriaMetrics, а не Prometheus |
| [docs/adr/ADR-002-vm-topology.md](docs/adr/ADR-002-vm-topology.md) | Single-node vs cluster рішення |
| [docs/adr/ADR-003-label-schema.md](docs/adr/ADR-003-label-schema.md) | Label taxonomy (env/service/component) |

### Конфігурація та деплой

| Документ | Зміст |
|----------|-------|
| [docs/deployment/monitoring-stack-deploy.md](docs/deployment/monitoring-stack-deploy.md) | Покроковий деплой з нуля |
| [docs/configuration/exporters-config.md](docs/configuration/exporters-config.md) | Конфіг кожного exporter'а; env-змінні |
| [docs/configuration/retention-policy.md](docs/configuration/retention-policy.md) | Retention 90d; backup schedule |

### Alerting та дашборди

| Документ | Зміст |
|----------|-------|
| [docs/alerting/alert-rules-catalog.md](docs/alerting/alert-rules-catalog.md) | Каталог усіх alert rules; семантика |
| [docs/dashboards/dashboard-catalog.md](docs/dashboards/dashboard-catalog.md) | Перелік дашбордів; Grafana IDs |
| [docs/dashboards/how-to-update-dashboards.md](docs/dashboards/how-to-update-dashboards.md) | Як оновлювати дашборди через Git |

### Безпека

| Документ | Зміст |
|----------|-------|
| [docs/security/monitoring-security-notes.md](docs/security/monitoring-security-notes.md) | Security baseline стеку |
| [docs/security/db-exporter-users.md](docs/security/db-exporter-users.md) | Мінімальні DB-юзери для exporters |

### Операційні runbooks

| Runbook | Тригер |
|---------|--------|
| [docs/runbooks/monitoring-down.md](docs/runbooks/monitoring-down.md) | VictoriaMetricsDown alert |
| [docs/runbooks/high-cpu.md](docs/runbooks/high-cpu.md) | HostHighCPU alert |
| [docs/runbooks/high-memory.md](docs/runbooks/high-memory.md) | HostHighMemory alert |
| [docs/runbooks/disk-space-low.md](docs/runbooks/disk-space-low.md) | HostDiskSpaceLow alert |
| [docs/runbooks/container-down.md](docs/runbooks/container-down.md) | ContainerDown alert |
| [docs/runbooks/database-connections-high.md](docs/runbooks/database-connections-high.md) | DB connections alert |
| [docs/runbooks/vm-backup-restore.md](docs/runbooks/vm-backup-restore.md) | VictoriaMetricsBackupStale / DR |
| [docs/runbooks/website-probe.md](docs/runbooks/website-probe.md) | Blackbox probe failure |

### Планування та changelog

| Документ | Зміст |
|----------|-------|
| [docs/ROADMAP.md](docs/ROADMAP.md) | Фазований план; поточний статус; Go-Live checklist |
| [CHANGELOG.md](CHANGELOG.md) | Зведений індекс змін |
| [CHANGELOGS/CHANGELOG_2026_VOL_03.md](CHANGELOGS/CHANGELOG_2026_VOL_03.md) | Детальний лог Phase 4–5 (поточний) |

---

## 14. Поточний статус проекту

| Фаза | Назва | Статус |
|------|-------|--------|
| Phase 0 | Pre-Flight (ADR, репо, .env) | ✅ Завершено |
| Phase 1 | Core Stack (VM + Grafana + Cloudflare) | ✅ Завершено |
| Phase 2 | Exporters + Dashboards | ✅ Завершено |
| Phase 3 | Alerting (P0 rules + email delivery) | ✅ Завершено |
| Phase 4 | Backup/Restore + Synthetic monitoring | ✅ Завершено |
| Phase 5 | Security & Production Readiness Gate | ✅ Завершено |

**Phase 5 закриті задачі:**
- ✅ `VictoriaMetricsDown` — критичний alert перевірено outage/recovery тестом
- ✅ ShellCheck CI errors виправлено (SC2034, SC2012, SC2329)
- ✅ Go-Live checklist пройдено (Security / Functionality / Config-as-Code / Reliability)

**Поза scope (заплановано на майбутнє):**
- Elasticsearch Exporter (Koha search)
- RabbitMQ Prometheus endpoint (KDV Integrator)
- KDV Integrator `/metrics` endpoint
- Loki / distributed tracing
