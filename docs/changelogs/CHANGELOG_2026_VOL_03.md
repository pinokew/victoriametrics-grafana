# CHANGELOG 2026 VOL 03

## [2026-03-10] — Rotation: старт нового тому changelog

- **Context:** `CHANGELOG_2026_VOL_02.md` досяг soft limit `300` рядків згідно політики ротації.
- **Change:** Створено новий активний том `CHANGELOGS/CHANGELOG_2026_VOL_03.md`.
- **Verification:** Перевірено наявність нового файлу в `CHANGELOGS/`.
- **Risks:** Відсутні (організаційна зміна, без впливу на runtime).
- **Rollback:** Видалити новий том і повернути `VOL_02` як active в `CHANGELOG.md`.

## [2026-03-10] — Phase 5 (інкремент 3): Grafana RBAC baseline (Admin/Viewer)

- **Context:** Наступний крок Phase 5: `Grafana RBAC` з розподілом ролей `Admin` для `ops-team` і `Viewer` для stakeholders.
- **Change:**
	- Оновлено `docker-compose.yml` (сервіс `grafana`):
		- `GF_USERS_ALLOW_SIGN_UP=false`
		- `GF_USERS_AUTO_ASSIGN_ORG=true`
		- `GF_USERS_AUTO_ASSIGN_ORG_ROLE=${GRAFANA_AUTO_ASSIGN_ORG_ROLE:-Viewer}`
	- Оновлено `.env.example`:
		- додано `GRAFANA_AUTO_ASSIGN_ORG_ROLE=Viewer`.
	- Додано новий обов'язковий security-документ:
		- `docs/security/monitoring-security-notes.md` (RBAC policy, validation, risks, rollback).
	- У `docs/ROADMAP.md` відмічено виконання пункту `Grafana RBAC: admin для ops-team, viewer для stakeholders`.
- **Verification:**
	- `docker compose -f docker-compose.yml config -q` проходить без помилок.
	- Очікуваний runtime результат: нові користувачі отримують роль `Viewer` за замовчуванням, self-signup вимкнений.
- **Risks:** Призначення `ops-team` у роль `Admin` лишається операційним кроком в Grafana org (після входу адміністратора).
- **Rollback:** Повернути попередні `GF_USERS_*` параметри у `docker-compose.yml`/`.env`, перезапустити Grafana.

## [2026-03-10] — Phase 5 (інкремент 4): backup VictoriaMetrics volume + restore test

- **Context:** Наступний P0-крок роадмапи: налаштувати backup VictoriaMetrics volume і підтвердити відновлення.
- **Change:**
	- Додано скрипт `scripts/backup-victoriametrics-volume.sh`:
		- консистентний backup через короткий stop/start `victoriametrics`;
		- архівація у `VM_BACKUP_DIR` (`vmdata-YYYYMMDD-HHMMSS.tar.gz`);
		- генерація checksum `.sha256`;
		- ротація архівів за `VM_BACKUP_RETENTION_COUNT`.
	- Додано скрипт `scripts/test-victoriametrics-restore.sh`:
		- валідація checksum;
		- підняття тимчасового VM контейнера з backup-даних;
		- health smoke test через `http://127.0.0.1:${VM_RESTORE_TEST_PORT}/health`.
	- Оновлено `.env.example`:
		- `VM_BACKUP_DIR`, `VM_BACKUP_RETENTION_COUNT`, `VM_RESTORE_TEST_PORT`.
	- Додано документацію `docs/configuration/retention-policy.md` (policy + cron приклади).
	- Оновлено `docs/deployment/monitoring-stack-deploy.md` секцією backup/restore.
	- В `docs/ROADMAP.md` відмічено виконання backup-пункту Phase 5 та чекпойнту `VM volume backup налаштований та протестований`.
- **Verification:**
	- `./scripts/backup-victoriametrics-volume.sh` -> backup архів і `.sha256` створені.
	- `./scripts/test-victoriametrics-restore.sh` -> `Restore smoke test passed`.
	- Перевірено checksum: `vmdata-...tar.gz: OK`.
- **Risks:** Backup-скрипт робить короткий stop/start `victoriametrics`, що дає невелике вікно недоступності.
- **Rollback:** Видалити/відкотити нові backup-скрипти та змінні `.env.example`, повернути попередню документацію.

