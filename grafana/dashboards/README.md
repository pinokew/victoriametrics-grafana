# Grafana Dashboards

Зберігаємо dashboard JSON тільки через Git.
Phase 3 (P0) включає 5 must-have dashboards:

- `host-overview-node-exporter-1860.json`
- `docker-containers-cadvisor-14282.json`
- `mariadb-overview-7362.json`
- `postgresql-overview-9628.json`
- `traefik-v3-official-17346.json`

Джерело: dashboards з Grafana.com, адаптовані під datasource `VictoriaMetrics` (`uid: victoriametrics`) для file provisioning.
