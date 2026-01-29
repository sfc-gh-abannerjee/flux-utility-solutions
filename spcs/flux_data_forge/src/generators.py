"""
FLUX Data Forge - Data Generators Module
Realistic correlated data generation for utility demo datasets.

Generators:
- Work Orders (SAP style) - correlated with transformer/circuit failures
- Outage Events (ERM style) - correlated with weather and asset health
- Power Quality Events - correlated with voltage readings
- Transformer Load - time-series load correlated with AMI readings
"""

import random
import uuid
from datetime import datetime, timedelta
from typing import List, Dict, Optional, Any
import logging

logger = logging.getLogger(__name__)

# ============================================================================
# WORK ORDER GENERATOR (SAP Style)
# ============================================================================

WORK_ORDER_TYPES = {
    'PM': {
        'name': 'Preventive Maintenance',
        'prefix': 'PM',
        'priority_weights': {'LOW': 60, 'MEDIUM': 35, 'HIGH': 5},
        'duration_hours': (1, 4),
        'descriptions': [
            'Scheduled transformer inspection',
            'Pole inspection and treatment',
            'Circuit breaker maintenance',
            'Vegetation management - routine trim',
            'Capacitor bank inspection',
            'Recloser testing and calibration',
            'Underground cable thermal scan',
            'Substation equipment inspection',
        ]
    },
    'CM': {
        'name': 'Corrective Maintenance',
        'prefix': 'CM',
        'priority_weights': {'LOW': 10, 'MEDIUM': 40, 'HIGH': 40, 'EMERGENCY': 10},
        'duration_hours': (2, 8),
        'descriptions': [
            'Transformer oil leak repair',
            'Replace damaged cross-arm',
            'Repair underground cable fault',
            'Fix voltage regulator malfunction',
            'Replace blown fuse cutout',
            'Repair damaged pole',
            'Fix capacitor bank failure',
            'Splice damaged conductor',
        ]
    },
    'EM': {
        'name': 'Emergency Maintenance',
        'prefix': 'EM',
        'priority_weights': {'HIGH': 30, 'EMERGENCY': 70},
        'duration_hours': (1, 6),
        'descriptions': [
            'Restore power - transformer failure',
            'Clear fallen tree on lines',
            'Replace blown transformer',
            'Emergency pole replacement',
            'Repair storm-damaged equipment',
            'Address downed power line',
            'Emergency cable repair',
            'Fire damage restoration',
        ]
    },
    'SI': {
        'name': 'Service Installation',
        'prefix': 'SI',
        'priority_weights': {'LOW': 20, 'MEDIUM': 70, 'HIGH': 10},
        'duration_hours': (2, 6),
        'descriptions': [
            'New residential meter installation',
            'Commercial service upgrade',
            'Install new transformer',
            'New underground service connection',
            'Meter exchange - AMI upgrade',
            'Install service disconnect',
            'New pole installation for service',
            'Secondary service extension',
        ]
    },
}

WORK_ORDER_STATUSES = ['CREATED', 'SCHEDULED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED']

CREW_TYPES = {
    'LINE': {'prefix': 'LINE', 'count': 50, 'skills': ['overhead', 'underground', 'hot_work']},
    'SUBSTATION': {'prefix': 'SUB', 'count': 15, 'skills': ['transformer', 'switching', 'relay']},
    'METER': {'prefix': 'MTR', 'count': 30, 'skills': ['ami', 'installation', 'testing']},
    'VEGETATION': {'prefix': 'VEG', 'count': 20, 'skills': ['trimming', 'removal', 'herbicide']},
}


