#!/bin/bash
set -e

export PATH="${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin/:${PATH}"

MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-123}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
SITE_NAME="${FRAPPE_SITE_NAME_HEADER:-ledger.pn.sorsiri.in}"

BENCH_DIR="/home/frappe/frappe-bench"

# Check if bench is fully initialized (has apps and sites)
if [ -d "${BENCH_DIR}/apps/frappe" ] && [ -d "${BENCH_DIR}/sites" ]; then
    echo "Bench fully initialized, starting..."
    cd "${BENCH_DIR}"
    bench start
fi

# Clean up any incomplete bench directory from failed runs
if [ -d "${BENCH_DIR}" ]; then
    echo "Removing incomplete bench directory..."
    rm -rf "${BENCH_DIR}"
fi

echo "Creating new bench..."

bench init --skip-redis-config-generation frappe-bench

cd frappe-bench

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