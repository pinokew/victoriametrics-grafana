# CHANGELOG 2026 VOL 01

## [2026-03-07] — Phase 0 старт: структура та ADR база

- **Context:** Старт `Phase 0 — Pre-Flight`, підготовка репозиторію до подальшого deployment етапу.
- **Change:** Створено каркас monitoring stack у корені репо (`docker-compose.yml`, `victoria-metrics/`, `grafana/`, `alerting/`, `exporters/`), додано `ADR-001..003`, створено `docs/architecture/monitoring-architecture.md` та `docs/architecture/ports-map.md`, ініціалізовано changelog-том.
- **Verification:** Перевірено наявність структури директорій та файлів; перевірено disk space (`df -h .`) — доступно 27G.
- **Risks:** Конфігураційні файли поки placeholder; фактичний deploy не виконано (очікується у Phase 1).
- **Rollback:** `git revert <commit>` після коміту змін.

## [2026-03-07] — Phase 1: Core Stack (VictoriaMetrics + Grafana + Node Exporter)

- **Context:** Початок `Phase 1 — Core Stack Deployment`, перехід від placeholder конфігів до робочого базового стеку.
- **Change:**
	- Заповнено `docker-compose.yml` сервісами `victoriametrics`, `grafana`, `node-exporter` з портами тільки `127.0.0.1`.
	- Додано retention через `VM_RETENTION_PERIOD` (з дефолтом `90d`) і `restart: unless-stopped` для ключових сервісів.
	- Увімкнено базові security-параметри Grafana (`GF_AUTH_ANONYMOUS_ENABLED=false`, admin credentials через `.env`).
	- Оновлено `victoria-metrics/scrape-config.yml` (self-scrape + node-exporter) з label schema `env/service`.
	- Додано provisioning datasource: `grafana/provisioning/datasources/victoriametrics.yml`.
	- Додано `docs/deployment/monitoring-stack-deploy.md` та каталог `grafana/provisioning/plugins/`.
- **Verification:**
	- `docker compose -f docker-compose.yml config --quiet`
	- `docker compose -f docker-compose.yml up -d`
	- `docker compose -f docker-compose.yml ps` → сервіси `Up`
	- `curl -s http://127.0.0.1:8428/health` → `OK`
	- `curl -s http://127.0.0.1:3000/api/health` → `database: ok`
	- `curl -s http://127.0.0.1:8428/targets` → `victoriametrics` і `node-exporter` у стані `up`
	- `ss -tlnp | grep -E '8428|3000|9100|9104|9187|8081|9114|15692|5001'` → тільки `127.0.0.1`
	- `docker compose -f docker-compose.yml logs --since=2m | grep -Ei "error|fatal|panic"` → нових критичних помилок не виявлено
- **Risks:** Cloudflare Tunnel/Access та CI/CD інтеграція ще не налаштовані в межах цього кроку; перевірка доступності Grafana через SSO лишається відкритою.
- **Rollback:** `git revert <commit>` + `docker compose -f docker-compose.yml up -d`.

## [2026-03-07] — Phase 1 refactor: env-driven compose + rename

- **Context:** Уніфікація конфігурації стека: прибрати хардкод image/ports/paths і перейти на `docker-compose.yml`.
- **Change:**
	- `docker-compose.monitoring.yml` перейменовано в `docker-compose.yml`.
	- У `docker-compose.yml` винесено в `.env`:
	  - образи (`VICTORIAMETRICS_IMAGE`, `GRAFANA_IMAGE`, `NODE_EXPORTER_IMAGE`)
	  - порти та bind IP (`MONITORING_BIND_IP`, `*_HOST_PORT`, `*_INTERNAL_PORT`)
	  - шляхи постійних томів (`VM_DATA_DIR`, `GRAFANA_DATA_DIR`, `GRAFANA_LOGS_DIR`)
	  - мережа (`MONITORING_NETWORK_NAME`)
	- Додано обмеження пам'яті для VictoriaMetrics (`VM_MEMORY_LIMIT`, `VM_MEMORY_SWAP_LIMIT`).
	- Для node-exporter додано `pid: "host"`.
	- Додано явну мережу `monitoring_net` (через env-параметр).
	- `grafana/provisioning/datasources/victoriametrics.yml` переведено на env URL (`VM_DATASOURCE_URL`).
	- `.env.example` доповнено всіма новими змінними.
	- `.gitignore` доповнено `/.data` для локальних persistent volume директорій.
