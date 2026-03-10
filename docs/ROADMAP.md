# Roadmap: Deep Observability for KDI
> **Stack:** VictoriaMetrics + Grafana | **v2.0** | 2026-03-07

---

## 1. Executive Summary

Будуємо production-ready систему моніторингу для KDI (Koha + DSpace + KDV Integrator) на базі VictoriaMetrics + Grafana.

**Production minimum:**
- VictoriaMetrics single-node — центральне зберігання метрик
- 6 exporters для критичних компонентів
- 5 must-have Grafana dashboards
- ≤15 critical alert rules → MS365 Email
- Все — у Git, без публічної експозиції

**Поза scope зараз:** Loki/ELK, distributed tracing, VuFind (статус не визначено), Redis/RabbitMQ для Integrator task persistence.

---

## 2. Priority Matrix

| Пріоритет | Визначення |
|-----------|-----------|
| **P0** | Блокер для production |
| **P1** | Зробити одразу після старту |
| **P2** | Відкласти на post-prod |

---

## 3. Production Architecture

```
HOST VM
├── VictoriaMetrics  127.0.0.1:8428  (internal only)
├── Grafana          127.0.0.1:3000  → Cloudflare Tunnel → MS Entra Auth
├── Node Exporter    127.0.0.1:9100
├── cAdvisor         127.0.0.1:8081
├── MariaDB Exporter 127.0.0.1:9104  (kohanet)
├── PG Exporter      127.0.0.1:9187  (dspacenet)
├── ES Exporter      127.0.0.1:9114  (kohanet)
├── RabbitMQ         127.0.0.1:15692 (built-in, kohanet)
└── KDV /metrics     127.0.0.1:5001  (internal only)

Traefik: вбудований /metrics endpoint (internal)
CI/CD: Tailscale VPN → GitHub Actions
Secrets: .env (never in Git)
```

---

## 4. Phased Roadmap

---

### ✅ Phase 0 — Pre-Flight
> **~1–2 дні | P0**

**Мета:** Зафіксувати рішення та підготувати репо до деплою.

**Задачі:**
- [x] Створити структуру репозиторію для monitoring stack у Git (compose, scrape-config, grafana provisioning, alerting, exporters, docs)
- [x] Написати ADR-001 (чому VictoriaMetrics), ADR-002 (single-node), ADR-003 (label schema)
- [x] Визначити label convention: `env=prod`, `service=koha|dspace|integrator`, `component=db|search|cache|broker`
- [x] Перевірити вільне місце на диску (потрібно ≥20 GB для VM volume)
- [x] Заповнити `.env.example` зі всіма необхідними змінними

**DoD:** ADRs написані, структура репо готова, label schema зафіксована, `.env.example` є.

**Артефакти:** структура в корені репо (`docker-compose.yml`, `victoria-metrics/`, `grafana/`, `alerting/`, `exporters/`), `docs/adr/ADR-001..003.md`, `docs/architecture/ports-map.md`

---

### ✅ Phase 1 — Core Stack Deployment
> **~2–3 дні | P0**

**Мета:** VictoriaMetrics + Grafana запущені, захищені та інтегровані у CD pipeline.

**Задачі:**
- [x] `docker-compose.yml` з VictoriaMetrics та Grafana (порти тільки `127.0.0.1:PORT`)
- [x] Retention = 90 днів, VM volume ≥20 GB
- [x] Grafana: datasource VictoriaMetrics через provisioning YAML
- [x] Grafana: `GF_AUTH_ANONYMOUS_ENABLED=false`, admin пароль з `.env`
- [x] Cloudflare Tunnel для Grafana + Cloudflare Access policy (MS Entra ID SSO) 
- [x] Базовий scrape-config: VictoriaMetrics self + Node Exporter
- [x] Додати деплой monitoring stack до існуючого CD pipeline (GitHub Actions + Tailscale Ephemeral Auth Key)

**DoD:**
- [x] `/health` VictoriaMetrics → 200
- [ ] Grafana доступна тільки через Cloudflare Tunnel з аутентифікацією 
- [x] `curl EXTERNAL_IP:8428` → timeout (не публічний)
- [x] Node Exporter метрики видно в Grafana Explore
- [x] CD pipeline деплоїть stack автоматично (за наявності deploy secrets і Tailscale доступу)

**Артефакти:** `docker-compose.yml`, `scrape-config.yml` (базовий), `grafana/provisioning/datasources/`, `docs/deployment/monitoring-stack-deploy.md`

---

### ✅ Phase 2 — Exporters
> **~3–5 днів | P0 (DB, cAdvisor, Traefik) / P1 (ES, RabbitMQ, KDV)**

**Мета:** Зібрати метрики з усіх критичних KDI-компонентів.

