#!/usr/bin/env bash
# Helper для базових операцій із Compose або Swarm сервісами monitoring stack.

DOCKER_RUNTIME_MODE="${DOCKER_RUNTIME_MODE:-swarm}"
STACK_NAME="${STACK_NAME:-monitoring}"

docker_runtime_log() {
  printf '[docker-runtime] %s\n' "$*" >&2
}

docker_runtime_die() {
  docker_runtime_log "ERROR: $*"
  exit 1
}

docker_runtime_container_id() {
  local service="$1"
  local service_name="${STACK_NAME}_${service}"
  local container_id

  container_id="$(docker ps \
    --filter "label=com.docker.swarm.service.name=${service_name}" \
    --filter "status=running" \
    --format '{{.ID}}' | head -n1)"
  [[ -n "${container_id}" ]] || return 1
  printf '%s\n' "${container_id}"
}

docker_runtime_service_accessible() {
  local service="$1"

  case "${DOCKER_RUNTIME_MODE}" in
    compose)
      docker compose ps "${service}" >/dev/null 2>&1
      ;;
    swarm)
      docker_runtime_container_id "${service}" >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

docker_runtime_stop_service() {
  local service="$1"
  local compose_file="${2:-docker-compose.yml}"

  case "${DOCKER_RUNTIME_MODE}" in
    compose)
      docker compose -f "${compose_file}" stop "${service}"
      ;;
    swarm)
      docker service scale "${STACK_NAME}_${service}=0" >/dev/null
      ;;
    *)
      docker_runtime_die "unsupported DOCKER_RUNTIME_MODE=${DOCKER_RUNTIME_MODE}"
      ;;
  esac
}

docker_runtime_start_service() {
  local service="$1"
  local compose_file="${2:-docker-compose.yml}"

  case "${DOCKER_RUNTIME_MODE}" in
    compose)
      docker compose -f "${compose_file}" up -d "${service}" >/dev/null
      ;;
    swarm)
      docker service scale "${STACK_NAME}_${service}=1" >/dev/null
      ;;
    *)
      docker_runtime_die "unsupported DOCKER_RUNTIME_MODE=${DOCKER_RUNTIME_MODE}"
      ;;
  esac
}

docker_runtime_logs() {
  local service="$1"
  local compose_file="${2:-docker-compose.yml}"

  case "${DOCKER_RUNTIME_MODE}" in
    compose)
      docker compose -f "${compose_file}" logs "${service}" --tail 200 || true
      ;;
    swarm)
      docker service logs "${STACK_NAME}_${service}" --tail 200 || true
      ;;
    *)
      docker_runtime_die "unsupported DOCKER_RUNTIME_MODE=${DOCKER_RUNTIME_MODE}"
      ;;
  esac
}
