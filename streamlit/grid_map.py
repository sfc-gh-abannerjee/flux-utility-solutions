"""
Flux Grid Map - Geospatial Visualization Demo

Streamlit in Snowflake app demonstrating:
- PyDeck map visualization
- Snowflake native geospatial queries
- Real-time data from PRODUCTION schema
"""

import streamlit as st
import pandas as pd
import pydeck as pdk

# Page config
st.set_page_config(
    page_title="Flux Grid Map",
    page_icon="⚡",
    layout="wide",
)

# Get Snowflake connection
conn = st.connection("snowflake")

# -----------------------------------------------------------------------------
# Data Loading
# -----------------------------------------------------------------------------

@st.cache_data(ttl=300)
def load_substations():
    """Load substation locations."""
    return conn.query("""
        SELECT 
            SUBSTATION_ID,
            SUBSTATION_NAME,
            ST_X(LOCATION) as LONGITUDE,
            ST_Y(LOCATION) as LATITUDE,
            CAPACITY_MVA,
            STATUS
        FROM SUBSTATIONS
        WHERE LOCATION IS NOT NULL
    """)

@st.cache_data(ttl=300)
def load_transformers_by_health(health_threshold: float):
    """Load transformers below health threshold."""
    return conn.query(f"""
        SELECT 
            TRANSFORMER_ID,
            SUBSTATION_ID,
            ST_X(LOCATION) as LONGITUDE,
            ST_Y(LOCATION) as LATITUDE,
            HEALTH_SCORE,
            KVA_RATING,
            INSTALLATION_DATE
        FROM TRANSFORMER_METADATA
        WHERE HEALTH_SCORE < {health_threshold}
          AND LOCATION IS NOT NULL
        LIMIT 5000
    """)

@st.cache_data(ttl=60)
def load_active_outages():
    """Load active outage locations."""
    return conn.query("""
        SELECT 
            o.OUTAGE_ID,
            o.CAUSE,
            o.CUSTOMERS_AFFECTED,
            o.START_TIME,
            ST_X(s.LOCATION) as LONGITUDE,
            ST_Y(s.LOCATION) as LATITUDE
        FROM OUTAGE_EVENTS o
        JOIN SUBSTATIONS s ON o.SUBSTATION_ID = s.SUBSTATION_ID
        WHERE o.STATUS = 'ACTIVE'
    """)

# -----------------------------------------------------------------------------
# Sidebar Controls
# -----------------------------------------------------------------------------

st.sidebar.title("⚡ Flux Grid Map")
st.sidebar.markdown("---")

show_substations = st.sidebar.checkbox("Show Substations", value=True)
show_transformers = st.sidebar.checkbox("Show At-Risk Transformers", value=True)
show_outages = st.sidebar.checkbox("Show Active Outages", value=True)

if show_transformers:
    health_threshold = st.sidebar.slider(
        "Health Score Threshold",
        min_value=0.0,
        max_value=100.0,
        value=70.0,
        help="Show transformers with health score below this value"
    )

st.sidebar.markdown("---")
st.sidebar.markdown("### Map Style")
map_style = st.sidebar.selectbox(
    "Base Map",
    ["dark", "light", "satellite"],
    index=0
)

# -----------------------------------------------------------------------------
# Load Data
# -----------------------------------------------------------------------------

substations_df = load_substations() if show_substations else pd.DataFrame()
transformers_df = load_transformers_by_health(health_threshold) if show_transformers else pd.DataFrame()
outages_df = load_active_outages() if show_outages else pd.DataFrame()

# -----------------------------------------------------------------------------
# Build Map Layers
# -----------------------------------------------------------------------------

layers = []

# Substations layer (blue circles)
if show_substations and len(substations_df) > 0:
    layers.append(
        pdk.Layer(
            "ScatterplotLayer",
            data=substations_df,
            get_position=["LONGITUDE", "LATITUDE"],
            get_radius="CAPACITY_MVA * 50",
            get_fill_color=[79, 195, 247, 180],
            pickable=True,
            auto_highlight=True,
        )
    )

# At-risk transformers (orange/red based on health)
if show_transformers and len(transformers_df) > 0:
    # Color based on health score: lower = redder
    transformers_df["COLOR_R"] = (255 * (1 - transformers_df["HEALTH_SCORE"] / 100)).astype(int)
    transformers_df["COLOR_G"] = (transformers_df["HEALTH_SCORE"] * 1.5).astype(int)
    
    layers.append(
        pdk.Layer(
            "ScatterplotLayer",
            data=transformers_df,
            get_position=["LONGITUDE", "LATITUDE"],
            get_radius=200,
            get_fill_color=["COLOR_R", "COLOR_G", 0, 200],
            pickable=True,
        )
    )

# Active outages (pulsing red)
if show_outages and len(outages_df) > 0:
    layers.append(
        pdk.Layer(
            "ScatterplotLayer",
            data=outages_df,
            get_position=["LONGITUDE", "LATITUDE"],
            get_radius="CUSTOMERS_AFFECTED * 10",
            get_fill_color=[244, 67, 54, 200],
            pickable=True,
            radius_min_pixels=10,
            radius_max_pixels=100,
        )
    )

# Map view state (centered on Houston)
view_state = pdk.ViewState(
    longitude=-95.37,
    latitude=29.76,
    zoom=10,
    pitch=45,
    bearing=0,
)

# Map style URLs
MAP_STYLES = {
    "dark": "mapbox://styles/mapbox/dark-v10",
    "light": "mapbox://styles/mapbox/light-v10",
    "satellite": "mapbox://styles/mapbox/satellite-streets-v11",
}

# -----------------------------------------------------------------------------
# Main Layout
# -----------------------------------------------------------------------------

st.title("⚡ Flux Grid Map")

# Stats row
col1, col2, col3, col4 = st.columns(4)
with col1:
    st.metric("Substations", len(substations_df))
with col2:
    st.metric("At-Risk Transformers", len(transformers_df))
with col3:
    st.metric("Active Outages", len(outages_df))
with col4:
    if len(outages_df) > 0:
        st.metric("Customers Affected", f"{outages_df['CUSTOMERS_AFFECTED'].sum():,}")
    else:
        st.metric("Customers Affected", 0)

# Map
st.pydeck_chart(
    pdk.Deck(
        layers=layers,
        initial_view_state=view_state,
        map_style=MAP_STYLES.get(map_style, MAP_STYLES["dark"]),
        tooltip={
            "html": "<b>{SUBSTATION_NAME}</b><br/>Capacity: {CAPACITY_MVA} MVA<br/>Status: {STATUS}",
            "style": {"backgroundColor": "#1a1a2e", "color": "white"},
        },
    ),
    use_container_width=True,
)

# Data tables
st.markdown("---")
tab1, tab2, tab3 = st.tabs(["Substations", "At-Risk Transformers", "Active Outages"])

with tab1:
    if len(substations_df) > 0:
        st.dataframe(substations_df, use_container_width=True)
    else:
        st.info("No substations loaded")

with tab2:
    if len(transformers_df) > 0:
        st.dataframe(
            transformers_df[["TRANSFORMER_ID", "HEALTH_SCORE", "KVA_RATING", "INSTALLATION_DATE"]],
            use_container_width=True
        )
    else:
        st.info("No at-risk transformers found")

with tab3:
    if len(outages_df) > 0:
        st.dataframe(outages_df, use_container_width=True)
    else:
        st.success("No active outages!")
