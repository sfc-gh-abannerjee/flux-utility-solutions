# Flux Utility Solutions - Demo Playbook

Step-by-step guides for demonstrating Snowflake capabilities to utility prospects.

## Quick Reference

| Demo | Duration | Audience | Key Features |
|------|----------|----------|--------------|
| Executive Overview | 15 min | C-Suite | ROI, scale, competitive positioning |
| Technical Deep Dive | 45 min | IT/Data Teams | Architecture, performance, security |
| Hands-On Workshop | 2 hours | Developers | Build and deploy components |
| Full POC | 2-5 days | All stakeholders | Complete ecosystem deployment |

---

## Demo 1: Executive Overview (15 minutes)

### Objective
Show business value and competitive differentiation vs legacy systems.

### Setup
- Pre-deploy Flux Ops Center to SPCS
- Load sample data (small dataset is sufficient)
- Open Streamlit dashboard

### Script

**[0:00-2:00] The Problem**
> "Utilities are drowning in data - 7 billion meter readings, 90,000 transformers, 700,000 customers. Legacy systems can't handle this scale or provide real-time insights."

**[2:00-5:00] Live Demo - Flux Ops Center**
- Show map with substations and transformers
- Highlight real-time health scores
- Show customer impact analysis

**[5:00-8:00] The "Ask Me Anything" Moment**
- Open Cortex Agent chat
- Ask: "Which transformers are at highest risk of failure this month?"
- Show AI reasoning and data-backed answer

**[8:00-12:00] Scale and Performance**
- Run query on 7.1B row AMI table: "How long does this take in your current system?"
- Show result in seconds
- Mention: "This same query powers real-time operations"

**[12:00-15:00] Close**
- Show deployment options (5 paths)
- Highlight: "One solution, deploy however you want"
- ROI talking points: 60% reduction in unplanned outages, $2M+ annual savings

### Key Metrics to Mention
- 7.1 billion AMI readings
- Sub-second query response
- 91,000 transformers monitored
- 686,000 customers served
- <20ms operational latency (hybrid PostgreSQL)

---

## Demo 2: Technical Deep Dive (45 minutes)

### Objective
Demonstrate architectural sophistication and Snowflake platform capabilities.

### Audience Prep
- Share ARCHITECTURE.md beforehand
- Confirm interest areas (Cortex, SPCS, performance, security)

### Script

**[0:00-5:00] Architecture Overview**
```
Transactional Layer → Streaming Layer → Analytics Layer → Application Layer
(PostgreSQL <20ms)   (CDC/Streams)     (Snowflake 7.1B)   (SPCS/Streamlit)
```

**[5:00-15:00] Data Platform Capabilities**

Show SQL scripts demonstrating:
1. **Geospatial**: Native H3 and PostGIS-compatible functions
   ```sql
   SELECT * FROM SUBSTATIONS 
   WHERE ST_DISTANCE(location, ST_MAKEPOINT(-95.37, 29.76)) < 10000;
   ```

2. **Time Series at Scale**: Query 7B rows efficiently
   ```sql
   SELECT DATE_TRUNC('hour', reading_timestamp), SUM(kwh_reading)
   FROM AMI_INTERVAL_READINGS 
   WHERE reading_timestamp >= DATEADD(day, -7, CURRENT_TIMESTAMP())
   GROUP BY 1;
   ```

3. **Dynamic Tables**: Real-time aggregations
   ```sql
   SHOW DYNAMIC TABLES LIKE 'TRANSFORMER%';
   ```

**[15:00-25:00] Cortex AI Integration**

1. **Semantic Model**: Show the 30-table utility semantic model
2. **Cortex Search**: Semantic search across documentation
3. **Cortex Agent**: 
   - Show agent YAML configuration
   - Demo natural language queries
   - Highlight tool calling and reasoning

**[25:00-35:00] Application Layer**

1. **SPCS Demo**:
   - Show running services
   - Explain architecture (nginx + FastAPI + React)
   - Health checks and scaling

