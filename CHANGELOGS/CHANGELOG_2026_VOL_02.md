# CHANGELOG 2026 VOL 02

## [2026-03-09] — Rotation: старт нового тому changelog

- **Context:** `CHANGELOG_2026_VOL_01.md` досяг soft limit `300` рядків згідно політики ротації.
- **Change:** Створено новий активний том `CHANGELOGS/CHANGELOG_2026_VOL_02.md`.
- **Verification:** Перевірено наявність нового файлу в `CHANGELOGS/`.
- **Risks:** Відсутні (організаційна зміна, без впливу на runtime).
- **Rollback:** Видалити новий том і повернути `VOL_01` як active в `CHANGELOG.md`.

## [2026-03-09] — Phase 4 старт: critical alerting as code

- **Context:** Розпочато `Phase 4 — Critical Alerting` (P0) з роадмапи: потрібні alert rules, routing та runbooks у Git.
- **Change:**
	- Додано каталог правил `alerting/rules/`: `host.yml`, `containers.yml`, `databases.yml`, `traefik.yml`, `monitoring.yml`.
	- Додано Grafana provisioning для alerting: `grafana/provisioning/alerting/contact-points.yml`, `notification-policies.yml`, `alert-rules.yml`.
	- Додано документацію: `docs/alerting/alert-rules-catalog.md`.
	- Додано runbooks: `docs/runbooks/high-cpu.md`, `high-memory.md`, `disk-space-low.md`, `container-down.md`, `database-connections-high.md`, `monitoring-down.md`.
	- Оновлено SMTP-параметри Grafana у `docker-compose.yml` та `.env.example` (`GRAFANA_SMTP_ENABLED`, `MS365_ALERT_FROM_NAME`).
- **Verification:** Виконано `docker compose config`, `docker compose restart grafana`, `docker compose logs grafana` — Grafana стартує, provisioning alerting завантажується.
- **Risks:**
	- Формат provisioning alert rules у Grafana чутливий до схеми; можливе ручне доопрацювання полів `model` під конкретну версію Grafana.
	- Для уникнення crash-loop на порожніх env, contact points тимчасово мають placeholders (`alerts@example.com`, тестовий Telegram token/chat id) і потребують заміни перед go-live.
- **Rollback:** `git revert <commit>` + `docker compose up -d`.

## [2026-03-09] — Phase 4: synthetic email-only smoke test

- **Context:** Потрібно перевірити доставку alertів тільки через email канал без ручного UI.
- **Change:**
	- Додано provisioning-файл `grafana/provisioning/alerting/synthetic-alerts.yml` з правилом `SyntheticEmailSmoke`.
	- Для тесту правило тимчасово було в активному стані (`vector(1)`), після перевірки повернуто в пасивний (`vector(0)`).
	- Маркування правила: `severity=warning`, щоб маршрут був тільки `warning-email`.
- **Verification:**
	- `docker compose up -d --force-recreate grafana`
	- У логах зафіксовано `rule_uid=synthetic-email-smoke` і відправку в local notifier.
	- SMTP runtime у Grafana активний (`GF_SMTP_ENABLED=true`), помилки `SMTP not configured` для synthetic warning після перевідтворення контейнера не з'явились.
- **Risks:**
	- Частина critical alertів може показувати помилки Telegram, якщо зовнішній доступ до API Telegram обмежений.
- **Rollback:** Видалити `grafana/provisioning/alerting/synthetic-alerts.yml` + `docker compose up -d --force-recreate grafana`.

## [2026-03-09] — Fix: `Disk Space Used Basic` (KDI Host Overview) показував `No data`

- **Context:** На дашборді `KDI Host Overview` панель `Disk Space Used Basic` була без даних.
- **Change:**
	- Оновлено `node-exporter` runtime конфіг у `docker-compose.yml`:
		- додано `--path.procfs=/host/proc` і `--path.sysfs=/host/sys`
		- додано маунти `/proc:/host/proc:ro`, `/sys:/host/sys:ro`
		- додано `--collector.filesystem.mount-points-exclude=^/(dev|proc|run($|/.*)|sys|var/lib/docker($|/.*)|var/lib/containers/storage($|/.*))`
	- Оновлено `.env.example`: `NODE_EXPORTER_IMAGE=quay.io/prometheus/node-exporter:v1.9.1`.
- **Verification:**
	- `curl http://127.0.0.1:9100/metrics` повертає `node_filesystem_size_bytes`/`node_filesystem_avail_bytes`.
	- `up{job="node-exporter"}=1`.
	- Запит панелі повертає серії для mountpoints `/` і `/boot/efi`.
- **Risks:**
	- Якщо в shell експортована змінна `NODE_EXPORTER_IMAGE`, вона має пріоритет над `.env` і може запустити іншу версію image.
- **Rollback:** Повернути попередні значення `docker-compose.yml`/`.env` для `node-exporter`, далі `docker compose up -d --force-recreate node-exporter`.

