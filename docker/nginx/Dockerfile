FROM nginx:alpine

# Copy the nginx configuration into the image. This avoids a host file
# bind-mount, which can fail if a previous deploy left nginx.conf as a
# directory on the host.
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80
