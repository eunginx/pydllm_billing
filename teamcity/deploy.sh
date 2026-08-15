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

# TeamCity checks out the repo into the current working directory.
# We build frontend assets here to avoid Docker volume mount issues with /opt.
CHECKOUT_DIR="$(pwd)"

build_frontend() {
	local build_dir="$1"

	if ! command -v npm >/dev/null 2>&1; then
		echo "ERROR: npm is not installed on the TeamCity agent."
		echo "Install Node.js 20 LTS on the agent, or install npm in the agent environment."
		echo "For Debian/Ubuntu: curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt-get install -y nodejs"
		exit 1
	fi

	echo "=== Building frontend assets with local npm ==="
	cd "${build_dir}"
	npm install
	npm run build
}

sync_to_deploy_path() {
	local source_dir="$1"
	local target_dir="$2"

	echo "=== Syncing built assets from ${source_dir} to ${target_dir} ==="

	if [ "${source_dir%/}" = "${target_dir%/}" ]; then
		echo "Source and target are the same; skipping sync."
		return
	fi

	mkdir -p "${target_dir}"

	if command -v rsync >/dev/null 2>&1; then
		rsync -a --delete \
			--exclude='.git' \
			--exclude='node_modules' \
			"${source_dir%/}/" "${target_dir%/}/"
	else
		echo "rsync not found; using tar pipeline instead."
		cd "${source_dir}"
		tar -cf - \
			--exclude='.git' \
			--exclude='node_modules' \
			. | tar -xf - -C "${target_dir}"
	fi
}

deploy_locally() {
	local deploy_path="$1"

	echo "=== Local deploy: checkout=${CHECKOUT_DIR}, deploy_path=${deploy_path} ==="

	# Build frontend assets in the TeamCity checkout directory.
	# The checkout is guaranteed to contain the repo files.
	build_frontend "${CHECKOUT_DIR}"

	# Sync the built repo (excluding .git and node_modules) to the runtime path.
	sync_to_deploy_path "${CHECKOUT_DIR}" "${deploy_path}"

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

		CHECKOUT_DIR="$(pwd)"

		build_frontend() {
			local build_dir="\$1"
			if ! command -v npm >/dev/null 2>&1; then
				echo "ERROR: npm is not installed on the remote host."
				echo "Install Node.js 20 LTS, or install npm in the remote environment."
				exit 1
			fi
			echo "=== Building frontend assets with local npm ==="
			cd "\${build_dir}"
			npm install
			npm run build
		}

		# Build in TeamCity checkout dir on remote host
		build_frontend "\${CHECKOUT_DIR}"

		# Sync built checkout to deploy path
		mkdir -p "${deploy_path}"
		if command -v rsync >/dev/null 2>&1; then
			rsync -a --delete \
				--exclude='.git' \
				--exclude='node_modules' \
				"\${CHECKOUT_DIR%/}/" "${deploy_path%/}/"
		else
			echo "rsync not found; using tar pipeline instead."
			cd "\${CHECKOUT_DIR}"
			tar -cf - \
				--exclude='.git' \
				--exclude='node_modules' \
				. | tar -xf - -C "${deploy_path}"
		fi

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

