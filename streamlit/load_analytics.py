"""
Flux Load Analytics - Time Series Visualization Demo

Streamlit in Snowflake app demonstrating:
- Time series charts with Altair
- Aggregation queries on 7.1B row AMI table
- Demand forecasting visualization
"""

import streamlit as st
import pandas as pd
import altair as alt
from datetime import datetime, timedelta

# Page config
st.set_page_config(
    page_title="Flux Load Analytics",
    page_icon="📊",
    layout="wide",
)

# Get Snowflake connection
conn = st.connection("snowflake")

# -----------------------------------------------------------------------------
# Data Loading
# -----------------------------------------------------------------------------

@st.cache_data(ttl=300)
def load_hourly_load(days: int = 7):
    """Load hourly aggregated load data."""
    return conn.query(f"""
        SELECT 
            DATE_TRUNC('hour', READING_TIMESTAMP) as HOUR,
            SUM(KWH_READING) as TOTAL_KWH,
            AVG(KWH_READING) as AVG_KWH,
            COUNT(*) as READING_COUNT,
            COUNT(DISTINCT METER_ID) as ACTIVE_METERS
        FROM AMI_INTERVAL_READINGS
        WHERE READING_TIMESTAMP >= DATEADD(day, -{days}, CURRENT_TIMESTAMP())
        GROUP BY 1
        ORDER BY 1
    """)

@st.cache_data(ttl=300)
def load_substation_load(substation_id: str, days: int = 7):
    """Load hourly load for a specific substation."""
    return conn.query(f"""
        SELECT 
            DATE_TRUNC('hour', a.READING_TIMESTAMP) as HOUR,
            SUM(a.KWH_READING) as TOTAL_KWH,
            COUNT(DISTINCT a.METER_ID) as METERS
        FROM AMI_INTERVAL_READINGS a
        JOIN TRANSFORMER_METADATA t ON a.TRANSFORMER_ID = t.TRANSFORMER_ID
        WHERE t.SUBSTATION_ID = '{substation_id}'
          AND a.READING_TIMESTAMP >= DATEADD(day, -{days}, CURRENT_TIMESTAMP())
        GROUP BY 1
        ORDER BY 1
    """)

@st.cache_data(ttl=600)
def load_substations_list():
    """Load list of substations for dropdown."""
    return conn.query("""
        SELECT SUBSTATION_ID, SUBSTATION_NAME, CAPACITY_MVA
        FROM SUBSTATIONS
        ORDER BY SUBSTATION_NAME
    """)

@st.cache_data(ttl=300)
def load_peak_demand_by_hour():
    """Load average demand by hour of day."""
    return conn.query("""
        SELECT 
            HOUR(READING_TIMESTAMP) as HOUR_OF_DAY,
            AVG(KWH_READING) as AVG_KWH,
            PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY KWH_READING) as P95_KWH
        FROM AMI_INTERVAL_READINGS
        WHERE READING_TIMESTAMP >= DATEADD(day, -30, CURRENT_TIMESTAMP())
        GROUP BY 1
        ORDER BY 1
    """)

# -----------------------------------------------------------------------------
# Sidebar Controls
# -----------------------------------------------------------------------------

st.sidebar.title("📊 Load Analytics")
st.sidebar.markdown("---")

analysis_type = st.sidebar.radio(
    "Analysis Type",
    ["System-Wide", "By Substation", "Peak Patterns"],
)

days_back = st.sidebar.slider(
    "Days of History",
    min_value=1,
    max_value=30,
    value=7,
)

if analysis_type == "By Substation":
    substations = load_substations_list()
    selected_sub = st.sidebar.selectbox(
        "Select Substation",
        substations["SUBSTATION_ID"].tolist(),
        format_func=lambda x: f"{x} - {substations[substations['SUBSTATION_ID']==x]['SUBSTATION_NAME'].values[0]}"
    )

# -----------------------------------------------------------------------------
# Main Content
# -----------------------------------------------------------------------------

st.title("📊 Flux Load Analytics")

