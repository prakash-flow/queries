#!/usr/bin/env bash
# Run a .sql file against a MySQL container and save the result as CSV.
#
# Usage:
#   ./export.sh <query.sql> [output.csv]
#
# Saves into the result/ folder with a unique, timestamped filename unless
# an explicit output path is given. Prints the resulting CSV path to
# stdout (all other messages go to stderr), so callers can do:
#   CSV_FILE=$(./export.sh query.sql)
#
# Connects via `docker exec` into the MySQL container (no local mysql
# client needed). Credentials are read from a .env file (see .env.example)
# next to this script. That file is gitignored, so it's safe to put real
# values there.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

usage() {
  echo "Usage: $0 <query.sql> [output.csv]" >&2
  exit 1
}

[[ $# -ge 1 ]] || usage
SQL_FILE="$1"
[[ -f "$SQL_FILE" ]] || { echo "SQL file not found: $SQL_FILE" >&2; exit 1; }

if [[ $# -ge 2 ]]; then
  OUT_FILE="$2"
else
  RESULT_DIR="$SCRIPT_DIR/result"
  mkdir -p "$RESULT_DIR"
  BASENAME="$(basename "$SQL_FILE")"
  NAME="${BASENAME%.sql}"
  TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
  OUT_FILE="$RESULT_DIR/${NAME}_${TIMESTAMP}_$$.csv"
fi

[[ -f "$ENV_FILE" ]] || {
  echo ".env file not found at $ENV_FILE (copy .env.example to .env and fill in your DB credentials)" >&2
  exit 1
}
set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

: "${DB_USER:?DB_USER not set in .env}"
: "${DB_PASS:?DB_PASS not set in .env}"
: "${DB_NAME:?DB_NAME not set in .env}"
DB_CONTAINER="${DB_CONTAINER:-mysql}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"

command -v docker >/dev/null 2>&1 || { echo "docker not found in PATH" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 not found in PATH" >&2; exit 1; }
docker ps --format '{{.Names}}' | grep -qx "$DB_CONTAINER" \
  || { echo "Container '$DB_CONTAINER' is not running (check DB_CONTAINER in .env)" >&2; exit 1; }

echo "Running $SQL_FILE against ${DB_NAME}@${DB_HOST}:${DB_PORT} via container '${DB_CONTAINER}' ..." >&2

TSV_TO_CSV='
import sys, csv

ESCAPES = [("\\t", "\t"), ("\\n", "\n"), ("\\r", "\r"), ("\\0", "\0"), ("\\\\", "\\")]

writer = csv.writer(sys.stdout, lineterminator="\n")
data = sys.stdin.read()
if data.endswith("\n"):
    data = data[:-1]
if not data:
    sys.exit(0)
for line in data.split("\n"):
    fields = line.split("\t")
    row = []
    for field in fields:
        # The mysql client prints SQL NULL as the literal text "NULL" (with
        # no way to tell it apart from an actual "NULL" string value), so we
        # treat a whole-field match as NULL and blank it out for CSV.
        if field == "NULL":
            row.append("")
            continue
        for old, new in ESCAPES:
            field = field.replace(old, new)
        row.append(field)
    writer.writerow(row)
'

docker exec -i "$DB_CONTAINER" \
  mysql \
    --host="$DB_HOST" \
    --port="$DB_PORT" \
    --user="$DB_USER" \
    --password="$DB_PASS" \
    --database="$DB_NAME" \
    --batch < "$SQL_FILE" \
  | python3 -c "$TSV_TO_CSV" > "$OUT_FILE"

ROWS=$(($(wc -l < "$OUT_FILE") - 1))
echo "Saved $ROWS row(s) to $OUT_FILE" >&2
echo "$OUT_FILE"
