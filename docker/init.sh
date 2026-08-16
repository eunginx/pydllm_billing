#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# INIT SCRIPT STARTUP DIAGNOSTICS
# ============================================================
log() {
    echo "[INIT] $(date -Is) $*"
}

log "============================================================"
log "INIT SCRIPT START"
log "============================================================"
log "PID=$$"
log "USER=$(id -un)"
log "UID=$(id -u)"
log "GID=$(id -g)"
log "PWD=$(pwd)"
log "SCRIPT=$0"
log "HOSTNAME=$(hostname)"
log "PATH=$PATH"

log "Script location:"
ls -lah "$(dirname "$0")" 2>/dev/null || true

log "Checking expected files..."
for path in \
    "/workspace" \
    "/workspace/docker" \
    "/workspace/docker/init.sh" \
    "/opt/pydllm_billing" \
    "/opt/pydllm_billing/docker" \
    "/opt/pydllm_billing/docker/init.sh"
do
    if [ -e "$path" ]; then
        log "FOUND: $path"
        ls -ld "$path" 2>/dev/null || true
    else
        log "MISSING: $path"
    fi
done

log "Environment (filtered):"
env | grep -v -E 'PASSWORD|SECRET|TOKEN|KEY|API_KEY|MASTER_KEY|DATABASE_URL' | sort

log "============================================================"
log "INIT SCRIPT CONTINUING"
log "============================================================"

# ============================================================
# ERROR TRAP
# ============================================================
trap 'rc=$?; log "[ERROR] command failed: ${BASH_COMMAND}"; log "[ERROR] exit_code=${rc} line=${LINENO}"; exit "$rc"' ERR
trap 'log "[EXIT] rc=$?"' EXIT

# ============================================================
# MAIN INIT LOGIC
# ============================================================
# The base image sets NODE_VERSION (e.g. 24.13.0), not NODE_VERSION_DEVELOP.
# Prepend the matching nvm node bin dir to PATH so `node`/`npm` resolve.
NODE_VERSION="${NODE_VERSION:-24.13.0}"
export PATH="${NVM_DIR}/versions/node/v${NODE_VERSION}/bin/:${PATH}"

MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-123}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
SITE_NAME="${FRAPPE_SITE_NAME_HEADER:-ledger.pn.sorsiri.in}"

BENCH_DIR="/home/frappe/frappe-bench"

# If the bench is already initialized, just start it.
if [ -d "${BENCH_DIR}/apps/frappe" ]; then
    log "Bench already exists, skipping init"
    cd "${BENCH_DIR}"
    bench start
fi

log "Creating new bench..."

# sites/ and logs/ are named volume mounts and already exist, so bench init
# cannot create frappe-bench directly (non-empty dir). Initialize into a
# temp dir and merge the results, preserving the volume mounts.
tmp_bench="$(mktemp -d /tmp/frappe-bench.XXXXXX)"
bench init --skip-redis-config-generation "${tmp_bench}"
cp -a "${tmp_bench}/." "${BENCH_DIR}/"
rm -rf "${tmp_bench}"

cd "${BENCH_DIR}"

# Use containers instead of localhost
bench set-mariadb-host mariadb
bench set-redis-cache-host redis://redis:6379
bench set-redis-queue-host redis://redis:6379
bench set-redis-socketio-host redis://redis:6379

# Remove redis, watch from Procfile
sed -i '/redis/d' ./Procfile
sed -i '/watch/d' ./Procfile

bench get-app erpnext
bench get-app hrms

bench new-site "${SITE_NAME}" \
    --force \
    --mariadb-root-password "${MYSQL_ROOT_PASSWORD}" \
    --admin-password "${ADMIN_PASSWORD}" \
    --no-mariadb-socket

bench --site "${SITE_NAME}" install-app hrms
bench --site "${SITE_NAME}" set-config developer_mode 1
bench --site "${SITE_NAME}" enable-scheduler
bench --site "${SITE_NAME}" clear-cache
bench use "${SITE_NAME}"

bench start