if analysis_type == "System-Wide":
    st.header("System-Wide Load Profile")
    
    with st.spinner("Loading system data..."):
        df = load_hourly_load(days_back)
    
    if len(df) > 0:
        # Summary metrics
        col1, col2, col3, col4 = st.columns(4)
        with col1:
            st.metric("Total Energy (MWh)", f"{df['TOTAL_KWH'].sum() / 1000:,.0f}")
        with col2:
            st.metric("Peak Demand (kWh)", f"{df['TOTAL_KWH'].max():,.0f}")
        with col3:
            st.metric("Avg Active Meters", f"{df['ACTIVE_METERS'].mean():,.0f}")
        with col4:
            st.metric("Total Readings", f"{df['READING_COUNT'].sum():,}")
        
        # Time series chart
        chart = alt.Chart(df).mark_area(
            line={'color': '#4fc3f7'},
            color=alt.Gradient(
                gradient='linear',
                stops=[
                    alt.GradientStop(color='#0093c4', offset=0),
                    alt.GradientStop(color='#4fc3f7', offset=1)
                ],
                x1=1, x2=1, y1=1, y2=0
            )
        ).encode(
            x=alt.X('HOUR:T', title='Time'),
            y=alt.Y('TOTAL_KWH:Q', title='Total Load (kWh)'),
            tooltip=['HOUR:T', 'TOTAL_KWH:Q', 'ACTIVE_METERS:Q']
        ).properties(
            height=400
        )
        
        st.altair_chart(chart, use_container_width=True)
        
        # Data table
        with st.expander("View Raw Data"):
            st.dataframe(df, use_container_width=True)
    else:
        st.warning("No data available for the selected period")

elif analysis_type == "By Substation":
    st.header(f"Load Profile: {selected_sub}")
    
    with st.spinner("Loading substation data..."):
        df = load_substation_load(selected_sub, days_back)
    
    if len(df) > 0:
        # Summary metrics
        col1, col2, col3 = st.columns(3)
        with col1:
            st.metric("Total Energy (kWh)", f"{df['TOTAL_KWH'].sum():,.0f}")
        with col2:
            st.metric("Peak Load (kWh)", f"{df['TOTAL_KWH'].max():,.0f}")
        with col3:
            st.metric("Meters Served", f"{df['METERS'].max():,}")
        
        # Time series chart
        chart = alt.Chart(df).mark_line(
            color='#4fc3f7',
            strokeWidth=2
        ).encode(
            x=alt.X('HOUR:T', title='Time'),
            y=alt.Y('TOTAL_KWH:Q', title='Load (kWh)'),
            tooltip=['HOUR:T', 'TOTAL_KWH:Q', 'METERS:Q']
        ).properties(
            height=400
        )
        
        st.altair_chart(chart, use_container_width=True)
    else:
        st.warning("No data available for the selected substation")

elif analysis_type == "Peak Patterns":
    st.header("Daily Peak Patterns")
    
    with st.spinner("Analyzing peak patterns..."):
        df = load_peak_demand_by_hour()
    
    if len(df) > 0:
        # Bar chart by hour
        chart = alt.Chart(df).mark_bar(
            color='#4fc3f7'
        ).encode(
            x=alt.X('HOUR_OF_DAY:O', title='Hour of Day'),
            y=alt.Y('AVG_KWH:Q', title='Average Demand (kWh)'),
            tooltip=['HOUR_OF_DAY:O', 'AVG_KWH:Q', 'P95_KWH:Q']
        ).properties(
            height=400
        )
        
        # Add P95 line
        p95_line = alt.Chart(df).mark_line(
            color='#ff7043',
            strokeDash=[5, 5]
        ).encode(
            x='HOUR_OF_DAY:O',
            y='P95_KWH:Q'
        )
        
        st.altair_chart(chart + p95_line, use_container_width=True)
        
        st.markdown("""
        **Legend:**
        - Blue bars: Average demand
        - Orange dashed line: 95th percentile (peak demand)
        
        **Key Insights:**
        - Morning peak: 7-9 AM (breakfast, workday start)
        - Evening peak: 6-9 PM (AC load, cooking, lighting)
        - Overnight valley: 1-5 AM (minimal activity)
        """)
    else:
        st.warning("No data available")
