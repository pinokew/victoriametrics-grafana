
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

## [2026-05-07] — Swarm secrets: hash-based versioned secret render
- **Context:** Swarm manifest використовує external Docker secrets через `*_SECRET_NAME`, але deploy path не створював hash-versioned secret names безпосередньо з decrypted orchestrator env.
- **Change:**
- Додано `scripts/render-versioned-env-secret.sh` за патерном DSpace:
	- створює immutable Docker secrets з 12-символьним sha256 suffix;
	- рендерить secret names для Grafana admin password, Grafana SMTP password, Koha MariaDB exporter password і Matomo MariaDB exporter password;
	- оновлює generated `*_SECRET_NAME` у тимчасовому decrypted env-файлі без друку значень секретів.
- `scripts/deploy-orchestrator-swarm.sh` тепер викликає render-versioned secrets після `render-scrape-config.sh` і до `docker compose config`.
- Оновлено `docs/scripts_runbook.md` з manual execution для нового скрипта.
- **Verification:** `bash -n` для змінених shell-скриптів; smoke-test нового render script на тимчасовому env-файлі з fake Docker CLI підтвердив hash suffix для всіх 4 generated secret names і оновлення env-файлу; `docker compose --env-file ... config` підтвердив підстановку versioned external secret names у Swarm manifest.
- **Risks:** Скрипт вимагає непорожні значення всіх 4 secret values, бо `docker-compose.swarm.yml` завжди посилається на відповідні external secrets.
- **Rollback:** Видалити `scripts/render-versioned-env-secret.sh`, прибрати його виклик з `deploy-orchestrator-swarm.sh` і відкотити runbook/changelog.

## [2026-05-08] — Grafana auth: local login form + AzureAD public redirect URL
- **Context:** Після налаштування Entra ID / MS365 Grafana одразу редіректила на AzureAD і ховала локальний login/password вхід. OAuth request також формував redirect URI як `http://localhost:3000/login/azuread`, що не збігалося з доменним redirect URI в Azure Portal.
- **Change:**
- Додано env-контракт у `.env.example`:
	- `GRAFANA_ADMIN_USER=m.zhuk@ldubgd.edu.ua`
	- `GRAFANA_ADMIN_EMAIL=m.zhuk@ldubgd.edu.ua`
	- `GF_AUTH_DISABLE_LOGIN_FORM=false`
	- `GF_AUTH_AZUREAD_ENABLED=false`
	- `GF_AUTH_AZUREAD_AUTO_LOGIN=false`
	- `GF_AUTH_AZUREAD_SKIP_ORG_ROLE_SYNC=true`
	- `GF_AUTH_OAUTH_ALLOW_INSECURE_EMAIL_LOOKUP=true`
	- `GF_SERVER_DOMAIN=grafana.example.com`
	- `GF_SERVER_ROOT_URL=https://grafana.example.com`
