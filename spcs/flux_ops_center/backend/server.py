"""
Flux Ops Center - FastAPI Backend Server

This server provides:
1. REST API for grid data (substations, transformers, meters)
2. Cortex Agent integration for natural language queries
3. Real-time SSE streaming for agent responses
4. PostgreSQL integration for sub-20ms operational queries
5. Snowflake integration for analytical queries

Architecture:
- Transactional queries → PostgreSQL (<20ms)
- Analytical queries → Snowflake (seconds)
- AI queries → Cortex Agent (streaming SSE)
"""

import os
import json
import asyncio
import logging
from typing import Optional, AsyncGenerator
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import StreamingResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from pydantic_settings import BaseSettings

import asyncpg
import snowflake.connector


# =============================================================================
# Configuration
# =============================================================================

class Settings(BaseSettings):
    """Application settings from environment variables."""
    
    # Snowflake connection
    snowflake_account: str = ""
    snowflake_user: str = ""
    snowflake_password: str = ""
    snowflake_warehouse: str = "FLUX_WH"
    snowflake_database: str = "FLUX_PROD"
    snowflake_schema: str = "PRODUCTION"
    
    # PostgreSQL connection (for hybrid architecture)
    postgres_host: str = ""
    postgres_port: int = 5432
    postgres_database: str = "postgres"
    postgres_user: str = "application"
    postgres_password: str = ""
    
    # Cortex Agent
    cortex_agent_name: str = "FLUX_GRID_AGENT"
    
    class Config:
        env_prefix = ""
        case_sensitive = False


settings = Settings()
logger = logging.getLogger("flux_ops_center")


# =============================================================================
# Database Connection Pools
# =============================================================================

class DatabasePools:
    """Manage database connection pools."""
    
    def __init__(self):
        self.pg_pool: Optional[asyncpg.Pool] = None
        self.sf_conn: Optional[snowflake.connector.SnowflakeConnection] = None
    
    async def init_postgres(self):
        """Initialize PostgreSQL connection pool."""
        if settings.postgres_host:
            self.pg_pool = await asyncpg.create_pool(
                host=settings.postgres_host,
                port=settings.postgres_port,
                database=settings.postgres_database,
                user=settings.postgres_user,
                password=settings.postgres_password,
                min_size=5,
                max_size=20,
                command_timeout=30,
            )
            logger.info("PostgreSQL pool initialized")
    
    def init_snowflake(self):
        """Initialize Snowflake connection."""
        if settings.snowflake_account:
            self.sf_conn = snowflake.connector.connect(
                account=settings.snowflake_account,
                user=settings.snowflake_user,
                password=settings.snowflake_password,
                warehouse=settings.snowflake_warehouse,
                database=settings.snowflake_database,
                schema=settings.snowflake_schema,
            )
            logger.info("Snowflake connection initialized")
    
    async def close(self):
        """Close all connections."""
        if self.pg_pool:
            await self.pg_pool.close()
        if self.sf_conn:
            self.sf_conn.close()


db = DatabasePools()


# =============================================================================
# FastAPI Application
# =============================================================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager."""
    # Startup
    await db.init_postgres()
    db.init_snowflake()
    yield
    # Shutdown
    await db.close()