def generate_work_order(
    customer_id: Optional[str] = None,
    transformer_id: Optional[str] = None,
    circuit_id: Optional[str] = None,
    work_order_type: Optional[str] = None,
    base_date: Optional[datetime] = None,
    weather_factor: float = 1.0,  # 1.0 = normal, >1 = bad weather (more EM)
    aging_factor: float = 1.0,   # 1.0 = normal, >1 = older equipment (more CM)
) -> Dict[str, Any]:
    """
    Generate a realistic SAP-style work order.
    
    Correlations:
    - Bad weather increases emergency work orders
    - Aging equipment increases corrective maintenance
    - Work orders link to customers, transformers, circuits
    """
    
    if base_date is None:
        base_date = datetime.now()
    
    # Select work order type with weather/aging correlation
    if work_order_type is None:
        type_weights = {'PM': 40, 'CM': 30, 'EM': 10, 'SI': 20}
        # Adjust for weather - bad weather = more emergency
        type_weights['EM'] = int(type_weights['EM'] * weather_factor)
        type_weights['PM'] = max(10, type_weights['PM'] - int(10 * (weather_factor - 1)))
        # Adjust for aging - older equipment = more corrective
        type_weights['CM'] = int(type_weights['CM'] * aging_factor)
        type_weights['PM'] = max(10, type_weights['PM'] - int(5 * (aging_factor - 1)))
        
        work_order_type = random.choices(
            list(type_weights.keys()),
            weights=list(type_weights.values())
        )[0]
    
    wo_config = WORK_ORDER_TYPES[work_order_type]
    
    # Generate work order ID
    wo_id = f"{wo_config['prefix']}-{base_date.strftime('%Y%m')}-{random.randint(100000, 999999)}"
    
    # Select priority based on type
    priority = random.choices(
        list(wo_config['priority_weights'].keys()),
        weights=list(wo_config['priority_weights'].values())
    )[0]
    
    # Select status with realistic distribution
    if priority == 'EMERGENCY':
        status_weights = {'CREATED': 5, 'SCHEDULED': 5, 'IN_PROGRESS': 30, 'COMPLETED': 60, 'CANCELLED': 0}
    else:
        status_weights = {'CREATED': 15, 'SCHEDULED': 25, 'IN_PROGRESS': 15, 'COMPLETED': 40, 'CANCELLED': 5}
    
    status = random.choices(
        list(status_weights.keys()),
        weights=list(status_weights.values())
    )[0]
    
    # Calculate dates
    created_date = base_date - timedelta(days=random.randint(0, 30))
    
    if status in ['SCHEDULED', 'IN_PROGRESS', 'COMPLETED']:
        scheduled_date = created_date + timedelta(days=random.randint(1, 14))
    else:
        scheduled_date = None
    
    if status == 'COMPLETED':
        min_hours, max_hours = wo_config['duration_hours']
        duration = random.uniform(min_hours, max_hours)
        completed_date = scheduled_date + timedelta(hours=duration) if scheduled_date else None
    else:
        completed_date = None
        duration = None
    
    # Select crew
    if work_order_type in ['PM', 'CM', 'EM']:
        crew_type = random.choice(['LINE', 'SUBSTATION'])
    elif work_order_type == 'SI':
        crew_type = random.choice(['LINE', 'METER'])
    else:
        crew_type = 'LINE'
    
    crew_config = CREW_TYPES[crew_type]
    crew_id = f"{crew_config['prefix']}-{random.randint(1, crew_config['count']):03d}"
    
    # Estimate costs
    labor_rate = 85  # $ per hour
    parts_base = {'PM': 150, 'CM': 800, 'EM': 2000, 'SI': 500}
    
    estimated_hours = random.uniform(*wo_config['duration_hours'])
    actual_hours = duration if duration else None
    
    labor_cost = round(estimated_hours * labor_rate, 2)
    parts_cost = round(parts_base[work_order_type] * random.uniform(0.5, 2.0), 2)
    
    return {
        'WORK_ORDER_ID': wo_id,
        'WORK_ORDER_TYPE': work_order_type,
        'WORK_ORDER_TYPE_NAME': wo_config['name'],
        'PRIORITY': priority,
        'STATUS': status,
        'CUSTOMER_ID': customer_id,
        'TRANSFORMER_ID': transformer_id,
        'CIRCUIT_ID': circuit_id,
        'DESCRIPTION': random.choice(wo_config['descriptions']),
        'CREATED_DATE': created_date,
        'SCHEDULED_DATE': scheduled_date,
        'COMPLETED_DATE': completed_date,
        'CREW_ID': crew_id,
        'CREW_TYPE': crew_type,
        'ESTIMATED_DURATION_HOURS': round(estimated_hours, 2),
        'ACTUAL_DURATION_HOURS': round(actual_hours, 2) if actual_hours else None,
        'LABOR_COST': labor_cost,
        'PARTS_COST': parts_cost,
        'TOTAL_COST': round(labor_cost + parts_cost, 2),
    }