2. **Streamlit Integration**:
   - Native Snowflake deployment
   - No external hosting required

**[35:00-45:00] Security & Operations**

1. **RBAC**: Show role hierarchy
2. **Data Masking**: PII protection patterns
3. **Network Policies**: SPCS egress controls
4. **Monitoring**: Query history and performance

---

## Demo 3: Hands-On Workshop (2 hours)

### Objective
Enable technical teams to deploy and customize the solution.

### Prerequisites
- Snowflake trial account or dev environment
- GitHub access
- Docker (for SPCS local testing)

### Agenda

| Time | Activity |
|------|----------|
| 0:00-0:15 | Environment setup and quickstart deployment |
| 0:15-0:45 | SQL scripts walkthrough and customization |
| 0:45-1:15 | Cortex AI configuration and testing |
| 1:15-1:45 | SPCS application deployment |
| 1:45-2:00 | Q&A and next steps |

### Hands-On Exercises

**Exercise 1: Deploy Core Tables**
```bash
cd flux-utility-solutions
./cli/quickstart.sh --env dev --connection your_connection
```

**Exercise 2: Query the Data**
Open `scripts/22_sample_queries.sql` and run:
- Basic analytics queries
- Geospatial queries
- Time series patterns

**Exercise 3: Configure Cortex Agent**
Edit `agents/flux_grid_agent.yaml`:
- Add custom instructions
- Configure tool access
- Test with domain-specific questions

**Exercise 4: Deploy Streamlit App**
```sql
CREATE STREAMLIT my_grid_map
  ROOT_LOCATION = '@my_stage'
  MAIN_FILE = 'grid_map.py';
```

---

## Demo 4: Full POC (2-5 days)

### Day 1: Foundation
- Deploy infrastructure (database, warehouses, roles)
- Load customer's sample data
- Validate data model fit

### Day 2: Analytics Layer
- Configure Dynamic Tables for their KPIs
- Set up Cortex Search on their documentation
- Build initial Semantic Model

### Day 3: Application Layer
- Deploy Flux Ops Center with their data
- Configure Cortex Agent for their use cases
- Create custom Streamlit dashboards

### Day 4: Integration
- PostgreSQL sync pipeline (if hybrid needed)
- API integration patterns
- Security review and RBAC configuration

### Day 5: Handoff
- Documentation and runbooks
- Training sessions
- Success criteria validation
- Production deployment planning

---

## Competitive Positioning

### vs. Palantir Foundry
| Capability | Flux on Snowflake | Palantir |
|------------|-------------------|----------|
| Time to Value | Days | Months |
| Pricing | Consumption-based | 7-figure contracts |
| AI Integration | Native Cortex | Requires custom dev |
| Data Sharing | Native Marketplace | Complex federation |

### vs. Databricks
| Capability | Flux on Snowflake | Databricks |
|------------|-------------------|------------|
| SQL Simplicity | Native SQL | Spark SQL complexity |
| Real-time Apps | SPCS + Streamlit | External hosting |
| Governance | Unified platform | Separate tools |

### vs. Custom Build
| Capability | Flux on Snowflake | Custom |
|------------|-------------------|--------|
| Time to Deploy | Hours | 12-18 months |
| Maintenance | Zero | Dedicated team |
| Scale | Automatic | Complex |

---

## Objection Handling

**"We already have a data warehouse"**
> "Flux doesn't replace your warehouse - it extends it with AI, real-time applications, and hybrid architecture. Start with one use case and expand."

**"Snowflake is expensive"**
> "Run this query on 7B rows. Now compare the cost to maintaining infrastructure that could do the same. Consumption-based pricing means you pay for value, not idle capacity."

**"We need real-time, not batch"**
> "Show the PostgreSQL hybrid architecture. <20ms for operations, unlimited scale for analytics. Best of both worlds."

**"Our team doesn't know Snowflake"**
> "Look at these SQL scripts - it's standard SQL with superpowers. Your team will be productive in days, not months."