- **Verification:**
	- `docker compose --env-file .env.example -f docker-compose.yml config --quiet`
	- Перевірено відсутність прямого хардкоду image/ports у YAML сервіс-конфігах.
- **Risks:** Якщо локальний `.env` не містить нових змінних, `docker compose` не стартує; перед запуском потрібно синхронізувати `.env` з `.env.example`.
- **Rollback:** `git revert <commit>` + `docker compose -f docker-compose.yml up -d`.

## [2026-03-07] — Phase 1: CD pipeline + Grafana Explore verification

- **Context:** Закриття залишку задач `Phase 1` після базового запуску Core Stack.
- **Change:**
	- Додано workflow `/.github/workflows/deploy-monitoring.yml` для автоматичного деплою monitoring stack через GitHub Actions на `self-hosted` runner.
	- Workflow покриває: `docker compose pull`, `docker compose up -d`, health-check, targets-check, перевірку localhost-only портів.
	- Оновлено `docs/deployment/monitoring-stack-deploy.md` секцією CI/CD з вимогою локального `.env` на runner.
	- Оновлено `docs/ROADMAP.md`: відмічено виконаними пункти про CD pipeline та видимість метрик Node Exporter у Grafana Explore.
- **Verification:**
	- `curl -s -u admin:change_me_before_deploy http://127.0.0.1:3000/api/datasources/uid/victoriametrics`
	- `curl -s -u admin:change_me_before_deploy -H 'Content-Type: application/json' -X POST http://127.0.0.1:3000/api/ds/query -d '{... "expr":"node_uname_info" ...}'` → повертаються series з `job="node-exporter"`.
- **Risks:** Автодеплой у GitHub Actions працює тільки після підключення self-hosted runner і наявності коректного `.env` на runner.
- **Rollback:** `git revert <commit>` + видалення workflow файлу.

## [2026-03-07] — CD strategy update: Tailscale Ephemeral Auth Key

- **Context:** Оновлення стратегії CD: відмова від `self-hosted` execution у GitHub Actions на користь підключення до target host через Tailscale ephemeral auth key.
- **Change:**
	- Переписано `.github/workflows/deploy-monitoring.yml` за еталоном `archive/ci-cd.yml` (CD-only логіка):
	  - `runs-on: ubuntu-latest`
	  - `tailscale/github-action@v4`
	  - deploy через `appleboy/ssh-action@v1.2.5`
	  - валідація deploy secrets + SemVer для tag deploy
	  - remote `docker compose pull && up -d --remove-orphans` + health/targets/ports checks
	- Оновлено `docs/deployment/monitoring-stack-deploy.md` та `docs/ROADMAP.md` під нову модель CD.
- **Verification:**
	- Локально перевірено синтаксис workflow та відсутність compile errors.
	- Логіка deploy кроків узгоджена зі структурою та business flow еталонного `archive/ci-cd.yml`.
- **Risks:** Пайплайн залежить від коректних GitHub secrets і доступності target host через Tailscale/SSH.
- **Rollback:** `git revert <commit>` для workflow і документації.

## [2026-03-08] — Phase 2 старт: P0 exporters configuration

