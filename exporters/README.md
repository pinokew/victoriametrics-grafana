# Exporters

Phase 2: exporters керуються через основний `docker-compose.yml`.

## P0 exporters
- `cadvisor` (always-on)
- `mariadb-exporter` (profile: `phase2-db`)
- `postgres-exporter` (profile: `phase2-db`)
- `traefik` metrics (scrape target, окремий endpoint у Traefik stack)

## Запуск

Базово:

```bash
docker compose up -d
```

З DB exporters:

```bash
docker compose --profile phase2-db up -d
```

## Див. також
- `docs/configuration/exporters-config.md`
- `docs/security/db-exporter-users.md`
