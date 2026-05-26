-- =============================================================================
-- 53_utility_pdf_stage.sql
-- Phase 3b: Production external S3 stage for utility PDF AI corpus
--
-- Creates FLUX_DB.APPLICATIONS.UTILITY_PDF_STAGE pointing at
-- s3://<your-pdf-bucket>/raw/pdfs/ via storage integration <YOUR_S3_INTEGRATION>.
--
-- REV-08: DESCRIBE integration before CREATE — confirms allowed locations
--         and aborts if integration is missing or misconfigured.
--
-- Deploy:
--   snow sql -f scripts/53_utility_pdf_stage.sql --connection se_demo
--
-- After deploy, verify with:
--   snow sql -q "SELECT RELATIVE_PATH, SIZE FROM DIRECTORY(@FLUX_DB.APPLICATIONS.UTILITY_PDF_STAGE);" --connection se_demo
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE FLUX_DB;
USE WAREHOUSE FLUX_WH;
USE SCHEMA APPLICATIONS;

-- =============================================================================
-- REV-08 pre-check: DESCRIBE integration to confirm it exists and covers raw/pdfs/
-- STORAGE_ALLOWED_LOCATIONS must include s3://<your-pdf-bucket>/ (covers all sub-paths).
-- If this errors, do NOT proceed — the stage create will fail at read/write time.
-- =============================================================================

DESCRIBE INTEGRATION <YOUR_S3_INTEGRATION>;

-- =============================================================================
-- Production external stage
-- No ENCRYPTION clause — external stages with storage integrations use the bucket's
-- default server-side encryption. AWS_SSE_S3/SNOWFLAKE_SSE are invalid here.
-- DIRECTORY enabled so DIRECTORY() table function reflects uploaded files.
-- =============================================================================

CREATE STAGE IF NOT EXISTS FLUX_DB.APPLICATIONS.UTILITY_PDF_STAGE
    STORAGE_INTEGRATION = <YOUR_S3_INTEGRATION>
    URL                 = 's3://<your-pdf-bucket>/raw/pdfs/'
    DIRECTORY           = (ENABLE = TRUE)
    COMMENT             = 'Production external S3 stage for utility PDF AI corpus (Phase 3b). Managed by 53_utility_pdf_stage.sql.';
-- Note: ENCRYPTION clause not specified — S3 bucket applies default SSE-S3 server-side encryption.
-- AWS_SSE_S3 / SNOWFLAKE_SSE are invalid for external stages backed by a storage integration.

-- Refresh directory listing (catches any files already present in the bucket)
ALTER STAGE FLUX_DB.APPLICATIONS.UTILITY_PDF_STAGE REFRESH;

-- Verify stage exists
SHOW STAGES IN SCHEMA FLUX_DB.APPLICATIONS;

-- List files currently in stage (expect empty before upload; populated after 53c_upload_seed_pdfs.sh)
SELECT RELATIVE_PATH, SIZE, LAST_MODIFIED
FROM   DIRECTORY(@FLUX_DB.APPLICATIONS.UTILITY_PDF_STAGE)
ORDER  BY RELATIVE_PATH;

SELECT COUNT(*) AS pdf_count
FROM   DIRECTORY(@FLUX_DB.APPLICATIONS.UTILITY_PDF_STAGE);
