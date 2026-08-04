Database SCD Type 2 — Phase 3A

Purpose
-------
This README documents the Phase 3A SCD Type 2 schema changes for the master database. It explains why surrogate keys are introduced, why existing business keys are preserved, the migration sequence, safe execution steps, and how this prepares the project for stored procedures, Glue SCD jobs, and Step Functions.

Why surrogate row keys are introduced
------------------------------------
- Surrogate row keys (vendor_row_id, golden_zone_row_id) provide a stable, single-column primary key for each row version.
- They allow multiple historical versions per business entity (SCD Type 2) without changing or losing the existing business identifier values.
- They simplify foreign-key relationships (single-column PK) and make row-level auditing simpler.

Why business keys are preserved
-------------------------------
- Business keys (vendor_id, location_id) are used across the AWS pipeline (Bronze → Silver → Gold → Athena → RDS) and by downstream consumers.
- Preserving them avoids breaking ETL joins and analytical processes and keeps historical grouping straightforward: versions are grouped by the business key.

Migration sequence (ordered)
-----------------------------
1. 001_add_surrogate_keys.sql    — Add vendor_row_id and golden_zone_row_id; populate sequences
2. 002_add_scd_columns.sql       — Add version, is_current, effective_date, end_date
3. 003_initialize_records.sql    — Backfill surrogate ids, populate golden_zones.location_id (best-effort), initialize SCD fields
4. 004_add_constraints.sql      — Add CHECKs and promote NOT NULLs (only when safe)
5. 005_add_indexes.sql          — Index creation plan (use helper script to run CONCURRENTLY)
5a. 005a_zone_matches_mapping.sql — Add golden_zone_row_id to zone_matches; populate mapping and add FK when complete
6. 006_validate_dependencies.sql — Run dependency checks (FKs, Views, Triggers, Functions, Indexes)
7. 007_switch_primary_keys.sql  — Switch PKs to surrogate row ids (after validation and maintenance window)
8. 008_drop_legacy_constraints.sql — Drop global UNIQUE constraints after validation and partial-index enforcement

Safe execution notes
--------------------
- Back up the database (RDS snapshot) before any migration.
- Apply migrations in a staging environment first and run validation queries.
- Index creation with "CONCURRENTLY" must be executed outside transactions. Use the helper script services/database/migrations/create_indexes_concurrent.ps1 to create indexes safely.
- Run 006_validate_dependencies.sql and remediate any returned dependencies before executing 007_switch_primary_keys.sql. Require sign-off.
- Do not run 008_drop_legacy_constraints.sql until partial unique indexes are created and validated.
- Schedule 007_switch_primary_keys.sql in a maintenance window — primary key changes require exclusive locks and may block writes.

Rollback guidance
-----------------
- Preferred rollback: restore the RDS snapshot taken before migration.
- Manual reversal is risky for PK switches and index/constraint drops; only attempt manual reversal with DB experts and thorough testing.
- Keep snapshot IDs and migration timestamps in the deployment log to facilitate automated restores if needed.

How this prepares the project for next phases
--------------------------------------------
- Stored Procedures (Phase 3B): The SCD columns and surrogate keys enable concise, single-transaction stored procedures to perform SCD upserts (close previous version, insert new version, set version numbers).
- Glue PySpark SCD Job (Phase 3C): Glue can detect changes using business keys (vendor_id/location_id) and call stored procedures or perform idempotent upserts into the master DB. Surrogate PKs keep inserts simple.
- Step Functions (Phase 5): Orchestrations can rely on clear semantics (is_current/effective_date/end_date) and partial unique indexes to coordinate state transitions safely.

Contact / Runbook
-----------------
- Migration scripts are in services/database/migrations/.
- Use create_indexes_concurrent.ps1 to create indexes in production safely.
- Run validation queries in 006_validate_dependencies.sql and the SELECTs included in 003_initialize_records.sql.

Concise rationale
-----------------
Surrogate keys + preserved business keys provide the minimal, maintainable path to SCD Type 2 that integrates cleanly with existing AWS Glue and Athena pipelines, minimizes consumer impact, and supports robust, atomic SCD upserts using stored procedures.
