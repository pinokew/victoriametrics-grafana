#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/scripts"
ENV_FILE_ARG=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE_ARG="${2:-}"
      shift
      ;;
    *)
      echo "ERROR: Unexpected argument: $1"
      exit 1
      ;;
  esac
  shift
done

# shellcheck source=scripts/lib/orchestrator-env.sh
. "$SCRIPT_DIR/lib/orchestrator-env.sh"

ENV_FILE="$(resolve_orchestrator_env_file "$ROOT_DIR" "$ENV_FILE_ARG")"

abs_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s/%s\n' "$ROOT_DIR" "$path"
  fi
}

NODE_EXPORTER_TEXTFILE_DIR="$(read_env_or_default NODE_EXPORTER_TEXTFILE_DIR "$ENV_FILE" "./.data/node-exporter-textfile")"
MATOMO_DB_CONTAINER_NAME="$(read_env_or_default MATOMO_DB_CONTAINER_NAME "$ENV_FILE" "matomo-db")"
MATOMO_MARIADB_EXPORTER_USER="$(read_env_or_default MATOMO_MARIADB_EXPORTER_USER "$ENV_FILE" "metrics_reader")"
MATOMO_MARIADB_EXPORTER_PASSWORD="$(read_env_or_default MATOMO_MARIADB_EXPORTER_PASSWORD "$ENV_FILE" "")"
TEXTFILE_DIR_ABS="$(abs_path "$NODE_EXPORTER_TEXTFILE_DIR")"
collect_timestamp="$(date +%s)"
metric_status="0"
db_size_bytes="0"

if [[ -z "$MATOMO_MARIADB_EXPORTER_PASSWORD" ]]; then
  echo "ERROR: MATOMO_MARIADB_EXPORTER_PASSWORD is required"
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$MATOMO_DB_CONTAINER_NAME"; then
  echo "ERROR: Matomo DB container is not running: $MATOMO_DB_CONTAINER_NAME"
  exit 1
fi

mkdir -p "$TEXTFILE_DIR_ABS"

emit_metrics() {
  local metrics_payload
  metrics_payload="$(cat <<EOF
# HELP kdi_matomo_database_size_bytes Size of Matomo MariaDB schema in bytes.
# TYPE kdi_matomo_database_size_bytes gauge
kdi_matomo_database_size_bytes{env="prod",service="matomo",component="db",database="$db_name"} $db_size_bytes
# HELP kdi_matomo_database_size_last_collect_timestamp_seconds Unix timestamp of the last Matomo DB size collection attempt.
# TYPE kdi_matomo_database_size_last_collect_timestamp_seconds gauge
kdi_matomo_database_size_last_collect_timestamp_seconds{env="prod",service="matomo",component="db",database="$db_name"} $collect_timestamp
# HELP kdi_matomo_database_size_last_status Last Matomo DB size collection status (1=success, 0=failure).
# TYPE kdi_matomo_database_size_last_status gauge
kdi_matomo_database_size_last_status{env="prod",service="matomo",component="db",database="$db_name"} $metric_status
EOF
)"

  printf '%s\n' "$metrics_payload" | docker run --rm -i \
    -v "$TEXTFILE_DIR_ABS:/metrics" \
    alpine:3.20 \
    sh -c 'cat > /metrics/matomo_db_size.prom'
}

trap 'emit_metrics' EXIT

db_name="matomo"

db_name="$(docker exec "$MATOMO_DB_CONTAINER_NAME" sh -lc 'printf "%s" "$DB_NAME"')"
if [[ -z "$db_name" ]]; then
  echo "ERROR: DB_NAME is empty in container $MATOMO_DB_CONTAINER_NAME"
  exit 1
fi

query="SELECT COALESCE(SUM(data_length + index_length), 0) FROM information_schema.tables WHERE table_schema = '$db_name';"
db_size_bytes="$(docker exec -e MYSQL_PWD="$MATOMO_MARIADB_EXPORTER_PASSWORD" "$MATOMO_DB_CONTAINER_NAME" sh -lc "mariadb -h127.0.0.1 -u \"$MATOMO_MARIADB_EXPORTER_USER\" -Nse \"$query\"")"

if [[ ! "$db_size_bytes" =~ ^[0-9]+$ ]]; then
  echo "ERROR: Unexpected DB size value: $db_size_bytes"
  exit 1
fi

metric_status="1"
emit_metrics
trap - EXIT

echo "Matomo DB size collected successfully: ${db_size_bytes} bytes"
