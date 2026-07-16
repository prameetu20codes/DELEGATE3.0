#!/usr/bin/env bash
# Runs the Maven test suite and produces JUnit XML reports.
#
# Unlike the old hand-written test.js, you don't build the XML yourself: the
# maven-surefire-plugin (declared in pom.xml) writes one XML file per test class
# to target/surefire-reports/ every time `mvn test` runs. This script just runs
# the tests, then lists + summarizes those XML files so you can see exactly what
# ran. This is the same suite the Test Intelligence step executes.
set -euo pipefail

# Resolve the app dir (where pom.xml lives) regardless of where this is called from.
APP_DIR="$(cd "$(dirname "$0")/../app" && pwd)"
cd "$APP_DIR"

# Set DB_ENABLED=true to also run the Postgres integration test (needs a DB on
# DB_HOST:DB_PORT). Left unset -> DatabaseHealthTest self-skips.
: "${DB_ENABLED:=false}"
: "${DB_HOST:=localhost}"
: "${DB_PORT:=5432}"
: "${DB_NAME:=appdb}"
: "${DB_USER:=postgres}"
: "${DB_PASSWORD:=postgres}"
export DB_ENABLED DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD

REPORT_DIR="$APP_DIR/target/surefire-reports"

echo ">> Running Maven tests in: $APP_DIR"
echo ">> DB_ENABLED=$DB_ENABLED (integration test ${DB_ENABLED:+will run}${DB_ENABLED:-skips})"
echo

# -B = batch (non-interactive) mode, cleaner CI logs. Surefire emits the XML.
mvn -B test

echo
echo ">> JUnit XML reports written to: $REPORT_DIR"
ls -1 "$REPORT_DIR"/TEST-*.xml 2>/dev/null || {
  echo "!! No surefire XML found — did any tests run?" >&2
  exit 1
}

echo
echo ">> Summary (per test class):"
# Pull the testsuite line from each XML: tests / failures / errors / skipped.
for f in "$REPORT_DIR"/TEST-*.xml; do
  # Grab the <testsuite ...> attributes without needing xmllint.
  line="$(grep -o '<testsuite [^>]*>' "$f" | head -n1)"
  name="$(printf '%s' "$line" | sed -n 's/.*name="\([^"]*\)".*/\1/p')"
  tests="$(printf '%s' "$line" | sed -n 's/.*[^a-z]tests="\([^"]*\)".*/\1/p')"
  failures="$(printf '%s' "$line" | sed -n 's/.*failures="\([^"]*\)".*/\1/p')"
  errors="$(printf '%s' "$line" | sed -n 's/.*errors="\([^"]*\)".*/\1/p')"
  skipped="$(printf '%s' "$line" | sed -n 's/.*skipped="\([^"]*\)".*/\1/p')"
  printf "   %-40s tests=%s failures=%s errors=%s skipped=%s\n" \
    "$name" "${tests:-?}" "${failures:-0}" "${errors:-0}" "${skipped:-0}"
done

echo
echo ">> Point the Harness Test step's Report Paths at:"
echo "   build-intel-app/app/target/surefire-reports/*.xml"
