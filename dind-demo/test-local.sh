#!/usr/bin/env bash
#
# Run this on YOUR machine FIRST to confirm the Docker Hub creds + build work,
# before wiring it into Harness. This mirrors exactly what the pipeline Run step does.
#
# Usage:
#   export DOCKER_PASSWORD='dckr_pat_xxx'      # your (rotated!) Docker Hub PAT
#   ./test-local.sh myapp                       # -> builds/pushes prameet2025/myapp
#
set -euo pipefail

DOCKER_USER="prameet2025"
REPO="${1:?Pass the repo name, e.g. ./test-local.sh myapp}"
TAG="${2:-local-test}"
IMAGE="${DOCKER_USER}/${REPO}"

: "${DOCKER_PASSWORD:?Set DOCKER_PASSWORD env var to your Docker Hub PAT}"

echo ">> Logging in to Docker Hub as ${DOCKER_USER}"
echo "${DOCKER_PASSWORD}" | docker login -u "${DOCKER_USER}" --password-stdin

echo ">> Building ${IMAGE}:${TAG}"
docker build \
  --build-arg BUILD_TIME="$(date -u +%FT%TZ)" \
  -t "${IMAGE}:${TAG}" \
  "$(dirname "$0")"

echo ">> Pushing ${IMAGE}:${TAG}"
docker push "${IMAGE}:${TAG}"

echo ">> Done. Pull test:"
echo "   docker run --rm ${IMAGE}:${TAG}"