- **Context:** Початок `Phase 2 — Exporters`, перехід від базового scrape до повного набору P0 targets.
- **Change:**
	- Оновлено `docker-compose.yml`: додано `cadvisor`, `mariadb-exporter`, `postgres-exporter`.
	- DB exporters винесені в profile `phase2-db` та підключені до `monitoring_net` + external networks `${KOHANET_NETWORK_NAME}` / `${DSPACENET_NETWORK_NAME}`.
	- Оновлено `victoria-metrics/scrape-config.yml`: додано jobs `cadvisor`, `mariadb-exporter`, `postgres-exporter`, `traefik` з label schema.
	- Розширено `.env.example` змінними image/ports/networks для P0 exporters.
	- Додано документацію: `docs/configuration/exporters-config.md`, `docs/security/db-exporter-users.md`, оновлено `exporters/README.md`.
- **Verification:**
	- `docker compose --env-file .env.example -f docker-compose.yml config --quiet`
	- `docker compose --env-file .env.example -f docker-compose.yml up -d cadvisor`
	- `curl -s http://127.0.0.1:8428/targets` → `cadvisor` у стані `UP`, базові jobs `node-exporter`/`victoriametrics` у стані `UP`.
- **Risks:** `mariadb-exporter`, `postgres-exporter`, `traefik` залишаються `DOWN`, доки не піднято відповідні сервіси/мережі та не налаштовано read-only DB users/DSN.
- **Rollback:** `git revert <commit>` + `docker compose up -d`.

## [2026-03-08] — Fix: cAdvisor port conflict with Koha

- **Context:** `cadvisor` конфліктував з локальним використанням host-порту `127.0.0.1:8081` (Koha stack).
- **Change:**
	- У `docker-compose.yml` прибрано host port publishing для `cadvisor`; scrape залишено по внутрішній адресі `cadvisor:8081` у `monitoring_net`.
	- Локальний `.env` синхронізовано відсутньою змінною `CADVISOR_IMAGE`, щоб `docker compose` коректно рендерив Phase 2 сервіси.
- **Verification:**
	- `docker compose -f docker-compose.yml config --quiet`
	- `docker compose -f docker-compose.yml up -d --force-recreate cadvisor`
	- `docker compose -f docker-compose.yml ps cadvisor` → `Up`
	- `docker ps` → `cadvisor` без host binding `127.0.0.1:8081`
	- `curl -s http://127.0.0.1:8428/targets` → `job=cadvisor (1/1 up)`
- **Risks:** Прямий доступ до cAdvisor UI з host більше не використовується; перевірка виконується через VictoriaMetrics/Grafana.
- **Rollback:** `git revert <commit>` + `docker compose up -d`.

## [2026-03-08] — Phase 2 completion (P0 exporters in user environment)

- **Context:** Виконано кроки 2–5 для `Phase 2` у локальному середовищі: DB exporters, зовнішні мережі, read-only users, Traefik metrics.
- **Change:**
	- Піднято DB exporters через `docker compose --profile phase2-db up -d`.
	- Перевірено/створено мережі `kohanet` і `dspacenet`; MariaDB контейнер підключено до `kohanet`.
	- Створено read-only user `metrics_reader` у MariaDB та PostgreSQL, оновлено локальний `.env` для exporter credentials.
	- Оновлено `mariadb-exporter` конфіг у `docker-compose.yml` на явні `--mysqld.*` параметри.
	- Увімкнено Traefik Prometheus metrics у `/home/pinokew/Dspace/DSpace-docker/docker-compose.yml` (`--entrypoints.metrics.address=:8082`, `--metrics.prometheus=true`, `--metrics.prometheus.entryPoint=metrics`) і перезапущено `dspace-traefik`.
	- Забезпечено мережеву досяжність `traefik:8082` із `monitoring_net`.
- **Verification:**
	- `curl -s http://127.0.0.1:8428/targets` → `cadvisor`, `mariadb-exporter`, `postgres-exporter`, `traefik`, `node-exporter`, `victoriametrics` у стані `UP`.
	- `ss -tlnp | grep -E '8428|3000|9100|9104|9187|8081|9114|15692|5001'` → лише localhost bind для monitoring портів.
	- `docker exec dspace-traefik wget http://127.0.0.1:8082/metrics` → `HTTP/1.1 200 OK`.
