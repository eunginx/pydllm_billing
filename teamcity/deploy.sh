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

	# Docker bind-mounts fail if the host path type does not match the
	# container target (file vs directory). A previous failed deploy may
	# have left nginx.conf as a directory, so clean it up and ensure ssl
	# is a directory *before* extracting the new files.
	ensure_nginx_mount_paths "${target_dir}"

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

	# Verify mount paths are still correct after extraction.
	ensure_nginx_mount_paths "${target_dir}"
}

ensure_nginx_mount_paths() {
	local deploy_path="$1"
	local nginx_dir="${deploy_path}/docker/nginx"
	local conf_path="${nginx_dir}/nginx.conf"
	local ssl_dir="${nginx_dir}/ssl"

	if [ -d "${conf_path}" ]; then
		echo "WARNING: ${conf_path} is a directory from a previous failed deploy; removing it."
		rm -rf "${conf_path}"
	fi

	if [ ! -f "${conf_path}" ]; then
		echo "WARNING: ${conf_path} does not exist after sync; copying from repo."
		mkdir -p "${nginx_dir}"
		cp "${deploy_path}/docker/nginx/nginx.conf" "${conf_path}" || true
	fi

	if [ -f "${ssl_dir}" ]; then
		echo "WARNING: ${ssl_dir} is a file; removing it so it can be a directory."
		rm -f "${ssl_dir}"
	fi

	mkdir -p "${ssl_dir}"
}

check_nginx_mount() {
	local deploy_path="$1"
	local conf_path="${deploy_path}/docker/nginx/nginx.conf"

	if [ ! -f "${conf_path}" ]; then
		echo "ERROR: ${conf_path} is missing or is not a regular file."
		ls -lah "${deploy_path}/docker/nginx/" || true
		exit 1
	fi

	echo "OK: ${conf_path} is a regular file."
}

deploy_locally() {
	local deploy_path="$1"

	echo "=== Local deploy: checkout=${CHECKOUT_DIR}, deploy_path=${deploy_path} ==="

	# Build frontend assets in the TeamCity checkout directory.
	# The checkout is guaranteed to contain the repo files.
	build_frontend "${CHECKOUT_DIR}"

	# Sync the built repo (excluding .git and node_modules) to the runtime path.
	sync_to_deploy_path "${CHECKOUT_DIR}" "${deploy_path}"

	# Fail fast with a clear message if nginx.conf is not a file.
	check_nginx_mount "${deploy_path}"

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

		# Ensure Docker bind-mount source types match container targets.
		# A previous failed deploy may have left nginx.conf as a directory.
		if [ -d "${deploy_path}/docker/nginx/nginx.conf" ]; then
			echo "WARNING: ${deploy_path}/docker/nginx/nginx.conf is a directory from a previous failed deploy; removing it."
			rm -rf "${deploy_path}/docker/nginx/nginx.conf"
		fi
		if [ -f "${deploy_path}/docker/nginx/ssl" ]; then
			echo "WARNING: ${deploy_path}/docker/nginx/ssl is a file; removing it."
			rm -f "${deploy_path}/docker/nginx/ssl"
		fi
		mkdir -p "${deploy_path}/docker/nginx/ssl"

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

		# Verify mount paths are still correct after extraction.
		if [ -d "${deploy_path}/docker/nginx/nginx.conf" ]; then
			rm -rf "${deploy_path}/docker/nginx/nginx.conf"
		fi
		if [ -f "${deploy_path}/docker/nginx/ssl" ]; then
			rm -f "${deploy_path}/docker/nginx/ssl"
		fi
		mkdir -p "${deploy_path}/docker/nginx/ssl"

		# Fail fast with a clear message if nginx.conf is not a file.
		if [ ! -f "${deploy_path}/docker/nginx/nginx.conf" ]; then
			echo "ERROR: ${deploy_path}/docker/nginx/nginx.conf is missing or is not a regular file."
			ls -lah "${deploy_path}/docker/nginx/" || true
			exit 1
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

