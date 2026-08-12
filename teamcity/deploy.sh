#!/usr/bin/env bash
set -eo pipefail

# TeamCity deployment script for pydllm_billing / Frappe HR
#
# This script can deploy in two modes:
#   1. Local: TeamCity agent runs on the production host.
#            Set only DEPLOY_PATH. The script runs git/docker locally.
#   2. Remote: TeamCity agent deploys over SSH.
#             Set DEPLOY_HOST and DEPLOY_PATH. SSH access must be configured.
#
# Expected environment variables (configure as TeamCity parameters):
#   DEPLOY_HOST          Optional. SSH target host (e.g. user@ledger.pn.sorsiri.in)
#   DEPLOY_PATH          Required. Path where the repo is cloned (e.g. /opt/pydllm_billing)
#   MYSQL_ROOT_PASSWORD  MariaDB root password
#   ADMIN_PASSWORD       Frappe Administrator password

REPO_URL="https://github.com/eunginx/pydllm_billing.git"
BRANCH="main"

DEPLOY_HOST="${DEPLOY_HOST:-}"
DEPLOY_PATH="${DEPLOY_PATH:-/opt/pydllm_billing}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-change-me-to-a-strong-password}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-change-me-to-a-strong-password}"

deploy_locally() {
	local deploy_path="$1"

	echo "=== Local deploy to ${deploy_path} ==="

	if [ -d "${deploy_path}/.git" ]; then
		cd "${deploy_path}"
		git fetch origin
		git reset --hard "origin/${BRANCH}"
	else
		mkdir -p "${deploy_path}"
		git clone --branch "${BRANCH}" --single-branch "${REPO_URL}" "${deploy_path}"
		cd "${deploy_path}"
	fi

	yarn install
	yarn build

	if [ ! -f .env ]; then
		cp .env.example .env
		echo "WARNING: .env did not exist; copied from .env.example. Update secrets before next deploy."
	fi

	docker compose -f docker/docker-compose.prod.yml pull
	docker compose -f docker/docker-compose.prod.yml down
	docker compose -f docker/docker-compose.prod.yml up -d --build

	docker image prune -f
}

deploy_remotely() {
	local deploy_host="$1"
	local deploy_path="$2"

	echo "=== Remote deploy via SSH to ${deploy_host}:${deploy_path} ==="

	ssh "${deploy_host}" <<EOF
		set -euo pipefail

		if [ -d "${deploy_path}/.git" ]; then
			cd "${deploy_path}"
			git fetch origin
			git reset --hard "origin/${BRANCH}"
		else
			git clone --branch "${BRANCH}" --single-branch "${REPO_URL}" "${deploy_path}"
			cd "${deploy_path}"
		fi

		yarn install
		yarn build

		if [ ! -f .env ]; then
			cp .env.example .env
			echo "WARNING: .env did not exist; copied from .env.example. Update secrets before next deploy."
		fi

		docker compose -f docker/docker-compose.prod.yml pull
		docker compose -f docker/docker-compose.prod.yml down
		docker compose -f docker/docker-compose.prod.yml up -d --build

		docker image prune -f
EOF
}

if [ -z "$DEPLOY_HOST" ]; then
	deploy_locally "$DEPLOY_PATH"
else
	deploy_remotely "$DEPLOY_HOST" "$DEPLOY_PATH"
fi

echo "=== Deployment complete ==="

