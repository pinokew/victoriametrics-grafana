
## [2026-03-19] — Phase 6 (Matomo Monitoring): Fix No data у Koha/Matomo MariaDB dashboards
- **Context:** Виявлено дві проблеми в Grafana:
- у `KDI Koha-MariaDB Overview` панель `Buffer Pool Size of Total RAM` показувала `No data`;
- у `Matomo MariaDB Overview` дашборд не показував метрики через відсутній default host.
- **Change:**
- Оновлено `grafana/dashboards/mariadb-overview-7362.json` і `grafana/dashboards/matomo-mariadb-overview-7362.json`:
- виправлено формулу panel `Buffer Pool Size of Total RAM` (прибрано некоректний join по `instance` з node-exporter);
- додано default `host.current` для Koha (`mariadb-exporter:9104`) та Matomo (`matomo-mariadb-exporter:9104`);
- увімкнено `refresh_on_load` для змінної `host`.
- Перезапущено Grafana для підхоплення provisioned JSON.
- **Verification:**
- VM query для нової формули Koha повертає значення (`~0.81`), тобто `No data` більше не очікується.
- VM query `mysql_global_status_uptime{instance="matomo-mariadb-exporter:9104"}` повертає дані.
- **Risks:** За відсутності scrape-даних для конкретного exporter dashboard знову буде порожнім до відновлення target.
- **Rollback:** Відкотити JSON-файли dashboard з Git history і перезапустити Grafana.

## [2026-03-19] — Phase 6 (Matomo Monitoring): DB size metric + warning alert > 5 GB
- **Context:** Наступний крок `6.3 Capacity Monitoring` — добова метрика розміру Matomo DB і warning-alert при перевищенні 5 GB.
- **Change:**
- Додано скрипт `scripts/collect-matomo-db-size.sh`, який:
	- підключається до `matomo-db` через read-only користувача exporter;
	- обчислює розмір схеми `matomo` через `information_schema.tables`;
	- записує textfile-метрики для `node-exporter`.
- Додано метрики:
	- `kdi_matomo_database_size_bytes`
	- `kdi_matomo_database_size_last_collect_timestamp_seconds`
	- `kdi_matomo_database_size_last_status`
- Додано warning-alert `MatomoDatabaseSizeHigh` у:
	- `alerting/rules/matomo.yml`
	- `grafana/provisioning/alerting/alert-rules.yml`
- Оновлено `.env.example` (`MATOMO_DB_CONTAINER_NAME`) і `docs/configuration/exporters-config.md` з прикладом daily cron.
- **Verification:**
- `./scripts/collect-matomo-db-size.sh` → успішно, отримано `2342912` bytes.
- `curl http://127.0.0.1:9100/metrics` показує `kdi_matomo_database_size_bytes`.
- `curl .../api/v1/query?query=kdi_matomo_database_size_bytes{...}` у VictoriaMetrics повертає значення.
- Поріг alert = `5_000_000_000` bytes, поточне значення нижче порога.
- **Risks:** Для регулярного оновлення метрики скрипт треба запускати щоденно через cron/systemd timer.
- **Rollback:** Видалити скрипт/alert rules/документацію, прибрати cron запуск і прибрати метрику з textfile collector.

## [2026-03-19] — Phase 6 (Matomo Monitoring): archiving freshness metric + stale alert
- **Context:** Наступний крок `6.4 Archiving Monitoring` — зафіксувати час останнього успішного `core:archive` і підняти critical alert, якщо archiving не був успішним більше 2 годин.
- **Change:**
- Додано скрипт `scripts/collect-matomo-archiving-metric.sh`, який:
	- читає `docker logs --timestamps` контейнера `matomo-cron`;
	- знаходить останній success marker `Done archiving!`;
	- конвертує timestamp у Unix epoch;
	- записує textfile-метрики для `node-exporter`.
- Додано env-шаблон `MATOMO_CRON_CONTAINER_NAME` у `.env.example`.
- Додано метрики:
	- `matomo_archiving_last_success_timestamp`
	- `matomo_archiving_last_collect_timestamp`
	- `matomo_archiving_last_status`
- Додано critical alert `MatomoArchivingStale` у:
	- `alerting/rules/matomo.yml`
	- `grafana/provisioning/alerting/alert-rules.yml`
- Оновлено `docs/configuration/exporters-config.md` прикладом ручного запуску й cron.
- **Verification:**
- `./scripts/collect-matomo-archiving-metric.sh` → успішно, зібрано `1773910847`.
- `docker logs --timestamps matomo-cron | grep 'Done archiving!' | tail -1` → останній успіх `2026-03-19T09:00:47...Z`.
- `curl http://127.0.0.1:9100/metrics | grep 'matomo_archiving_last_'` → усі 3 метрики присутні.
- `curl .../api/v1/query?query=matomo_archiving_last_success_timestamp{job="node-exporter"}` у VictoriaMetrics повертає значення з labels `service="host"`, `exported_service="matomo"`.
- `time() - matomo_archiving_last_success_timestamp` ≈ `1235s`, тобто нижче порога `7200s`.
- Після `docker restart grafana` provisioning alerting успішно перечитано без помилок.
- **Risks:** Якщо Docker logs для `matomo-cron` будуть очищені до наступного успішного run, скрипт тимчасово не зможе знайти success marker і виставить `matomo_archiving_last_status=0`.
- **Rollback:** Видалити скрипт/alert rules/документацію, прибрати cron запуск метрики і перезапустити Grafana.

