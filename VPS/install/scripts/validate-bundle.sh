#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INSTALL_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
CONFIG=${1:-"$INSTALL_DIR/config/vps.env"}
SECRETS=${2:-"$INSTALL_DIR/config/secrets.env"}

[ -r "$CONFIG" ] || {
  echo "Configuration absente : $CONFIG" >&2
  exit 1
}
[ -r "$SECRETS" ] || {
  echo "Secrets absents : $SECRETS" >&2
  exit 1
}

secret_mode=$(stat -c '%a' "$SECRETS")
case "$secret_mode" in
  400|600) ;;
  *)
    echo "Le fichier de secrets doit avoir le mode 0600 ou 0400." >&2
    exit 1
    ;;
esac

for script in \
  "$INSTALL_DIR/scripts/fetch-vps.sh" \
  "$INSTALL_DIR/scripts/generate-secrets.sh" \
  "$INSTALL_DIR/scripts/local-compose.sh" \
  "$INSTALL_DIR/scripts/vps-install.sh" \
  "$INSTALL_DIR/scripts/vps-compose" \
  "$INSTALL_DIR/scripts/vps-image-lock" \
  "$INSTALL_DIR/scripts/vps-image-audit" \
  "$INSTALL_DIR/scripts/vps-backup" \
  "$INSTALL_DIR/scripts/vps-health-report" \
  "$INSTALL_DIR/scripts/vps-nightly-maintenance" \
  "$INSTALL_DIR/gateway/scripts/vps-gateway" \
  "$INSTALL_DIR/monitoring/scripts/vps-monitoring" \
  "$INSTALL_DIR/monitoring/scripts/vps-local-metrics"; do
  sh -n "$script"
done

compose_check() {
  file=$1
  shift
  docker compose \
    --env-file "$CONFIG" \
    --env-file "$SECRETS" \
    -f "$file" \
    "$@" \
    config --quiet
}

for service in linkwarden davis freshrss ttrss web; do
  compose_check "$INSTALL_DIR/services/$service/docker-compose.yml"
done

compose_check "$INSTALL_DIR/databases/docker-compose.yml"
compose_check "$INSTALL_DIR/services/kill-newsletter/docker-compose.yml"
compose_check "$INSTALL_DIR/gateway/docker-compose.yml" --profile manual
compose_check "$INSTALL_DIR/monitoring/docker-compose.yml" \
  --profile containers --profile logs

echo "Validation terminée : scripts et projets Compose cohérents."
