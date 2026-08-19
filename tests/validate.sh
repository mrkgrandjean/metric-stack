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

echo "== postgres datasource sets database inside jsonData (root-level 'database' is ignored for queries since Grafana 12.2, grafana/grafana#112418) =="
if ! awk '
  /^    jsonData:/ { f=1; next }
  f && /^      / { if ($0 ~ /database:/) found=1; next }
  f { f=0 }
  END { exit !found }
' dashboards/grafana/provisioning/datasources/postgres.yml; then
  echo "MISSING database under jsonData in dashboards/grafana/provisioning/datasources/postgres.yml"
  exit 1
fi

echo "All checks passed."
