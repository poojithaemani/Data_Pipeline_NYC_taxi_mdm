Phase 3A Migration Runbook

Pre-requisites

- Take an RDS snapshot and record the snapshot identifier.
- Notify stakeholders and schedule a maintenance window for PK switch (007).
- Ensure psql client is available on the machine where you will run index creation (create_indexes_concurrent.ps1 requires psql).

Staging run

1. Apply 001_add_surrogate_keys.sql
2. Apply 002_add_scd_columns.sql
3. Apply 002a_add_hash_column.sql
4. Apply 003_initialize_records.sql
   - Inspect SELECT output for golden_zones_location_id_null and resolve ambiguous mappings.
5. Apply 004_add_constraints.sql
6. Run 005a_zone_matches_mapping.sql
   - If unmapped rows remain, export them for manual resolution and do not proceed.
7. Run create_indexes_concurrent.ps1 to create indexes CONCURRENTLY (see below). Use DryRun first:
   - Dry run: ./create_indexes_concurrent.ps1 -Host <host> -Database <db> -User <user> -DryRun:$true
   - Real run: $env:PGPASSWORD='<pwd>'; ./create_indexes_concurrent.ps1 -Host <host> -Database <db> -User <user>
8. Run 006_validate_dependencies.sql and address any results. Require sign-off by DB owner.
9. Run 007_prepare_pk_switch.sql to drop the legacy foreign key.
10. Run 008_switch_primary_keys.sql in a maintenance window to switch to surrogate PKs.
11. Run 009_finalize_scd_schema.sql to recreate the foreign key.

Production run notes

- Execute 1–5 during normal window.
- Create indexes using create_indexes_concurrent.ps1 during low-traffic time; ensure no long-running transactions.
- Run dependency validation and obtain sign-off via ticketing system.
- Execute PK switch (008) during maintenance window; expect brief exclusive locks.

Rollback plan

- If anything goes wrong before PK switch: restore from snapshot.
- If issue occurs after PK switch but before dropping legacy constraints: restore from snapshot; manual rollback is high risk.
- Always prefer snapshot restore for rollback — document the snapshot id and migration step that triggered restore.

Index creation (example commands)

- psql -h <host> -U <user> -d <db> -c "CREATE UNIQUE INDEX CONCURRENTLY idx_vendors_vendorid_current ON vendors (vendor_id) WHERE is_current;"
- psql -h <host> -U <user> -d <db> -c "CREATE INDEX CONCURRENTLY idx_vendors_vendorid_effective_date ON vendors (vendor_id, effective_date);"
- psql -h <host> -U <user> -d <db> -c "CREATE UNIQUE INDEX CONCURRENTLY idx_golden_locationid_current ON golden_zones (location_id) WHERE is_current AND location_id IS NOT NULL;"
- psql -h <host> -U <user> -d <db> -c "CREATE INDEX CONCURRENTLY idx_golden_borough_zone_effective ON golden_zones (borough, zone, effective_date);"
- psql -h <host> -U <user> -d <db> -c "CREATE INDEX CONCURRENTLY idx_golden_effective_date ON golden_zones (effective_date);"

Validation queries (after full run)

- Confirm columns exist: information_schema.columns queries
- Check initialization counts: SELECT counts in README + 003
- Verify partial unique indexes exist: SELECT to_regclass('public.idx_name')
- Run example point-in-time queries

Contact

- DB owner: (add your contact)
- ETL owner: (add your contact)

End of RUNBOOK
