#!/bin/sh
set -eu

MARIADB_ROOT_PASSWORD=$(cat /run/secrets/mariadb_admin_password)
DAVIS_DB_PASSWORD=$(cat /run/secrets/davis_db_password)
FRESHRSS_DB_PASSWORD=$(cat /run/secrets/freshrss_db_password)
WEB_DB_PASSWORD=$(cat /run/secrets/web_db_password)

mariadb --protocol=socket \
  --user=root \
  --password="$MARIADB_ROOT_PASSWORD" <<EOSQL
CREATE DATABASE IF NOT EXISTS davis CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'davis'@'%' IDENTIFIED BY '${DAVIS_DB_PASSWORD}';
ALTER USER 'davis'@'%' IDENTIFIED BY '${DAVIS_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON davis.* TO 'davis'@'%';

CREATE DATABASE IF NOT EXISTS freshrss CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'freshrss'@'%' IDENTIFIED BY '${FRESHRSS_DB_PASSWORD}';
ALTER USER 'freshrss'@'%' IDENTIFIED BY '${FRESHRSS_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON freshrss.* TO 'freshrss'@'%';

CREATE DATABASE IF NOT EXISTS web CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'web'@'%' IDENTIFIED BY '${WEB_DB_PASSWORD}';
ALTER USER 'web'@'%' IDENTIFIED BY '${WEB_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON web.* TO 'web'@'%';

FLUSH PRIVILEGES;
EOSQL
