#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: seed-planets-sql.sh \
  --server <sql-server-name> \
  --database <database-name> \
  [--auth aad|managed|sql] \
  [--user <sql-user>] \
  [--password-env <env-var>]

Environment variables:
  ACCESS_TOKEN   When --auth aad or managed, export ACCESS_TOKEN with an Azure AD token for https://database.windows.net/.
  SQL_PASSWORD   When --auth sql (or use --password-env to point at another variable), supply the SQL authentication password.

Examples:
  # Managed identity from Azure VM/Container with token already fetched via `az account get-access-token --resource https://database.windows.net/`.
  ACCESS_TOKEN=$(az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv) \
  /path/to/seed-planets-sql.sh --server myserver.database.windows.net --database Planets --auth managed

  # SQL auth
  SQL_PASSWORD='SuperSecurePW!' \
  /path/to/seed-planets-sql.sh --server myserver.database.windows.net --database Planets --auth sql --user planetsadmin
EOF
}

SERVER=""
DATABASE=""
AUTH_MODE="aad"
SQL_USER=""
PASSWORD_ENV="SQL_PASSWORD"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/../Data/Sql/planets.sql"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server)
      SERVER="$2"; shift 2;;
    --database)
      DATABASE="$2"; shift 2;;
    --auth)
      AUTH_MODE="$2"; shift 2;;
    --user)
      SQL_USER="$2"; shift 2;;
    --password-env)
      PASSWORD_ENV="$2"; shift 2;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "[Error] Unknown argument: $1" >&2
      usage
      exit 1;;
  esac
done

if [[ -z "$SERVER" || -z "$DATABASE" ]]; then
  echo "[Error] --server and --database are required." >&2
  usage
  exit 1
fi

if [[ ! -f "$SQL_FILE" ]]; then
  echo "[Error] SQL file not found: $SQL_FILE" >&2
  exit 1
fi

case "$AUTH_MODE" in
  aad|managed)
    if [[ -z "${ACCESS_TOKEN:-}" ]]; then
      echo "[Error] ACCESS_TOKEN environment variable must be set for $AUTH_MODE authentication." >&2
      exit 1
    fi
    echo "[Info] Using Azure AD access token authentication."
    sqlcmd -S "$SERVER" -d "$DATABASE" -G -P "$ACCESS_TOKEN" -l 30 -b -i "$SQL_FILE"
    ;;
  sql)
    if [[ -z "$SQL_USER" ]]; then
      echo "[Error] --user is required for sql authentication." >&2
      exit 1
    fi
    PASSWORD_VALUE="${!PASSWORD_ENV:-}"
    if [[ -z "$PASSWORD_VALUE" ]]; then
      echo "[Error] Password environment variable '$PASSWORD_ENV' is empty or not set." >&2
      exit 1
    fi
    echo "[Info] Using SQL authentication with user '$SQL_USER'."
    sqlcmd -S "$SERVER" -d "$DATABASE" -U "$SQL_USER" -P "$PASSWORD_VALUE" -l 30 -b -i "$SQL_FILE"
    ;;
  *)
    echo "[Error] Unsupported auth mode: $AUTH_MODE" >&2
    usage
    exit 1
    ;;
 esac

echo "[Success] Planets schema and seed applied to $SERVER/$DATABASE."
