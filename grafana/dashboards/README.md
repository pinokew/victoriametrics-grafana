# Grafana Dashboards

Зберігаємо dashboard JSON тільки через Git.
Phase 3 (P0) включає 5 must-have dashboards + Phase 6 розширення:

- `host-overview-node-exporter-1860.json`
- `docker-containers-cadvisor-14282.json`
- `mariadb-overview-7362.json` (KDI Koha-MariaDB Overview)
- `matomo-mariadb-overview-7362.json` (Matomo MariaDB Overview)
- `postgresql-overview-9628.json`
- `traefik-v3-official-17346.json`
- `cloudflare-tunnel-overview.json`

Джерело: dashboards з Grafana.com або KDI custom dashboards, адаптовані під datasource `VictoriaMetrics` (`uid: victoriametrics`) для file provisioning.
