#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/scripts"
ENV_FILE_ARG=""
DRY_RUN="false"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN="true"
      ;;
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

guard_path() {
  local path="$1"
  if [[ -z "$path" || "$path" == "/" || "$path" == "." || "$path" == ".." ]]; then
    echo "ERROR: unsafe path: $path"
    exit 1
  fi
}

run_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] $*"
    return 0
  fi
  "$@"
}

DOCKER_IMAGE="$(read_env_or_default INIT_VOLUMES_HELPER_IMAGE "$ENV_FILE" "alpine:3.20")"
HAS_DOCKER=false
CAN_SUDO_NOPASS=false

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  HAS_DOCKER=true
fi

if [[ "${EUID}" -ne 0 ]] && command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
  CAN_SUDO_NOPASS=true
fi

if [[ "$DRY_RUN" == "true" ]]; then
  if [[ "${EUID}" -eq 0 ]]; then
    PRIV_MODE="root"
  elif $HAS_DOCKER; then
    PRIV_MODE="docker"
  elif $CAN_SUDO_NOPASS; then
    PRIV_MODE="sudo"
  else
    PRIV_MODE="local"
  fi
else
  if [[ "${EUID}" -eq 0 ]]; then
    PRIV_MODE="root"
  elif $HAS_DOCKER; then
    PRIV_MODE="docker"
  elif $CAN_SUDO_NOPASS; then
    PRIV_MODE="sudo"
  else
    echo "ERROR: Need privileges for volume paths. Install Docker (recommended) or configure passwordless sudo."
    exit 1
  fi
fi

mkdir_with_docker() {
  local dir_path="$1"
  local parent_dir
  local base_name
  parent_dir="$(dirname "$dir_path")"
  base_name="$(basename "$dir_path")"
  run_cmd docker run --rm \
    -e BASE_NAME="$base_name" \
    -v "$parent_dir:/host-parent" \
    "$DOCKER_IMAGE" \
    sh -ceu "mkdir -p \"/host-parent/\$1\"" _ "$base_name"
}

chown_with_docker() {
  local owner="$1"
  local target="$2"
  run_cmd docker run --rm \
    -e OWNER="$owner" \
    -v "$target:/target" \
    "$DOCKER_IMAGE" \
    sh -ceu "chown \"\$1\" /target" _ "$owner"
}

chmod_with_docker() {
  local mode="$1"
  local target="$2"
  run_cmd docker run --rm \
    -e MODE="$mode" \
    -v "$target:/target" \
    "$DOCKER_IMAGE" \
    sh -ceu "chmod \"\$1\" /target" _ "$mode"
}

ensure_dir() {
  local dir="$1"

  if run_cmd mkdir -p "$dir"; then
    return 0
  fi

  case "$PRIV_MODE" in
    root)
      run_cmd mkdir -p "$dir"
      ;;
    sudo)
      run_cmd sudo -n mkdir -p "$dir"
      ;;
    docker)
      mkdir_with_docker "$dir"
      ;;
    *)
      echo "ERROR: Cannot create directory $dir without privileges"
      return 1
      ;;
  esac
}

run_chown() {
  local owner="$1"
  local target="$2"

  if run_cmd chown "$owner" "$target"; then
    return 0
  fi

  case "$PRIV_MODE" in
    sudo)
      run_cmd sudo -n chown "$owner" "$target"
      ;;
    docker)
      chown_with_docker "$owner" "$target"
      ;;
    *)
      echo "ERROR: Cannot change owner for $target to $owner"
      return 1
      ;;
  esac
}

run_chmod() {
  local mode="$1"
  local target="$2"

  if run_cmd chmod "$mode" "$target"; then
    return 0
  fi

  case "$PRIV_MODE" in
    sudo)
      run_cmd sudo -n chmod "$mode" "$target"
      ;;
    docker)
      chmod_with_docker "$mode" "$target"
      ;;
    *)
      echo "ERROR: Cannot change mode for $target to $mode"
      return 1
      ;;
  esac
}

VM_DATA_DIR="$(read_env_or_default VM_DATA_DIR "$ENV_FILE" "./.data/victoriametrics")"
VM_BACKUP_DIR="$(read_env_or_default VM_BACKUP_DIR "$ENV_FILE" "./.backups/victoriametrics")"
GRAFANA_DATA_DIR="$(read_env_or_default GRAFANA_DATA_DIR "$ENV_FILE" "./.data/grafana")"
GRAFANA_LOGS_DIR="$(read_env_or_default GRAFANA_LOGS_DIR "$ENV_FILE" "./.data/grafana-logs")"
NODE_EXPORTER_TEXTFILE_DIR="$(read_env_or_default NODE_EXPORTER_TEXTFILE_DIR "$ENV_FILE" "./.data/node-exporter-textfile")"
GRAFANA_CONTAINER_USER="$(read_env_or_default GRAFANA_CONTAINER_USER "$ENV_FILE" "0")"

if [[ "$GRAFANA_CONTAINER_USER" == *:* ]]; then
  GRAFANA_OWNER="$GRAFANA_CONTAINER_USER"
else
  GRAFANA_OWNER="${GRAFANA_CONTAINER_USER}:${GRAFANA_CONTAINER_USER}"
fi

VM_OWNER="0:0"

if [[ -n "${SUDO_UID:-}" ]] && [[ -n "${SUDO_GID:-}" ]]; then
  TEXTFILE_OWNER="${SUDO_UID}:${SUDO_GID}"
else
  TEXTFILE_OWNER="$(id -u):$(id -g)"
fi

VM_DATA_PATH="$(abs_path "$VM_DATA_DIR")"
VM_BACKUP_PATH="$(abs_path "$VM_BACKUP_DIR")"
NODE_EXPORTER_TEXTFILE_PATH="$(abs_path "$NODE_EXPORTER_TEXTFILE_DIR")"
GRAFANA_DATA_PATH="$(abs_path "$GRAFANA_DATA_DIR")"
GRAFANA_LOGS_PATH="$(abs_path "$GRAFANA_LOGS_DIR")"

guard_path "$VM_DATA_PATH"
guard_path "$VM_BACKUP_PATH"
guard_path "$NODE_EXPORTER_TEXTFILE_PATH"
guard_path "$GRAFANA_DATA_PATH"
guard_path "$GRAFANA_LOGS_PATH"

declare -a DIRS
DIRS=(
  "$VM_DATA_PATH|$VM_OWNER|0750"
  "$VM_BACKUP_PATH|$VM_OWNER|0750"
  "$NODE_EXPORTER_TEXTFILE_PATH|$TEXTFILE_OWNER|0775"
  "$GRAFANA_DATA_PATH|$GRAFANA_OWNER|0750"
  "$GRAFANA_LOGS_PATH|$GRAFANA_OWNER|0750"
)

echo "Initializing monitoring volume directories"
case "$PRIV_MODE" in
  root) echo "Privilege mode: root" ;;
  sudo) echo "Privilege mode: passwordless sudo" ;;
  docker) echo "Privilege mode: Docker ephemeral helper (${DOCKER_IMAGE})" ;;
  local) echo "Privilege mode: local (dry-run fallback)" ;;
esac

for entry in "${DIRS[@]}"; do
  IFS='|' read -r dir owner mode <<< "$entry"

  echo "- ensure dir: $dir"
  ensure_dir "$dir"

  echo "  owner: $owner"
  run_chown "$owner" "$dir"

  echo "  mode: $mode"
  run_chmod "$mode" "$dir"
done

echo "Volume initialization completed."
if [[ "$DRY_RUN" == "true" ]]; then
  echo "Dry-run mode: no filesystem changes were applied."
fi