- **Risks:** Traefik metrics зміни внесені у зовнішній DSpace compose (поза цим репозиторієм), тому при окремих апдейтах DSpace їх потрібно зберігати консистентно.
- **Rollback:** `git revert <commit>` у цьому репо + rollback змін у `/home/pinokew/Dspace/DSpace-docker/docker-compose.yml`.

## [2026-03-08] — Docs sync after Phase 2 fixes

- **Context:** Після стабілізації мережі Koha (`koha-deploy_kohanet`) та донастройки `mariadb-exporter` документація потребувала синхронізації з фактичним runtime.
- **Change:**
	- Оновлено `docs/configuration/exporters-config.md`:
	  - для `cadvisor` зафіксовано internal-only порт без host publishing;
	  - уточнено причину `DOWN` як credentials/target mismatch (а не тільки DSN).
	- Оновлено `docs/security/db-exporter-users.md`:
	  - для MariaDB додано `SLAVE MONITOR`;
	  - приклад підключення переведено на `MARIADB_EXPORTER_TARGET/USER/PASSWORD`.
- **Verification:**
	- Звірено з поточним `docker-compose.yml` та фактичним статусом `targets` у VictoriaMetrics.
- **Risks:** Мінімальні, зміни лише в документації.
- **Rollback:** `git revert <commit>`.

## [2026-03-08] — Phase 3 completion: Grafana dashboards via file provisioning

- **Context:** Виконання `Phase 3 — Dashboards (P0)` згідно roadmap: 5 must-have dashboards тільки через Git provisioning.
- **Change:**
	- Додано 5 dashboard JSON у `grafana/dashboards/`:
	  - `host-overview-node-exporter-1860.json`
	  - `docker-containers-cadvisor-14282.json`
	  - `mariadb-overview-7362.json`
	  - `postgresql-overview-9628.json`
	  - `traefik-v3-official-17346.json`
	- Оновлено `grafana/provisioning/dashboards/dashboards.yml` (provider `KDI / P0`, file-based provisioning).
	- JSON адаптовано для provisioning: datasource `uid: victoriametrics`, прибрано import-only поля `__inputs`/`gnetId`, задано стабільні `uid` `kdi-*`.
	- Додано документацію: `docs/dashboards/dashboard-catalog.md`, `docs/dashboards/how-to-update-dashboards.md`.
	- Оновлено `grafana/dashboards/README.md` та відмічено `Phase 3` як виконану у `docs/ROADMAP.md`.
- **Verification:**
	- `docker compose -f docker-compose.yml config --quiet`
	- `docker compose -f docker-compose.yml restart grafana`
	- `docker compose -f docker-compose.yml logs grafana --since=1m | grep -Ei 'provisioning.dashboard|error'`
	- `curl -u "$GRAFANA_ADMIN_USER:$GRAFANA_ADMIN_PASSWORD" "http://127.0.0.1:3000/api/search?query=KDI&type=dash-db"` → `count: 5`
- **Risks:** Базові шаблони з Grafana.com можуть змінюватись у нових ревізіях; при оновленні потрібно перевіряти сумісність запитів з метриками поточного exporter стеку.
- **Rollback:** `git revert <commit>` + `docker compose -f docker-compose.yml restart grafana`.

## [2026-03-08] — Incident note: несумісність cAdvisor з Docker container-level метриками

- **Context:** Після релізу `KDI Docker Containers` dashboard панелі показували `No data` або відображали host/system cgroups (`/system.slice/*`) замість docker контейнерів.

- **Symptoms (що спостерігалось):**
	- `up{job="cadvisor"} == 1` (target `UP`), але у Grafana dashboard немає очікуваних container series.
	- Початкові запити dashboard на label `name` повертали порожній результат (`name` у поточному cadvisor scrape відсутній).
	- Після тимчасового переключення dashboard на `id` з’явились дані, але це були переважно host/systemd cgroups (`/system.slice/*`, `/user.slice/*`), не docker workload.

