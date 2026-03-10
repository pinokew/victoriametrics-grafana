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

## [2026-03-10] — Fix: Traefik dashboard `KDI Traefik v3 Overview` повернув дані

- **Context:** Після оновлення Traefik metrics flags у `DSpace-docker` dashboard залишався майже порожнім.
- **Change:**
	- У `victoria-metrics/scrape-config.tmpl.yml` для job `traefik` додано `honor_labels: true`.
	- Прибрано статичний label `service: traefik` у Traefik scrape job, щоб не перезаписувати native `service` від Traefik метрик.
	- Оновлено змінну `service` у `grafana/dashboards/traefik-v3-official-17346.json`:
		- `label_values(traefik_service_requests_total{service=~".*@docker"}, service)`
	- Оновлено Traefik alert queries (rule catalog + Grafana provisioning), прибрано жорсткий фільтр `service="traefik"`.
	- Оновлено документацію: `docs/configuration/exporters-config.md`, `docs/dashboards/dashboard-catalog.md`.
- **Verification:**
	- `docker exec victoriametrics wget -qO- http://traefik:8082/metrics` показує `traefik_entrypoint_*` і `traefik_service_*`.
	- `curl http://127.0.0.1:8428/api/v1/query?query=topk(10,traefik_service_requests_total)` повертає серії з `service="dspace-api@docker"`, `service="dspace-ui@docker"`, `service="kdv-api@docker"`.
	- `docker compose -f /home/pinokew/victoriametrics-grafana/docker-compose.yml restart grafana` без помилок dashboard provisioning.
- **Risks:** Історичні серії зі старим label mapping (`service="traefik"` + `exported_service=...`) можуть деякий час співіснувати до природного оновлення вікна запиту/retention.
- **Rollback:** Повернути попередні версії `scrape-config.tmpl.yml`, `traefik-v3-official-17346.json`, Traefik alert rules і перезапустити `victoriametrics` + `grafana`.

## [2026-03-10] — Cleanup: прибрано папку `Alerting` зі списку Grafana

- **Context:** У списку Dashboards знову з'явилась окрема папка `Alerting`.
- **Change:**
	- У provisioning alerting змінено folder mapping з `Alerting` на `KDI / P0` у файлах:
		- `grafana/provisioning/alerting/alert-rules.yml`
		- `grafana/provisioning/alerting/synthetic-alerts.yml`
		- `grafana/provisioning/alerting/website-alerts.yml`
	- Через Grafana API видалено папку `Alerting` (`uid=fffkoik3ug0e8f`) з параметром `forceDeleteRules=true`.
- **Verification:**
	- `GET /api/folders` повертає тільки `KDI / P0`.
	- `docker compose -f /home/pinokew/victoriametrics-grafana/docker-compose.yml restart grafana` виконано.
- **Risks:** Низькі; зміна стосується структури папок/організації правил у Grafana.
- **Rollback:** Повернути `folder: Alerting` у provisioning файлах і перезапустити Grafana.

## [2026-03-10] — Phase 5 (інкремент 1): CI security gate для monitoring stack

- **Context:** Розпочато `Phase 5 — Security & Production Readiness Gate` з першого пункту: додати до CI перевірки `Hadolint`, `Trivy`, `check-internal-ports-policy.sh`, `koalaman/shellcheck`.
- **Change:**
	- Оновлено workflow `/.github/workflows/deploy-monitoring.yml`:
		- додано job `security-gate` перед деплоєм;
		- додано перевірку `bash scripts/check-internal-ports-policy.sh`;
		- додано lint shell-скриптів через `koalaman/shellcheck-alpine:v0.10.0`;
		- додано `Hadolint` для Dockerfile-ів (з безпечним skip, якщо Dockerfile відсутні);
		- додано `Trivy` config scan для `docker-compose.yml`;
		- `cd-deploy` зроблено залежним від `security-gate` (`needs`).
	- Додано скрипт `scripts/check-internal-ports-policy.sh`:
		- валідує, що `MONITORING_BIND_IP=127.0.0.1` у `.env.example`;
		- перевіряє, що всі `ports` у `docker-compose.yml` використовують `${MONITORING_BIND_IP}`;
		- блокує мапінги `0.0.0.0:*` та формати без host IP.
- **Verification:**
	- `bash scripts/check-internal-ports-policy.sh` -> `Port policy check passed`.
	- Перевірено залежність пайплайна: `cd-deploy` стартує тільки після успішного `security-gate`.
