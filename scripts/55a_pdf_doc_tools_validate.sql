-- =============================================================================
-- 55a_pdf_doc_tools_validate.sql
-- Phase 3a: Internal-stage _VALIDATE objects for fast demo gate
--
-- Objects created (all _VALIDATE-suffixed, safe to drop after gate passes):
--   1. INGEST_PDF_STAGE_TO_CHUNKS_VALIDATE  — Snowpark Python SP
--   2. UTILITY_PDF_DOCS_SEARCH_VALIDATE     — Cortex Search Service (APPLICATIONS)
--   3. PARSE_AND_EXTRACT_VALIDATE           — Snowpark Python SP, RETURNS VARIANT
--   4. LIST_PDF_DOCS_VALIDATE               — SQL UDTF (table function)
--
-- Source stage : FLUX_DB.APPLICATIONS.UTILITY_PDF_INTERNAL_STAGE (20 PDFs, 53a)
-- Chunks table : FLUX_DB.PRODUCTION.TECHNICAL_MANUALS_PDF_CHUNKS (reused, SOURCE_SYSTEM='INTERNAL_VALIDATE')
-- Region       : PUBLIC.AWS_US_EAST_1  (AI_COMPLETE + AI_PARSE_DOCUMENT available)
--
-- Deploy:
--   snow sql -f scripts/55a_pdf_doc_tools_validate.sql --connection se_demo
--
-- Ingest (after deploy):
--   snow sql -q "CALL FLUX_DB.APPLICATIONS.INGEST_PDF_STAGE_TO_CHUNKS_VALIDATE(
--       'FLUX_DB.APPLICATIONS.UTILITY_PDF_INTERNAL_STAGE','INTERNAL_VALIDATE',1500,200);" \
--     --connection se_demo
--
-- Cleanup (Phase 3a.11):
--   scripts/55a_validate_cleanup.sql
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE FLUX_DB;
USE WAREHOUSE FLUX_WH;
USE SCHEMA APPLICATIONS;


-- =============================================================================
-- SECTION 1: INGEST_PDF_STAGE_TO_CHUNKS_VALIDATE
--
-- Reads every .pdf from the supplied stage via AI_PARSE_DOCUMENT (LAYOUT mode),
-- splits extracted text into overlapping word-boundary chunks, and appends rows
-- to FLUX_DB.PRODUCTION.TECHNICAL_MANUALS_PDF_CHUNKS tagged SOURCE_SYSTEM=source_tag.
--
-- Implementation guardrails:
--   REV-11 : ALTER STAGE REFRESH before scanning DIRECTORY()
--   REV-09 : Skip files > 50 MB (AI_PARSE_DOCUMENT hard limit)
--   REV-02 : Snowpark DataFrame write for INSERT; bind param for DELETE
--   REV-04 : $$ delimiter per SP; bind param for AI_PARSE_DOCUMENT file path
-- =============================================================================

