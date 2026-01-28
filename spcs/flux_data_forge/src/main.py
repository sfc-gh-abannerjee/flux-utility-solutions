"""
Flux Data Forge - Streaming Synthetic Data Generator

Generates realistic utility data at configurable throughput:
- AMI interval readings (15-minute smart meter data)
- Transformer telemetry (temperature, load, oil level)
- Outage events (with realistic patterns)
- Customer service requests

Output destinations:
- Snowflake tables (direct INSERT)
- Internal stages (Parquet files)
- External stages (S3/GCS/Azure)
"""

import os
import asyncio
import logging
from datetime import datetime, timedelta
from typing import Optional
from contextlib import asynccontextmanager

from fastapi import FastAPI, BackgroundTasks
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from pydantic_settings import BaseSettings

import numpy as np
import pandas as pd
import snowflake.connector

from .generators import AMIGenerator, TransformerTelemetryGenerator, OutageGenerator


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
    
    # Generation settings
    generation_mode: str = "streaming"  # streaming | batch
    records_per_second: int = 1000
    batch_size: int = 10000
    
    # Output destinations
    output_snowflake: bool = True
    output_stage: bool = True
    output_external_stage: bool = False
    stage_path: str = "@DATA_FORGE_STAGE"
    
    class Config:
        env_prefix = ""


settings = Settings()
logger = logging.getLogger("flux_data_forge")
logging.basicConfig(level=logging.INFO)


# =============================================================================
# Application State
# =============================================================================

class GeneratorState:
    """Track generator state and metrics."""
    
    def __init__(self):
        self.is_running = False
        self.records_generated = 0
        self.batches_written = 0
        self.start_time: Optional[datetime] = None
        self.last_batch_time: Optional[datetime] = None
        self.errors = []
        self.sf_conn: Optional[snowflake.connector.SnowflakeConnection] = None
        
    def reset_metrics(self):
        self.records_generated = 0
        self.batches_written = 0
        self.start_time = datetime.now()
        self.errors = []


state = GeneratorState()


# =============================================================================
# FastAPI Application
# =============================================================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager."""
    # Startup - connect to Snowflake
    if settings.snowflake_account:
        try:
            state.sf_conn = snowflake.connector.connect(
                account=settings.snowflake_account,
                user=settings.snowflake_user,
                password=settings.snowflake_password,
                warehouse=settings.snowflake_warehouse,
                database=settings.snowflake_database,
                schema=settings.snowflake_schema,
            )
            logger.info("Connected to Snowflake")
        except Exception as e:
            logger.error(f"Failed to connect to Snowflake: {e}")
    yield
    # Shutdown
    state.is_running = False
    if state.sf_conn:
        state.sf_conn.close()


app = FastAPI(
    title="Flux Data Forge",
    description="Streaming synthetic data generator for utility demos",
    version="1.0.0",
    lifespan=lifespan,
)


# =============================================================================
# API Models
# =============================================================================

class GeneratorConfig(BaseModel):
    """Configuration for data generation."""
    data_type: str = "ami"  # ami | transformer | outage | all
    records_per_second: int = 1000
    duration_seconds: int = 60
    output_snowflake: bool = True
    output_stage: bool = False


class GeneratorStatus(BaseModel):
    """Current generator status."""
    is_running: bool
    records_generated: int
    batches_written: int
    uptime_seconds: float
    records_per_second: float
    errors: list


# =============================================================================
# Data Generation Logic
# =============================================================================

async def generate_ami_batch(batch_size: int) -> pd.DataFrame:
    """Generate a batch of AMI readings."""
    generator = AMIGenerator()
    return generator.generate_batch(batch_size)