## [2026-03-10] — Phase 5 (інкремент 4.1): init volumes + повний restore backup

- **Context:** Додаткові операційні вимоги до backup-напрямку: ініціалізація директорій томів із `.env` та окремий бойовий restore-скрипт.
- **Change:**
	- Додано `scripts/init-monitoring-volumes.sh`:
		- читає шляхи томів із `.env` (`VM_DATA_DIR`, `VM_BACKUP_DIR`, `GRAFANA_DATA_DIR`, `GRAFANA_LOGS_DIR`);
		- створює директорії;
		- виставляє owner/mode (VM: `root:root`, Grafana: з `GRAFANA_CONTAINER_USER`);
		- підтримує `--dry-run`.
	- Додано `scripts/restore-victoriametrics-backup.sh` (destructive restore):
		- валідує checksum архіву (якщо є `.sha256`);
		- зупиняє `victoriametrics`, очищає `VM_DATA_DIR`, розпаковує backup;
		- піднімає `victoriametrics` і перевіряє `/health`;
		- підтримує `--yes` (підтвердження) і `--dry-run`.
	- Оновлено документацію:
		- `docs/configuration/retention-policy.md`
		- `docs/deployment/monitoring-stack-deploy.md`.
- **Verification:**
	- `bash -n scripts/init-monitoring-volumes.sh`
	- `bash -n scripts/restore-victoriametrics-backup.sh`
	- `./scripts/init-monitoring-volumes.sh --dry-run`
	- `./scripts/restore-victoriametrics-backup.sh --dry-run`
- **Risks:** Неправильні права/власник на `/srv/...` можуть вимагати запуск через `sudo`.
- **Rollback:** Видалити нові скрипти й повернути попередню версію docs.

## [2026-03-10] — Phase 5 (інкремент 4.2): alerts для backup creation і smoke restore success

- **Context:** Потрібно алертити на відсутність успішного backup і відсутність успішного smoke restore test.
- **Change:**
	- `node-exporter` переведено на textfile collector для backup-метрик:
		- `--collector.textfile.directory=/vm-backup-metrics`
		- mount `${VM_BACKUP_DIR}:/vm-backup-metrics:ro`
	- `scripts/backup-victoriametrics-volume.sh` записує `vm_backup.prom` з метриками `kdi_vm_backup_*`.
	- `scripts/test-victoriametrics-restore.sh` записує `vm_restore_smoke.prom` з метриками `kdi_vm_restore_smoke_*`.
	- Додано Grafana provisioning rules: `grafana/provisioning/alerting/backup-alerts.yml`:
		- `VictoriaMetricsBackupStale` (critical)
		- `VictoriaMetricsRestoreSmokeStale` (warning)
	- Оновлено Prometheus-style catalog rules: `alerting/rules/monitoring.yml`.
	- Додано runbook: `docs/runbooks/vm-backup-restore.md`.
	- Оновлено `docs/alerting/alert-rules-catalog.md` і `docs/configuration/retention-policy.md`.
- **Verification:**
	- Після запуску backup/smoke скриптів з'являються файли `vm_backup.prom` і `vm_restore_smoke.prom` у `VM_BACKUP_DIR`.
	- Метрики доступні через node-exporter (`/metrics`) і у VictoriaMetrics query.
	- Після рестарту Grafana provisioning завантажує `backup-alerts.yml`.
- **Risks:** Якщо backup/smoke скрипти не виконуються регулярно (cron/systemd timer), alerts будуть спрацьовувати як stale.
- **Rollback:** Видалити `backup-alerts.yml`, прибрати textfile collector mount/flag, повернути попередні версії скриптів.

## [2026-03-10] — Phase 5 (інкремент 5): верифікація `VictoriaMetricsDown` (observability of observability)

- **Context:** У Phase 5 залишався production-блокер: підтвердити, що алерт `VictoriaMetricsDown` справді critical і коректно працює при падінні VictoriaMetrics.
- **Change:**
	- Оновлено `grafana/provisioning/alerting/alert-rules.yml` для правила `victoriametrics-down`:
		- `noDataState: NoData` (щоб уникнути false-positive у healthy стані);
		- `execErrState: Alerting` (щоб алерт спрацьовував при повній недоступності datasource).
	- Оновлено `docs/ROADMAP.md`: пункт Phase 5 про `VictoriaMetricsDown` позначено як виконаний.
