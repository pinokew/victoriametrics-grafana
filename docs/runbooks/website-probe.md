# Runbook: Website Probe Alerts (Koha)

## Тригери
- `WebsiteDown` (critical): `probe_success < 1` для `koha-opac` або `koha-staff`
- `WebsiteHighLatency` (warning): `probe_duration_seconds > 2s`

## Що означає
Blackbox Exporter не отримує коректну HTTP-відповідь 2xx або отримує надто повільну відповідь.

## Дії
1. Перевірити доступність сайтів вручну з браузера або `curl`.
2. Перевірити DNS/SSL сертифікат та термін дії.
3. Перевірити upstream (Koha/Apache/Plack) і логи реверс-проксі.
4. Якщо недоступний тільки один сайт, ізолювати проблему до конкретного endpoint.

## Перевірка відновлення
- `probe_success=1` стабільно 5+ хв
- `probe_duration_seconds` повернувся до baseline
- Алерт автоматично перейшов у resolved
