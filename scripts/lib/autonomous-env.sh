#!/usr/bin/env bash
# Helper для автономних scripts: SERVER_ENV/--env -> env.<env>.enc -> /dev/shm.

AUTONOMOUS_ENV_TMP=""
AUTONOMOUS_ENVIRONMENT=""

autonomous_env_log() {
  printf '[autonomous-env] %s\n' "$*" >&2
}

autonomous_env_die() {
  autonomous_env_log "ERROR: $*"
  exit 1
}

cleanup_autonomous_env() {
  if [[ -n "${AUTONOMOUS_ENV_TMP:-}" && -f "${AUTONOMOUS_ENV_TMP}" ]]; then
    if command -v shred >/dev/null 2>&1; then
      shred -u "${AUTONOMOUS_ENV_TMP}" 2>/dev/null || rm -f "${AUTONOMOUS_ENV_TMP}"
    else
      rm -f "${AUTONOMOUS_ENV_TMP}"
    fi
  fi
}

resolve_autonomous_environment() {
  local raw="${1:-${SERVER_ENV:-}}"

  case "${raw}" in
    dev|development) printf 'dev' ;;
    prod|production) printf 'prod' ;;
    "") autonomous_env_die "environment is not set. Set SERVER_ENV in /etc/environment or pass --env dev|prod." ;;
    *) autonomous_env_die "unsupported environment: ${raw}. Expected dev|development|prod|production." ;;
  esac
}

decrypt_autonomous_env() {
  local enc_file="$1"

  command -v sops >/dev/null 2>&1 || autonomous_env_die "sops is required"
  [[ -f "${enc_file}" ]] || autonomous_env_die "encrypted env file not found: ${enc_file}"
  [[ -d /dev/shm ]] || autonomous_env_die "/dev/shm is required for decrypted env"

  AUTONOMOUS_ENV_TMP="$(mktemp /dev/shm/env-XXXXXX)"
  chmod 600 "${AUTONOMOUS_ENV_TMP}"
  sops --decrypt --input-type dotenv --output-type dotenv "${enc_file}" > "${AUTONOMOUS_ENV_TMP}"
}

trim_env_key() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

unquote_env_value() {
  local value="$1"
  local quote

  value="${value%$'\r'}"
  if [[ "${#value}" -ge 2 ]]; then
    quote="${value:0:1}"
    if [[ "$quote" == "${value: -1}" && ( "$quote" == "'" || "$quote" == '"' ) ]]; then
      value="${value:1:${#value}-2}"
    fi
  fi

  printf '%s\n' "$value"
}

load_dotenv_without_eval() {
  local env_file="$1"
  local line
  local key
  local value

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    if [[ "$line" =~ ^[[:space:]]*export[[:space:]]+ ]]; then
      line="${line#export }"
    fi

    if [[ "$line" != *=* ]]; then
      autonomous_env_die "invalid dotenv line without '=' in decrypted env"
    fi

    key="$(trim_env_key "${line%%=*}")"
    value="${line#*=}"

    if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      autonomous_env_die "invalid dotenv key in decrypted env: ${key}"
    fi

    value="$(unquote_env_value "$value")"
    export "${key}=${value}"
  done < "${env_file}"
}

load_autonomous_env() {
  local project_root="$1"
  local environment_arg="${2:-}"
  local enc_file

  AUTONOMOUS_ENVIRONMENT="$(resolve_autonomous_environment "${environment_arg}")"
  enc_file="${project_root}/env.${AUTONOMOUS_ENVIRONMENT}.enc"

  trap cleanup_autonomous_env EXIT
  decrypt_autonomous_env "${enc_file}"

  autonomous_env_log "Loading env.${AUTONOMOUS_ENVIRONMENT}.enc from /dev/shm"
  load_dotenv_without_eval "${AUTONOMOUS_ENV_TMP}"
}