**Exporters (P0):**

| Exporter | Image | Мережа | Нотатка |
|----------|-------|--------|---------|
| cAdvisor | `gcr.io/cadvisor/cadvisor:v0.55.x` | monitoring | `:ro` маунти хоста |
| MariaDB Exporter | `prom/mysqld-exporter:v0.15.x` | monitoring + kohanet | Read-only user: `PROCESS, SELECT, REPLICATION CLIENT` |
| PG Exporter | `prometheuscommunity/postgres-exporter:v0.15.x` | monitoring + dspacenet | Read-only user: `SELECT ON pg_stat_*` |
| Traefik metrics | вбудований | internal | Додати до traefik config: `metrics.prometheus: true` |

**Exporters (P1):**

| Exporter | Нотатка |
|----------|---------|
| ES Exporter `v1.7.x` | Підключити до kohanet |
| RabbitMQ built-in | `rabbitmq-plugins enable rabbitmq_prometheus` → `:15692` |
| KDV Integrator custom | Додати `prometheus_client` до Flask, endpoint `/metrics` тільки на internal port |

**Задачі:**
- [x] Для кожного DB exporter — створити dedicated read-only user (не app credentials)
- [x] Перевірити, що жоден exporter порт не доступний публічно
- [x] Оновити `scrape-config.yml` з усіма targets та labels
- [x] Перевірити `http://127.0.0.1:8428/targets` — всі P0 targets `UP`

**DoD:** Всі P0 targets `UP`, метрики MariaDB/PostgreSQL/cAdvisor/Traefik видні в Grafana, жоден порт не публічний.

**Артефакти:** `exporters/README.md`, `scrape-config.yml` (повний), `docs/configuration/exporters-config.md`, `docs/security/db-exporter-users.md`

---

### ✅ Phase 3 — Dashboards
> **~3–4 дні | P0**

**Мета:** 5 must-have dashboards у Grafana через Git provisioning.

**Правило:** Тільки provisioning через файли, ніякого ручного редагування в UI. Зміна dashboard = коміт у Git.

**Must-have dashboards (P0):**

| Dashboard | Базується на | Ключові панелі |
|-----------|-------------|----------------|
| Host Overview | Node Exporter Full (ID: 1860) | CPU %, RAM %, Disk free %, Network I/O, Load avg |
| Docker Containers | cAdvisor dashboard | CPU/RAM per container, restarts |
| MariaDB | MySQL Overview (ID: 7362) | Connections %, QPS, InnoDB cache hit, slow queries |
| PostgreSQL | PG Dashboard (ID: 9628) | Connections %, cache hit ratio, locks, DB size |
| Traefik v3 | Traefik official | Request rate, 5xx rate, p95 latency |

**P1 dashboards (після Phase 2 P1):** Elasticsearch, RabbitMQ, KDV Integrator, Monitoring Self.

**Задачі:**
- [x] Завантажити базові dashboards з Grafana.com, адаптувати labels під KDI schema
- [x] Зберегти як JSON у `grafana/dashboards/`
- [x] Налаштувати `grafana/provisioning/dashboards/dashboards.yml`
- [x] Після `docker compose restart grafana` — dashboards автоматично присутні

**DoD:** Всі 5 dashboards provisioned через файли, дані відображаються, JSON у Git.

**Артефакти:** `grafana/dashboards/*.json`, `docs/dashboards/dashboard-catalog.md`, `docs/dashboards/how-to-update-dashboards.md`

---

### ✅ Phase 4 — Critical Alerting
> **~2–3 дні | P0**

**Мета:** Critical alerts активні, протестовані, доставка підтверджена.

**Stack:** Grafana Alerting (вбудований) — не потрібен окремий Alertmanager.

**Routing:**
- `severity=critical` → MS365 Email 
- `severity=warning` → MS365 Email (батч)

**Alert rules (P0):**

| Alert | Вираз (спрощено) | Severity |
|-------|-----------------|----------|
| HostHighCPU | CPU > 90% for 5m | critical |
| HostHighMemory | RAM > 95% for 5m | critical |
| HostDiskLow | Disk free < 10% for 5m | critical |
| HostDiskWarning | Disk free < 20% for 5m | warning |
| ContainerDown | `absent(container_last_seen[2m])` для key containers | critical |
| ContainerHighRestarts | >3 restarts/h | warning |
| MariaDBDown | `absent(mysql_up[2m])` | critical |
| MariaDBConnectionsHigh | connections/max > 90% | critical |
| PostgreSQLDown | `absent(pg_up[2m])` | critical |
| PostgreSQLConnectionsHigh | backends/max_connections > 90% | critical |
| TraefikHighErrorRate | 5xx/total > 5% for 5m | critical |
| TraefikHighLatency | p95 latency > 5s | warning |
| VictoriaMetricsDown | `absent(up{job="victoriametrics"}[2m])` | critical |
| AnyTargetDown | `up == 0` | warning |