## [2026-03-19] — Phase 6 (Matomo Monitoring): тест MatomoArchivingStale (controlled stale simulation)
- **Context:** Потрібно перевірити, що alert `MatomoArchivingStale` реально спрацьовує при застарілому значенні `matomo_archiving_last_success_timestamp`.
- **Change:**
- Тимчасово зменшено `for` для `matomo-archiving-stale` у provisioning з `10m` до `1m`.
- Через textfile collector інжектовано тестове stale-значення (`now - 10800`).
- Після перевірки alert повернуто штатну конфігурацію (`for: 10m`) і відновлено реальне значення метрики через `scripts/collect-matomo-archiving-metric.sh`.
- **Verification:**
- У Grafana logs зафіксовано спрацювання: `rule_uid=matomo-archiving-stale ... Sending alerts to local notifier`.
- У VictoriaMetrics під час тесту умова була істинна (`time() - metric > 7200`), після відновлення значення повернулося нижче порога.
- **Risks:** Під час тестового вікна можливі тимчасові notification send events по цьому правилу.
- **Rollback:** Відкотити зміну `for` у provisioning alert rules і повторно застосувати штатну метрику через collector script.

## [2026-03-19] — Phase 6 (Matomo Monitoring): тест MatomoBackupStale (controlled stale simulation)
- **Context:** Потрібно перевірити, що alert `MatomoBackupStale` реально спрацьовує, якщо `matomo_backup_last_success_timestamp` старший за 26 годин.
- **Change:**
- У репо `Matomo-analytics` вирівняно `NODE_EXPORTER_TEXTFILE_DIR` на `/srv/victoriametrics-grafana/.data/node-exporter-textfile` у `.env` та `.env.example`, щоб `backup.sh` писав у той самий каталог, який читає `node-exporter`.
- Тимчасово зменшено `for` для `matomo-backup-stale` у provisioning з `30m` до `1m`.
- Через textfile collector інжектовано тестове stale-значення `matomo_backup_last_success_timestamp = now - 97200`.
- Після перевірки alert повернуто штатну конфігурацію (`for: 30m`) і відновлено реальне значення метрики через `./scripts/backup.sh --dry-run`.
- **Verification:**
- `node-exporter` читає textfile-метрики з `/srv/victoriametrics-grafana/.data/node-exporter-textfile`.
- `:9100/metrics` показує `matomo_backup_last_run_timestamp`, `matomo_backup_last_success_timestamp`, `matomo_backup_last_status`.
- У VictoriaMetrics під час тесту `time() - matomo_backup_last_success_timestamp` стало `~97212s`, тобто вище порога `93600s`.
- У Grafana logs зафіксовано спрацювання: `rule_uid=matomo-backup-stale ... Sending alerts to local notifier`.
- Після відновлення метрики через `backup.sh --dry-run` у VictoriaMetrics вік метрики повернувся до `~74s`, тобто нижче порога.
- **Risks:** Під час тестового вікна можливі тимчасові notification send events по правилу `matomo-backup-stale`.
- **Rollback:** Відкотити зміни у `Matomo-analytics/.env*` та `grafana/provisioning/alerting/alert-rules.yml`, повторно застосувати штатну backup-метрику через `backup.sh --dry-run`.

## [2026-03-19] — Phase 6 (Matomo Monitoring): restore smoke metric + MatomoRestoreSmokeStale
- **Context:** Наступний крок `6.5 Restore Readiness` — публікувати `matomo_restore_smoke_last_success_timestamp` і підняти alert, якщо успішного weekly smoke restore не було понад 8 діб.
- **Change:**
- Підтверджено, що `Matomo-analytics/scripts/test-restore.sh` уже публікує textfile-метрики:
	- `matomo_restore_smoke_last_run_timestamp`
	- `matomo_restore_smoke_last_success_timestamp`
	- `matomo_restore_smoke_last_status`
- Додано alert `MatomoRestoreSmokeStale` у:
	- `alerting/rules/matomo.yml`
	- `grafana/provisioning/alerting/alert-rules.yml`
