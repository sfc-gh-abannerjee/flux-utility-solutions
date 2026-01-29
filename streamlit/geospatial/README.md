# Flux Geospatial Analytics - H3 Visualization App

Interactive Streamlit application for visualizing utility infrastructure using Snowflake's native **H3 hexagonal grid** capabilities.

## Overview

This app demonstrates how to leverage Snowflake's built-in H3 geospatial functions to aggregate and visualize large-scale infrastructure data. H3 (developed by Uber) provides a hierarchical hexagonal grid system that enables efficient spatial indexing and analysis.

## Features

### Analysis Types
- **Meter Density** - Visualize smart meter distribution across service territory
- **Transformer Health** - Identify areas with aging or low-health transformers
- **Load Utilization** - Spot overloaded grid segments requiring attention
- **Coverage Gaps** - Find areas with high meter-to-transformer ratios

### Interactive Controls
- **H3 Resolution Slider** (6-10) - Adjust hexagon granularity
  - Resolution 6: ~36 km² hexagons (regional view)
  - Resolution 7: ~5 km² hexagons (default)
  - Resolution 8: ~0.7 km² hexagons (neighborhood view)
  - Resolution 9: ~0.1 km² hexagons (street-level)
- **3D Elevation Toggle** - Enable/disable extruded hexagons based on count

### Visualization
- PyDeck H3HexagonLayer with color gradients
- Interactive tooltips showing metrics per hexagon
- Expandable raw data table

## Snowflake Features Used

| Feature | Usage |
|---------|-------|
| `H3_POINT_TO_CELL_STRING()` | Convert lat/lon coordinates to H3 cell IDs |
| `ST_MAKEPOINT()` | Create geometry points from coordinates |
| Streamlit in Snowflake | Native app deployment with secure data access |

## Prerequisites

- Snowflake account with Streamlit enabled
- Access to the following tables:
  - `PRODUCTION.METER_INFRASTRUCTURE`
  - `PRODUCTION.TRANSFORMER_METADATA`

## Deployment

### Option 1: Snowsight UI
1. Navigate to **Streamlit** in Snowsight
2. Click **+ Streamlit App**
3. Select your database and warehouse
4. Copy the contents of `streamlit_h3_app.py` into the editor
5. Click **Run**

### Option 2: Git Integration
```sql
CREATE OR REPLACE STREAMLIT FLUX_GEOSPATIAL_H3_APP
    ROOT_LOCATION = '@YOUR_DB.SCHEMA.GIT_REPO/branches/main/streamlit/geospatial'
    MAIN_FILE = 'streamlit_h3_app.py'
    QUERY_WAREHOUSE = 'COMPUTE_WH';
```

### Option 3: Snow CLI
```bash
snow streamlit deploy \
    --database YOUR_DB \
    --schema APPLICATIONS \
    --name FLUX_GEOSPATIAL_H3_APP
```

## Learn More

- [Snowflake H3 Functions Documentation](https://docs.snowflake.com/en/sql-reference/functions/h3_point_to_cell_string)
- [Streamlit in Snowflake](https://docs.snowflake.com/en/developer-guide/streamlit/about-streamlit)
- [PyDeck H3HexagonLayer](https://deckgl.readthedocs.io/en/latest/gallery/h3_hexagon_layer.html)

## File Structure

```
geospatial/
├── .streamlit/
│   └── config.toml      # Theme configuration
├── pyproject.toml       # Dependencies
├── streamlit_h3_app.py  # Main application (236 lines)
└── README.md            # This file
```
