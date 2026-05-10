#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/scripts"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
ENVIRONMENT_ARG=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --env)
      ENVIRONMENT_ARG="${2:-}"
      shift
      ;;
    *)
      echo "ERROR: Unexpected argument: $1"
      exit 1
      ;;
  esac
  shift
done

# shellcheck source=scripts/lib/autonomous-env.sh
. "$SCRIPT_DIR/lib/autonomous-env.sh"
# shellcheck source=scripts/lib/docker-runtime.sh
. "$SCRIPT_DIR/lib/docker-runtime.sh"

load_autonomous_env "$ROOT_DIR" "$ENVIRONMENT_ARG"

read_env_or_default() {
  local key="$1"
  local default_value="$2"
  local env_value="${!key:-}"

  if [[ -n "$env_value" ]]; then
    printf '%s\n' "$env_value"
    return 0
  fi

  printf '%s\n' "$default_value"
}

VM_DATA_DIR="$(read_env_or_default VM_DATA_DIR "./.data/victoriametrics")"
VM_BACKUP_DIR="$(read_env_or_default VM_BACKUP_DIR "./.backups/victoriametrics")"
NODE_EXPORTER_TEXTFILE_DIR="$(read_env_or_default NODE_EXPORTER_TEXTFILE_DIR "./.data/node-exporter-textfile")"
VM_BACKUP_RETENTION_COUNT="$(read_env_or_default VM_BACKUP_RETENTION_COUNT "7")"
VM_BACKUP_CLOUD_RETENTION_COUNT="$(read_env_or_default VM_BACKUP_CLOUD_RETENTION_COUNT "30")"
RCLONE_REMOTE="$(read_env_or_default RCLONE_REMOTE "")"
RCLONE_DEST_PATH="$(read_env_or_default RCLONE_DEST_PATH "")"
METRICS_FILE_NAME="vm_backup.prom"

if [[ ! "$VM_BACKUP_RETENTION_COUNT" =~ ^[0-9]+$ ]] || [[ "$VM_BACKUP_RETENTION_COUNT" -lt 1 ]]; then
  echo "ERROR: VM_BACKUP_RETENTION_COUNT must be a positive integer"
  exit 1
fi

if [[ ! "$VM_BACKUP_CLOUD_RETENTION_COUNT" =~ ^[0-9]+$ ]] || [[ "$VM_BACKUP_CLOUD_RETENTION_COUNT" -lt 1 ]]; then
  echo "ERROR: VM_BACKUP_CLOUD_RETENTION_COUNT must be a positive integer"
  exit 1
fi

cloud_backup_enabled="0"
if [[ -n "$RCLONE_REMOTE" || -n "$RCLONE_DEST_PATH" ]]; then
  if [[ -z "$RCLONE_REMOTE" || -z "$RCLONE_DEST_PATH" ]]; then
    echo "ERROR: RCLONE_REMOTE and RCLONE_DEST_PATH must be set together"
    exit 1
  fi
  if ! command -v rclone >/dev/null 2>&1; then
    echo "ERROR: rclone is required when RCLONE_REMOTE/RCLONE_DEST_PATH are set"
    exit 1
  fi
  cloud_backup_enabled="1"
fi

abs_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s/%s\n' "$ROOT_DIR" "$path"
  fi
}

VM_DATA_ABS="$(abs_path "$VM_DATA_DIR")"
VM_BACKUP_ABS="$(abs_path "$VM_BACKUP_DIR")"
TEXTFILE_DIR_ABS="$(abs_path "$NODE_EXPORTER_TEXTFILE_DIR")"

if [[ ! -d "$VM_DATA_ABS" ]]; then
  echo "ERROR: VictoriaMetrics data dir not found: $VM_DATA_ABS"
  exit 1
fi

mkdir -p "$VM_BACKUP_ABS"
mkdir -p "$TEXTFILE_DIR_ABS"

timestamp="$(date +%Y%m%d-%H%M%S)"
archive="$VM_BACKUP_ABS/vmdata-${timestamp}.tar.gz"
checksum_file="${archive}.sha256"
run_timestamp="$(date +%s)"
success_timestamp="0"
backup_status="0"
vm_stopped="0"

emit_backup_metrics() {
  local metrics_payload
  metrics_payload="$(cat <<EOF
# HELP kdi_vm_backup_last_run_timestamp_seconds Unix timestamp of the last VictoriaMetrics backup attempt.
# TYPE kdi_vm_backup_last_run_timestamp_seconds gauge
kdi_vm_backup_last_run_timestamp_seconds{env="prod",service="monitoring"} $run_timestamp
# HELP kdi_vm_backup_last_success_timestamp_seconds Unix timestamp of the last successful VictoriaMetrics backup.
# TYPE kdi_vm_backup_last_success_timestamp_seconds gauge
kdi_vm_backup_last_success_timestamp_seconds{env="prod",service="monitoring"} $success_timestamp
# HELP kdi_vm_backup_last_status Last VictoriaMetrics backup status (1=success, 0=failure).
# TYPE kdi_vm_backup_last_status gauge
kdi_vm_backup_last_status{env="prod",service="monitoring"} $backup_status
EOF
)"

  printf '%s\n' "$metrics_payload" | docker run --rm -i \
    -v "$TEXTFILE_DIR_ABS:/metrics" \
    alpine:3.20 \
    sh -c "cat > /metrics/$METRICS_FILE_NAME"
}

