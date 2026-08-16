#!/usr/bin/env bash
set -euo pipefail

# Local build script for the pydllm_billing production image.
#
# Builds the upstream frappe/frappe_docker layered Containerfile with our
# apps (erpnext + payments + hrms) pre-installed at build time.
#
# Usage:
#   ./scripts/build-local.sh            # build for the host arch (arm64 on Mac)
#   ./scripts/build-local.sh --push     # also push to GHCR (needs docker login)
#
# Note: this builds for the HOST architecture. On an Apple Silicon Mac that is
# arm64. The CI workflow (deploy-portainer.yml) builds amd64 on ubuntu-latest
# for EC2, so you do NOT need to push a local arm64 image for EC2.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAPPE_DOCKER_DIR="${REPO_ROOT}/.build/frappe_docker"
APPS_JSON="${REPO_ROOT}/.github/helper/apps.json"

FRAPPE_BRANCH="${FRAPPE_BRANCH:-version-16}"
IMAGE="${IMAGE:-ghcr.io/eunginx/pydllm_billing:latest}"

PUSH=0
if [[ "${1:-}" == "--push" ]]; then
    PUSH=1
fi

echo "=== Cloning frappe/frappe_docker (if needed) ==="
if [ ! -d "${FRAPPE_DOCKER_DIR}/.git" ]; then
    mkdir -p "$(dirname "${FRAPPE_DOCKER_DIR}")"
    git clone --depth 1 https://github.com/frappe/frappe_docker "${FRAPPE_DOCKER_DIR}"
else
    git -C "${FRAPPE_DOCKER_DIR}" pull --ff-only
fi

echo "=== Building image: ${IMAGE} (branch ${FRAPPE_BRANCH}) ==="
docker buildx build \
    --progress=plain \
    --build-arg "FRAPPE_BRANCH=${FRAPPE_BRANCH}" \
    --secret "id=apps_json,src=${APPS_JSON}" \
    --tag "${IMAGE}" \
    --file "${FRAPPE_DOCKER_DIR}/images/layered/Containerfile" \
    "${FRAPPE_DOCKER_DIR}"

if [ "${PUSH}" -eq 1 ]; then
    echo "=== Pushing ${IMAGE} ==="
    docker push "${IMAGE}"
fi

echo "=== Done ==="
