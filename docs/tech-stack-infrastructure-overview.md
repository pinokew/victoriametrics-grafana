# Tech Stack & Infrastructure Overview

## 1. Мета документа
Цей документ дає технічний зріз стеку, інфраструктури, мереж, операційних практик і залежностей для observability платформи KDI.

## 2. Platform Summary
- Архітектура: Docker Compose, single-host deployment.
- Дані: VictoriaMetrics single-node.
- Візуалізація та алерти: Grafana.
- Доступ зовні: тільки Grafana через Cloudflare Tunnel + Access.
- Підхід до конфігурації: config-as-code (YAML/JSON у Git).

## 3. Runtime Components
### Core services
- `victoriametrics`
  - роль: TSDB + scrape + query API
  - restart policy: `unless-stopped`
  - retention: `${VM_RETENTION_PERIOD}` (production baseline: `90d`)

- `grafana`
  - роль: dashboards, alerting, notification routing
  - restart policy: `unless-stopped`
  - auth baseline: anonymous disabled, controlled RBAC defaults

### Metric ingestion and telemetry services
- `node-exporter`: host metrics + textfile collector for backup/restore status metrics
- `cadvisor`: container metrics
- `mariadb-exporter`: MariaDB telemetry (read-only account)
- `postgres-exporter`: PostgreSQL telemetry (read-only account)
- `blackbox-exporter`: synthetic HTTP/TLS probes
- `traefik` metrics target: reverse-proxy metrics scraped via dedicated job
- `cloudflared` metrics target: зовнішній edge stack, scraped через `CLOUDFLARE_TUNNEL_METRICS_TARGET`

### Edge and access service
- `cloudflared`: tunnel client in an external edge stack; this repository only scrapes its metrics endpoint and does not run the tunnel container

## 4. Infra Topology
### Host model
Всі monitoring сервіси запускаються на одному Linux VM в контейнерах Docker.

### Docker networks
- `monitoring_net`: внутрішня мережа observability stack
- `kohanet`: зовнішня Docker network для доступу до Koha/MariaDB контурів
- `dspacenet`: зовнішня Docker network для доступу до DSpace/PostgreSQL контурів

### Port exposure model
Моніторингові порти біндяться тільки на `127.0.0.1`.

Ключові порти (host loopback):
- `8428`: VictoriaMetrics
- `3000`: Grafana
- `9100`: Node Exporter
- `9104`: MariaDB Exporter
- `9187`: PostgreSQL Exporter

Додаткові internal endpoints:
- `cadvisor:8081`
- `traefik:8082` (scrape target)
- `blackbox-exporter:9115`
- P1 endpoints: ES exporter `9114`, RabbitMQ `15692`, KDV metrics `5001`

## 5. Configuration Surfaces
### Compose and env
- Основна оркестрація: `docker-compose.yml`
- Runtime параметри/секрети: `.env`
- Приклади без секретів: `.env.example`

### VictoriaMetrics config
- `victoria-metrics/scrape-config.tmpl.yml`: шаблон у Git
- `victoria-metrics/scrape-config.yml`: згенерований runtime файл
- генерація через `scripts/render-scrape-config.sh`

### Grafana provisioning
- Datasources: `grafana/provisioning/datasources/`
- Dashboards: `grafana/provisioning/dashboards/` + JSON у `grafana/dashboards/`
- Alerting: `grafana/provisioning/alerting/`

### Alert catalogs and runbooks
- Rule catalog: `alerting/rules/`
- Alert documentation: `docs/alerting/alert-rules-catalog.md`
- Incident runbooks: `docs/runbooks/*.md`

## 6. Security Baseline
### Access control
- Grafana anonymous access disabled.
- Grafana sign-up disabled.
- Default role for new users: `Viewer`.
- Admin role granted only to ops-team.

### Secret management
- Паролі, DSN, SMTP credentials не комітяться.
- Секрети передаються через `.env`/CI secrets.

### Network hardening
- Monitoring services are localhost-only on host.
- VictoriaMetrics API not exposed on public edge.
- External user access terminates at Cloudflare Access policy.

## 7. Data Lifecycle and Reliability
### Retention and storage
- Production retention policy: `90d`.
- TSDB data path mounted from host volume.

### Backup and restore
- Backup: `scripts/backup-victoriametrics-volume.sh`
- Smoke restore test: `scripts/test-victoriametrics-restore.sh`
- Full restore: `scripts/restore-victoriametrics-backup.sh`
- Volume bootstrap: `scripts/init-monitoring-volumes.sh`

### Backup observability
Node Exporter textfile collector ingests backup/restore status metrics:
- `kdi_vm_backup_*`
- `kdi_vm_restore_smoke_*`

## 8. Monitoring and Alerting Model
### Dashboards
P0 dashboards cover host, containers, MariaDB, PostgreSQL, Traefik.

### Alert routing
- `severity=critical` -> critical channel (email + configured integrations)
- `severity=warning` -> warning email channel

### Observability of observability
`VictoriaMetricsDown` rule is configured as critical and tuned to avoid false positives:
- `for=2m`
- `noDataState=NoData`
- `execErrState=Alerting`

## 9. CI/CD and Quality Gates
### Automation scope
CI pipeline includes:
- compose validation and deployment checks
- internal ports policy check
- shell script linting (`shellcheck`)
- config security scans (`Trivy`, `Gitleaks`)

### Delivery prerequisites
- SSH access and deploy path configured via GitHub secrets
- Tailscale ephemeral auth key for remote connectivity

## 10. Operational Runbook Entry Points
- Deployment guide: `docs/deployment/monitoring-stack-deploy.md`
- Security notes: `docs/security/monitoring-security-notes.md`
- Retention/backup policy: `docs/configuration/retention-policy.md`
- Roadmap and readiness: `docs/ROADMAP.md`

## 11. Known Constraints
- Single-node stack has finite scalability and no HA across nodes.
- Some production checks depend on external SaaS controls (Cloudflare Access, MS Entra).
- Alert fidelity depends on stable exporter connectivity and correct label schema.

## 12. Future Evolution (Post-Prod)
- P1: ES/RabbitMQ/KDV dashboards and alerts baseline hardening.
- P1/P2: rollback procedure, known limitations, advanced incident-response docs.
- P2: VM cluster migration decision and scaling strategy.