restart_vm() {
  docker_runtime_start_service victoriametrics "$COMPOSE_FILE" >/dev/null 2>&1 || true
}

upload_backup_to_cloud() {
  local cloud_dest="${RCLONE_REMOTE}:${RCLONE_DEST_PATH%/}"
  local archive_name
  local checksum_name

  archive_name="$(basename "$archive")"
  checksum_name="$(basename "$checksum_file")"

  echo "Uploading backup to rclone remote: $cloud_dest"
  rclone mkdir "$cloud_dest"
  docker run --rm \
    -v "$VM_BACKUP_ABS:/backup:ro" \
    alpine:3.20 \
    cat "/backup/$archive_name" | rclone rcat "$cloud_dest/$archive_name"
  docker run --rm \
    -v "$VM_BACKUP_ABS:/backup:ro" \
    alpine:3.20 \
    cat "/backup/$checksum_name" | rclone rcat "$cloud_dest/$checksum_name"
}

rotate_cloud_backups() {
  local cloud_dest="${RCLONE_REMOTE}:${RCLONE_DEST_PATH%/}"
  local old_backup
  local backup_name
  local checksum_name
  local -a cloud_backups

  mapfile -t cloud_backups < <(
    rclone lsf "$cloud_dest" \
      --files-only \
      --format "p" \
      --include "vmdata-*.tar.gz" 2>/dev/null \
      | sort -r
  )

  if [[ "${#cloud_backups[@]}" -le "$VM_BACKUP_CLOUD_RETENTION_COUNT" ]]; then
    return 0
  fi

  for old_backup in "${cloud_backups[@]:$VM_BACKUP_CLOUD_RETENTION_COUNT}"; do
    backup_name="$(basename "$old_backup")"
    checksum_name="${backup_name}.sha256"
    echo "Removing old cloud backup: $cloud_dest/$backup_name"
    rclone deletefile "$cloud_dest/$backup_name"
    rclone deletefile "$cloud_dest/$checksum_name" || true
  done
}

rotate_local_backups() {
  docker run --rm \
    -v "$VM_BACKUP_ABS:/backup" \
    -e "VM_BACKUP_RETENTION_COUNT=$VM_BACKUP_RETENTION_COUNT" \
    alpine:3.20 \
    sh -c '
      set -eu
      cd /backup
      backups="$(ls -1 vmdata-*.tar.gz 2>/dev/null | sort -r || true)"
      backup_count="$(printf "%s\n" "$backups" | sed "/^$/d" | wc -l)"
      if [ "$backup_count" -le "$VM_BACKUP_RETENTION_COUNT" ]; then
        exit 0
      fi
      printf "%s\n" "$backups" \
        | sed "/^$/d" \
        | tail -n +"$((VM_BACKUP_RETENTION_COUNT + 1))" \
        | while IFS= read -r old_backup; do
            echo "Removing old backup: $old_backup"
            rm -f "$old_backup" "${old_backup}.sha256"
          done
    '
}

cleanup() {
  local exit_code=$?
  if [[ "$vm_stopped" == "1" ]]; then
    restart_vm
  fi
  emit_backup_metrics
  exit "$exit_code"
}

trap cleanup EXIT

echo "Stopping victoriametrics for consistent backup..."
docker_runtime_stop_service victoriametrics "$COMPOSE_FILE"
vm_stopped="1"

echo "Creating backup archive: $archive"
docker run --rm \
  -v "$VM_DATA_ABS:/source:ro" \
  -v "$VM_BACKUP_ABS:/backup" \
  alpine:3.20 \
  sh -c "set -e; tar -C /source -czf /backup/$(basename "$archive") .; cd /backup; sha256sum $(basename "$archive") > $(basename "$checksum_file")"

echo "Starting victoriametrics back..."
docker_runtime_start_service victoriametrics "$COMPOSE_FILE"
vm_stopped="0"

if [[ "$cloud_backup_enabled" == "1" ]]; then
  upload_backup_to_cloud
  rotate_cloud_backups
fi

backup_status="1"
success_timestamp="$(date +%s)"
emit_backup_metrics
trap - EXIT

rotate_local_backups

echo "Backup completed: $archive"
echo "Checksum file: $checksum_file"
