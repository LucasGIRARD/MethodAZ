#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
INSTALL_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
OUTPUT=${1:-"$INSTALL_DIR/config/secrets.env"}

if [ -e "$OUTPUT" ]; then
  echo "Refus d'écraser le fichier existant : $OUTPUT" >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "OpenSSL est requis pour générer les secrets." >&2
  exit 1
fi

umask 077
mkdir -p "$(dirname -- "$OUTPUT")"

random_hex() {
  openssl rand -hex "$1"
}

admin_password=$(random_hex 16)
admin_password_hash=$(openssl passwd -6 "$admin_password")

cat > "$OUTPUT" <<EOF
# Généré le $(date -u +%Y-%m-%dT%H:%M:%SZ).
# Conserver ce fichier hors Git avec le mode 0600.

ADMIN_INITIAL_PASSWORD=$admin_password
ADMIN_PASSWORD_HASH='$admin_password_hash'

LINKWARDEN_DB_PASSWORD=$(random_hex 24)
LINKWARDEN_NEXTAUTH_SECRET=$(random_hex 32)

POSTGRES_ADMIN_PASSWORD=$(random_hex 24)
MARIADB_ADMIN_PASSWORD=$(random_hex 24)

DAVIS_DB_PASSWORD=$(random_hex 24)
DAVIS_APP_SECRET=$(random_hex 32)
DAVIS_ADMIN_PASSWORD=$(random_hex 20)

FRESHRSS_DB_PASSWORD=$(random_hex 24)

TTRSS_DB_PASSWORD=$(random_hex 24)
TTRSS_ADMIN_PASSWORD=$(random_hex 20)

WEB_DB_PASSWORD=$(random_hex 24)

GRAFANA_HTTP_PASSWORD=$(random_hex 20)
EOF

chmod 0600 "$OUTPUT"
echo "Secrets générés dans $OUTPUT"
echo "Le mot de passe initial de l'administrateur est stocké dans ADMIN_INITIAL_PASSWORD."
