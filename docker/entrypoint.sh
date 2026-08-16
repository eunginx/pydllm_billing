#!/bin/bash
set -e

# Named volumes (sites/, logs/) are created root-owned by Docker. Fix
# ownership so the frappe user (UID 1000) can write to them, then drop
# privileges and run the init script as frappe.
chown -R frappe:frappe /home/frappe/frappe-bench 2>/dev/null || true

exec gosu frappe bash /usr/local/bin/init.sh
