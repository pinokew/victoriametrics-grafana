# Retention And Backup Policy (VictoriaMetrics)

## Мета
Зафіксувати політику зберігання метрик і операційний процес backup/restore для single-node VictoriaMetrics.

## Retention
- `VM_RETENTION_PERIOD=90d`.
- Дані зберігаються у `VM_DATA_DIR` (default: `./.data/victoriametrics`).

## Backup strategy (Phase 5)
Обрано `cron snapshot` на рівні volume-архіву з коротким downtime для консистентності.

### Скрипти
- `scripts/init-monitoring-volumes.sh`
- `scripts/backup-victoriametrics-volume.sh`
- `scripts/restore-victoriametrics-backup.sh`
- `scripts/test-victoriametrics-restore.sh`

### Backup observability metrics
Скрипти записують status-метрики у `NODE_EXPORTER_TEXTFILE_DIR` як textfile collector файли:
- `vm_backup.prom`
- `vm_restore_smoke.prom`

Метрики:
- `kdi_vm_backup_last_run_timestamp_seconds`
- `kdi_vm_backup_last_success_timestamp_seconds`
- `kdi_vm_backup_last_status`
- `kdi_vm_restore_smoke_last_run_timestamp_seconds`
- `kdi_vm_restore_smoke_last_success_timestamp_seconds`
- `kdi_vm_restore_smoke_last_status`

### Ініціалізація директорій томів з `.env`
Перед першим запуском (або після зміни шляхів у `.env`, наприклад `/srv/...`) виконай:

```bash
./scripts/init-monitoring-volumes.sh
```

Dry-run перевірка без змін:

```bash
./scripts/init-monitoring-volumes.sh --dry-run
```

### Параметри `.env`
- `VM_BACKUP_DIR` (default: `./.backups/victoriametrics`)
- `VM_BACKUP_RETENTION_COUNT` (default: `7`)
- `VM_BACKUP_CLOUD_RETENTION_COUNT` (default: `30`)
- `RCLONE_REMOTE` (example: `gdrive-backup`)
- `RCLONE_DEST_PATH` (example: `victoriametrics`)
- `VM_RESTORE_TEST_PORT` (default: `18428`)

### Ручний запуск backup
```bash
./scripts/backup-victoriametrics-volume.sh
```

### Тест відновлення (smoke test)
```bash
./scripts/test-victoriametrics-restore.sh
```

Альтернатива: явно вказати архів:
```bash
./scripts/test-victoriametrics-restore.sh ./.backups/victoriametrics/vmdata-YYYYMMDD-HHMMSS.tar.gz
```

### Повне відновлення (destructive)
Увага: команда перезаписує `VM_DATA_DIR`.

```bash
./scripts/restore-victoriametrics-backup.sh --yes
```

Відновлення з конкретного архіву:

```bash
./scripts/restore-victoriametrics-backup.sh ./.backups/victoriametrics/vmdata-YYYYMMDD-HHMMSS.tar.gz --yes
```

Dry-run для перевірки кроків без змін:

```bash
./scripts/restore-victoriametrics-backup.sh --dry-run
```

## Cron (приклад)
Щоденний backup о 02:30:
```cron
30 2 * * * cd /opt/victoriametrics-grafana && ./scripts/backup-victoriametrics-volume.sh >> /var/log/vm-backup.log 2>&1
```

Щотижневий smoke test restore (неділя 03:00):
```cron
0 3 * * 0 cd /opt/victoriametrics-grafana && ./scripts/test-victoriametrics-restore.sh >> /var/log/vm-restore-test.log 2>&1
```

## Validation checklist
- Backup архів створено у `VM_BACKUP_DIR`.
- Є файл checksum `.sha256`.
- Якщо задані `RCLONE_REMOTE` і `RCLONE_DEST_PATH`, архів і checksum скопійовано в `${RCLONE_REMOTE}:${RCLONE_DEST_PATH}`.
- Smoke test restore завершується повідомленням `Restore smoke test passed`.

## Risks
- Під час backup script сервіс `victoriametrics` коротко зупиняється.
- Якщо backup dir розміщений на тому самому диску, backup не захищає від повної втрати диска.

## Рекомендації
- Реплікувати backup архіви на окремий диск/хост або object storage.
- Моніторити вільне місце для `VM_DATA_DIR` та `VM_BACKUP_DIR`.
