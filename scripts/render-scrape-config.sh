#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_FILE="$ROOT_DIR/victoria-metrics/scrape-config.tmpl.yml"
OUTPUT_FILE="$ROOT_DIR/victoria-metrics/scrape-config.yml"
ENV_FILE="$ROOT_DIR/.env"

if [[ -z "${KOHA_OPAC_URL:-}" ]] && [[ -f "$ENV_FILE" ]]; then
  KOHA_OPAC_URL="$(grep '^KOHA_OPAC_URL=' "$ENV_FILE" | head -n1 | cut -d= -f2-)"
fi

if [[ -z "${KOHA_STAFF_URL:-}" ]] && [[ -f "$ENV_FILE" ]]; then
  KOHA_STAFF_URL="$(grep '^KOHA_STAFF_URL=' "$ENV_FILE" | head -n1 | cut -d= -f2-)"
fi

: "${KOHA_OPAC_URL:?KOHA_OPAC_URL is required (env var or .env)}"
: "${KOHA_STAFF_URL:?KOHA_STAFF_URL is required (env var or .env)}"

if [[ ! "$KOHA_OPAC_URL" =~ ^https?:// ]]; then
  echo "KOHA_OPAC_URL must start with http:// or https://" >&2
  exit 1
fi

if [[ ! "$KOHA_STAFF_URL" =~ ^https?:// ]]; then
  echo "KOHA_STAFF_URL must start with http:// or https://" >&2
  exit 1
fi

escape_sed() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

opac_escaped="$(escape_sed "$KOHA_OPAC_URL")"
staff_escaped="$(escape_sed "$KOHA_STAFF_URL")"

tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

sed \
  -e "s/__KOHA_OPAC_URL__/${opac_escaped}/g" \
  -e "s/__KOHA_STAFF_URL__/${staff_escaped}/g" \
  "$TEMPLATE_FILE" > "$tmp_file"

mv "$tmp_file" "$OUTPUT_FILE"

echo "Rendered $OUTPUT_FILE from template."