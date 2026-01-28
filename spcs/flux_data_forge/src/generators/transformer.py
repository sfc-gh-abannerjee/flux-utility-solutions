"""
Transformer Telemetry Data Generator

Generates realistic transformer monitoring data:
- Oil temperature
- Winding temperature
- Load percentage
- Oil level
- Dissolved gas analysis (DGA) indicators
"""

import numpy as np
import pandas as pd
from datetime import datetime
from typing import Optional
import uuid


class TransformerTelemetryGenerator:
    """Generate synthetic transformer telemetry."""
    
    def __init__(self, num_transformers: int = 91000):
        self.num_transformers = num_transformers
        np.random.seed(42)
        self.transformer_ids = [f"TRF-{i:05d}" for i in range(num_transformers)]
        
        # Pre-assign health profiles (some transformers are "sick")
        self.health_profiles = np.random.beta(8, 2, num_transformers)  # Mostly healthy
    
    def generate_batch(
        self,
        batch_size: int,
        timestamp: Optional[datetime] = None,
        ambient_temp: float = 85.0,  # Houston summer default
    ) -> pd.DataFrame:
        """Generate a batch of transformer readings."""
        
        if timestamp is None:
            timestamp = datetime.now()
        
        # Select random transformers
        indices = np.random.randint(0, self.num_transformers, batch_size)
        health_scores = self.health_profiles[indices]
        
        # Generate correlated readings based on health
        # Unhealthy transformers run hotter with more oil degradation
        
        # Load percentage (higher for stressed transformers)
        load_pct = np.random.normal(65, 15, batch_size) + (1 - health_scores) * 20
        load_pct = np.clip(load_pct, 10, 120)  # Allow overload
        
        # Oil temperature (correlated with load and health)
        oil_temp = ambient_temp + 20 + (load_pct * 0.3) + (1 - health_scores) * 15
        oil_temp += np.random.normal(0, 3, batch_size)
        
        # Winding temperature (higher than oil)
        winding_temp = oil_temp + 15 + (load_pct * 0.2)
        winding_temp += np.random.normal(0, 2, batch_size)
        
        # Oil level (degraded transformers may have leaks)
        oil_level = 95 - (1 - health_scores) * 10 + np.random.normal(0, 2, batch_size)
        oil_level = np.clip(oil_level, 60, 100)
        
        # DGA indicators (ppm of dissolved gases)
        # Healthy: low values; Degraded: elevated
        hydrogen_ppm = 50 + (1 - health_scores) * 200 + np.random.exponential(20, batch_size)
        methane_ppm = 20 + (1 - health_scores) * 80 + np.random.exponential(10, batch_size)
        
        df = pd.DataFrame({
            "telemetry_id": [str(uuid.uuid4()) for _ in range(batch_size)],
            "transformer_id": [self.transformer_ids[i] for i in indices],
            "reading_timestamp": [timestamp] * batch_size,
            "oil_temperature_f": np.round(oil_temp, 1),
            "winding_temperature_f": np.round(winding_temp, 1),
            "load_percentage": np.round(load_pct, 1),
            "oil_level_pct": np.round(oil_level, 1),
            "hydrogen_ppm": np.round(hydrogen_ppm, 0).astype(int),
            "methane_ppm": np.round(methane_ppm, 0).astype(int),
            "health_score": np.round(health_scores * 100, 1),
            "alert_status": np.where(
                (oil_temp > 150) | (load_pct > 100) | (hydrogen_ppm > 300),
                "ALERT",
                "NORMAL"
            ),
            "created_at": [datetime.now()] * batch_size,
        })
        
        return df
