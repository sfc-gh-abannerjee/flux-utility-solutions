"""
Flux Outage Dashboard - Real-Time Outage Tracking

Streamlit in Snowflake app demonstrating:
- Real-time metrics
- Map visualization of outages
- Historical trends
"""

import streamlit as st
import pandas as pd
import pydeck as pdk
import altair as alt

# Page config
st.set_page_config(
    page_title="Flux Outage Dashboard",
    page_icon="🚨",
    layout="wide",
)

# Get Snowflake connection
conn = st.connection("snowflake")

# -----------------------------------------------------------------------------
# Data Loading
# -----------------------------------------------------------------------------

@st.cache_data(ttl=30)  # Refresh every 30 seconds
def load_active_outages():
    """Load current active outages."""
    return conn.query("""
        SELECT 
            o.OUTAGE_ID,
            o.SUBSTATION_ID,
            s.SUBSTATION_NAME,
            o.CAUSE,
            o.STATUS,
            o.START_TIME,
            o.ESTIMATED_RESTORATION,
            o.CUSTOMERS_AFFECTED,
            o.PRIORITY,
            ST_X(s.LOCATION) as LONGITUDE,
            ST_Y(s.LOCATION) as LATITUDE,
            DATEDIFF('minute', o.START_TIME, CURRENT_TIMESTAMP()) as DURATION_MINUTES
        FROM OUTAGE_EVENTS o
        JOIN SUBSTATIONS s ON o.SUBSTATION_ID = s.SUBSTATION_ID
        WHERE o.STATUS = 'ACTIVE'
        ORDER BY o.CUSTOMERS_AFFECTED DESC
    """)

@st.cache_data(ttl=300)
def load_outage_stats():
    """Load outage statistics."""
    return conn.query("""
        SELECT 
            COUNT(*) as TOTAL_OUTAGES,
            SUM(CASE WHEN STATUS = 'ACTIVE' THEN 1 ELSE 0 END) as ACTIVE_OUTAGES,
            SUM(CASE WHEN STATUS = 'ACTIVE' THEN CUSTOMERS_AFFECTED ELSE 0 END) as CUSTOMERS_OUT,
            AVG(DATEDIFF('minute', START_TIME, COALESCE(ACTUAL_RESTORATION, CURRENT_TIMESTAMP()))) as AVG_DURATION_MINS
        FROM OUTAGE_EVENTS
        WHERE START_TIME >= DATEADD(day, -7, CURRENT_TIMESTAMP())
    """)

@st.cache_data(ttl=300)
def load_outages_by_cause():
    """Load outage breakdown by cause."""
    return conn.query("""
        SELECT 
            CAUSE,
            COUNT(*) as OUTAGE_COUNT,
            SUM(CUSTOMERS_AFFECTED) as TOTAL_CUSTOMERS,
            AVG(DATEDIFF('minute', START_TIME, COALESCE(ACTUAL_RESTORATION, CURRENT_TIMESTAMP()))) as AVG_DURATION
        FROM OUTAGE_EVENTS
        WHERE START_TIME >= DATEADD(day, -30, CURRENT_TIMESTAMP())
        GROUP BY CAUSE
        ORDER BY OUTAGE_COUNT DESC
    """)

@st.cache_data(ttl=300)
def load_outages_timeline():
    """Load outages over time."""
    return conn.query("""
        SELECT 
            DATE_TRUNC('hour', START_TIME) as HOUR,
            COUNT(*) as OUTAGES,
            SUM(CUSTOMERS_AFFECTED) as CUSTOMERS
        FROM OUTAGE_EVENTS
        WHERE START_TIME >= DATEADD(day, -7, CURRENT_TIMESTAMP())
        GROUP BY 1
        ORDER BY 1
    """)

# -----------------------------------------------------------------------------
# Main Layout
# -----------------------------------------------------------------------------

st.title("🚨 Flux Outage Dashboard")

# Auto-refresh button
col_refresh, col_spacer = st.columns([1, 5])
with col_refresh:
    if st.button("🔄 Refresh"):
        st.cache_data.clear()
        st.rerun()

# Load data
active_outages = load_active_outages()
stats = load_outage_stats()

# Summary metrics
st.markdown("---")
col1, col2, col3, col4 = st.columns(4)

