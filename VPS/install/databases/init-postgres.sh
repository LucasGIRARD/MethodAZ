#!/bin/sh
set -eu

POSTGRES_PASSWORD=$(cat /run/secrets/postgres_admin_password)
LINKWARDEN_DB_PASSWORD=$(cat /run/secrets/linkwarden_db_password)
DAVIS_DB_PASSWORD=$(cat /run/secrets/davis_db_password)
FRESHRSS_DB_PASSWORD=$(cat /run/secrets/freshrss_db_password)
TTRSS_DB_PASSWORD=$(cat /run/secrets/ttrss_db_password)
WEB_DB_PASSWORD=$(cat /run/secrets/web_db_password)

psql --set=ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" \
  --dbname postgres \
  --set=postgres_admin_password="$POSTGRES_PASSWORD" \
  --set=linkwarden_password="$LINKWARDEN_DB_PASSWORD" \
  --set=davis_password="$DAVIS_DB_PASSWORD" \
  --set=freshrss_password="$FRESHRSS_DB_PASSWORD" \
  --set=ttrss_password="$TTRSS_DB_PASSWORD" \
  --set=web_password="$WEB_DB_PASSWORD" <<'EOSQL'
ALTER ROLE postgres LOGIN PASSWORD :'postgres_admin_password';

SELECT 'CREATE ROLE linkwarden LOGIN'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'linkwarden') \gexec
ALTER ROLE linkwarden LOGIN PASSWORD :'linkwarden_password';
SELECT 'CREATE DATABASE linkwarden OWNER linkwarden'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'linkwarden') \gexec
ALTER DATABASE linkwarden OWNER TO linkwarden;

SELECT 'CREATE ROLE davis LOGIN'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'davis') \gexec
ALTER ROLE davis LOGIN PASSWORD :'davis_password';
SELECT 'CREATE DATABASE davis OWNER davis'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'davis') \gexec
ALTER DATABASE davis OWNER TO davis;

SELECT 'CREATE ROLE freshrss LOGIN'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'freshrss') \gexec
ALTER ROLE freshrss LOGIN PASSWORD :'freshrss_password';
SELECT 'CREATE DATABASE freshrss OWNER freshrss'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'freshrss') \gexec
ALTER DATABASE freshrss OWNER TO freshrss;

SELECT 'CREATE ROLE ttrss LOGIN'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'ttrss') \gexec
ALTER ROLE ttrss LOGIN PASSWORD :'ttrss_password';
SELECT 'CREATE DATABASE ttrss OWNER ttrss'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'ttrss') \gexec
ALTER DATABASE ttrss OWNER TO ttrss;

SELECT 'CREATE ROLE web LOGIN'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'web') \gexec
ALTER ROLE web LOGIN PASSWORD :'web_password';
SELECT 'CREATE DATABASE web OWNER web'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'web') \gexec
ALTER DATABASE web OWNER TO web;
EOSQL
