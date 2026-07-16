#!/usr/bin/env sh
#
# find-dockerfile.sh — locate the Dockerfile to build in a repo that may contain many.
#
# Runs at the repo root (Harness clones into the working dir). It:
#   1. Lists every Dockerfile in the repo.
#   2. Selects one, in this priority order:
#        a) $DOCKERFILE_PATH   - explicit path, if you set it
#        b) $TARGET_DIR        - first Dockerfile under this directory
#        c) fallback           - the only Dockerfile, if exactly one exists
#   3. Prints the chosen Dockerfile path and its build context (its directory).
#
# In Harness, capture DOCKERFILE and CONTEXT as output variables and use them in
# the build step (see README / pipeline.yml).
#
# Usage (local):
#   ./find-dockerfile.sh                 # auto-detect
#   TARGET_DIR=dind-demo ./find-dockerfile.sh
#   DOCKERFILE_PATH=dind-demo/Dockerfile ./find-dockerfile.sh
set -eu

echo ">> Scanning for Dockerfiles..."
# match: Dockerfile, Dockerfile.*, *.dockerfile (case-insensitive), skip .git
ALL=$(find . -type f \
        \( -iname 'Dockerfile' -o -iname 'Dockerfile.*' -o -iname '*.dockerfile' \) \
        -not -path './.git/*' \
      | sed 's|^\./||' | sort)

if [ -z "$ALL" ]; then
  echo "ERROR: no Dockerfile found in the repo." >&2
  exit 1
fi

echo "Found the following Dockerfile(s):"
echo "$ALL" | sed 's/^/   - /'

CHOSEN=""

# a) explicit path wins
if [ -n "${DOCKERFILE_PATH:-}" ]; then
  if [ -f "$DOCKERFILE_PATH" ]; then
    CHOSEN="$DOCKERFILE_PATH"
  else
    echo "ERROR: DOCKERFILE_PATH='$DOCKERFILE_PATH' does not exist." >&2
    exit 1
  fi
fi

# b) first match under TARGET_DIR
if [ -z "$CHOSEN" ] && [ -n "${TARGET_DIR:-}" ]; then
  CHOSEN=$(echo "$ALL" | grep "^${TARGET_DIR%/}/" | head -n 1 || true)
  if [ -z "$CHOSEN" ]; then
    echo "ERROR: no Dockerfile found under TARGET_DIR='$TARGET_DIR'." >&2
    exit 1
  fi
fi

# c) fallback: only if exactly one exists
if [ -z "$CHOSEN" ]; then
  COUNT=$(echo "$ALL" | wc -l | tr -d ' ')
  if [ "$COUNT" = "1" ]; then
    CHOSEN="$ALL"
  else
    echo "ERROR: multiple Dockerfiles found. Set TARGET_DIR or DOCKERFILE_PATH to choose one." >&2
    echo "       e.g. TARGET_DIR=dind-demo" >&2
    exit 1
  fi
fi

CONTEXT=$(dirname "$CHOSEN")

echo ">> Selected Dockerfile: $CHOSEN"
echo ">> Build context:       $CONTEXT"

# Export for Harness output variables (picked up when set as outputVariables)
export DOCKERFILE="$CHOSEN"
export CONTEXT="$CONTEXT"
