# Frontend Dockerfile - Multi-stage build for production
# Stage 1: Build frontend assets
FROM node:20-alpine AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./
COPY frontend/package*.json ./frontend/
COPY roster/package*.json ./roster/

# Install dependencies (no package-lock.json in repo; use npm install)
RUN npm install --workspaces --include-workspace-root

# Copy source code
COPY . .

# Build frontend and roster
RUN npm run build

# Stage 2: Serve with nginx
FROM nginx:alpine

# Copy built assets
COPY --from=builder /app/hrms/public/frontend /usr/share/nginx/html/assets/hrms/frontend
COPY --from=builder /app/hrms/public/roster /usr/share/nginx/html/assets/hrms/roster

# Copy nginx config for static assets
COPY docker/nginx/frontend.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]