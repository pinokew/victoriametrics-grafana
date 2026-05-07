# Runbook: scripts (VictoriaMetrics + Grafana)

## Env-контракти

- CI/CD decrypt flow: shared workflow розшифровує `env.dev.enc` або `env.prod.enc` у тимчасовий dotenv-файл і передає шлях через `ORCHESTRATOR_ENV_FILE`.
- Deploy-adjacent flow: скрипти Категорії 1б читають `ORCHESTRATOR_ENV_FILE` або явний `--env-file` через `scripts/lib/orchestrator-env.sh` без `source`/`eval`.
- Autonomous flow: cron/manual скрипти читають `SERVER_ENV` (`dev|prod`) або аргумент `--env dev|prod`, розшифровують `env.<env>.enc` у `/dev/shm` через `scripts/lib/autonomous-env.sh` і очищають tmp-файл після завершення.
- Runtime flow: production default для автономних скриптів — `DOCKER_RUNTIME_MODE=swarm`, `STACK_NAME=monitoring`. Compose fallback лишається для локального dev через `DOCKER_RUNTIME_MODE=compose`.
- Локальний fallback на `.env` дозволений тільки для deploy-adjacent скриптів, коли `ORCHESTRATOR_ENV_FILE` не передано.

## Категорія 1а: validation

### `scripts/check-internal-ports-policy.sh`

#### Бізнес-логіка

- Перевіряє, що published ports у `docker-compose.yml` прив'язані до `MONITORING_BIND_IP`.
- Валідує, що `.env.example` має `MONITORING_BIND_IP=127.0.0.1`.
- Не читає секрети і не потребує SOPS/env decrypt.

#### Manual execution

```bash
bash scripts/check-internal-ports-policy.sh
```

## Категорія 1б: deploy-adjacent

### `scripts/deploy-orchestrator-swarm.sh`

#### Бізнес-логіка

- Основний Swarm orchestrator для CI/CD.
- Перевіряє env-файл, оновлює Swarm secrets через Ansible якщо задано `INFRA_REPO_PATH`.
- Створює/перевіряє overlay network `MONITORING_NETWORK_NAME`.
- Перед deploy запускає `init-volumes.sh` і `render-scrape-config.sh`.
- Рендерить merged manifest через `docker compose --env-file ... config` і виконує `docker stack deploy`.

#### Manual execution

```bash
ENV_TMP="$(mktemp /dev/shm/env-XXXXXX)"
chmod 600 "${ENV_TMP}"
sops --decrypt --input-type dotenv --output-type dotenv env.dev.enc > "${ENV_TMP}"

ORCHESTRATOR_MODE=swarm \
ENVIRONMENT_NAME=development \
STACK_NAME=monitoring \
ORCHESTRATOR_ENV_FILE="${ENV_TMP}" \
bash scripts/deploy-orchestrator-swarm.sh

shred -u "${ENV_TMP}" 2>/dev/null || rm -f "${ENV_TMP}"
```

### `scripts/init-volumes.sh`

#### Бізнес-логіка

- Створює bind-mount директорії VictoriaMetrics, Grafana, backup і node-exporter textfile collector.
- Нормалізує ownership/mode через root, passwordless sudo або ephemeral Docker helper.
- Читає env через `ORCHESTRATOR_ENV_FILE` або `--env-file` без `source`.

#### Manual execution

```bash
ORCHESTRATOR_ENV_FILE=/tmp/env.decrypted bash scripts/init-volumes.sh --dry-run
ORCHESTRATOR_ENV_FILE=/tmp/env.decrypted bash scripts/init-volumes.sh
```

### `scripts/render-scrape-config.sh`

#### Бізнес-логіка

- Рендерить `victoria-metrics/scrape-config.yml` із template.
- Читає `KOHA_OPAC_URL`, `KOHA_STAFF_URL`, `MATOMO_URL` через `ORCHESTRATOR_ENV_FILE` або `--env-file` без `source`.
- Пише результат у tmp-файл, звіряє з поточним конфігом через `cmp`/checksum і не перезаписує файл, якщо змін немає.

#### Manual execution

```bash
ORCHESTRATOR_ENV_FILE=/tmp/env.decrypted bash scripts/render-scrape-config.sh
bash scripts/render-scrape-config.sh --env-file .env
```

### `scripts/collect-matomo-archiving-metric.sh`

#### Бізнес-логіка

