#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

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

VM_BACKUP_DIR="$(read_env_or_default VM_BACKUP_DIR "./.backups/victoriametrics")"
VM_RESTORE_TEST_PORT="$(read_env_or_default VM_RESTORE_TEST_PORT "18428")"
VICTORIAMETRICS_IMAGE="$(read_env_or_default VICTORIAMETRICS_IMAGE "victoriametrics/victoria-metrics:v1.118.0")"
NODE_EXPORTER_TEXTFILE_DIR="$(read_env_or_default NODE_EXPORTER_TEXTFILE_DIR "./.data/node-exporter-textfile")"
METRICS_FILE_NAME="vm_restore_smoke.prom"

abs_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s/%s\n' "$ROOT_DIR" "$path"
  fi
}

VM_BACKUP_ABS="$(abs_path "$VM_BACKUP_DIR")"
TEXTFILE_DIR_ABS="$(abs_path "$NODE_EXPORTER_TEXTFILE_DIR")"
run_timestamp="$(date +%s)"
success_timestamp="0"
restore_status="0"
backup_dir="$VM_BACKUP_ABS"

# shellcheck disable=SC2329
emit_restore_metrics() {
  mkdir -p "$TEXTFILE_DIR_ABS"
  local metrics_payload
  metrics_payload="$(cat <<EOF
# HELP kdi_vm_restore_smoke_last_run_timestamp_seconds Unix timestamp of the last VictoriaMetrics restore smoke test attempt.
# TYPE kdi_vm_restore_smoke_last_run_timestamp_seconds gauge
kdi_vm_restore_smoke_last_run_timestamp_seconds{env="prod",service="monitoring"} $run_timestamp
# HELP kdi_vm_restore_smoke_last_success_timestamp_seconds Unix timestamp of the last successful VictoriaMetrics restore smoke test.
# TYPE kdi_vm_restore_smoke_last_success_timestamp_seconds gauge
kdi_vm_restore_smoke_last_success_timestamp_seconds{env="prod",service="monitoring"} $success_timestamp
# HELP kdi_vm_restore_smoke_last_status Last VictoriaMetrics restore smoke test status (1=success, 0=failure).
# TYPE kdi_vm_restore_smoke_last_status gauge
kdi_vm_restore_smoke_last_status{env="prod",service="monitoring"} $restore_status
EOF
)"

  printf '%s\n' "$metrics_payload" | docker run --rm -i \
    -v "$TEXTFILE_DIR_ABS:/metrics" \
    alpine:3.20 \
    sh -c "cat > /metrics/$METRICS_FILE_NAME"
}

backup_path="${1:-}"
if [[ -n "$backup_path" ]]; then
  if [[ "$backup_path" != /* ]]; then
    backup_path="$(abs_path "$backup_path")"
  fi
  backup_dir="$(dirname "$backup_path")"
  backup_basename="$(basename "$backup_path")"
else
  backup_basename="$(docker run --rm -v "$VM_BACKUP_ABS:/backup" alpine:3.20 sh -c 'ls -1t /backup/vmdata-*.tar.gz 2>/dev/null | head -n1 | xargs -r basename' || true)"
  backup_dir="$VM_BACKUP_ABS"
fi

if [[ -z "${backup_basename:-}" ]]; then
  echo "ERROR: No backup archive found in $backup_dir"
  exit 1
fi

echo "Using backup archive: $backup_dir/$backup_basename"

if docker run --rm -v "$backup_dir:/backup" alpine:3.20 sh -c "test -f /backup/${backup_basename}.sha256"; then
  echo "Verifying checksum for $backup_dir/$backup_basename"
  docker run --rm -v "$backup_dir:/backup" alpine:3.20 sh -c "cd /backup && sha256sum -c ${backup_basename}.sha256"
fi

tmp_dir="$(mktemp -d)"
container_name="vm-restore-smoke-$(date +%s)"

# shellcheck disable=SC2329
cleanup() {
  local exit_code=$?
  docker rm -f "$container_name" >/dev/null 2>&1 || true
  if [[ -d "$tmp_dir" ]]; then
    rm -rf "$tmp_dir" 2>/dev/null || true
    if [[ -d "$tmp_dir" ]]; then
      docker run --rm -v "$tmp_dir:/tmpdir" alpine:3.20 sh -c 'rm -rf /tmpdir/* /tmpdir/.[!.]* /tmpdir/..?*' >/dev/null 2>&1 || true
      rmdir "$tmp_dir" >/dev/null 2>&1 || true
    fi
  fi
  emit_restore_metrics
  exit "$exit_code"
}
trap cleanup EXIT

echo "Extracting backup to temporary path: $tmp_dir"
mkdir -p "$tmp_dir/storage"
docker run --rm \
  -v "$backup_dir:/backup:ro" \
  -v "$tmp_dir/storage:/restore" \
  alpine:3.20 \
  sh -c "tar -C /restore -xzf /backup/$backup_basename"

echo "Starting temporary VictoriaMetrics container for restore smoke test"
docker run -d --name "$container_name" \
  -p "127.0.0.1:${VM_RESTORE_TEST_PORT}:18428" \
  -v "$tmp_dir/storage:/storage" \
  "$VICTORIAMETRICS_IMAGE" \
  --storageDataPath=/storage \
  --httpListenAddr=:18428 >/dev/null

for attempt in $(seq 1 20); do
  if curl -fsS "http://127.0.0.1:${VM_RESTORE_TEST_PORT}/health" >/dev/null; then
    restore_status="1"
    success_timestamp="$(date +%s)"
    echo "Restore smoke test passed on attempt ${attempt}."
    exit 0
  fi
  sleep 2
done

echo "ERROR: Restore smoke test failed. Temporary container logs:"
docker logs "$container_name" --tail 200 || true
exit 1
