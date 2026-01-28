"""
Outage Event Generator

Generates realistic power outage events with:
- Weather-correlated patterns (storms increase frequency)
- Equipment failure patterns
- Restoration time distributions
- Affected customer counts
"""

import numpy as np
import pandas as pd
from datetime import datetime, timedelta
from typing import Optional
import uuid


class OutageGenerator:
    """Generate synthetic outage events."""
    
    OUTAGE_CAUSES = [
        ("WEATHER", 0.35),       # Storms, wind, lightning
        ("EQUIPMENT", 0.25),     # Transformer, fuse, cable failure
        ("VEGETATION", 0.20),    # Tree contact
        ("VEHICLE", 0.10),       # Car-pole accidents
        ("ANIMAL", 0.05),        # Squirrels, birds
        ("PLANNED", 0.05),       # Scheduled maintenance
    ]
    
    def __init__(self, num_feeders: int = 500):
        self.num_feeders = num_feeders
        np.random.seed(42)
        self.feeder_ids = [f"FDR-{i:04d}" for i in range(num_feeders)]
        self.substation_ids = [f"SUB-{i:03d}" for i in range(98)]
    
    def _sample_cause(self, weather_severity: float = 0.0) -> str:
        """Sample outage cause, weighted by weather severity."""
        causes, probs = zip(*self.OUTAGE_CAUSES)
        probs = np.array(probs)
        
        # Increase weather probability during storms
        if weather_severity > 0.5:
            probs[0] *= (1 + weather_severity)
            probs = probs / probs.sum()
        
        return np.random.choice(causes, p=probs)
    
    def _sample_restoration_time(self, cause: str) -> float:
        """Sample restoration time in minutes based on cause."""
        if cause == "PLANNED":
            return np.random.uniform(60, 240)  # 1-4 hours planned
        elif cause == "WEATHER":
            return np.random.exponential(180)  # Avg 3 hours
        elif cause == "EQUIPMENT":
            return np.random.exponential(120)  # Avg 2 hours
        elif cause == "VEHICLE":
            return np.random.exponential(90)   # Avg 1.5 hours
        else:
            return np.random.exponential(60)   # Avg 1 hour
    
    def generate_batch(
        self,
        batch_size: int,
        timestamp: Optional[datetime] = None,
        weather_severity: float = 0.0,  # 0-1 scale
    ) -> pd.DataFrame:
        """Generate a batch of outage events."""
        
        if timestamp is None:
            timestamp = datetime.now()
        
        records = []
        for _ in range(batch_size):
            cause = self._sample_cause(weather_severity)
            restoration_mins = self._sample_restoration_time(cause)
            
            # Affected customers based on cause
            if cause == "WEATHER":
                customers = int(np.random.exponential(500))
            elif cause == "EQUIPMENT":
                customers = int(np.random.exponential(200))
            else:
                customers = int(np.random.exponential(100))
            customers = max(1, min(customers, 10000))
            
            feeder_idx = np.random.randint(0, self.num_feeders)
            sub_idx = feeder_idx % 98
            
            outage_start = timestamp - timedelta(minutes=np.random.uniform(0, 60))
            outage_end = outage_start + timedelta(minutes=restoration_mins)
            
            # Status based on time
            if outage_end < timestamp:
                status = "RESTORED"
            elif outage_start > timestamp:
                status = "SCHEDULED"
            else:
                status = "ACTIVE"
            
            records.append({
                "outage_id": str(uuid.uuid4()),
                "feeder_id": self.feeder_ids[feeder_idx],
                "substation_id": self.substation_ids[sub_idx],
                "cause": cause,
                "status": status,
                "start_time": outage_start,
                "estimated_restoration": outage_end,
                "actual_restoration": outage_end if status == "RESTORED" else None,
                "customers_affected": customers,
                "priority": "HIGH" if customers > 500 else "NORMAL",
                "created_at": datetime.now(),
            })
        
        return pd.DataFrame(records)