- Прокинуто ці змінні в `docker-compose.yml` і `docker-compose.swarm.yml`; для Swarm це обов'язково, бо `env_file` там скинутий.
- `GF_AUTH_AZUREAD_ENABLED=false` вимикає Entra ID / AzureAD provider декларативно через IaC до повторного увімкнення.
- `GF_AUTH_AZUREAD_SKIP_ORG_ROLE_SYNC=true` не дає OAuth login зняти роль останнього org admin під час MS365 role sync.
- `GF_AUTH_OAUTH_ALLOW_INSECURE_EMAIL_LOOKUP=true` дозволяє OAuth-мапування існуючого користувача за email.
- `GF_SERVER_ROOT_URL` керує публічною базовою URL Grafana, тому AzureAD redirect URI має формуватися як `https://<grafana-domain>/login/azuread`.
- Runtime cleanup: через backup/replace `grafana.db` видалено окремого користувача `id=3` з login/email `m.zhuk@ldubgd.edu.ua`; server admin `id=1` перейменовано на login/email `m.zhuk@ldubgd.edu.ua` і name `Максим Жук`.
- Runtime SSO fix: у DB `sso_setting` для provider `azuread` змінено тільки `skip_org_role_sync` з `false` на `true`, бо Entra ID був налаштований через Grafana UI і цей DB setting впливає на поточний OAuth login.
- **Verification:** `docker compose config` для Swarm overlay пройшов успішно; local compose перевірено через тимчасову копію без `env_file`, бо реального `.env` немає в repo. Rendered config містить `GF_AUTH_DISABLE_LOGIN_FORM=false`, `GF_AUTH_AZUREAD_ENABLED=false`, `GF_AUTH_AZUREAD_AUTO_LOGIN=false`, `GF_AUTH_AZUREAD_SKIP_ORG_ROLE_SYNC=true`, `GF_AUTH_OAUTH_ALLOW_INSECURE_EMAIL_LOOKUP=true`, `GF_SERVER_DOMAIN` і `GF_SERVER_ROOT_URL`. Після runtime cleanup Grafana service зійшовся в `1/1`, у DB лишилися користувачі `id=1 m.zhuk@ldubgd.edu.ua` (admin) і `id=4 test1@ldubgd.edu.ua`. Після runtime SSO fix service зійшовся в `1/1`, а `sso_setting.azuread.skip_org_role_sync=true`.
- **Risks:** У реальному `.env` потрібно виставити production-домен Grafana і додати точно такий redirect URI в Azure Portal.
- **Rollback:** Прибрати нові `GF_AUTH_*` / `GF_SERVER_*` змінні з env-шаблону та compose-файлів.

## [2026-05-08] — DB exporters: idempotent metrics_reader IaC + restore Koha/Matomo/PostgreSQL metrics
- **Context:** У Grafana/VM не відображалися Koha MariaDB і Matomo MariaDB metrics, а PostgreSQL dashboard мав неповний набір метрик. Runtime exporter services були `1/1`, але exporter endpoints показували `mysql_up=0` / `pg_up=0`.
- **Root cause:** Усі три exporter-и не проходили DB authentication:
	- Koha MariaDB exporter: `Access denied for user 'metrics_reader'`;
	- Matomo MariaDB exporter: `Access denied for user 'metrics_reader'`;
	- PostgreSQL exporter: `password authentication failed for user "metrics_reader"`.
- **Change:**
- Додано `scripts/ensure-db-exporter-users.sh`:
	- ідемпотентно створює/оновлює `metrics_reader` у Koha MariaDB, Matomo MariaDB і DSpace PostgreSQL;
	- читає credentials із decrypted orchestrator env або fallback-ить на поточні exporter containers/secrets;
	- не друкує паролі;
	- застосовує мінімальні read-only grants для exporter-ів.
- Додано env-контракт `KOHA_DB_CONTAINER_NAME` і `DSPACE_POSTGRES_CONTAINER_NAME` у `.env.example`.
- `scripts/deploy-orchestrator-swarm.sh` тепер викликає `ensure-db-exporter-users.sh` після render versioned secrets і до render/deploy Swarm manifest (`ENSURE_DB_EXPORTER_USERS_ON_DEPLOY=false` вимикає цей крок).
- Оновлено `docs/security/db-exporter-users.md` і `docs/scripts_runbook.md`.
- Runtime: запущено `scripts/ensure-db-exporter-users.sh` проти поточних DB контейнерів і перезапущено тільки `monitoring_mariadb-exporter`, `monitoring_matomo-mariadb-exporter`, `monitoring_postgres-exporter`.
- **Verification:**
- `bash -n scripts/ensure-db-exporter-users.sh scripts/deploy-orchestrator-swarm.sh` успішний.
- Koha exporter endpoint: `mysql_up 1`, `mysql_global_status_uptime` присутня.
- Matomo exporter endpoint: `mysql_up 1`, `mysql_global_status_uptime` присутня.
- PostgreSQL exporter endpoint: `pg_up 1`, `pg_exporter_last_scrape_error 0`, `pg_stat_database_numbackends{datname="dspace"}` присутня.
- VictoriaMetrics query API повертає `mysql_up{job="mariadb-exporter"}=1`, `mysql_up{job="matomo-mariadb-exporter"}=1`, `pg_up{job="postgres-exporter"}=1`, `pg_stat_database_numbackends{job="postgres-exporter",datname="dspace"}`.
- **Risks:** Скрипт очікує доступні app DB containers. Для деплоїв без Koha/Matomo/DSpace поруч можна встановити `ENSURE_DB_EXPORTER_USERS_ON_DEPLOY=false`.
- **Rollback:** Відкотити скрипт/виклик у deploy path/docs/changelog; за потреби вручну повернути попередні DB grants/passwords для `metrics_reader`.