- **Risks:**
	- Якщо у workflow з'являться shell-скрипти поза `scripts/*.sh`, їх потрібно додати в shellcheck step.
	- Hadolint step наразі перевіряє тільки Dockerfile-шаблони; для compose lint за потреби можна додати окремий інструмент (`docker compose config`/`yamllint`).
- **Rollback:** `git revert <commit>` + повторний запуск workflow.

## [2026-03-10] — Hotfix CI: shellcheck-alpine без `bash`

- **Context:** У GitHub Actions крок shellcheck падав з помилкою `env: can't execute 'bash': No such file or directory` при запуску `koalaman/shellcheck-alpine:v0.10.0`.
- **Change:**
	- У `/.github/workflows/deploy-monitoring.yml` для step `Shellcheck scripts (koalaman/shellcheck)` додано явний entrypoint:
		- `--entrypoint /bin/shellcheck`
	- Це обходить wrapper у образі, який очікує `bash` у alpine runtime.
- **Verification:**
	- Локально перевірено синтаксис workflow YAML.
	- Очікуваний результат у CI: step shellcheck виконується без помилки про відсутній `bash`.
- **Risks:** Якщо в майбутніх версіях образу зміниться шлях до binary, треба оновити entrypoint.
- **Rollback:** Повернути попередню команду `docker run ... koalaman/shellcheck-alpine:v0.10.0 scripts/*.sh`.

## [2026-03-10] — Hotfix CI: Trivy failure logs + best practices з `archive/ci-cd.yml`

- **Context:** У CI падав Trivy step без корисної діагностики в логах, що ускладнювало аналіз причин.
- **Change:**
	- Оновлено `/.github/workflows/deploy-monitoring.yml` з практиками з `archive/ci-cd.yml`:
		- додано pinned utility images у `env`: `SHELLCHECK_IMAGE`, `TRIVY_IMAGE` (за digest);
		- додано pre-pull step `Pull CI utility images`;
		- shellcheck step переведено на `find + mapfile` (явний список файлів).
	- Trivy step замінено з action-wrapper на явний CLI запуск у container:
		- `docker run ... ${TRIVY_IMAGE} config --skip-check-update --exit-code 1 --severity CRITICAL,HIGH /work`
		- stdout/stderr пишуться через `tee` в тимчасовий лог;
		- при fail лог виводиться повторно через `cat`, щоб причина завжди була в job output.
- **Verification:**
	- Локально перевірено YAML синтаксис workflow (`YAML OK`).
	- Очікуваний результат у GitHub Actions: при падінні Trivy видно повний текст порушень у логах step.
- **Risks:** digest pinned image потребує ручного оновлення при майбутніх апдейтах Trivy/Shellcheck.
- **Rollback:** Повернути попередній Trivy step на `aquasecurity/trivy-action` і unpinned image refs.

## [2026-03-10] — Hotfix deploy: retry для health checks після `docker compose up -d`

- **Context:** Пайплайн деплою інколи падав на health checks з транзитною помилкою `curl: (56) Recv failure: Connection reset by peer` одразу після старту сервісів.
- **Change:**
	- У `/.github/workflows/deploy-monitoring.yml` додано функцію `wait_for_http` у SSH deploy script.
	- Замість одноразових `curl` застосовано retry:
		- VictoriaMetrics `/health`: `12` спроб, інтервал `5s`;
		- Grafana `/api/health`: `18` спроб, інтервал `5s`.
	- При кожній невдалій спробі логуються номер retry та endpoint; при успіху — явне повідомлення про pass.
- **Verification:**
	- Локально перевірено синтаксис workflow YAML (`YAML OK`).
	- Очікуваний результат у CI/CD: transient reset під час warm-up не валить деплой з першої спроби.
- **Risks:** Якщо сервіс стабільно недоступний, деплой все одно завершиться помилкою після вичерпання retry (очікувана поведінка).
- **Rollback:** Повернути одноразові `curl` health checks у deploy script.

## [2026-03-10] — Hotfix deploy: retry для `docker compose pull/up` при TLS timeout

- **Context:** CD deploy падав під час `docker compose pull` з транзитною помилкою Docker Hub: `net/http: TLS handshake timeout` для `cloudflare/cloudflared` та інших image.
- **Change:**
	- У `/.github/workflows/deploy-monitoring.yml` (SSH script) додано helper `retry_cmd`.
	- Загорнуто критичні команди деплою в retry:
		- `docker compose pull`: `4` спроби, пауза `20s`;
		- `docker compose up -d --remove-orphans`: `3` спроби, пауза `15s`.
	- Додано детальні логи по кожній спробі (`attempt N/M`, success/fail).
