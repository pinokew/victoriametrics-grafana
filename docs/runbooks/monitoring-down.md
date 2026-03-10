# Runbook: Monitoring/Proxy Down

## Тригери
- `VictoriaMetricsDown`
- `AnyTargetDown`
- `TraefikHighErrorRate`

## Дії
1. Перевірити стан контейнерів monitoring stack (`docker compose ps`).
2. Перевірити логи `victoriametrics`, `grafana`, exporter/traefik.
3. Перевірити мережеву доступність target всередині Docker network.
4. Якщо проблема в host (power/network/disk): пріоритетно відновити host.
5. Після відновлення перевірити `http://127.0.0.1:8428/targets`.

## Перевірка відновлення
- P0 targets повернулись у `UP`
- Alert cleared
