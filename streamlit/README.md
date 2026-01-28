# Flux Streamlit Applications

Streamlit in Snowflake demo apps showcasing geospatial visualization and grid analytics.

## Applications

### 1. Grid Map (`grid_map.py`)

Interactive map visualization of grid infrastructure:
- Substations with capacity indicators
- At-risk transformers (health score filter)
- Active outage locations
- PyDeck 3D visualization

**Features Demonstrated:**
- Native Snowflake geospatial functions (ST_X, ST_Y)
- PyDeck ScatterplotLayer
- Real-time data refresh
- Interactive filtering

### 2. Load Analytics (`load_analytics.py`)

Time series visualization of energy consumption:
- System-wide load profiles
- Per-substation analysis
- Daily peak patterns
- Demand forecasting views

**Features Demonstrated:**
- Aggregation on 7.1B row AMI table
- Altair charting library
- Cached queries with TTL
- Interactive parameter controls

### 3. Outage Dashboard (`outage_dashboard.py`)

Real-time outage monitoring:
- Active outage map
- Metrics and KPIs
- Cause analysis charts
- Timeline visualization

**Features Demonstrated:**
- Auto-refresh with `st.cache_data(ttl=30)`
- Color-coded priority indicators
- Multi-tab layout
- Responsive design

## Deployment

### Deploy to Snowflake

```sql
-- 1. Create stage for Streamlit apps
CREATE STAGE IF NOT EXISTS {{ database }}.{{ schema }}.STREAMLIT_STAGE;

-- 2. Upload files
PUT file://streamlit/*.py @{{ database }}.{{ schema }}.STREAMLIT_STAGE/;

-- 3. Create Streamlit app
CREATE STREAMLIT {{ database }}.{{ schema }}.FLUX_GRID_MAP
  ROOT_LOCATION = '@{{ database }}.{{ schema }}.STREAMLIT_STAGE'
  MAIN_FILE = 'grid_map.py'
  QUERY_WAREHOUSE = '{{ warehouse }}';

CREATE STREAMLIT {{ database }}.{{ schema }}.FLUX_LOAD_ANALYTICS
  ROOT_LOCATION = '@{{ database }}.{{ schema }}.STREAMLIT_STAGE'
  MAIN_FILE = 'load_analytics.py'
  QUERY_WAREHOUSE = '{{ warehouse }}';

CREATE STREAMLIT {{ database }}.{{ schema }}.FLUX_OUTAGE_DASHBOARD
  ROOT_LOCATION = '@{{ database }}.{{ schema }}.STREAMLIT_STAGE'
  MAIN_FILE = 'outage_dashboard.py'
  QUERY_WAREHOUSE = '{{ warehouse }}';
```

### Local Development

```bash
# Install dependencies
pip install streamlit pandas pydeck altair snowflake-connector-python

# Create connection config
cat > ~/.streamlit/secrets.toml << EOF
[connections.snowflake]
account = "your-account"
user = "your-user"
password = "your-password"
warehouse = "FLUX_WH"
database = "FLUX_PROD"
schema = "PRODUCTION"
EOF

# Run locally
streamlit run streamlit/grid_map.py
```

## Required Tables

These apps query from the PRODUCTION schema:

| Table | Used By |
|-------|---------|
| SUBSTATIONS | Grid Map, Outage Dashboard |
| TRANSFORMER_METADATA | Grid Map |
| AMI_INTERVAL_READINGS | Load Analytics |
| OUTAGE_EVENTS | Outage Dashboard |

## Customization

### Changing Map Center

Edit the `view_state` in each app:

```python
view_state = pdk.ViewState(
    longitude=-95.37,  # Houston
    latitude=29.76,
    zoom=10,
    pitch=45,
)
```

### Adding New Layers

```python
layers.append(
    pdk.Layer(
        "GeoJsonLayer",
        data=geojson_data,
        get_fill_color=[255, 0, 0, 100],
        pickable=True,
    )
)
```

### Adjusting Refresh Rates

```python
@st.cache_data(ttl=30)  # Refresh every 30 seconds
def load_data():
    ...
```