- **Technical diagnostics (підтверджені факти):**
	- Runtime host: `CgroupDriver=systemd`, `CgroupVersion=2`, Docker storage driver `overlayfs`, root `/var/lib/docker`.
	- У cAdvisor логах стабільно відтворюється помилка:
	  `Failed to create existing container ... failed to identify the read-write layer ID ... /rootfs/var/lib/docker/image/overlayfs/layerdb/mounts/<container-id>/mount-id: no such file or directory`.
	- Через цю помилку cAdvisor не формує повноцінні docker container-level series (labels `image`, `container_label_*`, `name`) і віддає переважно host cgroups.

- **Change (що зроблено під час розслідування):**
	- Оновлено cadvisor service у `docker-compose.yml`:
	  - `pid: "host"`, `cgroup: host`, `privileged: true`
	  - додано mount ` /var/run/docker.sock:/var/run/docker.sock:ro`
	  - залишено mount ` /var/lib/docker:/var/lib/docker:ro`
	  - додано `--docker_root=/var/lib/docker`
	  - протестовано `--docker_only=false`.
	- Виконано A/B тест з `gcr.io/cadvisor/cadvisor:v0.52.1` (тимчасовий контейнер `cadvisor-test`) — симптом з `mount-id` залишився.
	- Для зменшення хибної візуалізації оновлено `grafana/dashboards/docker-containers-cadvisor-14282.json`:
	  - запити обмежені до docker scope regex `id=~"/system.slice/docker-.*\\.scope"`
	  - прибрано показ `system.slice/*` як «контейнерів» у dashboard.

- **Verification (що перевірено):**
	- `docker compose -f docker-compose.yml logs cadvisor --tail=80 | grep -E 'Failed to create existing container|mount-id'` — помилка відтворюється.
	- `curl -s 'http://127.0.0.1:8428/api/v1/query?query=count(container_last_seen{job="cadvisor",id=~"/system.slice/docker-.*"})'` — результат порожній/нестабільний для очікуваного docker view.
	- `docker compose -f docker-compose.yml logs grafana --since=1m | grep -Ei 'provisioning.dashboard|error'` — provisioning dashboard успішний (без syntax/runtime помилок у Grafana).

- **Current status:**
	- Проблема локалізована як **джерело метрик (cAdvisor ↔ Docker runtime)**, а не помилка Grafana provisioning.
	- Dashboard більше не змішує host/system процеси з docker view, але повноцінні docker container metrics у поточному runtime недоступні.

- **Risks / impact:**
	- P0 dashboard `KDI Docker Containers` частково деградований: без виправлення джерела не показує повний перелік контейнерів.
	- Alerting/thresholds на основі container-level cadvisor метрик можуть бути некоректними або неповними.

- **Recommended follow-up (separate change):**
	- Перевірити сумісність Docker daemon режиму (зокрема snapshotter/storage stack) з cAdvisor для cgroup v2.
	- Після зміни runtime повторно валідувати появу docker labels (`image`, `container_label_com_docker_compose_service`, `id=/system.slice/docker-*.scope`) та повернути dashboard на container-friendly legends.

- **Rollback:**
	- Dashboard-only rollback: `git revert <commit>` для `grafana/dashboards/docker-containers-cadvisor-14282.json` + `docker compose -f docker-compose.yml restart grafana`.
	- cAdvisor config rollback: `git revert <commit>` для `docker-compose.yml` + `docker compose -f docker-compose.yml up -d --force-recreate cadvisor`.

## [2026-03-09] — Incident isolation: cAdvisor vs Docker 29 snapshotter layout

