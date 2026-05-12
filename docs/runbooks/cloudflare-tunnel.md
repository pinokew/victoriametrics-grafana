# Runbook: Cloudflare Tunnel

## Симптоми
- `CloudflareTunnelMetricsDown`: VictoriaMetrics не може scrape-ити metrics endpoint `cloudflared`.
- `CloudflareTunnelHAConnectionsLow`: tunnel має менше ніж 2 HA connections.
- `CloudflareTunnelRequestErrorsHigh`: зростає частка помилок proxy до origin.
- `CloudflareTunnelQUICPacketLossHigh`: зростає packet loss на QUIC transport.

## Перевірка
1. Перевірити target у VictoriaMetrics:

```bash
curl -s http://127.0.0.1:8428/targets | grep cloudflare-tunnel
```

2. Перевірити доступність metrics endpoint із monitoring stack/network:

```bash
curl -s http://${CLOUDFLARE_TUNNEL_METRICS_TARGET}/metrics | head
```

3. Перевірити логи зовнішнього edge stack, де запущений `cloudflared`.

4. Перевірити, що `cloudflared` запущений з metrics endpoint, доступним не тільки з localhost всередині контейнера, а з monitoring stack:

```text
--metrics 0.0.0.0:2000
```

## Типові причини
- `cloudflared` metrics endpoint слухає тільки `127.0.0.1` всередині edge контейнера/хоста.
- Monitoring stack не має мережевого маршруту до edge stack.
- Невірний `CLOUDFLARE_TUNNEL_METRICS_TARGET` у env.
- Tunnel втратив HA connections до Cloudflare edge.
- Origin за Traefik/Grafana недоступний або відповідає помилками.

## Дії
1. Виправити `CLOUDFLARE_TUNNEL_METRICS_TARGET` або Docker network між monitoring і edge stack.
2. Перезапустити тільки зовнішній `cloudflared` сервіс, якщо endpoint не слухає або tunnel втратив edge connections.
3. Якщо `RequestErrorsHigh`, перевірити Traefik router/service для Grafana і доступність `grafana:3000`.
4. Якщо `QUICPacketLossHigh`, перевірити мережу хоста, firewall/NAT і Cloudflare tunnel protocol; тимчасово порівняти з `http2`, якщо це передбачено політикою edge stack.

## Rollback
Видалити Cloudflare Tunnel alert rules із provisioning/catalog, перезапустити Grafana і залишити тільки dashboard/scrape до стабілізації метрик.