async def write_to_snowflake(df: pd.DataFrame, table_name: str):
    """Write DataFrame to Snowflake table."""
    if not state.sf_conn:
        raise ValueError("Snowflake connection not available")
    
    cursor = state.sf_conn.cursor()
    try:
        # Use write_pandas for efficient loading
        from snowflake.connector.pandas_tools import write_pandas
        success, num_chunks, num_rows, output = write_pandas(
            state.sf_conn,
            df,
            table_name,
            database=settings.snowflake_database,
            schema=settings.snowflake_schema,
        )
        state.batches_written += 1
        logger.info(f"Wrote {num_rows} rows to {table_name}")
    finally:
        cursor.close()


async def write_to_stage(df: pd.DataFrame, filename: str):
    """Write DataFrame to internal stage as Parquet."""
    if not state.sf_conn:
        raise ValueError("Snowflake connection not available")
    
    # Write to temp file
    temp_path = f"/tmp/{filename}"
    df.to_parquet(temp_path, index=False)
    
    # PUT to stage
    cursor = state.sf_conn.cursor()
    try:
        cursor.execute(f"PUT file://{temp_path} {settings.stage_path}/")
        logger.info(f"Uploaded {filename} to stage")
    finally:
        cursor.close()
        os.remove(temp_path)


async def generation_loop(config: GeneratorConfig):
    """Main generation loop."""
    state.is_running = True
    state.reset_metrics()
    
    end_time = datetime.now() + timedelta(seconds=config.duration_seconds)
    batch_interval = config.records_per_second / settings.batch_size
    
    logger.info(f"Starting generation: {config.data_type} for {config.duration_seconds}s")
    
    while state.is_running and datetime.now() < end_time:
        try:
            # Generate batch
            if config.data_type in ("ami", "all"):
                df = await generate_ami_batch(settings.batch_size)
                state.records_generated += len(df)
                
                # Write to destinations
                if config.output_snowflake:
                    await write_to_snowflake(df, "AMI_INTERVAL_READINGS_STREAM")
                
                if config.output_stage:
                    filename = f"ami_{datetime.now().strftime('%Y%m%d_%H%M%S')}.parquet"
                    await write_to_stage(df, filename)
            
            state.last_batch_time = datetime.now()
            
            # Throttle to target rate
            await asyncio.sleep(1.0 / batch_interval if batch_interval > 0 else 1.0)
            
        except Exception as e:
            state.errors.append(str(e))
            logger.error(f"Generation error: {e}")
            await asyncio.sleep(5)  # Back off on error
    
    state.is_running = False
    logger.info(f"Generation complete: {state.records_generated} records")


# =============================================================================
# API Endpoints
# =============================================================================

@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy", "service": "flux-data-forge"}


@app.get("/status", response_model=GeneratorStatus)
async def get_status():
    """Get current generator status."""
    uptime = 0.0
    rps = 0.0
    
    if state.start_time:
        uptime = (datetime.now() - state.start_time).total_seconds()
        if uptime > 0:
            rps = state.records_generated / uptime
    
    return GeneratorStatus(
        is_running=state.is_running,
        records_generated=state.records_generated,
        batches_written=state.batches_written,
        uptime_seconds=uptime,
        records_per_second=rps,
        errors=state.errors[-10:],  # Last 10 errors
    )


@app.post("/start")
async def start_generation(config: GeneratorConfig, background_tasks: BackgroundTasks):
    """Start data generation."""
    if state.is_running:
        return JSONResponse(
            status_code=400,
            content={"error": "Generator already running"}
        )
    
    background_tasks.add_task(generation_loop, config)
    return {"status": "started", "config": config.dict()}


@app.post("/stop")
async def stop_generation():
    """Stop data generation."""
    state.is_running = False
    return {"status": "stopping"}


@app.get("/preview/{data_type}")
async def preview_data(data_type: str, rows: int = 10):
    """Preview generated data without writing."""
    if data_type == "ami":
        generator = AMIGenerator()
        df = generator.generate_batch(rows)
        return df.to_dict(orient="records")
    else:
        return {"error": f"Unknown data type: {data_type}"}


# =============================================================================
# Main Entry Point
# =============================================================================

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
