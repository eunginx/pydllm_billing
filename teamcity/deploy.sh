#!/usr/bin/env bash
set -euo pipefail

# TeamCity deployment script for pydllm_billing / Frappe HR
# Expected environment variables:
#   DEPLOY_HOST          SSH target host (e.g. user@ledger.pn.sorsiri.in)
#   DEPLOY_PATH          Remote path where the repo is cloned (e.g. /opt/pydllm_billing)
#   MYSQL_ROOT_PASSWORD  MariaDB root password
#   ADMIN_PASSWORD       Frappe Administrator password

REPO_URL="https://github.com/eunginx/pydllm_billing.git"
BRANCH="main"

echo "=== Deploying ${REPO_URL}@${BRANCH} to ${DEPLOY_HOST}:${DEPLOY_PATH} ==="

ssh "${DEPLOY_HOST}" <<EOF
    set -euo pipefail

    if [ -d "${DEPLOY_PATH}/.git" ]; then
        cd "${DEPLOY_PATH}"
        git fetch origin
        git reset --hard "origin/${BRANCH}"
    else
        git clone --branch "${BRANCH}" --single-branch "${REPO_URL}" "${DEPLOY_PATH}"
        cd "${DEPLOY_PATH}"
    fi

    # Build frontend assets locally (inside checkout) using the documented package.json commands
    yarn install
    yarn build

    # Ensure production environment file exists
    if [ ! -f .env ]; then
        cp .env.example .env
        echo "WARNING: .env did not exist; copied from .env.example. Update secrets before next deploy."
    fi

    # Pull images and deploy via production compose
    docker compose -f docker/docker-compose.prod.yml pull
    docker compose -f docker/docker-compose.prod.yml down
    docker compose -f docker/docker-compose.prod.yml up -d --build

    # Cleanup dangling images
    docker image prune -f
EOF

echo "=== Deployment complete ==="