- **Context:** Потрібно ізолювати причину, чому `job="cadvisor"` має статус `UP`, але dashboard контейнерів залишається без docker container-level метрик.
- **Change:**
	- Виконано runtime-діагностику через VictoriaMetrics API, `docker compose logs`, `docker info`, `docker inspect` і `docker exec cadvisor`.
	- Підтверджено фактичну межу проблеми:
	  - `count(container_last_seen{job="cadvisor"}) = 82`, але це лише host/systemd cgroups;
	  - `count(container_last_seen{job="cadvisor",id=~"/system.slice/docker-.*\\.scope"}) = 0`;
	  - `count(container_last_seen{job="cadvisor",image!=""}) = 0`, `name!="" = 0`.
	- Зсередини `cadvisor` підтверджено відсутність шляху, який він очікує для Docker layer metadata:
	  - `/rootfs/var/lib/docker/image/overlayfs/layerdb/mounts` — відсутній.
	- Зафіксовано runtime характеристики:
	  - `docker info`: `ServerVersion=29.2.1`, `Driver=overlayfs`, `DriverStatus.driver-type=io.containerd.snapshotter.v1`, `CgroupVersion=2`.
	  - `docker inspect`: відсутній `GraphDriver`, натомість використовується `Storage.RootFS.Snapshot`.
	- Висновок: інцидент ізольовано як **несумісність очікувань cAdvisor щодо legacy Docker layerdb layout** у поточному Docker runtime (containerd snapshotter mode), а не як помилку scrape/provisioning у VictoriaMetrics/Grafana.
- **Verification:**
	- `curl -sG 'http://127.0.0.1:8428/api/v1/query' --data-urlencode 'query=up{job="cadvisor"}'`
	- `curl -sG 'http://127.0.0.1:8428/api/v1/query' --data-urlencode 'query=count(container_last_seen{job="cadvisor"})'`
	- `curl -sG 'http://127.0.0.1:8428/api/v1/query' --data-urlencode 'query=count(container_last_seen{job="cadvisor",id=~"/system.slice/docker-.*\\.scope"})'`
	- `docker compose -f docker-compose.yml logs cadvisor --tail=140`
	- `docker info --format '{{json .}}'`
	- `docker inspect <cadvisor_container_id>`
	- `docker exec cadvisor sh -lc 'ls -la /rootfs/var/lib/docker && ls -ld /rootfs/var/lib/docker/image/overlayfs/layerdb/mounts || true'`
- **Risks:** Поки runtime/layout не узгоджено з cAdvisor, P0 dashboard контейнерів і container-level alerting залишаються неповними/потенційно хибними.
- **Rollback:** Документальний запис; rollback не потрібен.

## [2026-03-09] — Phase 1 gap closure: Cloudflare Tunnel runbook + non-public VM check

- **Context:** Потрібно закрити відкриті прогалини `Phase 1 — Core Stack Deployment`: Cloudflare edge-доступ до Grafana і перевірка непублічності VictoriaMetrics.
- **Change:**
	- Додано сервіс `cloudflared` у `docker-compose.yml` (profile `phase1-edge`) без публікації портів, з token-based запуском через `.env`.
	- Розширено `.env.example` змінними `CLOUDFLARED_IMAGE`, `CLOUDFLARE_TUNNEL_TOKEN`, `CLOUDFLARE_GRAFANA_HOSTNAME`.
	- Оновлено `docs/deployment/monitoring-stack-deploy.md`:
	  - покроковий запуск Tunnel-контейнера,
	  - baseline Access policy для MS Entra ID,
	  - DoD верифікація для external access до Grafana і перевірка `EXTERNAL_IP:8428`.
	- Оновлено `docs/ROADMAP.md`: task про Cloudflare Tunnel відмічено виконаним; DoD про непублічність `8428` відмічено виконаним.
- **Verification:**
	- `docker compose --env-file .env.example -f docker-compose.yml config --quiet`
	- `EXTERNAL_IP=$(hostname -I | awk '{print $1}') && curl --connect-timeout 3 http://${EXTERNAL_IP}:8428/health` → `Failed to connect`
	- `docker compose -f docker-compose.yml ps` → monitoring сервіси `Up`, порти VM/Grafana/exporters тільки на `127.0.0.1`.
