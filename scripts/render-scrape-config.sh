#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/scripts"
TEMPLATE_FILE="$ROOT_DIR/victoria-metrics/scrape-config.tmpl.yml"
OUTPUT_FILE="$ROOT_DIR/victoria-metrics/scrape-config.yml"
ENV_FILE_ARG=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE_ARG="${2:-}"
      shift
      ;;
    *)
      echo "ERROR: Unexpected argument: $1" >&2
      exit 1
      ;;
  esac
  shift
done

# shellcheck source=scripts/lib/orchestrator-env.sh
. "$SCRIPT_DIR/lib/orchestrator-env.sh"

ENV_FILE="$(resolve_orchestrator_env_file "$ROOT_DIR" "$ENV_FILE_ARG")"

KOHA_OPAC_URL="$(read_env_or_default KOHA_OPAC_URL "$ENV_FILE" "${KOHA_OPAC_URL:-}")"
KOHA_STAFF_URL="$(read_env_or_default KOHA_STAFF_URL "$ENV_FILE" "${KOHA_STAFF_URL:-}")"
MATOMO_URL="$(read_env_or_default MATOMO_URL "$ENV_FILE" "${MATOMO_URL:-}")"

: "${KOHA_OPAC_URL:?KOHA_OPAC_URL is required (env var or env file)}"
: "${KOHA_STAFF_URL:?KOHA_STAFF_URL is required (env var or env file)}"
: "${MATOMO_URL:?MATOMO_URL is required (env var or env file)}"

if [[ ! "$KOHA_OPAC_URL" =~ ^https?:// ]]; then
  echo "KOHA_OPAC_URL must start with http:// or https://" >&2
  exit 1
fi

if [[ ! "$KOHA_STAFF_URL" =~ ^https?:// ]]; then
  echo "KOHA_STAFF_URL must start with http:// or https://" >&2
  exit 1
fi

if [[ ! "$MATOMO_URL" =~ ^https?:// ]]; then
  echo "MATOMO_URL must start with http:// or https://" >&2
  exit 1
fi

escape_sed() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

opac_escaped="$(escape_sed "$KOHA_OPAC_URL")"
staff_escaped="$(escape_sed "$KOHA_STAFF_URL")"
matomo_escaped="$(escape_sed "$MATOMO_URL")"

tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

sed \
  -e "s/__KOHA_OPAC_URL__/${opac_escaped}/g" \
  -e "s/__KOHA_STAFF_URL__/${staff_escaped}/g" \
  -e "s/__MATOMO_URL__/${matomo_escaped}/g" \
  "$TEMPLATE_FILE" > "$tmp_file"

if [[ -f "$OUTPUT_FILE" ]] && cmp -s "$tmp_file" "$OUTPUT_FILE"; then
  current_checksum="$(sha256sum "$OUTPUT_FILE" | awk '{print $1}')"
  echo "Scrape config unchanged: $OUTPUT_FILE (sha256=$current_checksum)"
  exit 0
fi

new_checksum="$(sha256sum "$tmp_file" | awk '{print $1}')"
mv "$tmp_file" "$OUTPUT_FILE"

echo "Rendered $OUTPUT_FILE from template (sha256=$new_checksum)."