with col1:
    active_count = int(stats['ACTIVE_OUTAGES'].iloc[0]) if len(stats) > 0 else 0
    st.metric(
        "Active Outages",
        active_count,
        delta=None,
        delta_color="inverse"
    )

with col2:
    customers_out = int(stats['CUSTOMERS_OUT'].iloc[0]) if len(stats) > 0 else 0
    st.metric(
        "Customers Without Power",
        f"{customers_out:,}",
    )

with col3:
    avg_duration = float(stats['AVG_DURATION_MINS'].iloc[0]) if len(stats) > 0 else 0
    st.metric(
        "Avg Duration",
        f"{avg_duration:.0f} min",
    )

with col4:
    total_week = int(stats['TOTAL_OUTAGES'].iloc[0]) if len(stats) > 0 else 0
    st.metric(
        "Outages (7 days)",
        total_week,
    )

# Map and table layout
st.markdown("---")
map_col, table_col = st.columns([2, 1])

with map_col:
    st.subheader("Active Outage Locations")
    
    if len(active_outages) > 0:
        # Build map layer
        layer = pdk.Layer(
            "ScatterplotLayer",
            data=active_outages,
            get_position=["LONGITUDE", "LATITUDE"],
            get_radius="CUSTOMERS_AFFECTED * 5",
            get_fill_color=[244, 67, 54, 200],
            pickable=True,
            radius_min_pixels=10,
            radius_max_pixels=100,
        )
        
        view_state = pdk.ViewState(
            longitude=-95.37,
            latitude=29.76,
            zoom=9,
            pitch=0,
        )
        
        st.pydeck_chart(
            pdk.Deck(
                layers=[layer],
                initial_view_state=view_state,
                map_style="mapbox://styles/mapbox/dark-v10",
                tooltip={
                    "html": "<b>{SUBSTATION_NAME}</b><br/>Cause: {CAUSE}<br/>Customers: {CUSTOMERS_AFFECTED}<br/>Duration: {DURATION_MINUTES} min",
                    "style": {"backgroundColor": "#1a1a2e", "color": "white"},
                },
            ),
            use_container_width=True,
        )
    else:
        st.success("✅ No active outages!")

with table_col:
    st.subheader("Active Outages")
    
    if len(active_outages) > 0:
        # Priority color coding
        def priority_color(priority):
            return "🔴" if priority == "HIGH" else "🟡"
        
        display_df = active_outages[["SUBSTATION_NAME", "CAUSE", "CUSTOMERS_AFFECTED", "DURATION_MINUTES", "PRIORITY"]].copy()
        display_df["PRIORITY"] = display_df["PRIORITY"].apply(priority_color)
        display_df.columns = ["Location", "Cause", "Customers", "Duration (min)", "Priority"]
        
        st.dataframe(display_df, use_container_width=True, hide_index=True)
    else:
        st.info("All clear!")

# Analytics section
st.markdown("---")
st.subheader("Outage Analytics")

tab1, tab2 = st.tabs(["By Cause", "Timeline"])

with tab1:
    cause_data = load_outages_by_cause()
    
    if len(cause_data) > 0:
        chart = alt.Chart(cause_data).mark_bar().encode(
            x=alt.X('CAUSE:N', title='Cause', sort='-y'),
            y=alt.Y('OUTAGE_COUNT:Q', title='Number of Outages'),
            color=alt.Color('CAUSE:N', legend=None),
            tooltip=['CAUSE', 'OUTAGE_COUNT', 'TOTAL_CUSTOMERS', 'AVG_DURATION']
        ).properties(
            height=300
        )
        st.altair_chart(chart, use_container_width=True)

with tab2:
    timeline_data = load_outages_timeline()
    
    if len(timeline_data) > 0:
        chart = alt.Chart(timeline_data).mark_area(
            line={'color': '#f44336'},
            color=alt.Gradient(
                gradient='linear',
                stops=[
                    alt.GradientStop(color='#c62828', offset=0),
                    alt.GradientStop(color='#f44336', offset=1)
                ],
                x1=1, x2=1, y1=1, y2=0
            )
        ).encode(
            x=alt.X('HOUR:T', title='Time'),
            y=alt.Y('OUTAGES:Q', title='Outages'),
            tooltip=['HOUR:T', 'OUTAGES:Q', 'CUSTOMERS:Q']
        ).properties(
            height=300
        )
        st.altair_chart(chart, use_container_width=True)
