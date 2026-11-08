#!/bin/bash
set -e
for f in /migrations/*.sql; do
  psql -U postgres -d atuel -v ON_ERROR_STOP=1 -q -f "$f"
done
psql -U postgres -d atuel -c "ALTER ROLE app_rw PASSWORD '${APP_RW_PASSWORD}'"