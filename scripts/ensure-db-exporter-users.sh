#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/orchestrator-env.sh
source "${PROJECT_ROOT}/scripts/lib/orchestrator-env.sh"
# shellcheck source=scripts/lib/docker-runtime.sh
source "${PROJECT_ROOT}/scripts/lib/docker-runtime.sh"

ENV_FILE=""
SKIP_MISSING="false"

log() {
  printf '[ensure-db-exporter-users] %s\n' "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

usage() {
  cat <<'EOF'
Usage: scripts/ensure-db-exporter-users.sh [--env-file FILE] [--skip-missing]

Idempotently creates/updates read-only DB users used by monitoring exporters:
- Koha MariaDB metrics_reader
- Matomo MariaDB metrics_reader
- DSpace PostgreSQL metrics_reader

Credentials are read from the decrypted orchestrator env file when available.
If no env file is available, the script falls back to current running exporter
containers/secrets. Password values are never printed.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="${2:-}"
      [[ -n "${ENV_FILE}" ]] || die "--env-file requires a value"
      shift 2
      ;;
    --skip-missing)
      SKIP_MISSING="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

if [[ -z "${ENV_FILE}" && -n "${ORCHESTRATOR_ENV_FILE:-}" ]]; then
  ENV_FILE="${ORCHESTRATOR_ENV_FILE}"
elif [[ -z "${ENV_FILE}" && -f "${PROJECT_ROOT}/.env" ]]; then
  ENV_FILE="${PROJECT_ROOT}/.env"
fi

read_env_optional() {
  local key="$1"
  if [[ -n "${!key:-}" ]]; then
    printf '%s\n' "${!key}"
    return 0
  fi
  if [[ -n "${ENV_FILE}" && -f "${ENV_FILE}" ]]; then
    read_env_var "${key}" "${ENV_FILE}"
  fi
}

read_env_default_optional() {
  local key="$1"
  local default_value="$2"
  local value
  value="$(read_env_optional "${key}")"
  if [[ -n "${value}" ]]; then
    printf '%s\n' "${value}"
  else
    printf '%s\n' "${default_value}"
  fi
}

handle_missing() {
  local message="$1"
  if [[ "${SKIP_MISSING}" == "true" ]]; then
    log "WARNING: ${message}; skipping"
    return 0
  fi
  die "${message}"
}

running_container_by_name() {
  local requested_name="$1"
  local container

  container="$(docker ps --format '{{.Names}}' | awk -v name="${requested_name}" '
    $0 == name || $0 ~ "^" name "([.]|$)" || $0 ~ "_" name "([.]|$)" {
      print
      exit
    }
  ')"

  [[ -n "${container}" ]] || return 1
  printf '%s\n' "${container}"
}

monitoring_container() {
  local service="$1"
  local container_id

  container_id="$(docker_runtime_container_id "${service}" || true)"
  [[ -n "${container_id}" ]] || return 1
  printf '%s\n' "${container_id}"
}

read_secret_from_monitoring_container() {
  local service="$1"
  local secret_path="$2"
  local container_id

  container_id="$(monitoring_container "${service}" || true)"
  [[ -n "${container_id}" ]] || return 1
  docker exec "${container_id}" sh -lc "cat '${secret_path}'"
}

read_env_from_monitoring_container() {
  local service="$1"
  local key="$2"
  local container_id

  container_id="$(monitoring_container "${service}" || true)"
  [[ -n "${container_id}" ]] || return 1
  docker exec "${container_id}" sh -lc "printf '%s\n' \"\${${key}:-}\""
}

sql_escape() {
  printf '%s' "$1" | sed "s/'/''/g"
}

ensure_mariadb_exporter_user() {
  local label db_container_name exporter_service exporter_user exporter_password user_sql password_sql db_container root_password_file

  label="$1"
  db_container_name="$2"
  exporter_service="$3"
  exporter_user="$4"
  exporter_password="$5"
  root_password_file="$6"

  if [[ -z "${exporter_password}" ]]; then
    handle_missing "${label}: exporter password is empty"
    return 0
  fi

  db_container="$(running_container_by_name "${db_container_name}" || true)"
  if [[ -z "${db_container}" ]]; then
    handle_missing "${label}: DB container not found by name '${db_container_name}'"
    return 0
  fi

  user_sql="$(sql_escape "${exporter_user}")"
  password_sql="$(sql_escape "${exporter_password}")"

  log "${label}: ensuring MariaDB exporter user '${exporter_user}' in container '${db_container}'"
  docker exec -i "${db_container}" sh -lc "
    set -eu
    MYSQL_PWD=\"\$(cat \"${root_password_file}\")\" mariadb -uroot
  " <<SQL
CREATE USER IF NOT EXISTS '${user_sql}'@'%' IDENTIFIED BY '${password_sql}';
ALTER USER '${user_sql}'@'%' IDENTIFIED BY '${password_sql}';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO '${user_sql}'@'%';
GRANT SLAVE MONITOR ON *.* TO '${user_sql}'@'%';
FLUSH PRIVILEGES;
SQL

  log "${label}: applied grants for '${exporter_user}'"
}

parse_postgres_dsn() {
  local dsn="$1"
  python3 - "$dsn" <<'PY'
import shlex
import sys
from urllib.parse import urlparse, unquote

dsn = sys.argv[1]
parsed = urlparse(dsn)
if parsed.scheme not in ("postgres", "postgresql"):
    raise SystemExit("unsupported postgres DSN scheme")
if not parsed.username or parsed.password is None or not parsed.path.strip("/"):
    raise SystemExit("postgres DSN must include username, password and database")

values = {
    "PG_EXPORTER_USER": unquote(parsed.username),
    "PG_EXPORTER_PASSWORD": unquote(parsed.password),
    "PG_EXPORTER_DB": unquote(parsed.path.lstrip("/")),
}
for key, value in values.items():
    print(f"{key}={shlex.quote(value)}")
PY
}

ensure_postgres_exporter_user() {
  local pg_container_name postgres_dsn pg_container postgres_password_file user_sql password_sql db_sql

  pg_container_name="$1"
  postgres_dsn="$2"
  postgres_password_file="$3"

  if [[ -z "${postgres_dsn}" ]]; then
    handle_missing "DSpace PostgreSQL: POSTGRES_EXPORTER_DSN is empty"
    return 0
  fi

  eval "$(parse_postgres_dsn "${postgres_dsn}")"

  pg_container="$(running_container_by_name "${pg_container_name}" || true)"
  if [[ -z "${pg_container}" ]]; then
    handle_missing "DSpace PostgreSQL: DB container not found by name '${pg_container_name}'"
    return 0
  fi

  user_sql="$(sql_escape "${PG_EXPORTER_USER}")"
  password_sql="$(sql_escape "${PG_EXPORTER_PASSWORD}")"
  db_sql="$(sql_escape "${PG_EXPORTER_DB}")"

  log "DSpace PostgreSQL: ensuring exporter user '${PG_EXPORTER_USER}' for database '${PG_EXPORTER_DB}' in container '${pg_container}'"
  docker exec -i "${pg_container}" sh -lc "
    set -eu
    PGPASSWORD=\"\$(cat \"${postgres_password_file}\")\" psql -v ON_ERROR_STOP=1 -U \"\${POSTGRES_USER}\" -d \"\${POSTGRES_DB}\"
  " <<SQL
DO \$\$
DECLARE
  v_user text := '${user_sql}';
  v_pass text := '${password_sql}';
  v_db text := '${db_sql}';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_user) THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', v_user, v_pass);
  END IF;

  EXECUTE format('ALTER ROLE %I LOGIN PASSWORD %L', v_user, v_pass);
  EXECUTE format('GRANT CONNECT ON DATABASE %I TO %I', v_db, v_user);
  EXECUTE format('GRANT pg_monitor TO %I', v_user);
END
\$\$;
SQL

  log "DSpace PostgreSQL: applied grants for '${PG_EXPORTER_USER}'"
}