- **Verification:**
	- Перевірено runtime API правила:
		- `title=VictoriaMetricsDown`, `severity=critical`, `for=2m`, `noDataState=NoData`, `execErrState=Alerting`.
	- Проведено контрольований outage test:
		- `docker compose stop victoriametrics` -> після вікна оцінки алерт `VictoriaMetricsDown` переходить в `active`.
		- `docker compose start victoriametrics` -> після recovery/evaluation алерт очищається (active count -> `0`).
- **Risks:** Під час ручного outage test зупинка `victoriametrics` може тимчасово згенерувати `DatasourceError` для інших правил (очікувана поведінка під час тесту).
- **Rollback:** Повернути попередні `noDataState/execErrState` у `grafana/provisioning/alerting/alert-rules.yml` і виконати `docker compose restart grafana`.

## [2026-03-11] — Documentation: SAD + Tech Stack/Infrastructure overview

- **Context:** Потрібно сформувати детальні проектні документи в `docs/` на базі вже наявних артефактів (roadmap, architecture, deployment, security, alerting).
- **Change:**
	- Додано `docs/system-architecture-document.md` (System Architecture Document, SAD).
	- Додано `docs/tech-stack-infrastructure-overview.md` (огляд стеку та інфраструктури).
	- Документи синхронізовано з поточною реалізацією у `docker-compose.yml`, `docs/ROADMAP.md`, `docs/architecture/*`, `docs/deployment/*`, `docs/security/*`, `docs/alerting/*`.
- **Verification:**
	- Перевірено наявність файлів у `docs/`.
	- Контент не вводить нових архітектурних рішень, а консолідує вже затверджені у репозиторії.
- **Risks:** Можливе часткове застарівання деталей при майбутніх змінах compose/provisioning без оновлення цих документів.
- **Rollback:** Видалити додані файли або відкотити коміт із документацією.

## [2026-03-15] — README sync after ingress/network migration

- **Context:** Після міграції на центральний Traefik і видалення in-repo tunnel README містив застарілі описи (`cloudflared`, tunnel token, старі назви external networks).
- **Change:** Оновлено `README.md`:
	- у розділах Architecture/Security замінено модель доступу з in-repo Cloudflare Tunnel на central Traefik (`proxy-net`).
	- у таблиці сервісів прибрано `cloudflared`.
	- у prerequisites і `.env` секціях синхронізовано мережі/змінні (`proxy-net`, `koha-deploy_kohanet`, `dspace9_dspacenet`, `CLOUDFLARE_GRAFANA_HOSTNAME`).
	- у scrape jobs прибрано неактуальний `blackbox-dspace` рядок.
- **Verification:** README не містить застарілих посилань на `cloudflared`/`CLOUDFLARE_TUNNEL_TOKEN` і відповідає поточному `docker-compose.yml`/provisioning.
- **Risks:** Документаційна зміна без runtime-впливу.
- **Rollback:** Повернути попередню версію `README.md` з Git history.

## [2026-03-15] — CI/CD hardening: robust targets checks in deploy workflow

- **Context:** GitHub Actions CD періодично падав на кроці `---- targets checks ----` після успішних health checks через ламку текстову перевірку `curl /targets | grep ...`.
- **Change:** Оновлено `.github/workflows/deploy-monitoring.yml`:
	- замінено текстовий `grep` по `http://127.0.0.1:8428/targets` на JSON-перевірку `http://127.0.0.1:8428/api/v1/targets` через `jq`;
	- додано retry-loop `wait_for_targets_up 18 5` для транзитного стану після рестарту контейнерів;
	- додано діагностичний вивід `scrapeUrl/health/lastError` при невдалій спробі.
- **Verification:** Workflow скрипт тепер проходить targets-check лише коли `node-exporter` і `victoriametrics` мають `health=up`, та не падає на коротких race conditions після deploy.
- **Risks:** Потрібна наявність `jq` на remote host (використовувався і раніше в інших перевірках проєкту).
- **Rollback:** Повернути попередній блок `targets checks` з `grep` у `.github/workflows/deploy-monitoring.yml`.

