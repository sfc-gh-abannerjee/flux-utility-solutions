# Flux Ops Center - SPCS Dockerfile
# Multi-stage build: React frontend + FastAPI backend served via nginx
#
# Build: docker build -t flux-ops-center:latest .
# Run locally: docker run -p 8080:8080 flux-ops-center:latest

# ============================================================================
# Stage 1: Build React Frontend
# ============================================================================
FROM node:20-alpine AS frontend-builder

WORKDIR /app

# Copy package files first for layer caching
COPY package.json package-lock.json ./
RUN npm ci --silent

# Copy source and build
COPY src/ ./src/
COPY public/ ./public/
COPY index.html vite.config.ts tsconfig.json ./

RUN npm run build

# ============================================================================
# Stage 2: Production Runtime
# ============================================================================
FROM python:3.11-slim

WORKDIR /app

# Install nginx for static file serving
RUN apt-get update && apt-get install -y nginx && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY backend/requirements.txt ./backend/
RUN pip install --no-cache-dir -r backend/requirements.txt

# Copy built frontend from stage 1
COPY --from=frontend-builder /app/dist ./dist/

# Copy backend code
COPY backend/ ./backend/

# Configure nginx with:
# - gzip compression (30-70% smaller responses)
# - CSP headers for DeckGL/MapLibre
# - Asset caching (1 year for immutable hashed files)
# - API proxy to FastAPI backend
RUN echo 'server { \n\
    listen 8080; \n\
    server_name _; \n\
    \n\
    # Performance: Enable gzip compression \n\
    gzip on; \n\
    gzip_vary on; \n\
    gzip_min_length 1000; \n\
    gzip_comp_level 6; \n\
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/json application/xml application/xml+rss image/svg+xml; \n\
    gzip_proxied any; \n\
    \n\
    # Security: Content Security Policy for mapping libraries \n\
    add_header Content-Security-Policy "default-src '\''self'\'' '\''unsafe-inline'\'' '\''unsafe-eval'\'' blob: data:; connect-src '\''self'\'' https://*.cartocdn.com https://*.mapbox.com https://*.snowflakecomputing.com https://unpkg.com; style-src '\''self'\'' '\''unsafe-inline'\'' https://*.cartocdn.com https://fonts.googleapis.com https://unpkg.com; font-src '\''self'\'' https://fonts.gstatic.com data:; img-src '\''self'\'' data: https://*.cartocdn.com https://*.mapbox.com blob:; worker-src '\''self'\'' blob: https://unpkg.com;" always; \n\
    \n\
    # Cache static assets (immutable hashed filenames) \n\
    location /assets/ { \n\
        root /app/dist; \n\
        expires 1y; \n\
        add_header Cache-Control "public, immutable"; \n\
    } \n\
    \n\
    # Serve React SPA \n\
    location / { \n\
        root /app/dist; \n\
        try_files $uri $uri/ /index.html; \n\
    } \n\
    \n\
    # Proxy API requests to FastAPI \n\
    location /api/ { \n\
        proxy_pass http://127.0.0.1:3001/api/; \n\
        proxy_set_header Host $host; \n\
        proxy_set_header X-Real-IP $remote_addr; \n\
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; \n\
        proxy_http_version 1.1; \n\
        proxy_set_header Upgrade $http_upgrade; \n\
        proxy_set_header Connection "upgrade"; \n\
        proxy_buffering off; \n\
        proxy_cache off; \n\
        proxy_read_timeout 300s; \n\
    } \n\
}' > /etc/nginx/sites-available/default

EXPOSE 8080

# Health check for SPCS
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080')"

# Start script: FastAPI + nginx
RUN echo '#!/bin/bash\n\
cd /app/backend\n\
uvicorn server:app --host 127.0.0.1 --port 3001 --workers 4 --timeout-keep-alive 120 &\n\
nginx -g "daemon off;"' > /app/start.sh && chmod +x /app/start.sh

CMD ["/app/start.sh"]
