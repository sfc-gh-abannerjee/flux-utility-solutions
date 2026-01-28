"""
Flux Utility Solutions - AMI Sample Data Generator
Generates sample AMI (Advanced Metering Infrastructure) interval readings.
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import argparse
import os
import random

np.random.seed(42)
random.seed(42)

# Load profiles by hour (0-23) - multiplier on base consumption
RESIDENTIAL_PROFILE = [
    0.4, 0.35, 0.3, 0.3, 0.35, 0.5,   # 00:00 - 05:45
    0.7, 0.9, 0.8, 0.6, 0.5, 0.5,     # 06:00 - 11:45
    0.5, 0.5, 0.6, 0.7, 0.9, 1.0,     # 12:00 - 17:45
    1.0, 0.95, 0.85, 0.7, 0.55, 0.45  # 18:00 - 23:45
]

COMMERCIAL_PROFILE = [
    0.3, 0.3, 0.3, 0.3, 0.35, 0.5,    # 00:00 - 05:45
    0.7, 0.9, 1.0, 1.0, 1.0, 1.0,     # 06:00 - 11:45
    0.9, 1.0, 1.0, 1.0, 1.0, 0.9,     # 12:00 - 17:45
    0.7, 0.5, 0.4, 0.35, 0.3, 0.3     # 18:00 - 23:45
]

INDUSTRIAL_PROFILE = [
    0.8, 0.8, 0.8, 0.8, 0.85, 0.9,    # 00:00 - 05:45
    1.0, 1.0, 1.0, 1.0, 1.0, 1.0,     # 06:00 - 11:45
    0.9, 1.0, 1.0, 1.0, 1.0, 1.0,     # 12:00 - 17:45
    0.95, 0.9, 0.85, 0.8, 0.8, 0.8    # 18:00 - 23:45
]


def generate_ami_readings(
    meter_ids: list,
    start_date: datetime,
    end_date: datetime,
    segment_map: dict = None
) -> pd.DataFrame:
    """
    Generate 15-minute interval AMI readings.
    
    Args:
        meter_ids: List of meter IDs
        start_date: Start of reading period
        end_date: End of reading period
        segment_map: Dict mapping meter_id to customer segment
    """
    
    # Generate timestamp range (15-min intervals)
    timestamps = pd.date_range(start=start_date, end=end_date, freq='15min')
    n_intervals = len(timestamps)
    n_meters = len(meter_ids)
    
    print(f"  Generating {n_meters:,} meters x {n_intervals:,} intervals = {n_meters * n_intervals:,} readings")
    
    readings = []
    
    for idx, meter_id in enumerate(meter_ids):
        if (idx + 1) % 1000 == 0:
            print(f"    Processing meter {idx + 1:,}/{n_meters:,}...")
        
        # Determine segment and base consumption
        segment = segment_map.get(meter_id, 'RESIDENTIAL') if segment_map else 'RESIDENTIAL'
        
        if segment == 'RESIDENTIAL':
            profile = RESIDENTIAL_PROFILE
            base_kwh = random.uniform(0.3, 1.5)  # 15-min base
        elif segment == 'COMMERCIAL':
            profile = COMMERCIAL_PROFILE
            base_kwh = random.uniform(2.0, 10.0)
        else:  # INDUSTRIAL
            profile = INDUSTRIAL_PROFILE
            base_kwh = random.uniform(15.0, 50.0)
        
        for ts in timestamps:
            hour = ts.hour
            
            # Apply load profile
            profile_mult = profile[hour]
            
            # Add seasonal variation (summer peak in Texas)
            month = ts.month
            if month in [6, 7, 8]:  # Summer
                seasonal_mult = 1.4
            elif month in [12, 1, 2]:  # Winter
                seasonal_mult = 1.1
            else:
                seasonal_mult = 1.0
            
            # Add weekend reduction for commercial
            if segment == 'COMMERCIAL' and ts.dayofweek >= 5:
                weekend_mult = 0.3
            else:
                weekend_mult = 1.0
            
            # Calculate kWh with some noise
            kwh = base_kwh * profile_mult * seasonal_mult * weekend_mult
            kwh = kwh * random.uniform(0.85, 1.15)  # ±15% noise
            
            readings.append({
                'METER_ID': meter_id,
                'READING_TIMESTAMP': ts,
                'KWH': round(kwh, 3),
                'VOLTAGE': round(random.uniform(118, 122), 1),
                'POWER_FACTOR': round(random.uniform(0.92, 0.99), 3),
                'READING_QUALITY': random.choices(
                    ['ACTUAL', 'ESTIMATED', 'VALIDATED'],
                    weights=[0.95, 0.03, 0.02]
                )[0]
            })
    
    return pd.DataFrame(readings)


def main():
    parser = argparse.ArgumentParser(description='Generate AMI sample data')
    parser.add_argument('--meters', type=int, default=1000, help='Number of meters')
    parser.add_argument('--days', type=int, default=30, help='Days of data')
    parser.add_argument('--output', type=str, default='ami_readings.parquet', help='Output file')
    parser.add_argument('--format', choices=['parquet', 'csv'], default='parquet')
    parser.add_argument('--customers', type=str, help='Customer file for segment mapping')
    args = parser.parse_args()
    
    # Generate meter IDs
    meter_ids = [f"MTR-{i:08d}" for i in range(1, args.meters + 1)]
    
    # Load segment mapping if provided
    segment_map = {}
    if args.customers and os.path.exists(args.customers):
        cust_df = pd.read_parquet(args.customers)
        segment_map = dict(zip(cust_df['PRIMARY_METER_ID'], cust_df['CUSTOMER_SEGMENT']))
        print(f"Loaded segment mapping for {len(segment_map):,} meters")
    
    # Date range
    end_date = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    start_date = end_date - timedelta(days=args.days)
    
    print(f"Generating AMI readings:")
    print(f"  Meters: {args.meters:,}")
    print(f"  Period: {start_date.date()} to {end_date.date()}")
    
    df = generate_ami_readings(meter_ids, start_date, end_date, segment_map)
    
    output_dir = os.path.dirname(args.output) or '.'
    os.makedirs(output_dir, exist_ok=True)
    
    if args.format == 'parquet':
        df.to_parquet(args.output, index=False)
    else:
        df.to_csv(args.output, index=False)
    
    print(f"✓ Generated {len(df):,} AMI readings")
    print(f"  Output: {args.output}")
    print(f"  File size: {os.path.getsize(args.output) / 1024 / 1024:.1f} MB")


if __name__ == '__main__':
    main()
