"""
Flux Utility Solutions - Customer Data Generator
Generates 686,000 customer records with realistic demographics.
"""

import pandas as pd
import numpy as np
from faker import Faker
import random
from datetime import datetime, timedelta
import argparse
import os

fake = Faker('en_US')
Faker.seed(42)
np.random.seed(42)
random.seed(42)

# Houston area cities and their population weights
HOUSTON_CITIES = {
    'Houston': 0.45,
    'Pasadena': 0.05,
    'Pearland': 0.04,
    'League City': 0.03,
    'Sugar Land': 0.04,
    'The Woodlands': 0.04,
    'Baytown': 0.03,
    'Conroe': 0.03,
    'Missouri City': 0.03,
    'Katy': 0.04,
    'Spring': 0.04,
    'Humble': 0.03,
    'Cypress': 0.03,
    'Kingwood': 0.02,
    'Friendswood': 0.02,
    'Deer Park': 0.02,
    'La Porte': 0.02,
    'Galveston': 0.02,
    'Texas City': 0.02
}

CUSTOMER_SEGMENTS = {
    'RESIDENTIAL': 0.75,
    'COMMERCIAL': 0.20,
    'INDUSTRIAL': 0.05
}

HARRIS_COUNTY_ZIPS = [
    77001, 77002, 77003, 77004, 77005, 77006, 77007, 77008, 77009, 77010,
    77011, 77012, 77013, 77014, 77015, 77016, 77017, 77018, 77019, 77020,
    77021, 77022, 77023, 77024, 77025, 77026, 77027, 77028, 77029, 77030,
    77031, 77032, 77033, 77034, 77035, 77036, 77037, 77038, 77039, 77040,
    77041, 77042, 77043, 77044, 77045, 77046, 77047, 77048, 77049, 77050,
    77051, 77053, 77054, 77055, 77056, 77057, 77058, 77059, 77060, 77061,
    77062, 77063, 77064, 77065, 77066, 77067, 77068, 77069, 77070, 77071,
    77072, 77073, 77074, 77075, 77076, 77077, 77078, 77079, 77080, 77081,
    77082, 77083, 77084, 77085, 77086, 77087, 77088, 77089, 77090, 77091,
    77092, 77093, 77094, 77095, 77096, 77098, 77099
]


def generate_customer_id(index: int) -> str:
    """Generate customer ID"""
    return f"CUST-{index:08d}"


def generate_customers(count: int = 686000) -> pd.DataFrame:
    """Generate customer data matching PRODUCTION schema"""
    
    customers = []
    cities = list(HOUSTON_CITIES.keys())
    city_weights = list(HOUSTON_CITIES.values())
    
    segments = list(CUSTOMER_SEGMENTS.keys())
    segment_weights = list(CUSTOMER_SEGMENTS.values())
    
    for i in range(1, count + 1):
        if i % 50000 == 0:
            print(f"  Generated {i:,} customers...")
        
        first_name = fake.first_name()
        last_name = fake.last_name()
        city = random.choices(cities, weights=city_weights)[0]
        
        segment = random.choices(segments, weights=segment_weights)[0]
        
        # Service start date (most customers are long-term)
        service_start = fake.date_between(start_date='-20y', end_date='-6m')
        
        customers.append({
            'CUSTOMER_ID': generate_customer_id(i),
            'FIRST_NAME': first_name,
            'LAST_NAME': last_name,
            'FULL_NAME': f"{first_name} {last_name}",
            'PHONE': fake.phone_number()[:14],
            'EMAIL': f"{first_name.lower()}.{last_name.lower()}{random.randint(1,999)}@{fake.free_email_domain()}",
            'PRIMARY_METER_ID': f"MTR-{i:08d}",
            'ACCOUNT_STATUS': random.choices(['ACTIVE', 'CLOSED'], weights=[0.95, 0.05])[0],
            'SERVICE_START_DATE': service_start,
            'SERVICE_ADDRESS': fake.street_address(),
            'SERVICE_COUNTY': 'Harris' if random.random() < 0.7 else random.choice(['Fort Bend', 'Montgomery', 'Galveston', 'Brazoria']),
            'CITY': city,
            'ZIP_CODE': random.choice(HARRIS_COUNTY_ZIPS),
            'CUSTOMER_SEGMENT': segment,
            'DATA_SOURCE': 'SYNTHETIC_GENERATOR',
            'CREATED_AT': datetime.now()
        })
    
    return pd.DataFrame(customers)


def main():
    parser = argparse.ArgumentParser(description='Generate customer data')
    parser.add_argument('--count', type=int, default=686000, help='Number of customers')
    parser.add_argument('--output', type=str, default='customers.parquet', help='Output file')
    parser.add_argument('--format', choices=['parquet', 'csv'], default='parquet')
    args = parser.parse_args()
    
    print(f"Generating {args.count:,} customers...")
    df = generate_customers(args.count)
    
    output_dir = os.path.dirname(args.output) or '.'
    os.makedirs(output_dir, exist_ok=True)
    
    if args.format == 'parquet':
        df.to_parquet(args.output, index=False)
    else:
        df.to_csv(args.output, index=False)
    
    print(f"✓ Generated {len(df):,} customers")
    print(f"  Output: {args.output}")
    print(f"  Segments: {df['CUSTOMER_SEGMENT'].value_counts().to_dict()}")
    print(f"  Cities: {df['CITY'].value_counts().head(5).to_dict()}")


if __name__ == '__main__':
    main()
