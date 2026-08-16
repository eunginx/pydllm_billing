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

	# Verify critical deployment artifacts exist after extraction.
	verify_deploy_artifacts "${target_dir}"
}

ensure_nginx_mount_paths() {
	local deploy_path="$1"
	local nginx_dir="${deploy_path}/docker/nginx"
	local conf_path="${nginx_dir}/nginx.conf"

	# nginx.conf is now baked into the Docker image, so a stale directory on
	# the host does not break the container. Remove it to keep the deploy path
	# clean and avoid confusing later diagnostics.
	if [ -d "${conf_path}" ]; then
		echo "WARNING: ${conf_path} is a directory from a previous failed deploy; removing it."
		rm -rf "${conf_path}" || true
	fi
}

verify_deploy_artifacts() {
	local deploy_path="$1"
	local required_files=(
		"docker/docker-compose.prod.yml"
		"docker/init.sh"
		"docker/nginx/nginx.conf"
		"docker/nginx/Dockerfile"
	)

	echo "=== Verifying deployment artifacts ==="
	for f in "${required_files[@]}"; do
		local full_path="${deploy_path}/${f}"
		if [ ! -e "${full_path}" ]; then
			echo "ERROR: Required artifact missing after sync: ${full_path}"
			echo "Contents of ${deploy_path}/docker/:"
			ls -lah "${deploy_path}/docker/" || true
			exit 1
		fi
		echo "OK: ${f}"
	done

	# Sanity check the init script is executable and has a valid shebang.
	local init_path="${deploy_path}/docker/init.sh"
	if [ ! -x "${init_path}" ]; then
		echo "WARNING: ${init_path} is not executable; chmod +x applied."
		chmod +x "${init_path}" || true
	fi
	# Use 'file' command if available, otherwise use 'head' for shebang check
	if command -v file >/dev/null 2>&1; then
		file "${init_path}" || true
	else
		echo "Note: 'file' command not available; checking shebang with head:"
		head -1 "${init_path}" || true
	fi
}

