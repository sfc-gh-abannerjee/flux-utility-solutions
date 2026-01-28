-- ============================================================================
-- Flux Utility Solutions: Cascade Analysis Procedures
-- ============================================================================
-- Script: 21_cascade_procedures.sql
-- Purpose: Stored procedures for cascade failure analysis and response
--
-- Features:
-- - Cascade failure detection
-- - Impact assessment
-- - Automatic load shedding recommendations
-- - Network topology traversal
-- ============================================================================

USE DATABASE <% database %>;
USE SCHEMA <% schema %>;
USE WAREHOUSE <% warehouse %>;

-- ============================================================================
-- Cascade Analysis Procedures
-- ============================================================================

-- Analyze potential cascade impact from a substation outage
CREATE OR REPLACE PROCEDURE ANALYZE_CASCADE_IMPACT(
    p_substation_id VARCHAR,
    p_include_secondary BOOLEAN DEFAULT TRUE
)
RETURNS TABLE (
    impact_level VARCHAR,
    affected_substations ARRAY,
    affected_transformers NUMBER,
    affected_customers NUMBER,
    affected_load_mw FLOAT,
    recommended_actions ARRAY
)
LANGUAGE SQL
AS
$$
DECLARE
    v_affected_subs ARRAY;
    v_transformer_count NUMBER;
    v_customer_count NUMBER;
    v_load_mw FLOAT;
BEGIN
    -- Get directly connected substations
    SELECT ARRAY_AGG(DISTINCT connected_substation_id)
    INTO v_affected_subs
    FROM SUBSTATION_CONNECTIONS
    WHERE source_substation_id = p_substation_id;
    
    -- Count affected transformers
    SELECT COUNT(*)
    INTO v_transformer_count
    FROM TRANSFORMER_METADATA
    WHERE substation_id = p_substation_id
       OR (p_include_secondary AND substation_id IN (SELECT VALUE FROM TABLE(FLATTEN(v_affected_subs))));
    
    -- Count affected customers
    SELECT COUNT(DISTINCT c.customer_id)
    INTO v_customer_count
    FROM CUSTOMERS_MASTER_DATA c
    JOIN METER_INFRASTRUCTURE m ON c.customer_id = m.customer_id
    JOIN TRANSFORMER_METADATA t ON m.transformer_id = t.transformer_id
    WHERE t.substation_id = p_substation_id
       OR (p_include_secondary AND t.substation_id IN (SELECT VALUE FROM TABLE(FLATTEN(v_affected_subs))));
    
    -- Calculate affected load
    SELECT SUM(capacity_mva)
    INTO v_load_mw
    FROM SUBSTATIONS
    WHERE substation_id = p_substation_id
       OR substation_id IN (SELECT VALUE FROM TABLE(FLATTEN(v_affected_subs)));
    
    -- Return analysis
    RETURN TABLE(
        SELECT 
            CASE 
                WHEN v_customer_count > 100000 THEN 'CRITICAL'
                WHEN v_customer_count > 10000 THEN 'SEVERE'
                WHEN v_customer_count > 1000 THEN 'MODERATE'
                ELSE 'LOW'
            END as impact_level,
            v_affected_subs as affected_substations,
            v_transformer_count as affected_transformers,
            v_customer_count as affected_customers,
            v_load_mw as affected_load_mw,
            ARRAY_CONSTRUCT(
                'Activate emergency response team',
                'Notify affected customers',
                'Prepare load transfer to adjacent substations',
                'Deploy mobile generation if available'
            ) as recommended_actions
    );
END;
$$;

-- Calculate optimal load shedding sequence
CREATE OR REPLACE PROCEDURE CALCULATE_LOAD_SHED_SEQUENCE(
    p_overload_mw FLOAT,
    p_substation_id VARCHAR
)
RETURNS TABLE (
    shed_order NUMBER,
    feeder_id VARCHAR,
    load_mw FLOAT,
    customer_count NUMBER,
    priority VARCHAR,
    cumulative_shed_mw FLOAT
)
LANGUAGE SQL
AS
$$
BEGIN
    RETURN TABLE(
        WITH feeder_loads AS (
            SELECT 
                f.feeder_id,
                f.substation_id,
                f.priority_class,
                COUNT(DISTINCT c.customer_id) as customer_count,
                SUM(a.kwh_reading) / 4000.0 as load_mw  -- Convert kWh to MW estimate
            FROM FEEDERS f
            JOIN TRANSFORMER_METADATA t ON f.feeder_id = t.feeder_id
            JOIN METER_INFRASTRUCTURE m ON t.transformer_id = m.transformer_id
            JOIN CUSTOMERS_MASTER_DATA c ON m.customer_id = c.customer_id
            LEFT JOIN AMI_INTERVAL_READINGS a ON m.meter_id = a.meter_id
                AND a.reading_timestamp >= DATEADD(hour, -1, CURRENT_TIMESTAMP())
            WHERE f.substation_id = p_substation_id
            GROUP BY f.feeder_id, f.substation_id, f.priority_class
        ),
        ranked_feeders AS (
            SELECT 
                feeder_id,
                load_mw,
                customer_count,
                priority_class,
                -- Shed low priority feeders first
                ROW_NUMBER() OVER (
                    ORDER BY 
                        CASE priority_class 
                            WHEN 'CRITICAL' THEN 4
                            WHEN 'HIGH' THEN 3
                            WHEN 'MEDIUM' THEN 2
                            ELSE 1
                        END,
                        load_mw DESC  -- Shed larger loads first within priority
                ) as shed_order,
                SUM(load_mw) OVER (
                    ORDER BY 
                        CASE priority_class 
                            WHEN 'CRITICAL' THEN 4
                            WHEN 'HIGH' THEN 3
                            WHEN 'MEDIUM' THEN 2
                            ELSE 1
                        END,
                        load_mw DESC
                    ROWS UNBOUNDED PRECEDING
                ) as cumulative_shed_mw
            FROM feeder_loads
        )
        SELECT 
            shed_order,
            feeder_id,
            load_mw,
            customer_count,
            priority_class as priority,
            cumulative_shed_mw
        FROM ranked_feeders
        WHERE cumulative_shed_mw <= p_overload_mw * 1.1  -- Include 10% buffer
        ORDER BY shed_order
    );