CREATE OR REPLACE PROCEDURE FLUX_DB.APPLICATIONS.INGEST_PDF_STAGE_TO_CHUNKS_VALIDATE(
    STAGE_NAME    STRING,
    SOURCE_TAG    STRING,
    CHUNK_SIZE    INT DEFAULT 1500,
    CHUNK_OVERLAP INT DEFAULT 200
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
EXECUTE AS CALLER
AS $$
import hashlib
from snowflake.snowpark.types import (
    StructType, StructField, StringType, IntegerType
)

MAX_BYTES = 50 * 1024 * 1024  # 50 MB — AI_PARSE_DOCUMENT hard limit


def run(session, stage_name: str, source_tag: str,
        chunk_size: int = 1500, chunk_overlap: int = 200):
    results = []

    # REV-11: Refresh stage directory before scanning to catch newly uploaded files
    session.sql(f"ALTER STAGE {stage_name} REFRESH").collect()

    # List all PDFs with size (used for 50MB pre-check below)
    files = session.sql(
        f"SELECT RELATIVE_PATH, SIZE "
        f"FROM DIRECTORY(@{stage_name}) "
        f"WHERE RELATIVE_PATH LIKE '%.pdf'"
    ).collect()

    for row in files:
        rel_path  = row["RELATIVE_PATH"]
        file_size = int(row["SIZE"])

        # REV-09: skip files exceeding AI_PARSE_DOCUMENT 50MB limit
        if file_size > MAX_BYTES:
            results.append({
                "file": rel_path,
                "status": "SKIPPED",
                "reason": f"File size {file_size} bytes exceeds 50MB AI_PARSE_DOCUMENT limit",
                "chunks_written": 0,
            })
            continue

        # Derive stable document identity from path
        doc_id    = hashlib.md5(rel_path.encode()).hexdigest()[:16]
        doc_title = rel_path.rsplit("/", 1)[-1].removesuffix(".pdf").replace("_", " ").title()
        doc_type  = "TECHNICAL_MANUAL"

        try:
            # REV-04: bind rel_path (not f-string) to avoid path injection
            # stage_name is an identifier (not user data) so f-string is safe here
            parsed = session.sql(
                f"SELECT TO_VARCHAR("
                f"  AI_PARSE_DOCUMENT(TO_FILE('@{stage_name}', ?), {{'mode': 'LAYOUT'}}):content"
                f") AS content",
                params=[rel_path]
            ).collect()

            content = (parsed[0]["CONTENT"] or "") if parsed else ""
            if not content.strip():
                results.append({
                    "file": rel_path, "status": "ERROR",
                    "reason": "AI_PARSE_DOCUMENT returned empty content",
                    "chunks_written": 0,
                })
                continue

            # Word-boundary chunking with overlap
            words   = content.split()
            chunks  = []
            i       = 0
            step    = max(1, chunk_size - chunk_overlap)  # guard against 0-step infinite loop
            while i < len(words):
                chunks.append(" ".join(words[i: i + chunk_size]))
                i += step

            # REV-02: idempotent DELETE via bind param — no string interpolation of doc_id
            session.sql(
                "DELETE FROM FLUX_DB.PRODUCTION.TECHNICAL_MANUALS_PDF_CHUNKS "
                "WHERE DOCUMENT_ID = ?",
                params=[doc_id]
            ).collect()

            # REV-02: build rows as Python tuples; write via Snowpark DataFrame (no f-string INSERT)
            rows = [
                (
                    f"{doc_id}_{idx:04d}",  # CHUNK_ID
                    doc_id,                 # DOCUMENT_ID
                    doc_type,               # DOCUMENT_TYPE
                    doc_title,              # DOCUMENT_TITLE
                    source_tag,             # SOURCE_SYSTEM
                    "en",                   # LANGUAGE
                    idx,                    # CHUNK_INDEX
                    chunk_text,             # CHUNK_TEXT
                    len(chunk_text.split()) # TOKEN_COUNT
                )
                for idx, chunk_text in enumerate(chunks)
            ]

            if rows:
                schema = StructType([
                    StructField("CHUNK_ID",       StringType(),  nullable=False),
                    StructField("DOCUMENT_ID",    StringType(),  nullable=False),
                    StructField("DOCUMENT_TYPE",  StringType(),  nullable=True),
                    StructField("DOCUMENT_TITLE", StringType(),  nullable=True),
                    StructField("SOURCE_SYSTEM",  StringType(),  nullable=True),
                    StructField("LANGUAGE",       StringType(),  nullable=True),
                    StructField("CHUNK_INDEX",    IntegerType(), nullable=True),
                    StructField("CHUNK_TEXT",     StringType(),  nullable=False),
                    StructField("TOKEN_COUNT",    IntegerType(), nullable=True),
                ])
                df = session.create_dataframe(rows, schema=schema)
                df.write.mode("append").save_as_table(
                    "FLUX_DB.PRODUCTION.TECHNICAL_MANUALS_PDF_CHUNKS",
                    column_order="name"
                )

            results.append({
                "file": rel_path,
                "status": "OK",
                "doc_id": doc_id,
                "chunks_written": len(rows),
            })

        except Exception as exc:
            results.append({
                "file": rel_path,
                "status": "ERROR",
                "reason": str(exc),
                "chunks_written": 0,
            })

    total_chunks = sum(r.get("chunks_written", 0) for r in results)
    return {
        "results":         results,
        "total_chunks":    total_chunks,
        "files_scanned":   len(files),
        "source_tag":      source_tag,
    }
$$;


-- =============================================================================
-- SECTION 2: UTILITY_PDF_DOCS_SEARCH_VALIDATE
--
-- Cortex Search Service over INTERNAL_VALIDATE chunks only.
-- Isolated from prod TECHNICAL_DOCS_SEARCH (13 static rows).
-- TARGET_LAG = '5 minutes' for fast Phase 3a validation turnaround.
-- Located in APPLICATIONS schema (matches verify step SQL).
-- =============================================================================

USE SCHEMA APPLICATIONS;

CREATE OR REPLACE CORTEX SEARCH SERVICE FLUX_DB.APPLICATIONS.UTILITY_PDF_DOCS_SEARCH_VALIDATE
    ON CHUNK_TEXT
    ATTRIBUTES CHUNK_ID, DOCUMENT_ID, DOCUMENT_TITLE, DOCUMENT_TYPE, SOURCE_SYSTEM, LANGUAGE
    WAREHOUSE = FLUX_WH
    TARGET_LAG = '5 minutes'
    COMMENT = 'Phase-3a VALIDATE only — internal-stage PDFs, SOURCE_SYSTEM=INTERNAL_VALIDATE. Drop after gate.'
AS (
    SELECT
        CHUNK_ID,
        DOCUMENT_ID,
        DOCUMENT_TITLE,
        DOCUMENT_TYPE,
        SOURCE_SYSTEM,
        LANGUAGE,
        CHUNK_TEXT
    FROM FLUX_DB.PRODUCTION.TECHNICAL_MANUALS_PDF_CHUNKS
    WHERE SOURCE_SYSTEM = 'INTERNAL_VALIDATE'
      AND CHUNK_TEXT IS NOT NULL
);


-- =============================================================================
-- SECTION 3: PARSE_AND_EXTRACT_VALIDATE
--
-- On-the-fly extraction: AI_PARSE_DOCUMENT(LAYOUT) → AI_COMPLETE(claude-sonnet-4-5).
-- Reads directly from UTILITY_PDF_INTERNAL_STAGE on every call (no pre-ingest cache).
-- RETURNS VARIANT with answer, file, model, extraction_mode, doc_truncated,
-- doc_chars_used, citations [{file, type:'internal_stage', stage}].
--
-- Guards:
--   REV-04 : bind params for both file_path (TO_FILE) and prompt (AI_COMPLETE)
--   REV2-04: reject questions > 1000 chars
--   REV-10 : RETURNS VARIANT with structured answer object
-- =============================================================================

USE SCHEMA APPLICATIONS;

CREATE OR REPLACE PROCEDURE FLUX_DB.APPLICATIONS.PARSE_AND_EXTRACT_VALIDATE(
    FILE_PATH STRING,
    QUESTION  STRING
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'parse_and_extract_validate'
EXECUTE AS CALLER
AS $$

def parse_and_extract_validate(session, file_path: str, question: str) -> dict:
    # REV2-04: reject oversized questions before any Snowflake call
    if len(question) > 1000:
        return {
            "answer": None,
            "error": f"question length {len(question)} exceeds 1000-character limit",
        }

    # 1. Extract document text via AI_PARSE_DOCUMENT (LAYOUT mode)
    #    REV-04: file_path bound as param — stage identifier is a literal
    parsed = session.sql(
        "SELECT TO_VARCHAR("
        "  AI_PARSE_DOCUMENT("
        "    TO_FILE('@FLUX_DB.APPLICATIONS.UTILITY_PDF_INTERNAL_STAGE', ?), "
        "    {'mode': 'LAYOUT'}"
        "  ):content"
        ") AS content",
        params=[file_path]
    ).collect()

    if not parsed or not parsed[0]["CONTENT"]:
        return {
            "answer": None,
            "error": (
                f"Could not extract text from '{file_path}'. "
                "Verify the file exists on UTILITY_PDF_INTERNAL_STAGE."
            ),
        }

    doc_content = parsed[0]["CONTENT"]
    doc_chars   = len(doc_content)
    truncated   = doc_chars > 8000
    doc_excerpt = doc_content[:8000]

    # 2. Build grounded prompt
    prompt = (
        "You are a utility grid operations analyst reviewing internal documents. "
        "Answer the following question based ONLY on the document content provided. "
        "Be specific and cite concrete details, numbers, and named entities from the document.\n\n"
        f"Question: {question}\n\n"
        f"Document content:\n{doc_excerpt}\n\n"
        "Answer:"
    )

    # REV-04: bind prompt to avoid any dollar-quote nesting inside AI_COMPLETE
    answer = session.sql(
        "SELECT AI_COMPLETE('claude-sonnet-4-5', ?) AS answer",
        params=[prompt]
    ).collect()[0]["ANSWER"]

    return {
        "answer":          answer,
        "file":            file_path,
        "model":           "claude-sonnet-4-5",
        "extraction_mode": "layout_direct",
        "doc_truncated":   truncated,
        "doc_chars_used":  min(doc_chars, 8000),
        "citations": [
            {
                "file":  file_path,
                "type":  "internal_stage",
                "stage": "FLUX_DB.APPLICATIONS.UTILITY_PDF_INTERNAL_STAGE",
            }
        ],
    }
$$;


-- =============================================================================
-- SECTION 4: LIST_PDF_DOCS_VALIDATE
--
-- SQL UDTF: returns one row per .pdf in UTILITY_PDF_INTERNAL_STAGE.
-- Usage: SELECT * FROM TABLE(FLUX_DB.APPLICATIONS.LIST_PDF_DOCS_VALIDATE());
-- Pass criteria: returns exactly 20 rows matching the uploaded corpus.
-- =============================================================================

USE SCHEMA APPLICATIONS;

CREATE OR REPLACE FUNCTION FLUX_DB.APPLICATIONS.LIST_PDF_DOCS_VALIDATE()
RETURNS TABLE (RELATIVE_PATH STRING, SIZE_BYTES NUMBER, LAST_MODIFIED TIMESTAMP_TZ)
AS $$
SELECT
    RELATIVE_PATH,
    SIZE                    AS SIZE_BYTES,
    LAST_MODIFIED::TIMESTAMP_TZ(9) AS LAST_MODIFIED
FROM DIRECTORY(@FLUX_DB.APPLICATIONS.UTILITY_PDF_INTERNAL_STAGE)
WHERE RELATIVE_PATH LIKE '%.pdf'
$$;


-- =============================================================================
-- SECTION 5: RBAC — Phase 3a
--
-- Phase 3a uses ACCOUNTADMIN for all objects (owns DB, stage, and warehouse).
-- FLUX_RL_AGENT production grants are deferred to Phase 3b (55_pdf_doc_tools.sql).
-- Verify ownership with SHOW GRANTS.
-- =============================================================================

SHOW GRANTS ON PROCEDURE  FLUX_DB.APPLICATIONS.INGEST_PDF_STAGE_TO_CHUNKS_VALIDATE(STRING, STRING, INT, INT);
SHOW GRANTS ON CORTEX SEARCH SERVICE FLUX_DB.APPLICATIONS.UTILITY_PDF_DOCS_SEARCH_VALIDATE;
SHOW GRANTS ON PROCEDURE  FLUX_DB.APPLICATIONS.PARSE_AND_EXTRACT_VALIDATE(STRING, STRING);
SHOW GRANTS ON FUNCTION   FLUX_DB.APPLICATIONS.LIST_PDF_DOCS_VALIDATE();
