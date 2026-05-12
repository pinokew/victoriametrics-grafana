# ADR-003: Label Schema для scrape jobs та alerts

- Статус: Accepted
- Дата: 2026-03-07

## Контекст
Потрібна єдина схема labels для коректної фільтрації у дашбордах і алертах.

## Рішення
Фіксуємо схему labels:
- `env` (обов'язково): `prod`
- `service` (обов'язково): `koha|dspace|integrator|monitoring|host|traefik|cloudflare`
- `component` (опціонально): `db|search|cache|broker|tunnel`

## Приклад
```yaml
labels:
  env: prod
  service: koha
  component: db
```

## Наслідки
- Нові labels додаються тільки через оновлення цього ADR
- Дашборди та alert rules мають спиратися на цю схему