END;
$$;

-- Get transformer failure propagation risk
CREATE OR REPLACE PROCEDURE GET_FAILURE_PROPAGATION_RISK(
    p_transformer_id VARCHAR
)
RETURNS TABLE (
    transformer_id VARCHAR,
    health_score FLOAT,
    connected_transformers ARRAY,
    downstream_customers NUMBER,
    propagation_risk VARCHAR,
    recommended_maintenance_date DATE
)
LANGUAGE SQL
AS
$$
BEGIN
    RETURN TABLE(
        WITH transformer_info AS (
            SELECT 
                t.transformer_id,
                t.health_score,
                t.substation_id,
                t.kva_rating
            FROM TRANSFORMER_METADATA t
            WHERE t.transformer_id = p_transformer_id
        ),
        connected AS (
            SELECT ARRAY_AGG(t2.transformer_id) as connected_ids
            FROM TRANSFORMER_METADATA t2
            JOIN transformer_info ti ON t2.substation_id = ti.substation_id
            WHERE t2.transformer_id != p_transformer_id
        ),
        customer_count AS (
            SELECT COUNT(DISTINCT c.customer_id) as cnt
            FROM CUSTOMERS_MASTER_DATA c
            JOIN METER_INFRASTRUCTURE m ON c.customer_id = m.customer_id
            WHERE m.transformer_id = p_transformer_id
        )
        SELECT 
            ti.transformer_id,
            ti.health_score,
            c.connected_ids as connected_transformers,
            cc.cnt as downstream_customers,
            CASE 
                WHEN ti.health_score < 50 AND cc.cnt > 100 THEN 'CRITICAL'
                WHEN ti.health_score < 70 AND cc.cnt > 50 THEN 'HIGH'
                WHEN ti.health_score < 85 THEN 'MEDIUM'
                ELSE 'LOW'
            END as propagation_risk,
            CASE 
                WHEN ti.health_score < 50 THEN CURRENT_DATE()
                WHEN ti.health_score < 70 THEN DATEADD(day, 7, CURRENT_DATE())
                WHEN ti.health_score < 85 THEN DATEADD(day, 30, CURRENT_DATE())
                ELSE DATEADD(day, 90, CURRENT_DATE())
            END as recommended_maintenance_date
        FROM transformer_info ti
        CROSS JOIN connected c
        CROSS JOIN customer_count cc
    );
END;
$$;

-- ============================================================================
-- Real-time Cascade Monitoring Task
-- ============================================================================

CREATE OR REPLACE TASK MONITOR_CASCADE_RISK
  WAREHOUSE = <% warehouse %>
  SCHEDULE = '5 MINUTE'
AS
INSERT INTO CASCADE_RISK_LOG (
    check_timestamp,
    at_risk_substations,
    total_transformers_degraded,
    total_customers_at_risk,
    alert_level
)
SELECT 
    CURRENT_TIMESTAMP(),
    ARRAY_AGG(DISTINCT s.substation_id),
    COUNT(DISTINCT t.transformer_id),
    SUM(customer_count),
    CASE 
        WHEN COUNT(*) > 10 THEN 'CRITICAL'
        WHEN COUNT(*) > 5 THEN 'HIGH'
        WHEN COUNT(*) > 2 THEN 'MEDIUM'
        ELSE 'LOW'
    END
FROM SUBSTATIONS s
JOIN TRANSFORMER_METADATA t ON s.substation_id = t.substation_id
JOIN (
    SELECT transformer_id, COUNT(*) as customer_count
    FROM METER_INFRASTRUCTURE
    GROUP BY transformer_id
) m ON t.transformer_id = m.transformer_id
WHERE t.health_score < 70
  AND t.status = 'ACTIVE';

-- ============================================================================
-- Grant Execute Permissions
-- ============================================================================

GRANT USAGE ON PROCEDURE ANALYZE_CASCADE_IMPACT(VARCHAR, BOOLEAN) TO ROLE <% user_role %>;
GRANT USAGE ON PROCEDURE CALCULATE_LOAD_SHED_SEQUENCE(FLOAT, VARCHAR) TO ROLE <% user_role %>;
GRANT USAGE ON PROCEDURE GET_FAILURE_PROPAGATION_RISK(VARCHAR) TO ROLE <% user_role %>;

SELECT 'Cascade procedures created successfully' AS status;