- Знаходить останній success marker `Done archiving!` у Docker logs Matomo cron контейнера.
- Публікує textfile metrics `matomo_archiving_last_*` для node-exporter.
- Читає `NODE_EXPORTER_TEXTFILE_DIR` і `MATOMO_CRON_CONTAINER_NAME` через env-file без `source`.

#### Manual execution

```bash
ORCHESTRATOR_ENV_FILE=/tmp/env.decrypted bash scripts/collect-matomo-archiving-metric.sh
```

### `scripts/collect-matomo-db-size.sh`

#### Бізнес-логіка

- Підключається до Matomo MariaDB контейнера через exporter user.
- Обчислює розмір схеми Matomo через `information_schema.tables`.
- Публікує textfile metrics `kdi_matomo_database_size_*`.
- Читає exporter password через env-file без `source` і не друкує значення секрету.

#### Manual execution

```bash
ORCHESTRATOR_ENV_FILE=/tmp/env.decrypted bash scripts/collect-matomo-db-size.sh
```

## Категорія 2: autonomous

### `scripts/backup-victoriametrics-volume.sh`

#### Бізнес-логіка

- Зупиняє VictoriaMetrics для консистентного backup.
- Архівує `VM_DATA_DIR` у `VM_BACKUP_DIR`, створює `.sha256`.
- Публікує textfile metrics `kdi_vm_backup_*`.
- Видаляє старі локальні backup-и за `VM_BACKUP_RETENTION_COUNT`.
- Env завантажується через `SERVER_ENV`/`--env` + SOPS `/dev/shm`.

#### Manual execution

```bash
SERVER_ENV=dev bash scripts/backup-victoriametrics-volume.sh
SERVER_ENV=prod bash scripts/backup-victoriametrics-volume.sh
bash scripts/backup-victoriametrics-volume.sh --env prod
```

#### Runtime override

```bash
DOCKER_RUNTIME_MODE=compose bash scripts/backup-victoriametrics-volume.sh --env dev
```

### `scripts/restore-victoriametrics-backup.sh`

#### Бізнес-логіка

- Відновлює `vmdata-*.tar.gz` у `VM_DATA_DIR`.
- Перевіряє `.sha256`, якщо checksum-файл присутній.
- Має захист від випадкового destructive restore: потрібен `--yes`, крім `--dry-run`.
- Після restore чекає VictoriaMetrics `/health`.
- Env завантажується через `SERVER_ENV`/`--env` + SOPS `/dev/shm`.

#### Manual execution

```bash
SERVER_ENV=prod bash scripts/restore-victoriametrics-backup.sh --dry-run
bash scripts/restore-victoriametrics-backup.sh --env prod --yes /srv/victoriametrics-grafana/.backups/victoriametrics/vmdata-<timestamp>.tar.gz
```

### `scripts/test-victoriametrics-restore.sh`

#### Бізнес-логіка

- Виконує smoke restore в ізольований тимчасовий VictoriaMetrics контейнер.
- Якщо backup path не передано, бере найновіший `vmdata-*.tar.gz` з `VM_BACKUP_DIR`.
- Публікує textfile metrics `kdi_vm_restore_smoke_*`.
- Env завантажується через `SERVER_ENV`/`--env` + SOPS `/dev/shm`.

#### Manual execution

```bash
SERVER_ENV=dev bash scripts/test-victoriametrics-restore.sh
bash scripts/test-victoriametrics-restore.sh --env prod /srv/victoriametrics-grafana/.backups/victoriametrics/vmdata-<timestamp>.tar.gz
```

## Helpers

### `scripts/lib/orchestrator-env.sh`

#### Бізнес-логіка

- Спільний helper для Категорії 1б.
- Надає `resolve_orchestrator_env_file`, `read_env_var`, `read_env_or_default`, `require_env_var`, `dotenv_checksum_file`.
- Не виконує env-файл як shell-код.

### `scripts/lib/autonomous-env.sh`

#### Бізнес-логіка

- Спільний helper для Категорії 2.
- Визначає середовище через `--env`/`SERVER_ENV`.
- Розшифровує `env.<env>.enc` у `/dev/shm` і очищає tmp-файл при exit.

### `scripts/lib/docker-runtime.sh`

#### Бізнес-логіка

- Спільний helper для базового керування сервісами у `compose` або `swarm`.
- За замовчуванням використовує `DOCKER_RUNTIME_MODE=swarm` і `STACK_NAME=monitoring`.

## Out of scope

### `scripts/deploy-orchestrator.sh`

Legacy orchestrator. Залишається без змін.

### `scripts/validate_sops_encrypted.py`

SOPS validation helper. Залишається без змін.