- **Risks:** Без реального `CLOUDFLARE_TUNNEL_TOKEN` і застосованої policy в Cloudflare Zero Trust неможливо повністю підтвердити DoD `Grafana доступна тільки через Cloudflare Tunnel з аутентифікацією` у runtime.
- **Rollback:** `git revert <commit>` + `docker compose up -d`.

## [2026-03-09] — cAdvisor recovery: Docker 29 labels restored + dashboard rollback

- **Context:** Потрібно закрити інцидент із `Phase 3`/`Phase 2`, де cAdvisor віддавав лише host/system cgroups і ламав container-level видимість у dashboard.
- **Change:**
	- Оновлено cAdvisor runtime flags у `docker-compose.yml`:
	  - `--housekeeping_interval=10s`
	  - `--docker_only=true`
	  - `--store_container_labels=true`
	- Оновлено дефолт image у `.env.example` до `gcr.io/cadvisor/cadvisor:v0.55.1`.
	- Відновлено dashboard `grafana/dashboards/docker-containers-cadvisor-14282.json` до name-based логіки:
	  - всі основні панелі переведені з `id=~"/system.slice/docker-..."` на `name!=""`;
	  - legends повернуті до `{{name}}`;
	  - template variable `container` переведено на `label_values(...,name)`;
	  - оновлено опис dashboard та піднято `version` до `4`.
	- Синхронізовано локальний `.env` (runtime) на `CADVISOR_IMAGE=gcr.io/cadvisor/cadvisor:v0.55.1`.
- **Verification:**
	- `docker compose -f docker-compose.yml up -d --force-recreate cadvisor`
	- `docker compose -f docker-compose.yml ps cadvisor` → `Up (healthy)` на `v0.55.1`
	- `docker compose -f docker-compose.yml logs cadvisor --tail=120 | grep -Ei 'mount-id|failed to create existing container|error'` → критичних збігів не знайдено
	- `count(container_cpu_usage_seconds_total{job="cadvisor",name!=""}) = 22`
	- `api/v1/series` для `container_cpu_usage_seconds_total{job="cadvisor"}` підтверджує наявність labels: `name`, `image`, `container_label_com_docker_compose_service`
	- `curl -s http://127.0.0.1:3000/api/health` → `ok`
- **Risks:** Репозиторій `ghcr.io/google/cadvisor` з тегами `v0.55.0/v0.56.0` не резолвиться в поточному середовищі; для цього хоста валідно підтверджений `gcr.io/cadvisor/cadvisor:v0.55.1`.
- **Rollback:** `git revert <commit>` + `docker compose -f docker-compose.yml up -d --force-recreate cadvisor && docker compose -f docker-compose.yml restart grafana`.

## [2026-03-09] — Validation note: GHCR cadvisor commit-tag panic in runtime

- **Context:** Перевірка альтернативного образу `ghcr.io/google/cadvisor:2d5bbad-2d5bbada76eddb24d0979cc599ebb6d6a7a89fd6` (користувач надав як 0.56.1 build).
- **Change:**
	- Образ успішно pull-иться: digest `sha256:3c43597efb8eba804b7eaf8161261a57d817424326fa443e0a8d32357a0982d6`.
	- Після запуску в `docker-compose` контейнер `cadvisor` падає з `panic: runtime error: invalid memory address or nil pointer dereference`.
	- Виконано негайний rollback runtime і дефолтного конфігу на `gcr.io/cadvisor/cadvisor:v0.55.1`.
- **Verification:**
	- `docker compose -f docker-compose.yml ps cadvisor` → `Up (healthy)` на `v0.55.1`
	- `docker compose -f docker-compose.yml logs cadvisor --tail=120 | grep -Ei 'panic|mount-id|failed to create existing container|error'` → порожньо
	- `count(container_cpu_usage_seconds_total{job="cadvisor",name!=""}) = 22`
- **Risks:** commit-tag у GHCR може бути нестабільним для поточного runtime; використовувати тільки після окремого smoke-тесту у staging.
- **Rollback:** вже виконано в цьому кроці (`CADVISOR_IMAGE` повернуто на `v0.55.1`).
