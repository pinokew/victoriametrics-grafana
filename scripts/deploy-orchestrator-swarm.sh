#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

MODE="${ORCHESTRATOR_MODE:-noop}"
STACK_NAME="${STACK_NAME:-monitoring}"
ENV_FILE="${ORCHESTRATOR_ENV_FILE:-/tmp/env.decrypted}"

log() {
  printf '[deploy-orchestrator] %s\n' "$*"
}

read_env_var_from_file() {
  local key file raw value
  key="$1"
  file="$2"

  if [[ ! -f "${file}" ]]; then
    return 0
  fi

  raw="$(grep -m1 "^${key}=" "${file}" || true)"
  if [[ -z "${raw}" ]]; then
    return 0
  fi

  value="${raw#*=}"
  value="${value%\"}"
  value="${value#\"}"
  printf '%s' "${value}"
}

read_env_or_default_from_file() {
  local key file default_value value
  key="$1"
  file="$2"
  default_value="$3"

  value="$(read_env_var_from_file "${key}" "${file}")"
  if [[ -n "${value}" ]]; then
    printf '%s' "${value}"
  else
    printf '%s' "${default_value}"
  fi
}

abs_project_path() {
  local path="$1"

  if [[ "${path}" = /* ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s/%s\n' "${PROJECT_ROOT}" "${path}"
  fi
}

ensure_vm_storage_not_owned_by_other_stack() {
  local env_file vm_data_dir vm_data_abs service mount_line source target conflict_found
  env_file="$1"
  conflict_found="false"

  vm_data_dir="$(read_env_or_default_from_file "VM_DATA_DIR" "${env_file}" "./.data/victoriametrics")"
  vm_data_abs="$(abs_project_path "${vm_data_dir}")"

  while IFS= read -r service; do
    [[ -n "${service}" ]] || continue
    [[ "${service}" == "${STACK_NAME}_"* ]] && continue

    while IFS='|' read -r source target; do
      [[ -n "${source}" && -n "${target}" ]] || continue
      if [[ "${source}" == "${vm_data_abs}" && "${target}" == "/storage" ]]; then
        log "ERROR: VM_DATA_DIR already used by service '${service}' (source=${source})."
        conflict_found="true"
      fi
    done < <(
      docker service inspect \
        --format '{{range .Spec.TaskTemplate.ContainerSpec.Mounts}}{{printf "%s|%s\n" .Source .Target}}{{end}}' \
        "${service}" 2>/dev/null || true
    )
  done < <(docker service ls --format '{{.Name}}')

  if [[ "${conflict_found}" == "true" ]]; then
    log "ERROR: Refusing to deploy stack '${STACK_NAME}' because another stack owns the same VictoriaMetrics storage."
    log "Use the existing stack name or remove the duplicate stack intentionally before deploying."
    exit 1
  fi
}

detect_compose_file() {
  if [[ -f "docker-compose.yaml" ]]; then
    echo "docker-compose.yaml"
  elif [[ -f "docker-compose.yml" ]]; then
    echo "docker-compose.yml"
  else
    echo ""
  fi
}

run_ansible_secrets_if_configured() {
  local infra_repo_path environment inventory_env inventory_path playbook_path

  infra_repo_path="${INFRA_REPO_PATH:-}"
  environment="${ENVIRONMENT_NAME:-}"

  if [[ -z "${infra_repo_path}" ]]; then
    log "INFRA_REPO_PATH is not set; skip ansible secrets refresh"
    return 0
  fi

  if [[ ! -d "${infra_repo_path}" ]]; then
    log "ERROR: INFRA_REPO_PATH does not exist: ${infra_repo_path}"
    exit 1
  fi

  if ! command -v ansible-playbook >/dev/null 2>&1; then
    log "ERROR: ansible-playbook not found on host"
    exit 1
  fi

  case "${environment}" in
    development|dev)
      inventory_env="dev"
      ;;
    production|prod)
      inventory_env="prod"
      ;;
    *)
      log "ERROR: unsupported ENVIRONMENT_NAME=${environment} (expected: development|production)"
      exit 1
      ;;
  esac

  inventory_path="${infra_repo_path}/ansible/inventories/${inventory_env}/hosts.yml"
  playbook_path="${infra_repo_path}/ansible/playbooks/swarm.yml"

  if [[ ! -f "${inventory_path}" ]]; then
    log "ERROR: inventory file not found: ${inventory_path}"
    exit 1
  fi
  if [[ ! -f "${playbook_path}" ]]; then
    log "ERROR: playbook file not found: ${playbook_path}"
    exit 1
  fi

  log "Refreshing Swarm secrets via Ansible (inventory=${inventory_env})"
  ANSIBLE_CONFIG="${infra_repo_path}/ansible/ansible.cfg" \
    ansible-playbook \
    -i "${inventory_path}" \
    "${playbook_path}" \
    --tags secrets
}

ensure_swarm_overlay_network() {
  local network_name scope driver
  network_name="$1"

  if docker network inspect "${network_name}" >/dev/null 2>&1; then
    scope="$(docker network inspect -f '{{.Scope}}' "${network_name}" 2>/dev/null || true)"
    driver="$(docker network inspect -f '{{.Driver}}' "${network_name}" 2>/dev/null || true)"

    if [[ "${scope}" != "swarm" || "${driver}" != "overlay" ]]; then
      log "ERROR: network '${network_name}' exists but is '${driver}/${scope}', expected 'overlay/swarm'"
      log "Set MONITORING_NETWORK_NAME to an existing swarm overlay network or remove the conflicting network."
      exit 1
    fi

    log "Using existing swarm overlay network '${network_name}'"
    return 0
  fi

  log "Creating swarm overlay network '${network_name}'"
  docker network create --driver overlay --attachable "${network_name}" >/dev/null
}

deploy_swarm() {
  local compose_file swarm_file raw_manifest deploy_manifest

  compose_file="$(detect_compose_file)"
  swarm_file="docker-compose.swarm.yml"
  raw_manifest="$(mktemp "${PROJECT_ROOT}/.${STACK_NAME}.stack.raw.XXXXXX.yml")"
  deploy_manifest="$(mktemp "${PROJECT_ROOT}/.${STACK_NAME}.stack.deploy.XXXXXX.yml")"
  trap 'rm -f "${raw_manifest:-}" "${deploy_manifest:-}"' RETURN

  if [[ -z "${compose_file}" ]]; then
    log "ERROR: compose file not found (expected docker-compose.yaml|yml)"
    exit 1
  fi
  if [[ ! -f "${swarm_file}" ]]; then
    log "ERROR: ${swarm_file} not found"
    exit 1
  fi

  if [[ ! -f "${ENV_FILE}" ]]; then
    if [[ -f ".env" ]]; then
      ENV_FILE=".env"
      log "WARNING: env.*.enc не знайдено або ORCHESTRATOR_ENV_FILE не передано. Fallback на локальний .env — тільки для dev-середовища."
    else
      log "ERROR: env file not found (${ORCHESTRATOR_ENV_FILE:-/tmp/env.decrypted}) and .env missing"
      exit 1
    fi
  fi

  run_ansible_secrets_if_configured

  ensure_vm_storage_not_owned_by_other_stack "${ENV_FILE}"

  if [[ -z "${MONITORING_NETWORK_NAME:-}" ]]; then
    MONITORING_NETWORK_NAME="$(read_env_var_from_file "MONITORING_NETWORK_NAME" "${ENV_FILE}")"
  fi

  if [[ -z "${MONITORING_NETWORK_NAME:-}" ]]; then
    log "ERROR: MONITORING_NETWORK_NAME is not set"
    exit 1
  fi
  export MONITORING_NETWORK_NAME
  log "Using MONITORING_NETWORK_NAME=${MONITORING_NETWORK_NAME}"
  ensure_swarm_overlay_network "${MONITORING_NETWORK_NAME}"

  log "Initializing bind-mount directories"
  ORCHESTRATOR_ENV_FILE="${ENV_FILE}" bash scripts/init-volumes.sh

  log "Rendering VictoriaMetrics scrape config"
  ORCHESTRATOR_ENV_FILE="${ENV_FILE}" bash scripts/render-scrape-config.sh

  log "Rendering Swarm manifest (stack=${STACK_NAME}, env_file=${ENV_FILE})"
  docker compose --env-file "${ENV_FILE}" \
    -f "${compose_file}" \
    -f "${swarm_file}" \
    config > "${raw_manifest}"

  awk 'NR==1 && $1=="name:" {next} {print}' "${raw_manifest}" > "${deploy_manifest}"

  log "Deploying stack ${STACK_NAME}"
  docker stack deploy -c "${deploy_manifest}" "${STACK_NAME}"

  log "Swarm deploy completed"
}

cd "${PROJECT_ROOT}"

case "${MODE}" in
  noop)
    log "No-op mode. Set ORCHESTRATOR_MODE=swarm to enable Phase 8 Swarm deploy path."
    ;;
  swarm)
    deploy_swarm
    ;;
  *)
    log "ERROR: unknown ORCHESTRATOR_MODE=${MODE}. Supported: noop, swarm"
    exit 1
    ;;
esac