- Поріг alert: `time() - matomo_restore_smoke_last_success_timestamp > 691200` (8 діб), `for: 30m`, severity `warning`.
- Оновлено `docs/configuration/exporters-config.md` описом restore smoke metric, ручного запуску і weekly cron-прикладу.
- Для контрольного тесту тимчасово зменшено `for` до `1m`, інжектовано stale-значення `now - 700000`, після перевірки повернуто `for: 30m` і відновлено свіжу метрику через `./scripts/test-restore.sh --dry-run`.
- **Verification:**
- `./scripts/test-restore.sh --dry-run` записує `matomo_restore_smoke.prom` у `/srv/victoriametrics-grafana/.data/node-exporter-textfile`.
- `curl http://127.0.0.1:9100/metrics` показує всі 3 `matomo_restore_smoke_*` метрики.
- У VictoriaMetrics метрика присутня з labels `job="node-exporter"`, `service="host"`, `exported_service="matomo"`.
- Під час тесту `time() - matomo_restore_smoke_last_success_timestamp` стало `~700006s`, тобто вище порога `691200s`.
- У Grafana logs зафіксовано спрацювання: `rule_uid=matomo-restore-smoke-stale ... Sending alerts to local notifier`.
- Після відновлення метрики через `test-restore.sh --dry-run` у VictoriaMetrics знову заінжестився свіжий timestamp `1773916712`.
- **Risks:** Під час тестового вікна можливі тимчасові notification send events по правилу `matomo-restore-smoke-stale`.
- **Rollback:** Видалити alert з `matomo.yml` та provisioning, відкотити документацію і за потреби повторно згенерувати штатну metric через `./scripts/test-restore.sh --dry-run`.

## [2026-04-26] — Scripts refactoring: Swarm + SOPS env contracts
- **Context:** Поточна ітерація рефакторингу `/opt/victoriametrics-grafana/` під єдиний Swarm + SOPS патерн після успішного проходу в `/opt/Matomo-analytics/`.
- **Change:**
- Додано helper-и `scripts/lib/orchestrator-env.sh`, `scripts/lib/autonomous-env.sh`, `scripts/lib/docker-runtime.sh`.
- Переведено deploy-adjacent скрипти на читання `ORCHESTRATOR_ENV_FILE` / `--env-file` без `source`/`eval`.
- `scripts/render-scrape-config.sh` тепер рендерить у tmp-файл, звіряє з існуючим `scrape-config.yml` через `cmp`/checksum і не перезаписує файл без змін.
- Переведено autonomous backup/restore/smoke restore на `SERVER_ENV` / `--env` + SOPS decrypt у `/dev/shm`.
- `scripts/deploy-orchestrator-swarm.sh` запускає `init-volumes.sh` і `render-scrape-config.sh` перед render/deploy manifest.
- Додано `docs/scripts_runbook.md`, оновлено `CHANGELOG.md` на фактичний шлях `docs/changelogs/`.
- **Verification:**
- `bash -n` для змінених shell-скриптів і helper-ів пройшов успішно.
- Smoke-перевірка `render-scrape-config.sh` з тимчасовим env-файлом показала no-op: існуючий config не перезаписано, checksum збігається.
- Smoke-перевірки helper-ів `read_env_var` і `resolve_autonomous_environment` пройшли успішно.
- **Risks:** Реальні backup/restore і Swarm deploy не запускалися в межах цієї ітерації, щоб не змінювати runtime-інфраструктуру без окремого підтвердження.
- **Rollback:** Відкотити зміни у `scripts/lib/*`, змінених `scripts/*.sh`, `docs/scripts_runbook.md`, `CHANGELOG.md` і цей запис changelog.

## [2026-04-26] — Fix deploy runbook stack name + duplicate storage guard
- **Context:** Після ручного запуску прикладу з `docs/scripts_runbook.md` було створено другий Swarm stack `victoriametrics-grafana`, тоді як фактичний production stack уже працює як `monitoring`. Новий `victoriametrics-grafana_victoriametrics` впав з `cannot acquire lock on file "/storage/flock.lock"`, бо `monitoring_victoriametrics` уже тримав той самий `VM_DATA_DIR`.
- **Change:**
- Виправлено default `STACK_NAME` у `scripts/deploy-orchestrator-swarm.sh` і `scripts/lib/docker-runtime.sh` на `monitoring`.
- Виправлено приклад deploy у `docs/scripts_runbook.md` на `STACK_NAME=monitoring`.
- Додано guard у `deploy-orchestrator-swarm.sh`: перед deploy він перевіряє Swarm services і відмовляється деплоїти stack, якщо інший stack уже використовує той самий VictoriaMetrics `/storage`.
- **Verification:**
- `docker logs` failed container підтвердив причину: `cannot acquire lock on file "/storage/flock.lock"`.
- `docker service inspect monitoring_victoriametrics` підтвердив, що існуючий stack `monitoring` використовує `/srv/victoriametrics-grafana/.data/victoriametrics`.
- `docker run ... --promscrape.config=/etc/vm/scrape-config.yml --dryRun` підтвердив валідність scrape config.
- `bash -n scripts/deploy-orchestrator-swarm.sh scripts/lib/docker-runtime.sh` пройшов успішно.
- Guard smoke-test з `STACK_NAME=victoriametrics-grafana` зупиняється до init/deploy і показує конфлікт із `monitoring_victoriametrics`.
- **Risks:** Дубльований stack `victoriametrics-grafana` ще потрібно прибрати окремою явною операцією, щоб не лишати зайві сервіси.
- **Rollback:** Відкотити guard/default stack name і повернути попередній приклад у `docs/scripts_runbook.md`.
