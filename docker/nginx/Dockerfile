FROM nginx:alpine

# Copy the nginx configuration into the image. This avoids a host file
# bind-mount, which can fail if a previous deploy left nginx.conf as a
# directory on the host.
COPY nginx.conf /etc/nginx/nginx.conf

# Ensure the SSL directory exists. Real certificates should be mounted
# from the host at runtime via the ./nginx/ssl:/etc/nginx/ssl:ro bind.
RUN mkdir -p /etc/nginx/ssl

EXPOSE 80 443