## [2026-03-15] — Compose drift recovery: restore `proxy-net`, remove `cloudflared`

- **Context:** У робочому `docker-compose.yml` випадково повернувся сервіс `cloudflared`, зникла мережа `proxy-net`, і Grafana втратила Traefik labels/підключення до central ingress.
- **Change:**
	- Оновлено `docker-compose.yml`:
		- видалено сервіс `cloudflared`;
		- повернуто `proxy-net` в секцію `networks` (external `${PROXY_NET_NETWORK_NAME}`);
		- `grafana` знову підключена до `monitoring_net + proxy-net` і має Traefik labels;
		- `victoriametrics` знову підключено до `proxy-net` (для scrape `traefik:8082`) і збережено `--maxLabelsPerTimeseries=100`.
	- Оновлено `.env.example`:
		- прибрано `CLOUDFLARED_IMAGE`/`CLOUDFLARE_TUNNEL_TOKEN`;
		- додано `PROXY_NET_NETWORK_NAME=proxy-net`;
		- `DSPACENET_NETWORK_NAME` вирівняно до `dspace9_dspacenet`.
- **Verification:** `docker compose config -q` проходить; `docker compose up -d --remove-orphans` видаляє reintroduced `cloudflared` і застосовує мережеву модель з central Traefik.
- **Risks:** Якщо external network `proxy-net` відсутня на хості, старт `grafana`/`victoriametrics` завершиться помилкою до створення мережі.
- **Rollback:** Тимчасово прибрати `proxy-net` зі сервісів/мереж у `docker-compose.yml` і повернути попередню версію файлу з Git history.

## [2026-03-15] — Grafana UX fix: Traefik panels + folder duplication

- **Context:**
	- На дашборді `KDI Traefik v3 Overview` не відображались дані в панелях `Apdex score` та `Most requested services`.
	- Після рестартів Grafana знову з'являлися зайві папки `KDI`.
- **Change:**
	- Оновлено `grafana/dashboards/traefik-v3-official-17346.json`:
		- `Apdex score`: переведено з `entrypoint` latency-метрик на `service` latency-метрики (фактично присутні у вашому Traefik scrape), та прибрано жорсткий фільтр `code="200"`.
		- `Most requested services`: спрощено PromQL (без `label_replace` і булевого `> 0`) для надійного відображення топу сервісів.
		- Змінні dashboard:
			- `entrypoint`: джерело змінено на `traefik_entrypoint_requests_total` з виключенням `metrics|traefik`, додано `allValue`.
			- `service`: додано `allValue` для стабільної all-вибірки docker-сервісів.
	- Уніфіковано provisioning folder path до `KDI-P0` у файлах:
		- `grafana/provisioning/dashboards/dashboards.yml`
		- `grafana/provisioning/alerting/alert-rules.yml`
		- `grafana/provisioning/alerting/backup-alerts.yml`
		- `grafana/provisioning/alerting/synthetic-alerts.yml`
		- `grafana/provisioning/alerting/website-alerts.yml`
- **Verification:** Після рестарту Grafana дашборд Traefik отримує дані для проблемних панелей; у `GET /api/folders` залишається одна цільова папка `KDI-P0`.
- **Risks:** Потрібно синхронно тримати однакову назву folder у dashboard/alerting provisioning; розсинхрон поверне дублікати.
- **Rollback:** Повернути попередні версії dashboard JSON/provisioning YAML з Git history і перезапустити `grafana`.

## [2026-03-19] — Phase 6 (Matomo Monitoring): Крок 1 — HTTP probe (Blackbox)

- **Context:** Запуск нової фази моніторингу **Matomo Analytics**: збір метрик вебзахисту, поточність резервних копій та health перевірок. Крок 1 — налаштування базового HTTP probe доступності Matomo.
- **Change:**
	- Оновлено `victoria-metrics/scrape-config.yml`:
		- додано новий scrape job `blackbox-matomo`:
			- target: `https://matomo.pinokew.buzz`
			- модуль: `http_tls` (перевірка TLS + HTTP 2xx status)
			- labels: `env=prod`, `service=matomo`, `website=analytics`
			- relabel config за аналогією з існуючими Koha website проbes
	- Перезапущено VictoriaMetrics (`docker compose restart victoriametrics`)