**P1 alerts:** ElasticsearchClusterRed, RabbitMQQueueDepthHigh, KDVIntegratorHighErrorRate.

**Задачі:**
- [x] Написати YAML alert rules для всіх P0 alerts
- [x] Налаштувати contact points через Grafana provisioning YAML (не вручну в UI)
- [x] Налаштувати inhibition: якщо host down → не флудити database/container alerts (реалізовано через guard в expr для container/db alerts)
- [x] Кожен alert має annotation `runbook` з посиланням на `docs/runbooks/`
- [x] Протестувати: штучний тригер + підтвердження отримання на email

**DoD:** Всі P0 rules активні, тестовий alert отримано, rules у Git, inhibition налаштовано.

**Артефакти:** `alerting/rules/*.yml`, `grafana/provisioning/alerting/`, `docs/alerting/alert-rules-catalog.md`, `docs/runbooks/` (по одному на кожен critical alert)

---

### Phase 5 — Security & Production Readiness Gate
> **~1–2 дні | P0**

**Мета:** Фінальний security check та підтвердження production readiness.

**Задачі:**
- [ ] Додати monitoring compose до CI: Hadolint, Trivy scan, `check-internal-ports-policy.sh`
- [ ] Gitleaks scan — no secrets
- [ ] Grafana RBAC: admin для ops-team, viewer для stakeholders
- [ ] Налаштувати backup VictoriaMetrics volume (vmbackup або cron snapshot), протестувати відновлення
- [ ] Перевірити "observability of observability": alert `VictoriaMetricsDown` — критичний і працює
- [ ] Пройти Go-Live Checklist (Section 7)

**DoD:** Go-Live Checklist пройдено повністю, Trivy без CRITICAL, backup протестований.

**Артефакти:** `docs/security/monitoring-security-notes.md`, `docs/deployment/go-live-checklist.md`

---

## 5. Must-Have Metrics (критичні vs бажані)

| Метрика | P0 | Threshold warning/critical |
|---------|----|-----------------------------|
| CPU utilization | ✅ | >75% / >90% |
| RAM utilization | ✅ | >80% / >95% |
| Disk free (assetstore!) | ✅ | <20% / <10% |
| Container restarts | ✅ | >2/h / >5/h |
| MariaDB connections % | ✅ | >70% / >90% |
| PostgreSQL connections % | ✅ | >70% / >90% |
| Traefik 5xx rate | ✅ | >1% / >5% |
| Traefik p95 latency | ✅ | >2s / >5s |
| ES cluster health | P1 | yellow / red |
| RabbitMQ queue depth | P1 | >1000 / >5000 |
| KDV task error rate | P1 | >5% / >20% |
| Monitoring `up` | ✅ | absent = critical |
| InnoDB cache hit ratio | P1 (бажана) | <90% |
| PG cache hit ratio | P1 (бажана) | <90% |

---

## 6. Production Readiness Gate

### Go-Live Checklist

