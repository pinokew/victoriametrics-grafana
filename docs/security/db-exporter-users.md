# DB Exporter Users (Read-Only)

## Принцип
Exporter-користувачі для БД мають бути окремими від application users і мати тільки read-only права.

## IaC застосування

Основний спосіб створення/оновлення exporter-користувачів — ідемпотентний скрипт:

```bash
ORCHESTRATOR_ENV_FILE=/tmp/env.decrypted \
  DOCKER_RUNTIME_MODE=swarm \
  STACK_NAME=monitoring \
  bash scripts/ensure-db-exporter-users.sh --env-file /tmp/env.decrypted
```

Скрипт:
- читає exporter credentials із decrypted env-файлу або fallback-ить на поточні exporter containers/secrets;
- не друкує паролі;
- повторно застосовує `CREATE USER IF NOT EXISTS` / `ALTER USER` / `GRANT`;
- використовується в `scripts/deploy-orchestrator-swarm.sh` перед render/deploy Swarm manifest.

## MariaDB (мінімально необхідні права)

```sql
CREATE USER IF NOT EXISTS 'metrics_reader'@'%' IDENTIFIED BY 'change_me';
ALTER USER 'metrics_reader'@'%' IDENTIFIED BY 'change_me';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'metrics_reader'@'%';
GRANT SLAVE MONITOR ON *.* TO 'metrics_reader'@'%';
FLUSH PRIVILEGES;
```

Приклад змінних для `mariadb-exporter`:

```env
MARIADB_EXPORTER_TARGET=koha-deploy-db-1:3306
MARIADB_EXPORTER_USER=metrics_reader
MARIADB_EXPORTER_PASSWORD=change_me
```

## PostgreSQL (мінімально необхідні права)

```sql
CREATE ROLE metrics_reader LOGIN PASSWORD 'change_me';
ALTER ROLE metrics_reader LOGIN PASSWORD 'change_me';
GRANT CONNECT ON DATABASE dspace TO metrics_reader;
GRANT pg_monitor TO metrics_reader;
```

Приклад DSN:

```env
POSTGRES_EXPORTER_DSN=postgresql://metrics_reader:change_me@dspacedb:5432/dspace?sslmode=disable
```

## Перевірка
- У Grafana Explore з datasource `VictoriaMetrics` виконується запит `mysql_up` / `pg_up`.
- У `http://127.0.0.1:8428/targets` відповідні jobs мають стан `UP`.

## Заборонено
- Використовувати `root`/`postgres` superuser для exporter.
- Комітити реальні DSN або паролі в Git.