- **Verification:**
	- `curl -s http://127.0.0.1:8428/targets | grep blackbox-matomo` → `(1/1 up)`
	- `curl -s http://127.0.0.1:8428/api/v1/query?query=probe_success` включає метрику з labels `job="blackbox-matomo"` та value `"1"` (успіх)
	- Interval scrape: 15s, жодних errors у логах: `docker compose logs victoriametrics | tail -50`
- **Risks:** Якщо `https://matomo.pinokew.buzz` стає недоступною, метрика повернеться до `"0"` та активуватиме alert (коли буде налаштовано на Кроку 4).
- **Rollback:** Видалити блок `blackbox-matomo` з `scrape-config.yml` і виконати `docker compose restart victoriametrics`.
## [2026-03-19] — Phase 6 (Matomo Monitoring): Крок 1+ — Alert на availability (MatomoDown)

- **Context:** Завершення Кроку 1 — додання alert правила для моніторингу доступності Matomo. Alert повинна спрацювати якщо `probe_success` = 0 > 5 хвилин.
- **Change:**
- Додано alert rule `MatomoDown` до групи `phase4-website-alerting` у файлі `grafana/provisioning/alerting/website-alerts.yml`
- Вираз: бере метрику `probe_success` для Matomo (job="blackbox-matomo") та перевіряє чи value < 1
- Період оцінки: `for: 5m` (alert спрацює якщо умова істинна 5 хвилин)
- Severity: `critical` (критичний, тому що Matomo - це основний analytic сервіс)
- Annotations: summary і description з посиланням на runbook `docs/runbooks/matomo-down.md`
- **Verification (тест проведено):**
- Додано тимчасовий тестовий target `https://matomo-test-fail.invalid` до scrape-config.yml для спровокування failure
- Знижено `for` на `1m` для швидкого тесту (замість 5m)
- Перезапущено VictoriaMetrics и Grafana
- У логах Grafana побачено: `rule_uid=matomo-down org_id=1 ... "Sending alerts to local notifier" count=1` ✅
- Alert успішно спрацьовує повторно кожні хвилини на failed probe
- **Cleanup (після тесту):**
- Видалено тестовий target з `scrape-config.yml`
- Повернуто оригінальне `for: 5m` (замість 1m)
- Перевірено: `curl http://127.0.0.1:8428/targets | grep blackbox-matomo` → `(1/1 up)` з одним валідним target
- **Risks:** 
- Alert у браузинговому стані (OK, не firing) поки Matomo доступна
- При недоступності > 5m → critical alert + notification до contact points (MS365 Email)
- **Rollback:** Видалити alert блок з `website-alerts.yml` і перезапустити `docker compose restart grafana`

## [2026-03-19] — Phase 6 (Matomo Monitoring): render-шаблон + MATOMO_URL в env

- **Context:** Потрібно уніфікувати генерацію `scrape-config.yml` через шаблон та скрипт рендеру, щоб Matomo URL брався з env.
- **Change:**
	- Оновлено `victoria-metrics/scrape-config.tmpl.yml`: додано `blackbox-matomo` job з placeholder `__MATOMO_URL__`.
	- Оновлено `scripts/render-scrape-config.sh`: додано читання/валідацію `MATOMO_URL` і підстановку `__MATOMO_URL__`.
	- Оновлено `.env.example`: додано `MATOMO_URL=https://matomo.pinokew.buzz`.
	- Оновлено локальний `.env`: додано `MATOMO_URL=https://matomo.pinokew.buzz`.
- **Verification:**
	- `./scripts/render-scrape-config.sh` виконується успішно.
	- У згенерованому `victoria-metrics/scrape-config.yml` присутні:
		- `job_name: blackbox-matomo`
		- `https://matomo.pinokew.buzz`
- **Risks:** Якщо `MATOMO_URL` відсутній або не починається з `http://`/`https://`, рендер скриптом блокується (очікувана поведінка).
- **Rollback:** Відкотити зміни у шаблоні/скрипті/env та повторно згенерувати `scrape-config.yml`.

