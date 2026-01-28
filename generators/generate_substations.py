"""
Flux Utility Solutions - Substation Data Generator
Generates realistic substation data for the Houston metropolitan area.
"""

import pandas as pd
import numpy as np
from faker import Faker
import random
from datetime import datetime, timedelta
import argparse
import os

fake = Faker()
Faker.seed(42)
np.random.seed(42)
random.seed(42)

# Houston metro area bounding box
HOUSTON_BOUNDS = {
    'lat_min': 29.4,
    'lat_max': 30.2,
    'lon_min': -95.8,
    'lon_max': -94.9
}

# Substation types and their characteristics
SUBSTATION_TYPES = {
    'TRANSMISSION': {'voltage': '345KV', 'capacity_range': (500, 1500), 'count': 15},
    'DISTRIBUTION': {'voltage': '138KV', 'capacity_range': (100, 500), 'count': 70},
    'SWITCHING': {'voltage': '69KV', 'capacity_range': (50, 200), 'count': 13}
}

REGIONS = [
    'Houston Central', 'Houston North', 'Houston South', 'Houston East', 'Houston West',
    'Katy', 'Sugar Land', 'The Woodlands', 'Pearland', 'Pasadena',
    'League City', 'Missouri City', 'Baytown', 'Conroe', 'Galveston County'
]


def generate_substation_id(index: int) -> str:
    """Generate substation ID in format SUB-HOU-XXX"""
    return f"SUB-HOU-{index:03d}"


def generate_substations(count: int = 98) -> pd.DataFrame:
    """Generate substation data matching PRODUCTION schema"""
    
    substations = []
    sub_index = 1
    
    for sub_type, config in SUBSTATION_TYPES.items():
        for _ in range(config['count']):
            if sub_index > count:
                break
                
            lat = random.uniform(HOUSTON_BOUNDS['lat_min'], HOUSTON_BOUNDS['lat_max'])
            lon = random.uniform(HOUSTON_BOUNDS['lon_min'], HOUSTON_BOUNDS['lon_max'])
            
            capacity = random.randint(*config['capacity_range'])
            current_load = capacity * random.uniform(0.4, 0.85)
            peak_load = capacity * random.uniform(0.75, 0.95)
            
            # Commissioned between 1960 and 2020
            commissioned = fake.date_between(start_date='-65y', end_date='-5y')
            last_inspection = fake.date_between(start_date='-2y', end_date='today')
            
            substations.append({
                'SUBSTATION_ID': generate_substation_id(sub_index),
                'SUBSTATION_NAME': f"{random.choice(REGIONS)} Substation {sub_index}",
                'REGION': random.choice(REGIONS),
                'SUBSTATION_TYPE': sub_type,
                'VOLTAGE_LEVEL': config['voltage'],
                'LATITUDE': round(lat, 6),
                'LONGITUDE': round(lon, 6),
                'LOCATION_COORDINATE': f"POINT({lon:.6f} {lat:.6f})",
                'DISTANCE_FROM_COAST_MILE': round(random.uniform(10, 80), 1),
                'CAPACITY_MVA': capacity,
                'CURRENT_LOAD_MW': round(current_load, 2),
                'PEAK_LOAD_MW': round(peak_load, 2),
                'N_MINUS_1_CONTINGENCY_RATING_MW': round(capacity * 0.8, 2),
                'LOAD_FACTOR_PCT': round(current_load / capacity * 100, 2),
                'COMMISSIONED_DATE': commissioned,
                'OPERATIONAL_STATUS': random.choices(
                    ['OPERATIONAL', 'MAINTENANCE', 'OFFLINE'],
                    weights=[0.92, 0.06, 0.02]
                )[0],
                'LAST_INSPECTION_DATE': last_inspection,
                'CRITICAL_INFRASTRUCTURE_FLAG': random.random() < 0.15,
                'ENTITY_ID': random.randint(1000000, 9999999),
                'CREATED_AT': datetime.now(),
                'UPDATED_AT': datetime.now()
            })
            
            sub_index += 1
    
    return pd.DataFrame(substations)


def main():
    parser = argparse.ArgumentParser(description='Generate substation data')
    parser.add_argument('--count', type=int, default=98, help='Number of substations')
    parser.add_argument('--output', type=str, default='substations.parquet', help='Output file')
    parser.add_argument('--format', choices=['parquet', 'csv'], default='parquet')
    args = parser.parse_args()
    
    print(f"Generating {args.count} substations...")
    df = generate_substations(args.count)
    
    output_dir = os.path.dirname(args.output) or '.'
    os.makedirs(output_dir, exist_ok=True)
    
    if args.format == 'parquet':
        df.to_parquet(args.output, index=False)
    else:
        df.to_csv(args.output, index=False)
    
    print(f"✓ Generated {len(df)} substations")
    print(f"  Output: {args.output}")
    print(f"  Types: {df['SUBSTATION_TYPE'].value_counts().to_dict()}")


if __name__ == '__main__':
    main()
