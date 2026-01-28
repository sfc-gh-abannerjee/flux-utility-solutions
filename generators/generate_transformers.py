"""
Flux Utility Solutions - Transformer Data Generator
Generates 91,000+ distribution transformers with health scores.
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

MANUFACTURERS = [
    'ABB', 'Siemens', 'GE', 'Eaton', 'Schneider Electric',
    'Howard Industries', 'Cooper Power', 'Hitachi', 'Toshiba'
]

PHASE_CODES = ['ABC', 'AB', 'BC', 'AC', 'A', 'B', 'C']

RATED_KVA_OPTIONS = [15, 25, 37.5, 50, 75, 100, 167, 250, 333, 500, 750, 1000]

HOUSTON_BOUNDS = {
    'lat_min': 29.4,
    'lat_max': 30.2,
    'lon_min': -95.8,
    'lon_max': -94.9
}


def generate_transformer_id(index: int, synthetic: bool = False) -> str:
    """Generate transformer ID"""
    if synthetic:
        return f"SYNTH-XFMR-{index:06d}"
    return f"XFMR-HOU-{index:06d}"


def calculate_health_score(age: int, load_pct: float, last_maintenance_days: int) -> float:
    """Calculate transformer health score (0-100)"""
    # Age factor (older = lower score)
    age_score = max(0, 100 - (age * 1.5))
    
    # Load factor (higher load = lower score)
    load_score = max(0, 100 - (load_pct * 0.5))
    
    # Maintenance factor
    maintenance_score = max(0, 100 - (last_maintenance_days / 365 * 20))
    
    # Weighted combination with some randomness
    base_score = (age_score * 0.4 + load_score * 0.3 + maintenance_score * 0.3)
    
    # Add some variance
    variance = random.gauss(0, 5)
    final_score = max(0, min(100, base_score + variance))
    
    return round(final_score, 1)


def generate_transformers(count: int = 91000, substation_ids: list = None) -> pd.DataFrame:
    """Generate transformer data matching PRODUCTION schema"""
    
    if substation_ids is None:
        substation_ids = [f"SUB-HOU-{i:03d}" for i in range(1, 99)]
    
    transformers = []
    
    for i in range(1, count + 1):
        if i % 10000 == 0:
            print(f"  Generated {i:,} transformers...")
        
        lat = random.uniform(HOUSTON_BOUNDS['lat_min'], HOUSTON_BOUNDS['lat_max'])
        lon = random.uniform(HOUSTON_BOUNDS['lon_min'], HOUSTON_BOUNDS['lon_max'])
        
        # Installation year between 1970 and 2024
        install_year = random.randint(1970, 2024)
        age = 2026 - install_year
        
        # Last maintenance within past 3 years
        last_maintenance = fake.date_between(start_date='-3y', end_date='today')
        maintenance_days = (datetime.now().date() - last_maintenance).days
        
        rated_kva = random.choice(RATED_KVA_OPTIONS)
        
        # Load utilization varies by transformer size
        if rated_kva <= 50:
            load_pct = random.uniform(30, 90)
        elif rated_kva <= 167:
            load_pct = random.uniform(40, 85)
        else:
            load_pct = random.uniform(50, 80)
        
        current_load = rated_kva * load_pct / 100
        peak_load = current_load * random.uniform(1.1, 1.4)
        
        health_score = calculate_health_score(age, load_pct, maintenance_days)
        
        # Assign to substation (geographic clustering)
        substation_id = random.choice(substation_ids)
        circuit_id = f"CKT-{substation_id[-3:]}-{random.randint(1, 99):02d}"
        
        transformers.append({
            'TRANSFORMER_ID': generate_transformer_id(i),
            'LATITUDE': round(lat, 6),
            'LONGITUDE': round(lon, 6),
            'SUBSTATION_ID': substation_id,
            'CIRCUIT_ID': circuit_id,
            'RATED_KVA': rated_kva,
            'PRIMARY_VOLTAGE_KV': random.choice([4.16, 12.47, 13.2, 13.8, 24.94]),
            'PHASE_CODE': random.choice(PHASE_CODES),
            'MANUFACTURER': random.choice(MANUFACTURERS),
            'MODEL_NUMBER': f"{random.choice(MANUFACTURERS)[:3].upper()}-{random.randint(1000, 9999)}",
            'INSTALL_YEAR': install_year,
            'LAST_MAINTENANCE_DATE': last_maintenance,
            'HEALTH_SCORE': health_score,
            'CURRENT_LOAD_KVA': round(current_load, 1),
            'PEAK_LOAD_KVA': round(peak_load, 1),
            'LOAD_UTILIZATION_PCT': round(load_pct, 2),
            'METER_COUNT': random.randint(1, 25),
            'TRANSFORMER_ROLE': random.choice(['SERVICE', 'SPLIT', 'NETWORK']),
            'PARENT_TRANSFORMER_ID': None
        })
    
    return pd.DataFrame(transformers)


def main():
    parser = argparse.ArgumentParser(description='Generate transformer data')
    parser.add_argument('--count', type=int, default=91000, help='Number of transformers')
    parser.add_argument('--output', type=str, default='transformers.parquet', help='Output file')
    parser.add_argument('--format', choices=['parquet', 'csv'], default='parquet')
    parser.add_argument('--substations', type=str, help='Path to substations file for FK')
    args = parser.parse_args()
    
    substation_ids = None
    if args.substations and os.path.exists(args.substations):
        subs_df = pd.read_parquet(args.substations)
        substation_ids = subs_df['SUBSTATION_ID'].tolist()
        print(f"Using {len(substation_ids)} substations from {args.substations}")
    
    print(f"Generating {args.count:,} transformers...")
    df = generate_transformers(args.count, substation_ids)
    
    output_dir = os.path.dirname(args.output) or '.'
    os.makedirs(output_dir, exist_ok=True)
    
    if args.format == 'parquet':
        df.to_parquet(args.output, index=False)
    else:
        df.to_csv(args.output, index=False)
    
    print(f"✓ Generated {len(df):,} transformers")
    print(f"  Output: {args.output}")
    print(f"  Health score distribution:")
    print(f"    Critical (<30): {len(df[df['HEALTH_SCORE'] < 30]):,}")
    print(f"    At-risk (30-50): {len(df[(df['HEALTH_SCORE'] >= 30) & (df['HEALTH_SCORE'] < 50)]):,}")
    print(f"    Fair (50-70): {len(df[(df['HEALTH_SCORE'] >= 50) & (df['HEALTH_SCORE'] < 70)]):,}")
    print(f"    Good (70-90): {len(df[(df['HEALTH_SCORE'] >= 70) & (df['HEALTH_SCORE'] < 90)]):,}")
    print(f"    Excellent (90+): {len(df[df['HEALTH_SCORE'] >= 90]):,}")


if __name__ == '__main__':
    main()