## [2026-03-19] — Phase 6 (Matomo Monitoring): Крок 2 — Koha/Matomo MariaDB dashboards + alerts

- **Context:** Потрібно розділити MariaDB observability для Koha і Matomo: окремі дашборди та окремі alert rules без змішування.
- **Change:**
	- Dashboards:
		- Перейменовано `grafana/dashboards/mariadb-overview-7362.json` → title `KDI Koha-MariaDB Overview`.
		- Додано новий дашборд `grafana/dashboards/matomo-mariadb-overview-7362.json` з title `Matomo MariaDB Overview`, uid `kdi-matomo-mariadb-overview`.
		- Для обох дашбордів змінна `host` тепер фільтрується по `service`:
			- Koha: `label_values(mysql_up{service="koha",component="db"}, instance)`
			- Matomo: `label_values(mysql_up{service="matomo",component="db"}, instance)`
	- Exporter/metrics path:
		- Додано сервіс `matomo-mariadb-exporter` у `docker-compose.yml`.
		- Додано external network `matomonet` (`MATOMO_NETWORK_NAME`).
		- Додано env-шаблонні змінні для Matomo exporter у `.env.example`.
		- Додано scrape job `matomo-mariadb-exporter` у `victoria-metrics/scrape-config.tmpl.yml` і перерендерено `scrape-config.yml`.
	- Alerts (rename + add):
		- Перейменовано Koha alerts:
			- `MariaDBDown` → `KohaMariaDBDown`
			- `MariaDBConnectionsHigh` → `KohaMariaDBConnectionsHigh`
		- Додано Matomo alerts:
			- `MatomoMariaDBDown`
			- `MatomoMariaDBConnectionsHigh`
		- Оновлено обидва джерела правил: `alerting/rules/databases.yml` і `grafana/provisioning/alerting/alert-rules.yml`.
	- Оновлено документацію каталогів дашбордів:
		- `grafana/dashboards/README.md`
		- `docs/dashboards/dashboard-catalog.md`
- **Verification:**
	- `./scripts/render-scrape-config.sh` → успішно.
	- `docker compose config -q` → успішно.
	- `curl http://127.0.0.1:8428/targets` показує `job=matomo-mariadb-exporter (1/1 up)`.
	- YAML валідний для `alerting/rules/databases.yml` та `grafana/provisioning/alerting/alert-rules.yml`.
	- `mysql_up`:
		- Koha: `1`
		- Matomo: `0` (потрібні коректні credentials/read-only user для exporter).
- **Risks:** Matomo DB alert `MatomoMariaDBDown` буде firing, доки `mysql_up` для Matomo не стане `1`.
- **Rollback:** Відкотити зміни у `docker-compose.yml`, scrape template, dashboards і alert rules + `docker compose up -d`.

## [2026-03-19] — Phase 6 (Matomo Monitoring): Matomo MariaDB read-only user + mysql_up=1
- **Context:** Після додавання `matomo-mariadb-exporter` метрика `mysql_up{service="matomo"}` була `0`; потрібна робоча read-only авторизація.
- **Change:**
- У контейнері `matomo-db` створено/оновлено користувача `metrics_reader@%`.
- Надано права: `PROCESS`, `REPLICATION CLIENT`, `SELECT` (read-only для exporter).
- Оновлено локальні runtime-змінні exporter у `.env`: `MATOMO_MARIADB_EXPORTER_USER`, `MATOMO_MARIADB_EXPORTER_PASSWORD`, `MATOMO_MARIADB_EXPORTER_TARGET`.
- Перезапущено `matomo-mariadb-exporter` та `victoriametrics`.
- **Verification:**
- `curl http://127.0.0.1:8428/targets` → `job=matomo-mariadb-exporter (1/1 up)`.
- `curl .../api/v1/query?query=mysql_up{job="matomo-mariadb-exporter",service="matomo"}` → value `1`.
- Локально у exporter `/metrics` присутній `mysql_up 1`.
- **Risks:** У логах exporter можливі попередження по `slave_status` (не впливає на `mysql_up=1`).
- **Rollback:** Видалити/відкликати `metrics_reader` у Matomo MariaDB, повернути попередні runtime env exporter, перезапустити compose.