app = FastAPI(
    title="Flux Ops Center API",
    description="Grid operations API with Cortex AI integration",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# =============================================================================
# API Models
# =============================================================================

class ChatMessage(BaseModel):
    """Chat message for Cortex Agent."""
    message: str
    conversation_id: Optional[str] = None


class GridStats(BaseModel):
    """Grid statistics response."""
    substations: int
    transformers: int
    customers: int
    meters: int
    active_outages: int


# =============================================================================
# Health Check Endpoints
# =============================================================================

@app.get("/api/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy", "service": "flux-ops-center"}


@app.get("/api/health/postgres")
async def postgres_health():
    """Check PostgreSQL connectivity."""
    if not db.pg_pool:
        return {"status": "not_configured"}
    try:
        async with db.pg_pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
        return {"status": "healthy"}
    except Exception as e:
        return {"status": "unhealthy", "error": str(e)}


@app.get("/api/health/snowflake")
async def snowflake_health():
    """Check Snowflake connectivity."""
    if not db.sf_conn:
        return {"status": "not_configured"}
    try:
        cursor = db.sf_conn.cursor()
        cursor.execute("SELECT 1")
        cursor.close()
        return {"status": "healthy"}
    except Exception as e:
        return {"status": "unhealthy", "error": str(e)}


# =============================================================================
# Grid Data Endpoints (PostgreSQL - Low Latency)
# =============================================================================

@app.get("/api/grid/stats")
async def get_grid_stats() -> GridStats:
    """Get grid statistics from PostgreSQL cache."""
    if not db.pg_pool:
        raise HTTPException(503, "PostgreSQL not configured")
    
    async with db.pg_pool.acquire() as conn:
        stats = await conn.fetchrow("""
            SELECT 
                (SELECT COUNT(*) FROM substations) as substations,
                (SELECT COUNT(*) FROM transformers) as transformers,
                (SELECT COUNT(*) FROM customers) as customers,
                (SELECT COUNT(*) FROM meters) as meters,
                (SELECT COUNT(*) FROM outages WHERE status = 'ACTIVE') as active_outages
        """)
    
    return GridStats(**dict(stats))


@app.get("/api/grid/substations")
async def get_substations(
    bounds: Optional[str] = Query(None, description="Bounding box: west,south,east,north")
):
    """Get substations, optionally filtered by bounding box."""
    if not db.pg_pool:
        raise HTTPException(503, "PostgreSQL not configured")
    
    query = """
        SELECT 
            substation_id,
            name,
            ST_X(location::geometry) as longitude,
            ST_Y(location::geometry) as latitude,
            capacity_mva,
            status
        FROM substations
    """
    
    params = []
    if bounds:
        west, south, east, north = map(float, bounds.split(","))
        query += """
            WHERE ST_Within(
                location::geometry,
                ST_MakeEnvelope($1, $2, $3, $4, 4326)
            )
        """
        params = [west, south, east, north]
    
    async with db.pg_pool.acquire() as conn:
        rows = await conn.fetch(query, *params)
    
    return [dict(row) for row in rows]


@app.get("/api/grid/transformers")
async def get_transformers(
    substation_id: Optional[str] = None,
    health_below: Optional[float] = None,
    limit: int = Query(1000, le=10000),
):
    """Get transformers with optional filters."""
    if not db.pg_pool:
        raise HTTPException(503, "PostgreSQL not configured")
    
    query = "SELECT * FROM transformers WHERE 1=1"
    params = []
    param_idx = 1
    
    if substation_id:
        query += f" AND substation_id = ${param_idx}"
        params.append(substation_id)
        param_idx += 1
    
    if health_below is not None:
        query += f" AND health_score < ${param_idx}"
        params.append(health_below)
        param_idx += 1
    
    query += f" LIMIT ${param_idx}"
    params.append(limit)
    
    async with db.pg_pool.acquire() as conn:
        rows = await conn.fetch(query, *params)
    
    return [dict(row) for row in rows]


# =============================================================================
# Analytics Endpoints (Snowflake)
# =============================================================================

@app.get("/api/analytics/load-profile")
async def get_load_profile(
    transformer_id: str,
    days: int = Query(7, le=30),
):
    """Get transformer load profile from Snowflake."""
    if not db.sf_conn:
        raise HTTPException(503, "Snowflake not configured")
    
    cursor = db.sf_conn.cursor()
    try:
        cursor.execute("""
            SELECT 
                DATE_TRUNC('hour', reading_timestamp) as hour,
                AVG(kwh_reading) as avg_kwh,
                MAX(kwh_reading) as peak_kwh,
                COUNT(*) as reading_count
            FROM AMI_INTERVAL_READINGS
            WHERE transformer_id = %s
              AND reading_timestamp >= DATEADD(day, -%s, CURRENT_TIMESTAMP())
            GROUP BY 1
            ORDER BY 1
        """, (transformer_id, days))
        
        columns = [desc[0].lower() for desc in cursor.description]
        rows = [dict(zip(columns, row)) for row in cursor.fetchall()]
        return rows
    finally:
        cursor.close()


# =============================================================================
# Cortex Agent Endpoints (AI-Powered)
# =============================================================================

@app.post("/api/agent/chat")
async def agent_chat(message: ChatMessage):
    """Send message to Cortex Agent and stream response."""
    if not db.sf_conn:
        raise HTTPException(503, "Snowflake not configured")
    
    async def generate_response() -> AsyncGenerator[str, None]:
        """Stream SSE events from Cortex Agent."""
        cursor = db.sf_conn.cursor()
        try:
            # Call Cortex Agent
            cursor.execute(f"""
                SELECT SNOWFLAKE.CORTEX.COMPLETE(
                    'claude-3-5-sonnet',
                    ARRAY_CONSTRUCT(
                        OBJECT_CONSTRUCT('role', 'user', 'content', %s)
                    ),
                    OBJECT_CONSTRUCT(
                        'temperature', 0.3,
                        'max_tokens', 2048
                    )
                )
            """, (message.message,))
            
            result = cursor.fetchone()
            if result:
                response_json = json.loads(result[0])
                content = response_json.get("choices", [{}])[0].get("message", {}).get("content", "")
                
                # Stream as SSE
                yield f"data: {json.dumps({'type': 'text', 'content': content})}\n\n"
            
            yield f"data: {json.dumps({'type': 'done'})}\n\n"
            
        except Exception as e:
            yield f"data: {json.dumps({'type': 'error', 'content': str(e)})}\n\n"
        finally:
            cursor.close()
    
    return StreamingResponse(
        generate_response(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


# =============================================================================
# GeoJSON Endpoints (for DeckGL visualization)
# =============================================================================

@app.get("/api/geojson/substations")
async def get_substations_geojson():
    """Get substations as GeoJSON for map visualization."""
    if not db.pg_pool:
        raise HTTPException(503, "PostgreSQL not configured")
    
    async with db.pg_pool.acquire() as conn:
        rows = await conn.fetch("""
            SELECT 
                substation_id as id,
                name,
                capacity_mva,
                status,
                ST_AsGeoJSON(location)::json as geometry
            FROM substations
        """)
    
    features = [
        {
            "type": "Feature",
            "properties": {
                "id": row["id"],
                "name": row["name"],
                "capacity_mva": row["capacity_mva"],
                "status": row["status"],
            },
            "geometry": row["geometry"],
        }
        for row in rows
    ]
    
    return {"type": "FeatureCollection", "features": features}


# =============================================================================
# Main Entry Point
# =============================================================================

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=3001)
