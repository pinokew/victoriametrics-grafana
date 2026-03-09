# Каталог дашбордів (Phase 3)

## Мета
Каталог P0 дашбордів, які завантажуються в Grafana тільки через provisioning з файлів.

## P0 дашборди

| Dashboard | Файл у Git | Базовий шаблон | Основні метрики |
|---|---|---|---|
| Host Overview | `grafana/dashboards/host-overview-node-exporter-1860.json` | Node Exporter Full (`1860`) | CPU %, RAM %, disk free %, network I/O, load average |
| Docker Containers | `grafana/dashboards/docker-containers-cadvisor-14282.json` | cAdvisor Exporter (`14282`) | CPU/RAM per container, container load, filesystem usage |
| MariaDB | `grafana/dashboards/mariadb-overview-7362.json` | MySQL Overview (`7362`) | connections, QPS, InnoDB metrics, slow queries |
| PostgreSQL | `grafana/dashboards/postgresql-overview-9628.json` | PostgreSQL Database (`9628`) | connections, transactions, cache stats, locks |
| Traefik v3 | `grafana/dashboards/traefik-v3-official-17346.json` | Traefik Official (`17346`) | request rate, error rate, latency percentiles |

## Адаптація під стек KDI
- Усі dashboards переведені на datasource `uid: victoriametrics`.
- Прибрані import-only поля (`__inputs`, `gnetId`), щоб dashboards стабільно завантажувались через provisioning.
- Для уникнення конфліктів між інсталяціями задано власні `uid` у форматі `kdi-*`.
- Dashboards позначені тегами `kdi`, `phase3`, `provisioned`, `victoriametrics`.

## Перевірка
1. `docker compose restart grafana`
2. Відкрити Grafana → Dashboards → папка `KDI / P0`.
3. Переконатись, що завантажені всі 5 dashboards і панелі показують дані з datasource `VictoriaMetrics`.
