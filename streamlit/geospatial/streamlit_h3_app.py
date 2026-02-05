"""
Flux Geospatial Analytics - H3 Visualization App
================================================
Streamlit in Snowflake app for visualizing Houston utility infrastructure
using H3 hexagonal grids.

Deploy to Snowflake:
1. Go to Snowsight > Streamlit
2. Create new app in your target database (e.g., FLUX_PROD)
3. Copy this code into the editor
4. Run the app

The app uses the database context from where it's deployed, or you can
configure it via the sidebar.
"""

import streamlit as st
import pandas as pd
import pydeck as pdk
import os

# Page config
st.set_page_config(
    page_title="Flux Geospatial Analytics",
    page_icon="⚡",
    layout="wide"
)

# Get Snowflake session
session = st.connection("snowflake").session()

# Get current database context (for SiS apps, this is the database where the app is deployed)
try:
    current_db = session.sql("SELECT CURRENT_DATABASE()").collect()[0][0]
except:
    current_db = os.getenv("SNOWFLAKE_DATABASE", "FLUX_DB")  # Fallback default

# Configuration - can be overridden via sidebar
DB = current_db
SCHEMA = "PRODUCTION"

# Title and description
st.title("Flux - SiS Geospatial Analytics Demo")
st.markdown("""
Visualize Houston utility infrastructure using **H3 hexagonal grids** - 
Snowflake's native spatial indexing capability.
""")

# Sidebar controls
st.sidebar.header("Analysis Controls")

analysis_type = st.sidebar.selectbox(
    "Select Analysis",
    ["Meter Density", "Transformer Health", "Load Utilization", "Coverage Gaps"]
)

h3_resolution = st.sidebar.slider(
    "H3 Resolution",
    min_value=6,
    max_value=10,
    value=7,
    help="Higher resolution = smaller hexagons (more detail)"
)

show_3d = st.sidebar.checkbox("3D Elevation", value=True)

# Queries based on analysis type
if analysis_type == "Meter Density":
    query = f"""
    SELECT 
        H3_POINT_TO_CELL_STRING(ST_MAKEPOINT(METER_LONGITUDE, METER_LATITUDE), {h3_resolution}) as H3,
        COUNT(*) as COUNT,
        COUNT(DISTINCT TRANSFORMER_ID) as TRANSFORMERS,
        COUNT(DISTINCT CIRCUIT_ID) as CIRCUITS,
        AVG(METER_LATITUDE) as LAT,
        AVG(METER_LONGITUDE) as LON
    FROM {DB}.{SCHEMA}.METER_INFRASTRUCTURE
    WHERE METER_LATITUDE IS NOT NULL
    GROUP BY 1
    """
    color_field = "COUNT"
    tooltip_html = "<b>Hexagon:</b> {H3}<br/><b>Meters:</b> {COUNT}<br/><b>Transformers:</b> {TRANSFORMERS}"
    
elif analysis_type == "Transformer Health":
    query = f"""
    SELECT 
        H3_POINT_TO_CELL_STRING(ST_MAKEPOINT(LONGITUDE, LATITUDE), {h3_resolution}) as H3,
        COUNT(*) as COUNT,
        ROUND(AVG(HEALTH_SCORE), 1) as AVG_HEALTH,
        SUM(CASE WHEN HEALTH_SCORE < 60 THEN 1 ELSE 0 END) as LOW_HEALTH_COUNT,
        AVG(LATITUDE) as LAT,
        AVG(LONGITUDE) as LON
    FROM {DB}.{SCHEMA}.TRANSFORMER_METADATA
    WHERE LATITUDE IS NOT NULL AND HEALTH_SCORE IS NOT NULL
    GROUP BY 1
    """
    color_field = "AVG_HEALTH"
    tooltip_html = "<b>Hexagon:</b> {H3}<br/><b>Transformers:</b> {COUNT}<br/><b>Avg Health:</b> {AVG_HEALTH}%<br/><b>Low Health:</b> {LOW_HEALTH_COUNT}"

elif analysis_type == "Load Utilization":
    query = f"""
    SELECT 
        H3_POINT_TO_CELL_STRING(ST_MAKEPOINT(LONGITUDE, LATITUDE), {h3_resolution}) as H3,
        COUNT(*) as COUNT,
        ROUND(AVG(LOAD_UTILIZATION_PCT), 1) as AVG_LOAD,
        SUM(CASE WHEN LOAD_UTILIZATION_PCT > 80 THEN 1 ELSE 0 END) as HIGH_LOAD_COUNT,
        AVG(LATITUDE) as LAT,
        AVG(LONGITUDE) as LON
    FROM {DB}.{SCHEMA}.TRANSFORMER_METADATA
    WHERE LATITUDE IS NOT NULL AND LOAD_UTILIZATION_PCT IS NOT NULL
    GROUP BY 1
    """
    color_field = "AVG_LOAD"
    tooltip_html = "<b>Hexagon:</b> {H3}<br/><b>Transformers:</b> {COUNT}<br/><b>Avg Load:</b> {AVG_LOAD}%<br/><b>High Load:</b> {HIGH_LOAD_COUNT}"