## [2026-05-08] — Website probes: add DSpace UI/API blackbox jobs
- **Context:** Website probes були налаштовані для Koha OPAC, Koha staff і Matomo, але DSpace не мав окремої synthetic HTTP probe. DSpace частково покривався PostgreSQL exporter, cAdvisor і Traefik metrics, але це не перевіряє зовнішню доступність UI/API без реального користувацького трафіку.
- **Change:**
- Додано env-змінні в `.env.example`:
	- `DSPACE_UI_URL=https://dspace.example.com`
	- `DSPACE_API_URL=https://dspace-api.example.com/server`
- Оновлено `scripts/render-scrape-config.sh`: читає, валідує `http(s)://` і підставляє `DSPACE_UI_URL` / `DSPACE_API_URL`.
- Оновлено `victoria-metrics/scrape-config.tmpl.yml`:
	- `blackbox-dspace-ui` з labels `service="dspace"`, `website="ui"`;
	- `blackbox-dspace-api` з labels `service="dspace"`, `website="api"`.
- Додано alert rules у `grafana/provisioning/alerting/website-alerts.yml`:
	- `DSpaceWebsiteDown`;
	- `DSpaceWebsiteHighLatency`.
- Оновлено `docs/configuration/exporters-config.md` і `docs/scripts_runbook.md`.
- **Verification:** `bash -n scripts/render-scrape-config.sh` успішний; render перевірено на тимчасовому env-файлі з DSpace URL без зміни `env.*.enc`.
- **Risks:** До наступного deploy/render потрібно додати `DSPACE_UI_URL` і `DSPACE_API_URL` у реальний decrypted env (`env.*.enc` після розшифрування), інакше `render-scrape-config.sh` очікувано зупиниться.
- **Rollback:** Видалити DSpace env-змінні, template jobs, alert rules і документацію; перерендерити `victoria-metrics/scrape-config.yml`.

## [2026-05-08] — Cloudflare Tunnel metrics: external edge scrape target
- **Context:** Cloudflare Tunnel винесений у зовнішній edge stack, до якого підключений Traefik; контейнер `cloudflared` не повертаємо в monitoring compose/swarm stack.
- **Change:**
- Додано env-контракт у `.env.example`:
	- `CLOUDFLARE_TUNNEL_METRICS_TARGET=cloudflared:2000`
	- `CLOUDFLARE_TUNNEL_NAME=grafana`
- Оновлено `scripts/render-scrape-config.sh`: читає, валідує `host:port` target без URL-схеми і підставляє Cloudflare Tunnel labels.
- Оновлено `victoria-metrics/scrape-config.tmpl.yml`: додано scrape job `cloudflare-tunnel` з labels `service="cloudflare"`, `component="tunnel"`.
- Оновлено label schema ADR і документацію для external edge stack моделі.
- **Verification:** `bash -n scripts/render-scrape-config.sh` і `git diff --check` успішні; render smoke у тимчасовій копії через `.env.example` створив job `cloudflare-tunnel` з target `cloudflared:2000` і labels `service="cloudflare"`, `component="tunnel"`, `tunnel="grafana"`.
- **Risks:** До наступного deploy/render потрібно додати `CLOUDFLARE_TUNNEL_METRICS_TARGET` і `CLOUDFLARE_TUNNEL_NAME` у реальний decrypted env (`env.*.enc` після розшифрування), інакше `render-scrape-config.sh` очікувано зупиниться.
- **Rollback:** Видалити Cloudflare env-змінні, scrape job, label schema/doc updates і перерендерити `victoria-metrics/scrape-config.yml`.

