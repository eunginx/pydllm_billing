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

build_frontend() {
	local deploy_path="$1"
	local install_cmd
	local build_cmd

	if command -v yarn >/dev/null 2>&1; then
		install_cmd="yarn install"
		build_cmd="yarn build"
	elif command -v npm >/dev/null 2>&1; then
		install_cmd="npm install"
		build_cmd="npm run build"
	else
		echo "=== Building frontend assets inside Node.js Docker container ==="
		docker run --rm \
			-v "${deploy_path}:${deploy_path}" \
			-w "${deploy_path}" \
			node:20-slim \
			bash -c "corepack enable && cd '${deploy_path}' && yarn install && yarn build"
		return
	fi

	echo "=== Building frontend assets with local Node tooling ==="
	cd "${deploy_path}"
	${install_cmd}
	${build_cmd}
}

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
	fi

	build_frontend "${deploy_path}"

	cd "${deploy_path}"

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

		build_frontend() {
			local deploy_path="\$1"
			if command -v yarn >/dev/null 2>&1; then
				echo "=== Building frontend assets with local yarn ==="
				cd "\${deploy_path}"
				yarn install
				yarn build
			elif command -v npm >/dev/null 2>&1; then
				echo "=== Building frontend assets with local npm ==="
				cd "\${deploy_path}"
				npm install
				npm run build
			else
				echo "=== Building frontend assets inside Node.js Docker container ==="
				docker run --rm \\
					-v "\${deploy_path}:\${deploy_path}" \\
					-w "\${deploy_path}" \\
					node:20-slim \\
					bash -c "corepack enable && cd '\${deploy_path}' && yarn install && yarn build"
			fi
		}

		if [ -d "${deploy_path}/.git" ]; then
			cd "${deploy_path}"
			git fetch origin
			git reset --hard "origin/${BRANCH}"
		else
			git clone --branch "${BRANCH}" --single-branch "${REPO_URL}" "${deploy_path}"
		fi

		build_frontend "${deploy_path}"

		cd "${deploy_path}"

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