deploy_locally() {
	local deploy_path="$1"

	# ============================================================
	# TEAMCITY DEPLOYMENT DIAGNOSTICS
	# ============================================================
	echo "============================================================"
	echo "TEAMCITY DEPLOYMENT"
	echo "============================================================"
	echo "DATE=$(date -Is)"
	echo "HOST=$(hostname)"
	echo "USER=$(whoami)"
	echo "PWD=$(pwd)"
	echo "BUILD_CHECKOUT_DIR=${CHECKOUT_DIR:-unknown}"
	echo "DEPLOY_PATH=${deploy_path:-unknown}"
	echo "============================================================"

	# Verify TeamCity checkout directory
	echo "Repository checkout:"
	pwd
	ls -lah

	# Build frontend assets in the TeamCity checkout directory.
	# The checkout is guaranteed to contain the repo files.
	build_frontend "${CHECKOUT_DIR}"

	# Sync the built repo (excluding .git and node_modules) to the runtime path.
	sync_to_deploy_path "${CHECKOUT_DIR}" "${deploy_path}"

	# Verify deployment directory
	echo "Deployment directory:"
	ls -lah "${deploy_path}"

	echo "Docker files in deployment:"
	ls -lah "${deploy_path}/docker"

	echo "init.sh:"
	ls -lah "${deploy_path}/docker/init.sh"

	# Verify critical deployment artifacts
	test -f "${deploy_path}/docker/init.sh" || { echo "ERROR: init.sh missing"; exit 1; }
	test -f "${deploy_path}/docker/nginx/nginx.conf" || { echo "ERROR: nginx.conf missing"; exit 1; }
	test -f "${deploy_path}/docker/nginx/Dockerfile" || { echo "ERROR: nginx Dockerfile missing"; exit 1; }
	test -f "${deploy_path}/docker/docker-compose.prod.yml" || { echo "ERROR: docker-compose.prod.yml missing"; exit 1; }

	if [ ! -f .env ]; then
		cp .env.example .env
		echo "WARNING: .env did not exist; copied from .env.example. Update secrets before next deploy."
	fi

	# Safety check: the internal nginx must not try to bind privileged host
	# ports if an external reverse proxy already owns them.
	if grep -qE '^\s*-\s*"80:80"' docker-compose.prod.yml; then
		echo "ERROR: docker-compose.prod.yml still binds host port 80. The external reverse proxy owns 80/443."
		exit 1
	fi

	# The compose file uses DEPLOY_PATH to mount the repo root into /workspace.
	export DEPLOY_PATH="${deploy_path}"

	# Run docker-compose from the docker/ directory where the compose file lives.
	cd "${deploy_path}/docker"

	echo "=== Running docker compose from $(pwd) with DEPLOY_PATH=${DEPLOY_PATH} ==="

	# ============================================================
	# DOCKER COMPOSE DIAGNOSTICS BEFORE UP
	# ============================================================
	echo "=== Docker Compose resolved configuration ==="
	docker compose -f docker-compose.prod.yml config > /tmp/docker-compose-resolved.yml 2>&1 || true
	grep -n -B5 -A10 -E '/workspace|init\.sh|entrypoint|command' /tmp/docker-compose-resolved.yml 2>/dev/null || true

	# Diagnostics: show the init script on the host before starting compose.
	echo "=== Host file check ==="
	ls -lah "${DEPLOY_PATH}/docker/init.sh" || true
	if command -v file >/dev/null 2>&1; then
		file "${DEPLOY_PATH}/docker/init.sh" || true
	else
		head -1 "${DEPLOY_PATH}/docker/init.sh" || true
	fi

	docker compose -f docker-compose.prod.yml pull
	docker compose -f docker-compose.prod.yml down --remove-orphans
	docker compose -f docker-compose.prod.yml rm -f || true
	docker compose -f docker-compose.prod.yml up -d --build --force-recreate

	docker image prune -f

	# ============================================================
	# POST-DEPLOYMENT VALIDATION
	# ============================================================
	echo "=== Post-deployment validation ==="
	docker compose -f docker-compose.prod.yml ps

	echo "=== Container logs (tail 200) ==="
	docker compose -f docker-compose.prod.yml logs --no-color --tail=200 2>&1 | head -500

	# Check each service health
	for service in backend nginx mariadb redis; do
		container=$(docker compose -f docker-compose.prod.yml ps -q ${service} 2>/dev/null || true)
		if [ -n "${container}" ]; then
			status=$(docker inspect "${container}" --format '{{.State.Status}} {{.State.ExitCode}} {{.State.Error}}' 2>/dev/null || true)
			echo "Service ${service}: ${status}"
			if [ "${status}" = "exited 0 " ] || [ "${status}" = "exited 1 " ] || [ "${status}" = "exited 125 " ] || [ "${status}" = "exited 127 " ]; then
				echo "ERROR: Service ${service} exited unexpectedly"
				docker logs "${container}" --tail=200
				exit 1
			fi
		fi
	done

	echo "=== DEPLOYMENT SUCCESS ==="
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

		# Clean up stale nginx.conf directory from earlier failed deploys.
		# It is no longer bind-mounted (nginx.conf is baked into the image).
		if [ -d "${deploy_path}/docker/nginx/nginx.conf" ]; then
			echo "WARNING: ${deploy_path}/docker/nginx/nginx.conf is a stale directory; removing it."
			rm -rf "${deploy_path}/docker/nginx/nginx.conf"
		fi

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

		# The compose file uses DEPLOY_PATH to mount the repo root into /workspace.
		export DEPLOY_PATH="${deploy_path}"

		# Run compose from the docker/ directory so the project name is stable.
		cd "${deploy_path}/docker"
		echo "=== Running docker compose from \$(pwd) with DEPLOY_PATH=\${DEPLOY_PATH} ==="

		# Docker Compose diagnostics before up
		echo "=== Docker Compose resolved configuration ==="
		docker compose -f docker-compose.prod.yml config > /tmp/docker-compose-resolved.yml 2>&1 || true
		grep -n -B5 -A10 -E '/workspace|init\.sh|entrypoint|command' /tmp/docker-compose-resolved.yml 2>/dev/null || true

		# Host file check
		echo "=== Host file check ==="
		ls -lah "\${DEPLOY_PATH}/docker/init.sh" || true
		if command -v file >/dev/null 2>&1; then
			file "\${DEPLOY_PATH}/docker/init.sh" || true
		else
			head -1 "\${DEPLOY_PATH}/docker/init.sh" || true
		fi

		docker compose -f docker-compose.prod.yml pull
		docker compose -f docker-compose.prod.yml down --remove-orphans
		docker compose -f docker-compose.prod.yml rm -f || true
		docker compose -f docker-compose.prod.yml up -d --build --force-recreate

		docker image prune -f

		# Post-deployment validation
		echo "=== Post-deployment validation ==="
		docker compose -f docker-compose.prod.yml ps

		echo "=== Container logs (tail 200) ==="
		docker compose -f docker-compose.prod.yml logs --no-color --tail=200 2>&1 | head -500

		for service in backend nginx mariadb redis; do
			container=\$(docker compose -f docker-compose.prod.yml ps -q \${service} 2>/dev/null || true)
			if [ -n "\${container}" ]; then
				status=\$(docker inspect "\${container}" --format '{{.State.Status}} {{.State.ExitCode}} {{.State.Error}}' 2>/dev/null || true)
				echo "Service \${service}: \${status}"
				if [ "\${status}" = "exited 0 " ] || [ "\${status}" = "exited 1 " ] || [ "\${status}" = "exited 125 " ] || [ "\${status}" = "exited 127 " ]; then
					echo "ERROR: Service \${service} exited unexpectedly"
					docker logs "\${container}" --tail=200
					exit 1
				fi
			fi
		done

		echo "=== DEPLOYMENT SUCCESS ==="
EOF
}

if [ -z "$DEPLOY_HOST" ]; then
	deploy_locally "$DEPLOY_PATH"
else
	deploy_remotely "$DEPLOY_HOST" "$DEPLOY_PATH"
fi

echo "=== Deployment complete ==="

