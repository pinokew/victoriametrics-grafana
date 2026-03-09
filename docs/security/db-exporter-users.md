# DB Exporter Users (Read-Only)

## Принцип
Exporter-користувачі для БД мають бути окремими від application users і мати тільки read-only права.

## MariaDB (мінімально необхідні права)

```sql
CREATE USER 'metrics_reader'@'%' IDENTIFIED BY 'change_me';
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
CREATE USER metrics_reader WITH PASSWORD 'change_me';
GRANT CONNECT ON DATABASE postgres TO metrics_reader;
GRANT pg_monitor TO metrics_reader;
```

Приклад DSN:

```env
POSTGRES_EXPORTER_DSN=postgresql://metrics_reader:change_me@postgres:5432/postgres?sslmode=disable
```

## Перевірка
- У Grafana Explore з datasource `VictoriaMetrics` виконується запит `mysql_up` / `pg_up`.
- У `http://127.0.0.1:8428/targets` відповідні jobs мають стан `UP`.

## Заборонено
- Використовувати `root`/`postgres` superuser для exporter.
- Комітити реальні DSN або паролі в Git.
