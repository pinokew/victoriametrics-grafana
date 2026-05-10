## [2026-05-08] — VictoriaMetrics backup: fix autonomous env loading, rclone upload, and alert age logic
- **Context:** `SERVER_ENV=prod bash scripts/backup-victoriametrics-volume.sh` падав під час завантаження decrypted `env.prod.enc` з `/dev/shm`: Bash `source` ламався на dotenv-значенні `MARIADB_EXPORTER_DSN` з `tcp(...)`.
- **Change:**
- Оновлено `scripts/lib/autonomous-env.sh`: dotenv тепер читається без `source`/`eval`, з явним парсингом `KEY=VALUE`, щоб значення з дужками або пробілами не виконувалися як shell-код.
- Оновлено `scripts/backup-victoriametrics-volume.sh`:
	- rclone upload переведено на streaming через Docker mount + `rclone rcat`, бо host user не має прямого доступу до `/data/backup/victoriametrics-grafana`;
	- локальну ротацію backup-ів переведено на Docker container, щоб вона також не залежала від host permissions.
- Оновлено `grafana/provisioning/alerting/backup-alerts.yml`: Grafana alert queries для backup/restore тепер повертають age metric, а пороги `93600` і `691200` застосовуються в evaluator; це не перетворює нормальний стан на empty vector при `noDataState=Alerting`.
- **Verification:**
- `SERVER_ENV=prod bash scripts/backup-victoriametrics-volume.sh` успішно створив backup `vmdata-20260508-133241.tar.gz` і завантажив його в `gdrive-backup:victoriametrics`.
- `SERVER_ENV=prod bash scripts/test-victoriametrics-restore.sh` успішно перевірив checksum і restore smoke test пройшов на 2-й спробі.
- Node exporter показує `kdi_vm_backup_*` і `kdi_vm_restore_smoke_*` зі status `1`.
- VictoriaMetrics API повертає backup/restore series з labels `job="node-exporter"`, `service="host"`, `exported_service="monitoring"`.
- Age queries для Grafana alert-ів повернули свіжі значення нижче порогів.
- `bash -n` для env loader, backup і restore scripts успішний; `grafana/provisioning/alerting/backup-alerts.yml` валідний YAML; `git diff --check` успішний.
- **Risks:** Якщо rclone remote або шлях у SOPS env зміняться, backup завершиться помилкою після старту VictoriaMetrics назад і запише failure metric.
- **Rollback:** Повернути `source`-loader тільки після обов'язкового quoting усіх shell-sensitive dotenv values; повернути rclone `copyto` тільки якщо host user має read/execute доступ до backup directory.

## [2026-05-08] — DSpace backup/restore freshness alerts
- **Context:** DSpace repo додав textfile metrics для backup і restore smoke; monitoring stack має підняти alerts за тим самим freshness-патерном, що VictoriaMetrics/Matomo.
- **Change:**
- Додано Prometheus-style catalog rules у `alerting/rules/monitoring.yml`:
	- `DSpaceBackupStale` — critical, якщо немає успішного backup понад 26 годин;
	- `DSpaceRestoreSmokeStale` — warning, якщо немає успішного restore smoke понад 8 діб.
- Додано Grafana provisioning rules у `grafana/provisioning/alerting/backup-alerts.yml`.
- Оновлено `docs/alerting/alert-rules-catalog.md`.
- **Verification:** YAML parse для `backup-alerts.yml` і `monitoring.yml` успішний; VictoriaMetrics API повертає `dspace_backup_last_success_timestamp_seconds` і `dspace_restore_smoke_last_success_timestamp_seconds` з labels `job="node-exporter"`, `service="host"`, `exported_service="dspace"`; age queries повернули свіжі значення нижче порогів.
- **Risks:** Якщо DSpace backup/test-restore cron не запускаються регулярно або textfile path розійдеться з mount-ом node-exporter, alerts перейдуть у stale/no-data.
- **Rollback:** Видалити DSpace alert rules з `backup-alerts.yml`, `monitoring.yml` і catalog docs.

## [2026-05-10] — Koha backup/restore freshness alerts
- **Context:** Koha backup і restore smoke scripts додають textfile collector metrics; monitoring stack має alert-и за тим самим freshness-патерном, що DSpace/VictoriaMetrics.
- **Change:**
- Додано Prometheus-style catalog rules у `alerting/rules/monitoring.yml`:
	- `KohaBackupStale` — critical, якщо немає успішного backup понад 26 годин;
	- `KohaRestoreSmokeStale` — warning, якщо немає успішного restore smoke понад 8 діб.
- Додано Grafana provisioning rules у `grafana/provisioning/alerting/backup-alerts.yml`; query повертає age, thresholds `93600` і `691200` задані через evaluator.
- Оновлено `docs/alerting/alert-rules-catalog.md`.
- **Verification:** YAML parse для `backup-alerts.yml` і `monitoring.yml` успішний; node-exporter читає `koha_backup_*` і `koha_restore_smoke_*` з `node_textfile_scrape_error=0`; VictoriaMetrics API повертає `koha_backup_last_success_timestamp_seconds` і `koha_restore_smoke_last_success_timestamp_seconds` з labels `job="node-exporter"`, `service="host"`, `exported_service="koha"`; age expressions для Koha backup/restore нижче порогів і alert threshold queries повертають empty vector; `docker service update --force monitoring_grafana` завершився converged, Grafana logs показали `finished to provision alerting`.
- **Risks:** Якщо Koha cron не запускає backup/test-restore регулярно або textfile path не змонтовано в node-exporter, alerts перейдуть у stale/no-data.
- **Rollback:** Видалити Koha alert rules з `backup-alerts.yml`, `monitoring.yml` і catalog docs.
