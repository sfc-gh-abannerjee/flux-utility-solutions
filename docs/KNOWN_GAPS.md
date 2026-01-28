# Flux Utility Solutions - Known Gaps & Roadmap

Transparency about current limitations and planned enhancements.

## Current Gaps

### 1. Data Gaps

| Gap | Impact | Workaround | Planned Fix |
|-----|--------|------------|-------------|
| **No real weather data** | Outage correlation limited | Use synthetic weather patterns | Integrate NOAA API |
| **Simplified grid topology** | Network analysis incomplete | Pre-computed adjacency | Full graph model |
| **No SCADA integration** | Missing real-time telemetry | Synthetic telemetry generator | OpenADR connector |
| **Limited vegetation data** | Vegetation risk incomplete | Buffer zones only | LiDAR integration |

### 2. Feature Gaps

| Gap | Impact | Workaround | Planned Fix |
|-----|--------|------------|-------------|
| **No mobile app** | Field workers need desktop | Responsive Streamlit | React Native app |
| **Single-region only** | Houston area only | Re-run generators | Multi-region support |
| **English only** | Limited international use | None | i18n framework |
| **No offline mode** | Requires connectivity | None | PWA support |

### 3. Integration Gaps

| Gap | Impact | Workaround | Planned Fix |
|-----|--------|------------|-------------|
| **No SAP integration** | Manual data sync | CSV export | SAP connector |
| **No GIS export** | Can't export to ESRI | Manual conversion | Shapefile export |
| **No OMS integration** | Siloed outage data | API calls | Bidirectional sync |
| **Limited SSO** | Snowflake auth only | Manual user management | SAML/OAuth |

### 4. Scale Limitations

| Limitation | Current | Production Need | Resolution |
|------------|---------|-----------------|------------|
| AMI rows | 7.1B | 50B+ | Partitioning strategy |
| Real-time latency | 5-10s | <1s | Kafka + Snowpipe Streaming |
| Concurrent users | ~50 | 500+ | SPCS auto-scaling |
| Dashboard refresh | 30s | 5s | WebSocket implementation |

---

## Technical Debt

### High Priority

1. **Hardcoded coordinates**
   - Location: `streamlit/grid_map.py`, `spcs/flux_ops_center/src/App.tsx`
   - Issue: Houston coordinates hardcoded
   - Fix: Config-driven map center

2. **Missing error handling**
   - Location: `sync/sync_to_postgres.py`
   - Issue: Exceptions not fully caught
   - Fix: Add retry logic and dead-letter queue

3. **No input validation**
   - Location: `spcs/flux_ops_center/backend/server.py`
   - Issue: SQL injection possible in some endpoints
   - Fix: Parameterized queries everywhere

### Medium Priority

4. **Incomplete type hints**
   - Location: Multiple Python files
   - Issue: Inconsistent typing
   - Fix: Add mypy and enforce types

5. **No unit tests**
   - Location: All Python code
   - Issue: No automated testing
   - Fix: pytest suite with fixtures

6. **CSS in components**
   - Location: React components
   - Issue: Inline styles scattered
   - Fix: Styled-components or CSS modules

### Low Priority

7. **Console.log statements**
   - Location: React components
   - Issue: Debug logs in production
   - Fix: Remove or use proper logging

8. **Unused dependencies**
   - Location: `package.json`, `requirements.txt`
   - Issue: Bloated installs
   - Fix: Audit and remove unused

---

## Roadmap

### Q1 2025: Foundation Hardening

- [ ] Add comprehensive test suite
- [ ] Implement proper error handling
- [ ] Add input validation and sanitization
- [ ] Create configuration management system
- [ ] Document all API endpoints

### Q2 2025: Scale & Performance

- [ ] Implement Snowpipe Streaming for real-time
- [ ] Add Redis caching layer
- [ ] Optimize PostgreSQL sync for large datasets
- [ ] Implement connection pooling
- [ ] Add performance benchmarks

### Q3 2025: Enterprise Features

- [ ] SAML/OAuth SSO integration
- [ ] Multi-tenant support
- [ ] Audit logging and compliance
- [ ] Role-based feature access
- [ ] API rate limiting

### Q4 2025: Advanced Analytics

- [ ] Real weather data integration
- [ ] Advanced ML models (GNN for grid)
- [ ] Anomaly detection pipeline
- [ ] Demand response optimization
- [ ] Carbon tracking integration

---

## Known Issues

### Critical

None currently.

### High

1. **PostgreSQL sync can timeout on large tables**
   - Symptom: Sync fails after 30 minutes
   - Workaround: Run with `--limit 100000` in batches
   - Fix: Implement chunked sync with checkpointing

2. **Cortex Agent sometimes hallucinates transformer IDs**
   - Symptom: Agent references non-existent transformers
   - Workaround: Add validation in prompt
   - Fix: Implement tool result validation

### Medium

3. **Streamlit map doesn't render on Safari mobile**
   - Symptom: Blank map on iOS Safari
   - Workaround: Use Chrome
   - Fix: Update PyDeck version

4. **Health scores don't update after telemetry sync**
   - Symptom: Stale health scores
   - Workaround: Manual refresh
   - Fix: Add Dynamic Table for health calculation

### Low

5. **Dark mode toggle doesn't persist**
   - Symptom: Resets on page refresh
   - Workaround: None
   - Fix: Add localStorage persistence

---

## Assumptions

### Data Assumptions

1. **Meter-to-transformer ratio**: Assumed 7:1 average
2. **Customer-to-meter ratio**: Assumed 1:1 (no multi-meter customers)
3. **Substation service area**: Assumed non-overlapping
4. **Load factor**: Assumed 65% average for transformers

### Technical Assumptions

1. **Snowflake region**: US West 2 (can deploy elsewhere)
2. **PostgreSQL version**: 17.x (may work with 15+)
3. **Browser support**: Modern browsers (Chrome, Firefox, Edge)
4. **Network**: Assumes reliable connectivity

### Business Assumptions

1. **Utility type**: Investor-owned utility (IOU)
2. **Regulatory environment**: US-based (Texas-like deregulated)
3. **Customer mix**: 80% residential, 15% commercial, 5% industrial

---

## Contributing

### Reporting Issues

1. Check if issue already exists in this document
2. Create GitHub issue with:
   - Clear description
   - Steps to reproduce
   - Expected vs actual behavior
   - Environment details

### Proposing Enhancements

1. Open GitHub Discussion first
2. Reference relevant use case from USE_CASE_MAP.md
3. Include rough implementation approach
4. Consider backwards compatibility

### Pull Request Guidelines

1. Reference issue or discussion
2. Include tests for new features
3. Update documentation
4. Follow existing code style
5. Keep PRs focused and small
