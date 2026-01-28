# Flux Ops Center - SPCS Application

Real-time grid operations dashboard built with React, DeckGL, and FastAPI, deployed on Snowpark Container Services.

## Features

- **Interactive Map**: DeckGL-powered visualization of grid infrastructure
- **Real-time Stats**: Live dashboard showing substations, transformers, customers, meters
- **Cortex AI Chat**: Natural language queries powered by Snowflake Cortex
- **Hybrid Architecture**: PostgreSQL for <20ms operations, Snowflake for analytics

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     SPCS Container                          │
├─────────────────────────────────────────────────────────────┤
│  nginx:8080                                                 │
│  ├── /           → React SPA (dist/)                       │
│  ├── /assets/    → Static files (cached 1yr)               │
│  └── /api/*      → FastAPI backend (port 3001)             │
├─────────────────────────────────────────────────────────────┤
│  FastAPI Backend                                            │
│  ├── /api/grid/*      → PostgreSQL (operational data)      │
│  ├── /api/analytics/* → Snowflake (analytical queries)     │
│  └── /api/agent/*     → Cortex Agent (AI chat)             │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### Local Development

```bash
# Install frontend dependencies
npm install

# Start frontend dev server
npm run dev

# In another terminal, start backend
cd backend
pip install -r requirements.txt
uvicorn server:app --reload --port 3001
```

### Build Docker Image

```bash
# Build frontend first
npm run build

# Build container
docker build -t flux-ops-center:latest .

# Run locally
docker run -p 8080:8080 \
  -e POSTGRES_HOST=your-postgres-host \
  -e SNOWFLAKE_ACCOUNT=your-account \
  flux-ops-center:latest
```

### Deploy to SPCS

```sql
-- 1. Create image repository
CREATE IMAGE REPOSITORY IF NOT EXISTS {{ database }}.{{ schema }}.flux_ops_center_repo;

-- 2. Get repository URL
SHOW IMAGE REPOSITORIES LIKE 'flux_ops_center_repo' IN SCHEMA {{ database }}.{{ schema }};
-- Note the repository_url column

-- 3. Tag and push image (from local machine)
-- docker tag flux-ops-center:latest <repository_url>/flux_ops_center:latest
-- docker push <repository_url>/flux_ops_center:latest

-- 4. Create compute pool
CREATE COMPUTE POOL IF NOT EXISTS flux_ops_pool
  MIN_NODES = 1
  MAX_NODES = 3
  INSTANCE_FAMILY = CPU_X64_S;

-- 5. Create service
CREATE SERVICE {{ database }}.{{ schema }}.FLUX_OPS_CENTER
  IN COMPUTE POOL flux_ops_pool
  FROM SPECIFICATION_FILE = 'service.yaml'
  EXTERNAL_ACCESS_INTEGRATIONS = (allow_all_access_integration);

-- 6. Get endpoint URL
SHOW ENDPOINTS IN SERVICE FLUX_OPS_CENTER;
```

## Configuration

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `SNOWFLAKE_WAREHOUSE` | Warehouse for analytical queries | Yes |
| `POSTGRES_HOST` | PostgreSQL hostname (hybrid mode) | No |
| `POSTGRES_USER` | PostgreSQL username | No |
| `POSTGRES_PASSWORD` | PostgreSQL password | No |

### Service Specification

Edit `service.yaml` to customize:
- Resource limits (CPU, memory)
- Min/max instances for scaling
- Environment variables

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/health` | GET | Health check |
| `/api/grid/stats` | GET | Grid statistics |
| `/api/grid/substations` | GET | List substations |
| `/api/grid/transformers` | GET | List transformers |
| `/api/analytics/load-profile` | GET | Load profile analysis |
| `/api/agent/chat` | POST | Cortex AI chat (SSE) |

## Tech Stack

**Frontend:**
- React 18 with TypeScript
- DeckGL for WebGL map visualization
- MapLibre GL for base maps
- MUI for component library

**Backend:**
- FastAPI with async support
- asyncpg for PostgreSQL
- snowflake-connector-python for Snowflake
- uvicorn with multiple workers

**Infrastructure:**
- nginx reverse proxy
- gzip compression
- Static asset caching
- Health checks for SPCS