## [2026-05-08] — Cloudflare Tunnel dashboard: provisioned Grafana overview
- **Context:** Після додання scrape job `cloudflare-tunnel` потрібен provisioned Grafana dashboard для tunnel health, traffic і QUIC transport metrics.
- **Change:**
- Додано dashboard `grafana/dashboards/cloudflare-tunnel-overview.json` з uid `kdi-cloudflare-tunnel-overview`.
- Панелі покривають:
	- scrape status;
	- HA connections;
	- request/error rate;
	- active streams і concurrent requests;
	- QUIC RTT і lost packets;
	- current edge locations;
	- `cloudflared` build info.
- Dashboard використовує datasource `uid: victoriametrics` і labels `job="cloudflare-tunnel"`, `env="prod"`, `tunnel`.
- Оновлено `grafana/dashboards/README.md` і `docs/dashboards/dashboard-catalog.md`.
- **Verification:** `jq empty grafana/dashboards/cloudflare-tunnel-overview.json` і `git diff --check` успішні; grep-перевірка підтвердила `uid`, datasource `victoriametrics` і query references на `cloudflare-tunnel` / `cloudflared_tunnel_*` / `quic_client_*`.
- **Risks:** Частина панелей буде `No data`, доки external `cloudflared` metrics endpoint не стане доступним для VictoriaMetrics і не почне віддавати відповідні метрики.
- **Rollback:** Видалити dashboard JSON і записи з dashboard docs/catalog.

## [2026-05-08] — Cloudflare Tunnel alerts: metrics, HA, proxy errors, QUIC loss
- **Context:** Після додання Cloudflare Tunnel scrape job і dashboard потрібні alert-и на базові ризики external edge stack.
- **Change:**
- Додано Prometheus-style catalog rules у `alerting/rules/cloudflare.yml`:
	- `CloudflareTunnelMetricsDown` — critical, якщо `up < 1` понад 2 хвилини;
	- `CloudflareTunnelHAConnectionsLow` — warning, якщо HA connections < 2 понад 5 хвилин;
	- `CloudflareTunnelRequestErrorsHigh` — warning, якщо origin proxy error rate > 1% понад 5 хвилин;
	- `CloudflareTunnelQUICPacketLossHigh` — warning, якщо QUIC lost packets > 1 packet/sec понад 5 хвилин.
- Додано Grafana provisioning rules у `grafana/provisioning/alerting/cloudflare-alerts.yml`.
- Додано runbook `docs/runbooks/cloudflare-tunnel.md`.
- Оновлено `docs/alerting/alert-rules-catalog.md`.
- **Verification:** YAML parse для `alerting/rules/cloudflare.yml` і `grafana/provisioning/alerting/cloudflare-alerts.yml` успішний; grep-перевірка підтвердила всі rule UID/title/runbook references; `git diff --check` успішний.
- **Risks:** До фактичного scrape target up правила з `NoDataState=Alerting` для `CloudflareTunnelMetricsDown` можуть перейти в firing, якщо provisioning застосувати до того, як `cloudflared` metrics endpoint доступний.
- **Rollback:** Видалити `cloudflare-alerts.yml`, `alerting/rules/cloudflare.yml`, runbook/catalog записи і перезапустити Grafana.

## [2026-05-08] — Docs: remove stale in-repo cloudflared deployment steps
- **Context:** `docs/deployment/monitoring-stack-deploy.md` досі описував старий `cloudflared` service/profile `phase1-edge` і `CLOUDFLARE_TUNNEL_TOKEN`, хоча tunnel винесений у зовнішній edge stack.
- **Change:** Оновлено Cloudflare Tunnel deployment section: зафіксовано, що `cloudflared` не запускається з цього репозиторію, а monitoring stack використовує тільки `CLOUDFLARE_GRAFANA_HOSTNAME` і external metrics target `CLOUDFLARE_TUNNEL_METRICS_TARGET`.
- **Verification:** `rg` підтвердив, що deployment doc більше не містить `phase1-edge`, `CLOUDFLARE_TUNNEL_TOKEN` або команд запуску `cloudflared` з цього repo; `git diff --check` успішний.
- **Risks:** Реальні інструкції запуску зовнішнього edge stack лишаються поза цим репозиторієм.
- **Rollback:** Повернути попередній текст розділу Cloudflare Tunnel у deployment doc.
