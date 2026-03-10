# Alert Rules Catalog (Phase 4)

## Routing
- `severity=critical` -> `critical-email-telegram` (MS365 Email + Telegram)
- `severity=warning` -> `warning-email` (MS365 Email)

## Важливо перед production
- У `grafana/provisioning/alerting/contact-points.yml` задані safe placeholders (`alerts@example.com`, тестовий bot token/chat id), щоб Grafana не падала на порожніх значеннях.
- Перед go-live замініть ці значення на реальні канали нотифікацій і перевірте тестовий alert.

## Inhibition/Suppression
- Для `ContainerDown`, `MariaDB*`, `PostgreSQL*` додано guard `and on() (max(up{job="node-exporter",...}) == 1)`.
- Це пригнічує flood secondary alert-ів, коли сам host недоступний.

## P0 Rules

| Rule | Severity | For | Runbook |
|------|----------|-----|---------|
| HostHighCPU | critical | 5m | `docs/runbooks/high-cpu.md` |
| HostHighMemory | critical | 5m | `docs/runbooks/high-memory.md` |
| HostDiskLow | critical | 5m | `docs/runbooks/disk-space-low.md` |
| HostDiskWarning | warning | 5m | `docs/runbooks/disk-space-low.md` |
| ContainerDown | critical | 2m | `docs/runbooks/container-down.md` |
| ContainerHighRestarts | warning | 5m | `docs/runbooks/container-down.md` |
| MariaDBDown | critical | 2m | `docs/runbooks/monitoring-down.md` |
| MariaDBConnectionsHigh | critical | 5m | `docs/runbooks/database-connections-high.md` |
| PostgreSQLDown | critical | 2m | `docs/runbooks/monitoring-down.md` |
| PostgreSQLConnectionsHigh | critical | 5m | `docs/runbooks/database-connections-high.md` |
| TraefikHighErrorRate | critical | 5m | `docs/runbooks/monitoring-down.md` |
| TraefikHighLatency | warning | 5m | `docs/runbooks/monitoring-down.md` |
| VictoriaMetricsDown | critical | 2m | `docs/runbooks/monitoring-down.md` |
| AnyTargetDown | warning | 2m | `docs/runbooks/monitoring-down.md` |
| WebsiteDown | critical | 2m | `docs/runbooks/website-probe.md` |
| WebsiteHighLatency | warning | 5m | `docs/runbooks/website-probe.md` |

## Synthetic Smoke Rule

| Rule | Severity | For | Purpose | Default state |
|------|----------|-----|---------|---------------|
| SyntheticEmailSmoke | warning | 0s | Перевірка email маршруту без Telegram | passive (`vector(0)`) |

Файл: `grafana/provisioning/alerting/synthetic-alerts.yml`.
Для короткого smoke-тесту тимчасово змінюй `expr` з `vector(0)` на `vector(1)` і перевідтворюй Grafana.

## Файли конфігурації
- Grafana provisioning:
  - `grafana/provisioning/alerting/contact-points.yml`
  - `grafana/provisioning/alerting/notification-policies.yml`
  - `grafana/provisioning/alerting/alert-rules.yml`
  - `grafana/provisioning/alerting/website-alerts.yml`
- Rule catalog (Prometheus-style):
  - `alerting/rules/host.yml`
  - `alerting/rules/containers.yml`
  - `alerting/rules/databases.yml`
  - `alerting/rules/traefik.yml`
  - `alerting/rules/monitoring.yml`
