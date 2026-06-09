#!/bin/sh
set -eu

POSTGRES_PASSWORD=$(cat /run/secrets/postgres_admin_password)
LINKWARDEN_DB_PASSWORD=$(cat /run/secrets/linkwarden_db_password)
TTRSS_DB_PASSWORD=$(cat /run/secrets/ttrss_db_password)

psql --set=ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" \
  --dbname postgres \
  --set=postgres_admin_password="$POSTGRES_PASSWORD" \
  --set=linkwarden_password="$LINKWARDEN_DB_PASSWORD" \
  --set=ttrss_password="$TTRSS_DB_PASSWORD" <<'EOSQL'
ALTER ROLE postgres LOGIN PASSWORD :'postgres_admin_password';

SELECT 'CREATE ROLE linkwarden LOGIN'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'linkwarden') \gexec
ALTER ROLE linkwarden LOGIN PASSWORD :'linkwarden_password';
SELECT 'CREATE DATABASE linkwarden OWNER linkwarden'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'linkwarden') \gexec
ALTER DATABASE linkwarden OWNER TO linkwarden;

SELECT 'CREATE ROLE ttrss LOGIN'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'ttrss') \gexec
ALTER ROLE ttrss LOGIN PASSWORD :'ttrss_password';
SELECT 'CREATE DATABASE ttrss OWNER ttrss'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'ttrss') \gexec
ALTER DATABASE ttrss OWNER TO ttrss;
EOSQL