def generate_work_orders_batch(
    count: int,
    customers: List[Dict] = None,
    transformers: List[Dict] = None,
    circuits: List[Dict] = None,
    start_date: datetime = None,
    end_date: datetime = None,
    seasonal_pattern: str = 'SUMMER',  # SUMMER, WINTER, SPRING, FALL
) -> List[Dict]:
    """
    Generate a batch of correlated work orders.
    
    Seasonal patterns affect work order distribution:
    - SUMMER: More PM (vegetation), more EM (storm damage)
    - WINTER: More CM (equipment failures), fewer SI
    - SPRING/FALL: Balanced, more PM
    """
    
    if start_date is None:
        start_date = datetime.now() - timedelta(days=180)
    if end_date is None:
        end_date = datetime.now()
    
    # Seasonal adjustments
    seasonal_factors = {
        'SUMMER': {'weather_factor': 1.5, 'aging_factor': 1.0},
        'WINTER': {'weather_factor': 1.3, 'aging_factor': 1.3},
        'SPRING': {'weather_factor': 1.2, 'aging_factor': 1.0},
        'FALL': {'weather_factor': 1.1, 'aging_factor': 1.1},
    }
    
    factors = seasonal_factors.get(seasonal_pattern, seasonal_factors['SUMMER'])
    
    work_orders = []
    date_range_days = (end_date - start_date).days
    
    for _ in range(count):
        # Random date within range
        base_date = start_date + timedelta(days=random.randint(0, date_range_days))
        
        # Select related entities if available
        customer_id = random.choice(customers)['CUSTOMER_ID'] if customers else None
        transformer_id = random.choice(transformers)['TRANSFORMER_ID'] if transformers else None
        circuit_id = random.choice(circuits)['CIRCUIT_ID'] if circuits else None
        
        wo = generate_work_order(
            customer_id=customer_id,
            transformer_id=transformer_id,
            circuit_id=circuit_id,
            base_date=base_date,
            **factors
        )
        work_orders.append(wo)
    
    return work_orders


# ============================================================================
# OUTAGE EVENT GENERATOR (ERM Style)
# ============================================================================

OUTAGE_CAUSES = {
    'WEATHER': {
        'causes': ['Lightning strike', 'Wind damage', 'Ice accumulation', 'Flooding', 'Tornado damage'],
        'weight': 35,
        'duration_hours': (1, 8),
        'customers_affected_multiplier': 1.5,
    },
    'EQUIPMENT_FAILURE': {
        'causes': ['Transformer failure', 'Fuse failure', 'Cable fault', 'Switch malfunction', 'Capacitor failure'],
        'weight': 25,
        'duration_hours': (0.5, 4),
        'customers_affected_multiplier': 1.0,
    },
    'VEGETATION': {
        'causes': ['Tree contact', 'Branch fell on line', 'Vegetation growth into line', 'Root damage to underground'],
        'weight': 20,
        'duration_hours': (0.5, 3),
        'customers_affected_multiplier': 0.8,
    },
    'ANIMAL': {
        'causes': ['Squirrel contact', 'Bird contact', 'Snake in equipment', 'Raccoon damage'],
        'weight': 10,
        'duration_hours': (0.25, 2),
        'customers_affected_multiplier': 0.5,
    },
    'VEHICLE': {
        'causes': ['Vehicle hit pole', 'Construction equipment contact', 'Crane contact with line'],
        'weight': 5,
        'duration_hours': (1, 6),
        'customers_affected_multiplier': 1.2,
    },
    'PLANNED': {
        'causes': ['Scheduled maintenance', 'System upgrade', 'New construction', 'Capacity expansion'],
        'weight': 5,
        'duration_hours': (2, 8),
        'customers_affected_multiplier': 0.7,
    },
}


