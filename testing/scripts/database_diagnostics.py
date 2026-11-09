#!/usr/bin/env python3
"""Read-only aggregate connection/lock diagnostics, without account data or SQL text."""
import schema_audit

schema_audit.QUERY = """
BEGIN READ ONLY;
SELECT application_name, state, wait_event_type, wait_event, count(*) AS connections,
       max(EXTRACT(epoch FROM now()-xact_start))::integer AS max_transaction_seconds,
       max(EXTRACT(epoch FROM now()-query_start))::integer AS max_query_seconds
FROM pg_stat_activity WHERE datname=current_database()
GROUP BY application_name,state,wait_event_type,wait_event ORDER BY connections DESC;
SELECT count(*) AS blocked_connections FROM pg_stat_activity
WHERE datname=current_database() AND cardinality(pg_blocking_pids(pid)) > 0;
SELECT c.relname AS table_name, t.tgname AS trigger_name
FROM pg_trigger t JOIN pg_class c ON t.tgrelid=c.oid
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND NOT t.tgisinternal;
ROLLBACK;
"""
if __name__ == '__main__':
    raise SystemExit(schema_audit.main())
