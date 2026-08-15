FROM nginx:alpine

# Copy the nginx configuration into the image. This avoids a host file
# bind-mount, which can fail if a previous deploy left nginx.conf as a
# directory on the host.
COPY nginx.conf /etc/nginx/nginx.conf

# Wait for the Frappe backend service to be resolvable before starting nginx,
# because nginx resolves upstream hostnames at configuration load time.
RUN cat > /wait-and-run.sh <<'EOF'
#!/bin/sh
set -e
until getent hosts backend > /dev/null 2>&1; do
    echo "Waiting for backend DNS..."
    sleep 2
done
exec /docker-entrypoint.sh nginx -g "daemon off;"
EOF
RUN chmod +x /wait-and-run.sh

CMD ["/wait-and-run.sh"]

EXPOSE 80