def generate_outage_event(
    transformer_id: Optional[str] = None,
    circuit_id: Optional[str] = None,
    substation_id: Optional[str] = None,
    base_timestamp: Optional[datetime] = None,
    weather_severity: float = 1.0,  # 1.0 = normal, >1 = severe weather
    transformer_health: float = 1.0,  # 1.0 = good, <1 = poor health
    meters_on_transformer: int = 10,
) -> Dict[str, Any]:
    """
    Generate a realistic outage event.
    
    Correlations:
    - Severe weather increases weather-related outages
    - Poor transformer health increases equipment failures
    - More meters = more customers affected
    """
    
    if base_timestamp is None:
        base_timestamp = datetime.now()
    
    # Adjust cause weights based on conditions
    adjusted_weights = {}
    for cause_type, config in OUTAGE_CAUSES.items():
        weight = config['weight']
        if cause_type == 'WEATHER':
            weight *= weather_severity
        elif cause_type == 'EQUIPMENT_FAILURE':
            weight *= (2.0 - transformer_health)  # Poor health = more failures
        adjusted_weights[cause_type] = weight
    
    # Select cause type
    cause_type = random.choices(
        list(adjusted_weights.keys()),
        weights=list(adjusted_weights.values())
    )[0]
    
    cause_config = OUTAGE_CAUSES[cause_type]
    
    # Generate outage details
    outage_id = f"OUT-{base_timestamp.strftime('%Y%m%d')}-{random.randint(10000, 99999)}"
    
    min_hours, max_hours = cause_config['duration_hours']
    duration_hours = random.uniform(min_hours, max_hours)
    
    outage_start = base_timestamp - timedelta(hours=random.randint(0, 24))
    outage_end = outage_start + timedelta(hours=duration_hours)
    
    # Calculate customers affected
    base_customers = meters_on_transformer * random.randint(1, 3)  # 1-3 customers per meter
    customers_affected = int(base_customers * cause_config['customers_affected_multiplier'])
    
    # Determine if weather related
    weather_related = cause_type in ['WEATHER', 'VEGETATION']
    
    return {
        'OUTAGE_ID': outage_id,
        'TRANSFORMER_ID': transformer_id,
        'CIRCUIT_ID': circuit_id,
        'SUBSTATION_ID': substation_id,
        'OUTAGE_START_TIME': outage_start,
        'OUTAGE_END_TIME': outage_end,
        'DURATION_HOURS': round(duration_hours, 2),
        'OUTAGE_CAUSE': random.choice(cause_config['causes']),
        'OUTAGE_CAUSE_CATEGORY': cause_type,
        'CUSTOMERS_AFFECTED': customers_affected,
        'WEATHER_RELATED': weather_related,
        'RESTORATION_CREW': f"CREW-{random.randint(100, 999)}",
        'CMI': customers_affected * round(duration_hours * 60),  # Customer Minutes Interrupted
        'SAIDI_CONTRIBUTION': round(duration_hours * 60, 2),  # Minutes
    }


def generate_outages_batch(
    count: int,
    transformers: List[Dict] = None,
    circuits: List[Dict] = None,
    start_date: datetime = None,
    end_date: datetime = None,
    seasonal_pattern: str = 'SUMMER',
) -> List[Dict]:
    """Generate a batch of correlated outage events."""
    
    if start_date is None:
        start_date = datetime.now() - timedelta(days=180)
    if end_date is None:
        end_date = datetime.now()
    
    # Seasonal weather severity
    seasonal_weather = {
        'SUMMER': 1.5,  # Storm season
        'WINTER': 1.3,  # Ice storms
        'SPRING': 1.2,
        'FALL': 1.0,
    }
    
    weather_severity = seasonal_weather.get(seasonal_pattern, 1.0)
    date_range_days = (end_date - start_date).days
    
    outages = []
    for _ in range(count):
        base_timestamp = start_date + timedelta(
            days=random.randint(0, date_range_days),
            hours=random.randint(0, 23)
        )
        
        transformer = random.choice(transformers) if transformers else {}
        circuit = random.choice(circuits) if circuits else {}
        
        outage = generate_outage_event(
            transformer_id=transformer.get('TRANSFORMER_ID'),
            circuit_id=circuit.get('CIRCUIT_ID'),
            substation_id=transformer.get('SUBSTATION_ID'),
            base_timestamp=base_timestamp,
            weather_severity=weather_severity,
            transformer_health=random.uniform(0.7, 1.0),
            meters_on_transformer=random.randint(5, 25),
        )
        outages.append(outage)
    
    return outages