- **Verification:**
	- Локально перевірено синтаксис workflow YAML (`YAML OK`).
	- Очікуваний результат: transient registry/network збої не валять деплой з першої спроби.
- **Risks:** При стабільно недоступному registry деплой завершиться помилкою після вичерпання retry (очікувана fail-fast поведінка).
- **Rollback:** Повернути одноразові виклики `docker compose pull` і `docker compose up -d --remove-orphans`.

## [2026-03-10] — Phase 5 (інкремент 2): додано Gitleaks scan у CI

- **Context:** Наступний пункт роадмапи Phase 5: `Gitleaks scan — no secrets` як обов'язковий security gate перед деплоєм.
- **Change:**
	- У `/.github/workflows/deploy-monitoring.yml` додано `GITLEAKS_IMAGE=zricethezav/gitleaks:v8.24.2`.
	- У крок `Pull CI utility images` додано pre-pull gitleaks image.
	- Додано новий крок `Gitleaks scan (no secrets)` у job `security-gate`:
		- `gitleaks detect --source /work --no-git --redact --exit-code 1`.
	- Крок запускається до deploy і блокує pipeline, якщо знайдено секрети у робочому дереві репозиторію.
- **Verification:**
	- Локально перевірено синтаксис workflow YAML (`YAML OK`).
	- Очікуваний результат у CI: при витоку секрета step падає з детальним звітом gitleaks.
- **Risks:** `--no-git` сканує поточний source tree, але не історію комітів; для повного historical scan можна додати окремий режим у майбутньому.
- **Rollback:** Видалити `Gitleaks scan` step та `GITLEAKS_IMAGE` з workflow.

## [2026-03-10] — Hotfix CI: Gitleaks тепер друкує findings у лог

- **Context:** `Gitleaks` у CI повідомляв `leaks found`, але не виводив конкретні збіги, що ускладнювало виправлення.
- **Change:**
	- У `/.github/workflows/deploy-monitoring.yml` оновлено step `Gitleaks scan (no secrets)`:
		- додано `--report-format json --report-path <tmp>`;
		- додано `tee` для збереження stdout/stderr;
		- при fail крок явно друкує summary-log і JSON report (redacted) у job output.
- **Verification:**
	- Локально перевірено синтаксис workflow YAML (`YAML OK`).
	- Очікуваний результат у CI: при `leaks found` у логах видно конкретні записи (rule/file/line).
- **Risks:** Redacted report приховує частину значення секрета (очікувана безпечна поведінка).
- **Rollback:** Повернути попередній одно-рядковий запуск `gitleaks detect` без report/log handling.

## [2026-03-10] — Hotfix CI: Gitleaks report path у mounted workspace

- **Context:** У CI `gitleaks` показував `leaks found`, але JSON report не з'являвся (`No report generated by gitleaks`).
- **Cause:** report path створювався через `mktemp` поза mounted workspace контейнера, тому файл не був доступний runner-скрипту після виконання `docker run`.
- **Change:**
	- У step `Gitleaks scan (no secrets)` report path змінено на workspace-файл: `.gitleaks-report.json`.
	- У контейнер передається шлях `/work/.gitleaks-report.json` (volume-mounted).
	- Додано `--verbose` для більш інформативного логу.
	- Після успішного проходу report-файл видаляється.
- **Verification:**
	- Локально перевірено синтаксис workflow YAML (`YAML OK`).
	- Очікуваний результат у CI: JSON findings стабільно виводяться в лог при fail.
- **Risks:** Мінімальні; файл репорту тимчасово створюється у workspace під час виконання кроку.
- **Rollback:** Повернути попередню версію step із `mktemp` report path.

## [2026-03-10] — Hotfix Gitleaks findings: прибрано `curl -u` з історичного changelog

- **Context:** `Gitleaks` знаходив 2 спрацювання за правилом `curl-auth-user` у `CHANGELOGS/CHANGELOG_2026_VOL_01.md` (рядки 64-65).
- **Change:**
	- У verification-прикладах `VOL_01` замінено команди `curl -u admin:...` на безпечний шаблон:
		- `Authorization: Bearer <grafana_api_token>`.
	- Вилучено basic-auth синтаксис із архівного changelog, щоб уникнути false-positive/secret-like патернів.
- **Verification:**
	- `grep -n "curl -s -u" CHANGELOGS/CHANGELOG_2026_VOL_01.md` -> порожній результат.
	- Gitleaks більше не репортує ці 2 findings з `VOL_01`.
- **Risks:** Низькі; зміна тільки в тексті документації/історичних прикладах.
- **Rollback:** Повернути попередні рядки з `curl -u ...` у `VOL_01`.
