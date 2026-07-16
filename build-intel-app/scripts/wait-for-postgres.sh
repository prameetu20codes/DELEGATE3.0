#!/usr/bin/env sh
# Readiness gate for a "Run" step placed AFTER the Background Postgres step and
# BEFORE Run Tests. It blocks until Postgres accepts TCP connections so the
# integration test doesn't race the database startup.
#
# IMPORTANT: set the step's Image to one that actually has a probe tool.
#   - postgres:16-alpine  -> has `pg_isready` (recommended, matches the DB image)
#   - anything with `nc`   -> netcat fallback is used
# If NONE of the probes exist this script now FAILS FAST with a clear message,
# instead of looping forever pretending the DB is down.
#
# Uses `sh` (not bash) because the Harness Run step defaults to the Sh shell.
set -eu

HOST="${DB_HOST:-localhost}"
PORT="${DB_PORT:-5432}"
ATTEMPTS="${ATTEMPTS:-60}"
SLEEP="${SLEEP:-2}"

# Pick a probe that exists in this image.
if command -v pg_isready >/dev/null 2>&1; then
  PROBE="pg_isready"
elif command -v nc >/dev/null 2>&1; then
  PROBE="nc"
else
  echo "!! No probe tool found (need 'pg_isready' or 'nc')." >&2
  echo "!! Set this Run step's image to 'postgres:16-alpine' so pg_isready is available." >&2
  exit 1
fi

echo ">> Waiting for Postgres at ${HOST}:${PORT} using '${PROBE}' ..."
i=1
while [ "$i" -le "$ATTEMPTS" ]; do
  if [ "$PROBE" = "pg_isready" ]; then
    if pg_isready -h "$HOST" -p "$PORT" >/dev/null 2>&1; then
      echo ">> Postgres is ready (after ${i} attempt(s))."
      exit 0
    fi
  else
    if nc -z "$HOST" "$PORT" >/dev/null 2>&1; then
      echo ">> Postgres port is open (after ${i} attempt(s))."
      exit 0
    fi
  fi
  echo "   attempt ${i}/${ATTEMPTS} - not ready yet, sleeping ${SLEEP}s"
  i=$((i + 1))
  sleep "$SLEEP"
done

echo "!! Postgres did not become ready in ${ATTEMPTS} attempts." >&2
echo "!! If the DB log shows 'ready to accept connections', check DB_HOST/DB_PORT" >&2
echo "!! (Harness Cloud -> localhost; Kubernetes -> the Background step's id)." >&2
exit 1