# ============================================================================
# POWER QUALITY EVENT GENERATOR
# ============================================================================

POWER_QUALITY_EVENTS = {
    'VOLTAGE_SAG': {
        'description': 'Voltage dropped below 90% of nominal',
        'voltage_range': (95, 108),  # Lower than nominal
        'duration_ms': (100, 3000),
        'weight': 40,
    },
    'VOLTAGE_SWELL': {
        'description': 'Voltage rose above 110% of nominal',
        'voltage_range': (125, 135),  # Higher than nominal
        'duration_ms': (100, 2000),
        'weight': 20,
    },
    'HARMONIC_DISTORTION': {
        'description': 'Total Harmonic Distortion exceeded threshold',
        'thd_range': (5, 15),  # THD percentage
        'duration_ms': (1000, 60000),
        'weight': 15,
    },
    'FLICKER': {
        'description': 'Voltage flicker detected',
        'pst_range': (1.0, 3.0),  # Short-term flicker severity
        'duration_ms': (60000, 600000),
        'weight': 10,
    },
    'TRANSIENT': {
        'description': 'High-frequency voltage transient',
        'magnitude_pct': (120, 200),  # % of nominal
        'duration_ms': (0.1, 50),
        'weight': 10,
    },
    'INTERRUPTION': {
        'description': 'Momentary power interruption',
        'voltage_range': (0, 10),
        'duration_ms': (100, 3000),
        'weight': 5,
    },
}


def generate_power_quality_event(
    meter_id: Optional[str] = None,
    transformer_id: Optional[str] = None,
    base_timestamp: Optional[datetime] = None,
    event_type: Optional[str] = None,
) -> Dict[str, Any]:
    """Generate a power quality event."""
    
    if base_timestamp is None:
        base_timestamp = datetime.now()
    
    if event_type is None:
        event_type = random.choices(
            list(POWER_QUALITY_EVENTS.keys()),
            weights=[e['weight'] for e in POWER_QUALITY_EVENTS.values()]
        )[0]
    
    event_config = POWER_QUALITY_EVENTS[event_type]
    
    # Generate event ID
    event_id = f"PQ-{base_timestamp.strftime('%Y%m%d%H%M%S')}-{random.randint(1000, 9999)}"
    
    # Duration
    min_ms, max_ms = event_config['duration_ms']
    duration_ms = random.uniform(min_ms, max_ms)
    
    # Event-specific measurements
    voltage = None
    thd = None
    pst = None
    magnitude_pct = None
    
    if 'voltage_range' in event_config:
        voltage = round(random.uniform(*event_config['voltage_range']), 1)
    if 'thd_range' in event_config:
        thd = round(random.uniform(*event_config['thd_range']), 2)
    if 'pst_range' in event_config:
        pst = round(random.uniform(*event_config['pst_range']), 2)
    if 'magnitude_pct' in event_config:
        magnitude_pct = round(random.uniform(*event_config['magnitude_pct']), 1)
    
    return {
        'EVENT_ID': event_id,
        'METER_ID': meter_id,
        'TRANSFORMER_ID': transformer_id,
        'TIMESTAMP': base_timestamp,
        'EVENT_TYPE': event_type,
        'DESCRIPTION': event_config['description'],
        'DURATION_MS': round(duration_ms, 2),
        'VOLTAGE': voltage,
        'THD_PCT': thd,
        'FLICKER_PST': pst,
        'TRANSIENT_MAGNITUDE_PCT': magnitude_pct,
        'NOMINAL_VOLTAGE': 120,
        'SEVERITY': 'HIGH' if event_type in ['INTERRUPTION', 'TRANSIENT'] else 'MEDIUM',
    }