## [2026-03-10] — Cleanup: прибрано шумові папки `KDI` у Grafana Dashboards

- **Context:** У Dashboards з'являлись численні технічні папки `KDI` з вкладеним `Alerting`, що створювало інформаційний шум.
- **Change:**
	- Для alerting provisioning змінено folder mapping на пласку папку `Alerting` (без шляху `KDI / Alerting`):
		- `grafana/provisioning/alerting/alert-rules.yml`
		- `grafana/provisioning/alerting/synthetic-alerts.yml`
	- Через Grafana API видалено дублікати папок з назвою `KDI`, включно з останньою non-empty папкою через `forceDeleteRules=true`.
- **Verification:**
	- `GET /api/folders` -> залишилась тільки `KDI / P0`.
	- У логах Grafana: `starting to provision alerting` -> `finished to provision alerting`.
- **Risks:** Низькі; зміна стосується організації папок, не метрик scrape.
- **Rollback:** Повернути попередні `folder` значення у provisioning і перезапустити Grafana.

## [2026-03-10] — Alert contact points: прибрано хардкод контактів

- **Context:** Потрібно виключити потрапляння контактних даних у Git та дозволити кілька email-адрес для алертів.
- **Change:**
	- `grafana/provisioning/alerting/contact-points.yml` переведено на env-змінні для email:
		- `addresses: ${MS365_ALERT_EMAIL_TO}`
	- `critical-email-telegram` тимчасово залишено email-only (без telegram receiver), щоб Grafana не падала, коли Telegram вимкнений/недоступний.
	- У `.env.example` додано приклад множинних адрес:
		- `MS365_ALERT_EMAIL_TO=ops@example.com,devops@example.com`
- **Verification:** `docker compose up -d --force-recreate grafana`; у логах: `starting to provision alerting` -> `finished to provision alerting`.
- **Risks:** Після повернення Telegram receiver потрібно перевірити валідність `TELEGRAM_*` змінних перед рестартом Grafana.
- **Rollback:** Повернути попередній `contact-points.yml` з хардкодом/Telegram і перевідтворити Grafana.

## [2026-03-10] — Phase 4: додано Blackbox Exporter для перевірки Koha сайтів

- **Context:** Traefik метрики не покривають зовнішню доступність Koha OPAC/Staff у поточній мережевій топології.
- **Change:**
	- Додано сервіс `blackbox-exporter` у `docker-compose.yml` (internal-only, без публікації порту).
	- Додано конфіг `blackbox/blackbox.yml` з модулями `http_2xx` і `http_tls`.
	- Додано scrape jobs у `victoria-metrics/scrape-config.yml`:
		- `blackbox-koha-opac`
		- `blackbox-koha-staff`
	- Додано provisioning rules `grafana/provisioning/alerting/website-alerts.yml`:
		- `WebsiteDown` (critical)
		- `WebsiteHighLatency` (warning)
	- Додано runbook `docs/runbooks/website-probe.md` і оновлено документацію.
- **Verification:**
	- `docker compose up -d --force-recreate blackbox-exporter victoriametrics grafana`
	- `/targets` показує `blackbox-koha-opac` і `blackbox-koha-staff` у `UP`
	- Присутні метрики `up{job=~"blackbox-koha-opac|blackbox-koha-staff"}` та `probe_success{...}`
- **Risks:**
	- За замовчуванням у scrape-config задані прикладні URL (`opac.example.com`, `staff.example.com`), потрібно замінити на реальні Koha URL, інакше `WebsiteDown` може спрацьовувати постійно.
- **Rollback:** Видалити blackbox jobs/rules/service, далі `docker compose up -d --force-recreate victoriametrics grafana`.

## [2026-03-10] — Fix: шаблонізація scrape-config без хардкоду URL

- **Context:** `${KOHA_OPAC_URL}`/`${KOHA_STAFF_URL}` у `scrape-config.yml` не інтерполюються VictoriaMetrics і залишаються literal значеннями.
- **Change:**
	- Додано шаблон `victoria-metrics/scrape-config.tmpl.yml` з маркерами `__KOHA_OPAC_URL__` і `__KOHA_STAFF_URL__`.
	- Додано скрипт `scripts/render-scrape-config.sh` для генерації `victoria-metrics/scrape-config.yml`.
	- Скрипт читає `KOHA_OPAC_URL`/`KOHA_STAFF_URL` з env або з `.env`, валідуючи формат `http(s)://`.
	- Оновлено `docs/deployment/monitoring-stack-deploy.md` з кроком рендеру перед `docker compose up -d`.
- **Verification:**
	- `./scripts/render-scrape-config.sh`
	- `docker compose restart victoriametrics`
	- `/targets` показує resolved URL (`https://biblio...`, `https://library...`) для blackbox jobs.
- **Risks:** В історичних метриках можуть тимчасово лишатися старі серії з instance `${KOHA_*}` до завершення retention.
- **Rollback:** Повернути попередній `scrape-config.yml` і видалити template/script.
