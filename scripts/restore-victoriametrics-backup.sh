#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
ENV_FILE="$ROOT_DIR/.env"

DRY_RUN="false"
CONFIRM="false"
BACKUP_ARG=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN="true"
      ;;
    --yes)
      CONFIRM="true"
      ;;
    *)
      if [[ -z "$BACKUP_ARG" ]]; then
        BACKUP_ARG="$1"
      else
        echo "ERROR: Unexpected argument: $1"
        exit 1
      fi
      ;;
  esac
  shift
done

read_env_or_default() {
  local key="$1"
  local default_value="$2"
  local env_value="${!key:-}"

  if [[ -n "$env_value" ]]; then
    printf '%s\n' "$env_value"
    return 0
  fi

  if [[ -f "$ENV_FILE" ]]; then
    local line
    line="$(grep -E "^${key}=" "$ENV_FILE" | tail -n1 || true)"
    if [[ -n "$line" ]]; then
      printf '%s\n' "${line#*=}"
      return 0
    fi
  fi

  printf '%s\n' "$default_value"
}

abs_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s/%s\n' "$ROOT_DIR" "$path"
  fi
}

run_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] $*"
    return 0
  fi
  "$@"
}

wait_for_http() {
  local url="$1"
  local attempts="$2"
  local delay="$3"

  for _ in $(seq 1 "$attempts"); do
    if curl -fsS "$url" >/dev/null; then
      return 0
    fi
    sleep "$delay"
  done

  return 1
}

VM_DATA_DIR="$(read_env_or_default VM_DATA_DIR "./.data/victoriametrics")"
VM_BACKUP_DIR="$(read_env_or_default VM_BACKUP_DIR "./.backups/victoriametrics")"
VM_HOST_PORT="$(read_env_or_default VM_HOST_PORT "8428")"

VM_DATA_ABS="$(abs_path "$VM_DATA_DIR")"
VM_BACKUP_ABS="$(abs_path "$VM_BACKUP_DIR")"

if [[ -n "$BACKUP_ARG" ]]; then
  if [[ "$BACKUP_ARG" = /* ]]; then
    BACKUP_PATH="$BACKUP_ARG"
  else
    BACKUP_PATH="$(abs_path "$BACKUP_ARG")"
  fi
else
  BACKUP_PATH="$(
    find "$VM_BACKUP_ABS" -maxdepth 1 -type f -name 'vmdata-*.tar.gz' -printf '%T@ %p\n' 2>/dev/null \
      | sort -nr \
      | head -n1 \
      | cut -d' ' -f2-
  )"
fi

if [[ -z "$BACKUP_PATH" ]]; then
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "No backup archive found in $VM_BACKUP_ABS (dry-run mode)."
    echo "Dry-run completed without destructive actions."
    exit 0
  fi
  echo "ERROR: No backup archive found in $VM_BACKUP_ABS"
  exit 1
fi

if [[ ! -f "$BACKUP_PATH" ]]; then
  echo "ERROR: Backup archive not found: $BACKUP_PATH"
  exit 1
fi

if [[ -f "${BACKUP_PATH}.sha256" ]]; then
  echo "Verifying checksum for $BACKUP_PATH"
  (cd "$(dirname "$BACKUP_PATH")" && sha256sum -c "$(basename "$BACKUP_PATH").sha256")
fi

if [[ "$CONFIRM" != "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
  echo "ERROR: Restore is destructive and will overwrite $VM_DATA_ABS"
  echo "Re-run with --yes to continue"
  exit 1
fi

if [[ ! -d "$VM_DATA_ABS" ]]; then
  echo "ERROR: VM data dir not found: $VM_DATA_ABS"
  exit 1
fi

echo "Stopping victoriametrics before restore"
run_cmd docker compose -f "$COMPOSE_FILE" stop victoriametrics

echo "Clearing VM data directory: $VM_DATA_ABS"
run_cmd docker run --rm -v "$VM_DATA_ABS:/target" alpine:3.20 \
  sh -c 'rm -rf /target/* /target/.[!.]* /target/..?*'

echo "Extracting backup into VM data directory"
run_cmd docker run --rm \
  -v "$VM_DATA_ABS:/target" \
  -v "$(dirname "$BACKUP_PATH"):/backup" \
  alpine:3.20 \
  sh -c "tar -C /target -xzf /backup/$(basename "$BACKUP_PATH")"

echo "Starting victoriametrics after restore"
run_cmd docker compose -f "$COMPOSE_FILE" up -d victoriametrics

if [[ "$DRY_RUN" == "true" ]]; then
  echo "Restore dry-run completed."
  exit 0
fi

echo "Waiting for VictoriaMetrics health endpoint"
if wait_for_http "http://127.0.0.1:${VM_HOST_PORT}/health" 30 2; then
  echo "Restore completed successfully."
  exit 0
fi

echo "ERROR: VictoriaMetrics health check failed after restore"
docker compose -f "$COMPOSE_FILE" logs victoriametrics --tail 200 || true
exit 1
