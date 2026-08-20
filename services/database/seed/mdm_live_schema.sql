-- Live schema of the MDM tables, reconstructed from information_schema
-- at decommissioning. Columns, types, defaults and primary keys only -
-- constraints, triggers and procedures remain in migrations/001-011.

CREATE TABLE IF NOT EXISTS golden_zones (
  golden_id integer DEFAULT nextval('golden_zones_golden_id_seq'::regclass) NOT NULL,
  borough character varying NOT NULL,
  zone character varying NOT NULL,
  service_zone character varying,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  golden_zone_row_id bigint DEFAULT nextval('golden_zones_golden_zone_row_id_seq'::regclass) NOT NULL,
  version integer DEFAULT 1 NOT NULL,
  is_current boolean DEFAULT true NOT NULL,
  effective_date timestamp with time zone NOT NULL,
  end_date timestamp with time zone,
  location_id integer,
  record_hash text,
  PRIMARY KEY (golden_zone_row_id)
);

CREATE TABLE IF NOT EXISTS zone_matches (
  match_id integer DEFAULT nextval('zone_matches_match_id_seq'::regclass) NOT NULL,
  golden_zone_id integer NOT NULL,
  source_zone_id integer NOT NULL,
  confidence_score numeric NOT NULL,
  status character varying NOT NULL,
  operation character varying NOT NULL,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  golden_zone_row_id bigint,
  PRIMARY KEY (match_id)
);

CREATE TABLE IF NOT EXISTS taxi_zones (
  location_id integer NOT NULL,
  borough character varying NOT NULL,
  zone character varying NOT NULL,
  service_zone character varying,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (location_id)
);

CREATE TABLE IF NOT EXISTS pipeline_runs (
  run_id character varying NOT NULL,
  job_name character varying NOT NULL,
  status character varying NOT NULL,
  records_processed bigint,
  started_at timestamp with time zone NOT NULL,
  completed_at timestamp with time zone NOT NULL,
  PRIMARY KEY (run_id)
);

CREATE TABLE IF NOT EXISTS audit_log (
  audit_id integer DEFAULT nextval('audit_log_audit_id_seq'::regclass) NOT NULL,
  table_name character varying NOT NULL,
  record_id character varying,
  operation character varying NOT NULL,
  changed_by character varying NOT NULL,
  changed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  old_values jsonb,
  new_values jsonb,
  PRIMARY KEY (audit_id)
);
