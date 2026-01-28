# Flux Utility Solutions - Use Case Map

Mapping business problems to Snowflake capabilities.

## Use Case Categories

1. [Asset Health & Predictive Maintenance](#1-asset-health--predictive-maintenance)
2. [Outage Management & Response](#2-outage-management--response)
3. [Load Forecasting & Grid Planning](#3-load-forecasting--grid-planning)
4. [Customer Analytics & Engagement](#4-customer-analytics--engagement)
5. [Regulatory Compliance & Reporting](#5-regulatory-compliance--reporting)
6. [AI-Powered Operations](#6-ai-powered-operations)

---

## 1. Asset Health & Predictive Maintenance

### Business Problem
Utilities spend millions on reactive maintenance. Transformer failures cause outages affecting thousands of customers and cost $50K-500K per incident.

### Snowflake Solution

| Component | Implementation |
|-----------|---------------|
| **Data Foundation** | `TRANSFORMER_METADATA` (91K transformers), `TRANSFORMER_TELEMETRY_HOURLY` (211M readings) |
| **ML Pipeline** | Cortex ML for health score prediction |
| **Visualization** | Streamlit `grid_map.py` with health overlays |
| **AI Assistant** | Cortex Agent for "which transformers need attention?" |

### Key Queries
```sql
-- Transformers at risk this month
SELECT transformer_id, health_score, 
       DATEDIFF(year, installation_date, CURRENT_DATE()) as age
FROM TRANSFORMER_METADATA
WHERE health_score < 70
ORDER BY health_score;

-- Failure prediction using ML
SELECT transformer_id,
       PREDICT_TRANSFORMER_FAILURE(telemetry_features) as failure_probability
FROM TRANSFORMER_FEATURE_TABLE
WHERE failure_probability > 0.7;
```

### Business Impact
- 60% reduction in unplanned failures
- $2M+ annual maintenance savings
- 15% extension of asset lifespan

---

## 2. Outage Management & Response

### Business Problem
Outages cost utilities $100K+ per hour in lost revenue and regulatory penalties. Slow response times damage customer satisfaction and regulatory standing.

### Snowflake Solution

| Component | Implementation |
|-----------|---------------|
| **Real-time Layer** | PostgreSQL (<20ms) for operational queries |
| **Analytics Layer** | `OUTAGE_EVENTS`, `CASCADE_RISK_LOG` tables |
| **Visualization** | Streamlit `outage_dashboard.py` |
| **Procedures** | `ANALYZE_CASCADE_IMPACT()`, `CALCULATE_LOAD_SHED_SEQUENCE()` |

### Key Queries
```sql
-- Active outages with customer impact
SELECT substation_id, cause, customers_affected,
       DATEDIFF(minute, start_time, CURRENT_TIMESTAMP()) as duration_min
FROM OUTAGE_EVENTS
WHERE status = 'ACTIVE'
ORDER BY customers_affected DESC;

-- Cascade impact analysis
CALL ANALYZE_CASCADE_IMPACT('SUB-042', TRUE);
```

### Business Impact
- 40% faster outage response time
- 25% reduction in customer minutes interrupted (CMI)
- Real-time situational awareness for dispatchers

---

## 3. Load Forecasting & Grid Planning

### Business Problem
Inaccurate load forecasts lead to over/under-provisioning, costly peak demand charges, and reliability issues.

### Snowflake Solution

| Component | Implementation |
|-----------|---------------|
| **Data Foundation** | `AMI_INTERVAL_READINGS` (7.1B rows, 15-min intervals) |
| **Time Series** | Dynamic Tables for hourly/daily aggregations |
| **ML Models** | `hourly_load_forecast` in Model Registry |
| **Visualization** | Streamlit `load_analytics.py` |

### Key Queries
```sql
-- Load profile by hour of day
SELECT HOUR(reading_timestamp) as hour,
       AVG(kwh_reading) as avg_kwh,
       MAX(kwh_reading) as peak_kwh
FROM AMI_INTERVAL_READINGS
WHERE reading_timestamp >= DATEADD(day, -30, CURRENT_TIMESTAMP())
GROUP BY 1
ORDER BY 1;

-- Forecast accuracy validation
SELECT forecast_date, predicted_mw, actual_mw,
       ABS(predicted_mw - actual_mw) / actual_mw as error_pct
FROM LOAD_FORECASTS
WHERE forecast_date >= DATEADD(day, -7, CURRENT_DATE());
```

### Business Impact
- 15% improvement in forecast accuracy
- $500K+ reduction in peak demand charges
- Better capacity planning decisions

---

## 4. Customer Analytics & Engagement

### Business Problem
Utilities struggle to understand customer behavior, leading to poor rate design, missed upsell opportunities, and churn.

### Snowflake Solution

| Component | Implementation |
|-----------|---------------|
| **Data Foundation** | `CUSTOMERS_MASTER_DATA` (686K), linked to AMI |
| **Segmentation** | `customer_usage_segmentation` model |
| **Search** | Cortex Search on customer service records |
| **Personalization** | Cortex LLM for tailored communications |

### Key Queries
```sql
-- Customer segmentation
SELECT customer_id, rate_class,
       AVG(kwh_reading) as avg_daily_kwh,
       CASE 
         WHEN AVG(kwh_reading) > 50 THEN 'High Usage'
         WHEN AVG(kwh_reading) > 20 THEN 'Medium Usage'
         ELSE 'Low Usage'
       END as segment
FROM CUSTOMERS_MASTER_DATA c
JOIN METER_INFRASTRUCTURE m ON c.customer_id = m.customer_id
JOIN AMI_INTERVAL_READINGS a ON m.meter_id = a.meter_id
GROUP BY 1, 2;

-- High-value customer identification
SELECT customer_id, total_revenue, tenure_years
FROM CUSTOMER_VALUE_SCORES
WHERE value_segment = 'HIGH'
ORDER BY total_revenue DESC;
```

### Business Impact
- 20% improvement in rate plan optimization
- Targeted energy efficiency programs
- Reduced customer churn through proactive engagement

---

## 5. Regulatory Compliance & Reporting

### Business Problem
Utilities face complex reporting requirements (NERC, state PUCs) with tight deadlines and accuracy requirements.

### Snowflake Solution

| Component | Implementation |
|-----------|---------------|
| **Data Governance** | Row-level security, data masking |
| **Audit Trail** | Query history, access logs |
| **Reporting** | Dynamic Tables for aggregations |
| **Documentation** | Cortex Search on regulatory docs |

### Key Queries
```sql
-- SAIDI/SAIFI metrics (reliability indices)
SELECT 
    YEAR(start_time) as year,
    SUM(customers_affected * duration_minutes) / total_customers as SAIDI,
    COUNT(*) / total_customers as SAIFI
FROM OUTAGE_EVENTS
WHERE status = 'RESTORED'
GROUP BY 1;

-- Data quality audit
SELECT table_name, column_name, 
       COUNT(*) as total_rows,
       COUNT(column_value) as non_null,
       COUNT(column_value) * 100.0 / COUNT(*) as completeness_pct
FROM information_schema.columns
WHERE table_schema = 'PRODUCTION';
```

### Business Impact
- 80% reduction in reporting preparation time
- Audit-ready data lineage
- Automated compliance dashboards

---

## 6. AI-Powered Operations

### Business Problem
Operational decisions require synthesizing data from multiple systems. Traditional BI tools can't answer complex, context-dependent questions.

### Snowflake Solution

| Component | Implementation |
|-----------|---------------|
| **Semantic Model** | 30-table `utility_semantic_model.yaml` |
| **Cortex Agent** | Natural language interface to all data |
| **Tool Calling** | SQL execution, search, analysis |
| **Chat UI** | Flux Ops Center with embedded assistant |

### Example Conversations

**Q: "What caused the most outages last month?"**
> Agent queries OUTAGE_EVENTS, aggregates by cause, returns:
> "Weather events caused 45% of outages (127 incidents), followed by equipment failure at 28%..."

**Q: "Which substations should we prioritize for upgrades?"**
> Agent analyzes transformer health, load growth, customer density:
> "SUB-042 and SUB-078 have the highest upgrade priority. SUB-042 serves 12,000 customers with 3 transformers below 60% health..."

**Q: "Explain the load pattern for commercial customers"**
> Agent queries AMI data, segments by rate class:
> "Commercial customers show peak usage 9AM-5PM weekdays, with 2.3x higher consumption than residential..."

### Business Impact
- Democratized data access for field workers
- Faster decision-making in emergency situations
- Reduced dependency on data analysts

---

## Implementation Priority Matrix

| Use Case | Business Value | Implementation Effort | Recommended Phase |
|----------|---------------|----------------------|-------------------|
| Asset Health | High | Medium | Phase 1 |
| Outage Management | High | Low | Phase 1 |
| Load Forecasting | Medium | Medium | Phase 2 |
| Customer Analytics | Medium | Medium | Phase 2 |
| Compliance Reporting | High | Low | Phase 1 |
| AI Operations | Very High | High | Phase 2-3 |

---

## Success Metrics by Use Case

| Use Case | KPI | Target |
|----------|-----|--------|
| Asset Health | Unplanned outages | -60% |
| Outage Management | Mean time to restore | -40% |
| Load Forecasting | Forecast error (MAPE) | <5% |
| Customer Analytics | Customer satisfaction | +15 NPS |
| Compliance | Report preparation time | -80% |
| AI Operations | Questions answered without analyst | 70% |
