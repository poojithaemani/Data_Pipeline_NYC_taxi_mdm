Database SCD Type 2

## Purpose

This README documents the Phase SCD Type 2 schema changes for the master database. It explains why surrogate keys are introduced, why existing business keys are preserved, the migration sequence, safe execution steps, and how this prepares the project for stored procedures, Glue SCD jobs, and Step Functions.

## Why surrogate row keys are introduced

- Surrogate row keys (vendor_row_id, golden_zone_row_id) provide a stable, single-column primary key for each row version.
- They allow multiple historical versions per business entity (SCD Type 2) without changing or losing the existing business identifier values.
- They simplify foreign-key relationships (single-column PK) and make row-level auditing simpler.

## Why business keys are preserved

- Business keys (vendor_id, location_id) are used across the AWS pipeline (Bronze → Silver → Gold → Athena → RDS) and by downstream consumers.
- Preserving them avoids breaking ETL joins and analytical processes and keeps historical grouping straightforward: versions are grouped by the business key.

## Migration sequence (ordered)

1. `001_add_surrogate_keys.sql` - Add surrogate key columns (`_row_id`).
2. `002_add_scd_columns.sql` - Add SCD columns (`version`, `is_current`, etc.).
3. `002a_add_hash_column.sql` - Add `record_hash` for ETL change detection.
4. `003_initialize_records.sql` - Backfill initial values for new columns.
5. `004_add_constraints.sql` - Add `CHECK` and `NOT NULL` constraints.
6. `005a_zone_matches_mapping.sql` - Map `zone_matches` to the new surrogate key.
7. `create_indexes_concurrent.ps1` - Run this script to create all necessary indexes safely.
8. `006_validate_dependencies.sql` - Run pre-flight checks for dependencies.
9. `007_prepare_pk_switch.sql` - Drop the legacy foreign key to remove the dependency lock.
10. `008_switch_primary_keys.sql` - Switch the primary keys to the surrogate `_row_id` columns.
11. `009_finalize_scd_schema.sql` - Recreate the foreign key to point to the new surrogate primary key.

## Safe execution notes

- Back up the database (RDS snapshot) before any migration.
- Apply migrations in a staging environment first and run validation queries.
- Index creation with "CONCURRENTLY" must be executed outside transactions. Use the helper script services/database/migrations/create_indexes_concurrent.ps1 to create indexes safely.
- Run 006_validate_dependencies.sql and remediate any returned dependencies before executing 007_switch_primary_keys.sql. Require sign-off.
- Schedule 008_switch_primary_keys.sql in a maintenance window — primary key changes require exclusive locks and may block writes.

## Rollback guidance

- Preferred rollback: restore the RDS snapshot taken before migration.
- Manual reversal is risky for PK switches and index/constraint drops; only attempt manual reversal with DB experts and thorough testing.
- Keep snapshot IDs and migration timestamps in the deployment log to facilitate automated restores if needed.

## How this prepares the project for next phases

- Stored Procedures (Phase 3B): The SCD columns and surrogate keys enable concise, single-transaction stored procedures to perform SCD upserts (close previous version, insert new version, set version numbers).
- Glue PySpark SCD Job (Phase 3C): Glue can detect changes using business keys (vendor_id/location_id) and call stored procedures or perform idempotent upserts into the master DB. Surrogate PKs keep inserts simple.
- Step Functions (Phase 5): Orchestrations can rely on clear semantics (is_current/effective_date/end_date) and partial unique indexes to coordinate state transitions safely.

## Contact / Runbook

- Migration scripts are in services/database/migrations/.
- Use create_indexes_concurrent.ps1 to create indexes in production safely.
- Run validation queries in 006_validate_dependencies.sql and the SELECTs included in 003_initialize_records.sql.

## Concise rationale

Surrogate keys + preserved business keys provide the minimal, maintainable path to SCD Type 2 that integrates cleanly with existing AWS Glue and Athena pipelines, minimizes consumer impact, and supports robust, atomic SCD upserts using stored procedures.