else:  # Coverage Gaps
    query = f"""
    WITH meter_hex AS (
        SELECT 
            H3_POINT_TO_CELL_STRING(ST_MAKEPOINT(METER_LONGITUDE, METER_LATITUDE), {h3_resolution}) as H3,
            COUNT(*) as METER_COUNT,
            AVG(METER_LATITUDE) as LAT,
            AVG(METER_LONGITUDE) as LON
        FROM {DB}.{SCHEMA}.METER_INFRASTRUCTURE
        WHERE METER_LATITUDE IS NOT NULL
        GROUP BY 1
    ),
    transformer_hex AS (
        SELECT 
            H3_POINT_TO_CELL_STRING(ST_MAKEPOINT(LONGITUDE, LATITUDE), {h3_resolution}) as H3,
            COUNT(*) as TRANSFORMER_COUNT
        FROM {DB}.{SCHEMA}.TRANSFORMER_METADATA
        WHERE LATITUDE IS NOT NULL
        GROUP BY 1
    )
    SELECT 
        m.H3,
        m.METER_COUNT as COUNT,
        COALESCE(t.TRANSFORMER_COUNT, 0) as TRANSFORMERS,
        ROUND(m.METER_COUNT / NULLIF(t.TRANSFORMER_COUNT, 0), 1) as METERS_PER_TRANSFORMER,
        m.LAT,
        m.LON
    FROM meter_hex m
    LEFT JOIN transformer_hex t ON m.H3 = t.H3
    """
    color_field = "METERS_PER_TRANSFORMER"
    tooltip_html = "<b>Hexagon:</b> {H3}<br/><b>Meters:</b> {COUNT}<br/><b>Transformers:</b> {TRANSFORMERS}<br/><b>Ratio:</b> {METERS_PER_TRANSFORMER}"

# Execute query
with st.spinner("Loading geospatial data..."):
    df = session.sql(query).to_pandas()

# Calculate color based on field
if len(df) > 0:
    max_val = df[color_field].max()
    min_val = df[color_field].min()
    
    if analysis_type == "Transformer Health":
        # Green = high health, Red = low health
        df['COLOR'] = df[color_field].apply(
            lambda x: [int(255 * (1 - (x - min_val) / (max_val - min_val + 0.01))),
                      int(255 * ((x - min_val) / (max_val - min_val + 0.01))),
                      0, 180] if pd.notna(x) else [128, 128, 128, 100]
        )
    else:
        # Yellow to Red gradient
        df['COLOR'] = df[color_field].apply(
            lambda x: [255,
                      int(255 * (1 - (x - min_val) / (max_val - min_val + 0.01))),
                      0, 180] if pd.notna(x) else [128, 128, 128, 100]
        )

# Metrics row
col1, col2, col3, col4 = st.columns(4)
with col1:
    st.metric("Total Hexagons", f"{len(df):,}")
with col2:
    st.metric("Total Count", f"{df['COUNT'].sum():,}")
with col3:
    if color_field in df.columns:
        st.metric(f"Avg {color_field}", f"{df[color_field].mean():.1f}")
with col4:
    if color_field in df.columns:
        st.metric(f"Max {color_field}", f"{df[color_field].max():.1f}")

# Create map
if len(df) > 0:
    # H3 Hexagon layer
    layer = pdk.Layer(
        "H3HexagonLayer",
        df,
        get_hexagon="H3",
        get_fill_color="COLOR",
        get_elevation=f"COUNT" if show_3d else "0",
        elevation_scale=5 if show_3d else 0,
        extruded=show_3d,
        pickable=True,
        opacity=0.6,
        coverage=1
    )
    
    # Center on Houston
    view_state = pdk.ViewState(
        latitude=df['LAT'].mean() if 'LAT' in df.columns else 29.76,
        longitude=df['LON'].mean() if 'LON' in df.columns else -95.37,
        zoom=9,
        pitch=45 if show_3d else 0
    )
    
    # Render map
    st.pydeck_chart(
        pdk.Deck(
            layers=[layer],
            initial_view_state=view_state,
            tooltip={"html": tooltip_html, "style": {"color": "white"}}
        ),
        use_container_width=True
    )
else:
    st.warning("No data returned from query")

# Data table
with st.expander("View Raw Data"):
    st.dataframe(df.drop(columns=['COLOR'], errors='ignore'), use_container_width=True)

# Sidebar info
st.sidebar.markdown("---")
st.sidebar.markdown("""
### About H3
H3 is Uber's Discrete Global Grid System:
- **Resolution 6**: ~36 km² hexagons
- **Resolution 7**: ~5 km² hexagons  
- **Resolution 8**: ~0.7 km² hexagons
- **Resolution 9**: ~0.1 km² hexagons

### Key Functions
- `H3_POINT_TO_CELL_STRING()` - Convert lat/lon to H3
- `H3_GRID_DISK()` - Get neighboring hexagons
- `H3_CELL_TO_BOUNDARY()` - Get hexagon polygon
""")

st.sidebar.markdown("---")
st.sidebar.info("""
**Integration Points:**
- Flux Ops Center
- Snowflake Intelligence
- Semantic Views
- Cortex Agents
""")