def generate_power_quality_batch(
    count: int,
    meters: List[Dict] = None,
    transformers: List[Dict] = None,
    start_date: datetime = None,
    end_date: datetime = None,
) -> List[Dict]:
    """Generate a batch of power quality events."""
    
    if start_date is None:
        start_date = datetime.now() - timedelta(days=30)
    if end_date is None:
        end_date = datetime.now()
    
    date_range_days = (end_date - start_date).days
    events = []
    
    for _ in range(count):
        base_timestamp = start_date + timedelta(
            days=random.randint(0, date_range_days),
            hours=random.randint(0, 23),
            minutes=random.randint(0, 59)
        )
        
        meter = random.choice(meters) if meters else {}
        transformer = random.choice(transformers) if transformers else {}
        
        event = generate_power_quality_event(
            meter_id=meter.get('METER_ID'),
            transformer_id=transformer.get('TRANSFORMER_ID'),
            base_timestamp=base_timestamp,
        )
        events.append(event)
    
    return events


# ============================================================================
# TRANSFORMER LOAD GENERATOR
# ============================================================================

def generate_transformer_load_reading(
    transformer_id: str,
    kva_rating: float,
    timestamp: datetime,
    hour_of_day: int = None,
    is_summer: bool = True,
    connected_meters: int = 10,
) -> Dict[str, Any]:
    """
    Generate a transformer load reading correlated with time and season.
    
    Correlations:
    - Higher load during peak hours (2-7 PM)
    - Higher load in summer (AC) and winter (heating)
    - Load proportional to connected meters
    """
    
    if hour_of_day is None:
        hour_of_day = timestamp.hour
    
    # Base load factor by time of day
    if 14 <= hour_of_day <= 19:  # Peak hours
        base_load_factor = random.uniform(0.6, 0.9)
    elif 6 <= hour_of_day <= 9:  # Morning peak
        base_load_factor = random.uniform(0.4, 0.7)
    elif 22 <= hour_of_day or hour_of_day <= 5:  # Night
        base_load_factor = random.uniform(0.2, 0.4)
    else:  # Off-peak
        base_load_factor = random.uniform(0.3, 0.5)
    
    # Seasonal adjustment
    if is_summer:
        seasonal_multiplier = 1.3  # AC load
    else:
        seasonal_multiplier = 1.1  # Heating load
    
    # Calculate load
    load_factor = min(1.2, base_load_factor * seasonal_multiplier)  # Can be overloaded
    load_kva = kva_rating * load_factor
    load_kw = load_kva * random.uniform(0.85, 0.95)  # Power factor
    
    # Temperature rise based on load
    ambient_temp = random.uniform(25, 40) if is_summer else random.uniform(0, 20)
    temp_rise = (load_factor ** 2) * 65  # Simplified thermal model
    oil_temp = ambient_temp + temp_rise
    
    # Determine status
    if load_factor > 1.0:
        status = 'OVERLOADED'
    elif load_factor > 0.8:
        status = 'HIGH_LOAD'
    else:
        status = 'NORMAL'
    
    return {
        'TRANSFORMER_ID': transformer_id,
        'TIMESTAMP': timestamp,
        'KVA_RATING': kva_rating,
        'LOAD_KVA': round(load_kva, 2),
        'LOAD_KW': round(load_kw, 2),
        'LOAD_FACTOR': round(load_factor, 3),
        'CONNECTED_METERS': connected_meters,
        'AMBIENT_TEMP_C': round(ambient_temp, 1),
        'OIL_TEMP_C': round(oil_temp, 1),
        'STATUS': status,
        'HOUR_OF_DAY': hour_of_day,
        'IS_PEAK_HOUR': 14 <= hour_of_day <= 19,
    }


