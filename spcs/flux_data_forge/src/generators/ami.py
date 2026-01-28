"""
AMI (Advanced Metering Infrastructure) Data Generator

Generates realistic 15-minute interval smart meter readings with:
- Time-of-day load patterns (morning/evening peaks)
- Seasonal variations
- Weather correlation
- Random noise and anomalies
"""

import numpy as np
import pandas as pd
from datetime import datetime, timedelta
from typing import Optional
import uuid


class AMIGenerator:
    """Generate synthetic AMI interval readings."""
    
    def __init__(
        self,
        num_meters: int = 10000,
        base_load_kwh: float = 1.5,
        peak_multiplier: float = 2.5,
        noise_factor: float = 0.15,
    ):
        self.num_meters = num_meters
        self.base_load_kwh = base_load_kwh
        self.peak_multiplier = peak_multiplier
        self.noise_factor = noise_factor
        
        # Pre-generate meter IDs for consistency
        np.random.seed(42)
        self.meter_ids = [f"MTR-{i:06d}" for i in range(num_meters)]
        self.transformer_ids = [f"TRF-{i:05d}" for i in range(num_meters // 10)]
    
    def _time_of_day_factor(self, hour: int) -> float:
        """Get load factor based on time of day."""
        # Morning peak: 7-9 AM
        # Evening peak: 6-9 PM
        # Overnight low: 1-5 AM
        if 7 <= hour <= 9:
            return 1.8
        elif 18 <= hour <= 21:
            return self.peak_multiplier
        elif 1 <= hour <= 5:
            return 0.6
        else:
            return 1.0
    
    def _seasonal_factor(self, month: int) -> float:
        """Get load factor based on season (Houston climate)."""
        # Summer (Jun-Sep): High AC usage
        # Winter (Dec-Feb): Moderate heating
        if 6 <= month <= 9:
            return 1.4  # Summer AC
        elif month in (12, 1, 2):
            return 1.1  # Winter heating
        else:
            return 1.0  # Mild seasons
    
    def generate_batch(
        self,
        batch_size: int,
        timestamp: Optional[datetime] = None,
    ) -> pd.DataFrame:
        """Generate a batch of AMI readings."""
        
        if timestamp is None:
            timestamp = datetime.now()
        
        # Select random meters for this batch
        meter_indices = np.random.randint(0, self.num_meters, batch_size)
        
        # Calculate load factors
        hour = timestamp.hour
        month = timestamp.month
        tod_factor = self._time_of_day_factor(hour)
        seasonal_factor = self._seasonal_factor(month)
        
        # Generate readings with noise
        base_readings = (
            self.base_load_kwh 
            * tod_factor 
            * seasonal_factor
        )
        noise = np.random.normal(1.0, self.noise_factor, batch_size)
        readings = base_readings * noise
        readings = np.maximum(readings, 0.1)  # Minimum reading
        
        # Add occasional anomalies (0.5% of readings)
        anomaly_mask = np.random.random(batch_size) < 0.005
        readings[anomaly_mask] *= np.random.uniform(3.0, 5.0, anomaly_mask.sum())
        
        # Build DataFrame
        df = pd.DataFrame({
            "reading_id": [str(uuid.uuid4()) for _ in range(batch_size)],
            "meter_id": [self.meter_ids[i] for i in meter_indices],
            "transformer_id": [self.transformer_ids[i // 10] for i in meter_indices],
            "reading_timestamp": [timestamp] * batch_size,
            "kwh_reading": np.round(readings, 3),
            "voltage": np.round(np.random.normal(240, 5, batch_size), 1),
            "power_factor": np.round(np.random.uniform(0.85, 0.99, batch_size), 2),
            "quality_flag": np.where(anomaly_mask, "ANOMALY", "VALID"),
            "created_at": [datetime.now()] * batch_size,
        })
        
        return df
    
    def generate_time_series(
        self,
        meter_id: str,
        start_time: datetime,
        intervals: int = 96,  # 24 hours of 15-min intervals
    ) -> pd.DataFrame:
        """Generate time series for a specific meter."""
        
        records = []
        current_time = start_time
        
        for _ in range(intervals):
            tod_factor = self._time_of_day_factor(current_time.hour)
            seasonal_factor = self._seasonal_factor(current_time.month)
            
            reading = (
                self.base_load_kwh 
                * tod_factor 
                * seasonal_factor 
                * np.random.normal(1.0, self.noise_factor)
            )
            
            records.append({
                "reading_id": str(uuid.uuid4()),
                "meter_id": meter_id,
                "reading_timestamp": current_time,
                "kwh_reading": round(max(reading, 0.1), 3),
                "voltage": round(np.random.normal(240, 5), 1),
                "power_factor": round(np.random.uniform(0.85, 0.99), 2),
                "quality_flag": "VALID",
            })
            
            current_time += timedelta(minutes=15)
        
        return pd.DataFrame(records)