**🔒 Безпека (всі обов'язкові)**
- [ ] VictoriaMetrics недоступний публічно
- [ ] Grafana недоступна без Cloudflare Access auth
- [ ] Жоден exporter порт не публічний
- [ ] Grafana admin password — не `admin/admin`, береться з `.env`
- [ ] Gitleaks scan — no secrets
- [ ] DB exporters — read-only users
- [ ] Trivy scan — no CRITICAL

**⚙️ Функціональність (всі обов'язкові)**
- [ ] Всі P0 scrape targets `UP`
- [ ] Метрики зберігаються ≥24 год без втрат
- [ ] Всі P0 dashboards відображають реальні дані
- [ ] Всі P0 alert rules активні
- [ ] Тестовий alert отримано на email 
- [ ] Alert `VictoriaMetricsDown` протестований
- [ ] Grafana datasource Test → success

**📁 Config-as-Code (всі обов'язкові)**
- [ ] Dashboards у Git як JSON
- [ ] Alert rules у Git як YAML
- [ ] Grafana datasources у Git (provisioning)
- [ ] Після `docker compose down && up` — все відновлюється автоматично

**💾 Надійність (всі обов'язкові)**
- [ ] Retention 90d встановлений
- [ ] VM volume backup налаштований та протестований
- [ ] `restart: unless-stopped` для VictoriaMetrics і Grafana

### Примітка щодо go-live блокерів

Актуальний перелік go-live блокерів ведеться в `docs/AGENTS.md` (секція `Production блокери`).
Щоб уникати дублювання, у цьому файлі окремий список не підтримується.

---

## 7. Post-Prod Roadmap

| Фаза | Коли | Задачі |
|------|------|--------|
| **Стабілізація** | Тижні 1–2 | Тюнінг порогів alertів по baseline, P1 dashboards (ES, RabbitMQ, KDV), maintenance silences |
| **Tuning** | Тижні 3–6 | Capacity planning dashboard (disk growth trend), MariaDB/PG/Plack tuning на основі метрик |
| **Log aggregation** | Місяць 1–2 | ADR: Loki vs ELK, Promtail для Docker logs, correlation logs+metrics у Grafana |
| **New services** | По потребі | `docs/onboarding/add-new-service.md`, VuFind exporter (після уточнення статусу), template dashboard |
| **Governance** | Місяць 3+ | ADR: VM Cluster migration, SLO/SLA dashboards, Grafana RBAC розширення |

---

## 8. Required `docs/` Documentation

> ✅ = обов'язково до production | P1/P2 = post-prod

| Файл | Призначення | Обов'язковий |
|------|-------------|--------------|
| `adr/ADR-001-victoriametrics-choice.md` | Чому VictoriaMetrics | ✅ |
| `adr/ADR-002-vm-topology.md` | Single-node vs Cluster | ✅ |
| `adr/ADR-003-label-schema.md` | Label naming convention | ✅ |
| `architecture/monitoring-architecture.md` | Схема стеку, компоненти, мережі | ✅ |
| `architecture/ports-map.md` | Карта всіх exporter портів | ✅ |
| `deployment/monitoring-stack-deploy.md` | Покроковий гайд деплою | ✅ |
| `deployment/go-live-checklist.md` | Go-live checklist | ✅ |
| `configuration/exporters-config.md` | Конфіг кожного exporter, env vars | ✅ |
| `configuration/secrets-management.md` | Робота з секретами, ротація | ✅ |
| `configuration/retention-policy.md` | Retention та backup стратегія | ✅ |
| `security/db-exporter-users.md` | Read-only DB users: права, як створені | ✅ |
| `security/monitoring-security-notes.md` | Security design, no-public-exposure | ✅ |
| `dashboards/dashboard-catalog.md` | Список дашбордів і що показують | ✅ |
| `dashboards/how-to-update-dashboards.md` | Config-as-Code workflow для dashboards | ✅ |
| `alerting/alert-rules-catalog.md` | Всі alert rules, thresholds, routing | ✅ |
| `runbooks/high-cpu.md` | Дії при High CPU | ✅ |
| `runbooks/high-memory.md` | Дії при High Memory | ✅ |
| `runbooks/disk-space-low.md` | Дії при Low Disk (assetstore!) | ✅ |
| `runbooks/container-down.md` | Дії при Container Down | ✅ |
| `runbooks/database-connections-high.md` | Дії при DB connections spike | ✅ |
| `runbooks/monitoring-down.md` | Дії при VictoriaMetrics/Grafana Down | ✅ |
| `incident-response/incident-severity-matrix.md` | P0/P1/P2 incidents, SLA часи | ✅ |
| `incident-response/incident-response-procedure.md` | Що робити при інциденті | ✅ |
| `adr/ADR-004-alerting-stack.md` | Grafana Alerting vs vmalert+Alertmanager | P1 |
| `deployment/rollback-procedure.md` | Як відкотити monitoring stack | P1 |
| `onboarding/add-new-service.md` | Підключення нового сервісу | P2 |
| `scaling/vm-cluster-migration.md` | Коли мігрувати на VM Cluster | P2 |
| `known-limitations/known-limitations.md` | Відомі обмеження реалізації | P1 |

---

## 9. Open Questions

Актуальні відкриті питання ведуться в `docs/AGENTS.md` (секція `Відкриті питання цього проєкту`).
У роадмапі залишаємо тільки фази, артефакти та критерії готовності без дублювання.

---

## Timeline

| Phase | Тривалість | Ключовий результат |
|-------|-----------|-------------------|
| Phase 0: Pre-Flight | 1–2 дні | ADRs, label schema, repo structure |
| Phase 1: Core Stack | 2–3 дні | VM + Grafana live & secured |
| Phase 2: Exporters | 3–5 днів | Метрики з усіх компонентів |
| Phase 3: Dashboards | 3–4 дні | 5 dashboards у Git provisioning |
| Phase 4: Alerting | 2–3 дні | Critical alerts active & tested |
| Phase 5: Security Gate | 1–2 дні | Go-live checklist passed |
| **Total** | **~12–19 днів** | **Production-ready** |

---

*v2.0 | 2026-03-07 | Owner: Platform / DevOps Team*
