#!/usr/bin/env bash
# Validates this orchestration repo without needing the private GHCR images:
# compose file parses, dashboard JSON is well-formed, and every env var the
# compose file references is documented in .env.example.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "== docker compose config =="
docker compose config >/dev/null

echo "== dashboard JSON is valid =="
python3 -m json.tool dashboards/grafana/provisioning/dashboards/json/starter.json >/dev/null

echo "== every var referenced in docker-compose.yml is documented in .env.example =="
compose_vars=$(grep -oE '\$\{[A-Z_]+' docker-compose.yml | sed -E 's/^\$\{//' | sed -E 's/:-.*//' | sort -u)
missing=0
for var in $compose_vars; do
  if ! grep -q "^${var}=" .env.example; then
    echo "MISSING from .env.example: ${var}"
    missing=1
  fi
done
if [ "$missing" -ne 0 ]; then
  exit 1
fi

echo "== grafana service passes through the postgres credentials the datasource needs =="
for var in POSTGRES_DB POSTGRES_USER POSTGRES_PASSWORD; do
  if ! docker compose config | awk '/^  grafana:/{f=1} f && /^  [a-z-]+:$/ && !/^  grafana:/{exit} f' | grep -q "${var}:"; then
    echo "MISSING from grafana service environment: ${var}"
    exit 1
  fi
done

echo "All checks passed."