def generate_transformer_load_batch(
    transformers: List[Dict],
    start_date: datetime = None,
    end_date: datetime = None,
    interval_minutes: int = 15,
    seasonal_pattern: str = 'SUMMER',
) -> List[Dict]:
    """Generate transformer load time series for all transformers."""
    
    if start_date is None:
        start_date = datetime.now() - timedelta(days=7)
    if end_date is None:
        end_date = datetime.now()
    
    is_summer = seasonal_pattern in ['SUMMER', 'SPRING']
    
    readings = []
    current_time = start_date
    
    while current_time <= end_date:
        for transformer in transformers:
            reading = generate_transformer_load_reading(
                transformer_id=transformer.get('TRANSFORMER_ID'),
                kva_rating=transformer.get('KVA_RATING', 50),
                timestamp=current_time,
                is_summer=is_summer,
                connected_meters=transformer.get('METER_COUNT', 10),
            )
            readings.append(reading)
        
        current_time += timedelta(minutes=interval_minutes)
    
    return readings


# ============================================================================
# NARRATIVE CONFIGURATION
# ============================================================================

NARRATIVE_TEMPLATES = {
    'SUMMER_STORM': {
        'name': 'Summer Storm Season',
        'description': 'Houston summer with frequent thunderstorms and high AC load',
        'seasonal_pattern': 'SUMMER',
        'weather_severity': 1.8,
        'work_order_multiplier': 1.5,
        'outage_multiplier': 2.0,
        'date_range': ('2024-06-01', '2024-08-31'),
    },
    'WINTER_FREEZE': {
        'name': 'Winter Freeze Event',
        'description': 'Texas winter storm with equipment failures and heating load',
        'seasonal_pattern': 'WINTER',
        'weather_severity': 2.5,
        'work_order_multiplier': 2.0,
        'outage_multiplier': 3.0,
        'date_range': ('2024-01-01', '2024-02-28'),
    },
    'NORMAL_OPERATIONS': {
        'name': 'Normal Operations',
        'description': 'Typical operations with routine maintenance',
        'seasonal_pattern': 'SPRING',
        'weather_severity': 1.0,
        'work_order_multiplier': 1.0,
        'outage_multiplier': 1.0,
        'date_range': ('2024-03-01', '2024-05-31'),
    },
    'HURRICANE_SEASON': {
        'name': 'Hurricane Season',
        'description': 'Gulf Coast hurricane preparation and recovery',
        'seasonal_pattern': 'SUMMER',
        'weather_severity': 3.0,
        'work_order_multiplier': 2.5,
        'outage_multiplier': 4.0,
        'date_range': ('2024-08-01', '2024-10-31'),
    },
}


def get_narrative_config(narrative_name: str) -> Dict:
    """Get configuration for a narrative template."""
    return NARRATIVE_TEMPLATES.get(narrative_name, NARRATIVE_TEMPLATES['NORMAL_OPERATIONS'])


# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

def correlate_events_with_weather(
    events: List[Dict],
    weather_data: List[Dict],
    timestamp_field: str = 'TIMESTAMP',
) -> List[Dict]:
    """
    Correlate events with weather data by timestamp.
    Adds weather context to each event.
    """
    
    # Build weather lookup by hour
    weather_by_hour = {}
    for w in weather_data:
        ts = w.get('TIMESTAMP')
        if ts:
            hour_key = ts.strftime('%Y-%m-%d %H:00')
            weather_by_hour[hour_key] = w
    
    # Add weather to events
    for event in events:
        ts = event.get(timestamp_field)
        if ts:
            hour_key = ts.strftime('%Y-%m-%d %H:00')
            weather = weather_by_hour.get(hour_key, {})
            event['WEATHER_TEMP_F'] = weather.get('TEMPERATURE_F')
            event['WEATHER_CONDITION'] = weather.get('WEATHER_CONDITION')
            event['WEATHER_WIND_MPH'] = weather.get('WIND_SPEED_MPH')
    
    return events
