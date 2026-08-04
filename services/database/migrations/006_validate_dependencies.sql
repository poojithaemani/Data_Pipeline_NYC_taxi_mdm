-- =================================================================
-- 006_validate_dependencies.sql
-- Dependency validation queries to run BEFORE switching primary keys.
-- Check for foreign keys, views, triggers, functions, and indexes that depend on vendor_id or golden_id.
-- Intentionally read-only — safe to run anytime.
-- =================================================================

-- 1) Foreign keys referencing vendors.vendor_id
SELECT
  tc.constraint_name,
  tc.table_schema,
  tc.table_name,
  kcu.column_name,
  ccu.table_schema AS foreign_table_schema,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND ccu.table_name = 'vendors'
  AND ccu.column_name = 'vendor_id';

-- 2) Foreign keys referencing golden_zones.golden_id
SELECT
  tc.constraint_name,
  tc.table_schema,
  tc.table_name,
  kcu.column_name,
  ccu.table_schema AS foreign_table_schema,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND ccu.table_name = 'golden_zones'
  AND ccu.column_name = 'golden_id';

-- 3) Views referencing vendors or vendor_id
SELECT table_schema, table_name, view_definition
FROM information_schema.views
WHERE view_definition ILIKE '%vendors%' OR view_definition ILIKE '%vendor_id%';

-- 4) Views referencing golden_zones or golden_id
SELECT table_schema, table_name, view_definition
FROM information_schema.views
WHERE view_definition ILIKE '%golden_zones%' OR view_definition ILIKE '%golden_id%';

-- 5) Triggers that reference vendors or golden_zones (search function/trigger source)
SELECT tg.tgname AS trigger_name, tbl.relname AS table_name, pg_get_triggerdef(tg.oid) AS trigger_def
FROM pg_trigger tg
JOIN pg_class tbl ON tg.tgrelid = tbl.oid
WHERE pg_get_triggerdef(tg.oid) ILIKE '%vendors%' OR pg_get_triggerdef(tg.oid) ILIKE '%golden_zones%';

-- 6) Functions referencing vendors or golden_zones (search source code)
SELECT n.nspname AS schema, p.proname AS function_name, pg_get_functiondef(p.oid) AS definition
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE pg_get_functiondef(p.oid) ILIKE '%vendors%' OR pg_get_functiondef(p.oid) ILIKE '%golden_zones%';

-- 7) Indexes on vendor_id or golden_id
SELECT indexname, indexdef FROM pg_indexes WHERE indexdef ILIKE '%vendor_id%' OR indexdef ILIKE '%golden_id%';

-- 8) Check references in other DB objects (casts a wider net, may show false positives)
SELECT distinct objid::regprocedure::text AS object, objid, refobjid, deptype
FROM pg_depend d
JOIN pg_rewrite r ON d.objid = r.oid
LIMIT 10;

-- Recommendation: If any rows are returned above, capture and coordinate owners before switching PKs.

-- End of 006_validate_dependencies.sql