koha_container_name="$(read_env_default_optional "KOHA_DB_CONTAINER_NAME" "koha_db")"
matomo_container_name="$(read_env_default_optional "MATOMO_DB_CONTAINER_NAME" "matomo-db")"
dspace_pg_container_name="$(read_env_default_optional "DSPACE_POSTGRES_CONTAINER_NAME" "dspace_dspacedb")"

koha_user="$(read_env_default_optional "MARIADB_EXPORTER_USER" "metrics_reader")"
koha_password="$(read_env_optional "MARIADB_EXPORTER_PASSWORD")"
if [[ -z "${koha_password}" ]]; then
  koha_password="$(read_secret_from_monitoring_container "mariadb-exporter" "/run/secrets/mariadb_exporter_password" || true)"
fi

matomo_user="$(read_env_default_optional "MATOMO_MARIADB_EXPORTER_USER" "metrics_reader")"
matomo_password="$(read_env_optional "MATOMO_MARIADB_EXPORTER_PASSWORD")"
if [[ -z "${matomo_password}" ]]; then
  matomo_password="$(read_secret_from_monitoring_container "matomo-mariadb-exporter" "/run/secrets/matomo_mariadb_exporter_password" || true)"
fi

postgres_dsn="$(read_env_optional "POSTGRES_EXPORTER_DSN")"
if [[ -z "${postgres_dsn}" ]]; then
  postgres_dsn="$(read_env_from_monitoring_container "postgres-exporter" "DATA_SOURCE_NAME" || true)"
fi

ensure_mariadb_exporter_user \
  "Koha MariaDB" \
  "${koha_container_name}" \
  "mariadb-exporter" \
  "${koha_user}" \
  "${koha_password}" \
  "\${MYSQL_ROOT_PASSWORD_FILE}"

ensure_mariadb_exporter_user \
  "Matomo MariaDB" \
  "${matomo_container_name}" \
  "matomo-mariadb-exporter" \
  "${matomo_user}" \
  "${matomo_password}" \
  "\${MARIADB_ROOT_PASSWORD_FILE}"

ensure_postgres_exporter_user \
  "${dspace_pg_container_name}" \
  "${postgres_dsn}" \
  "\${POSTGRES_PASSWORD_FILE}"

log "DB exporter users are in desired state"
