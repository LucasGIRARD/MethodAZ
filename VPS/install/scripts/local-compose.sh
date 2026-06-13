#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
INSTALL_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
LOCAL_DIR="$INSTALL_DIR/local"
WORK_DIR="$LOCAL_DIR/work"
CONFIG_FILE="$LOCAL_DIR/vps.env"
CONFIG_EXAMPLE="$LOCAL_DIR/vps.env.example"
SECRETS_FILE="$LOCAL_DIR/secrets.env"
SECRETS_EXAMPLE="$LOCAL_DIR/secrets.env.example"
CORE_SERVICES="linkwarden davis freshrss ttrss web"
ALL_SERVICES="$CORE_SERVICES kill-newsletter"
MANAGED_STACKS="databases $ALL_SERVICES"

ACTION=${1:-validate}
SERVICE=${2:-all}

initialize_local() {
  mkdir -p "$WORK_DIR"
  if [ ! -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_EXAMPLE" "$CONFIG_FILE"
    chmod 0600 "$CONFIG_FILE" 2>/dev/null || true
    echo "Configuration locale créée : $CONFIG_FILE"
  fi
  if [ ! -f "$SECRETS_FILE" ]; then
    cp "$SECRETS_EXAMPLE" "$SECRETS_FILE"
    chmod 0600 "$SECRETS_FILE" 2>/dev/null || true
    echo "Secrets locaux créés : $SECRETS_FILE"
  fi
  grep -q '^POSTGRES_ADMIN_PASSWORD=' "$SECRETS_FILE" \
    || printf '%s\n' 'POSTGRES_ADMIN_PASSWORD=local_postgres_admin' \
      >> "$SECRETS_FILE"

  for name in $MANAGED_STACKS; do
    if [ "$name" = databases ]; then
      source_dir="$INSTALL_DIR/databases"
    else
      source_dir="$INSTALL_DIR/services/$name"
    fi
    target_dir="$WORK_DIR/$name"
    mkdir -p "$target_dir"
    cp -R "$source_dir/." "$target_dir/"
  done

  if [ ! -f "$WORK_DIR/web/html/index.php" ]; then
    mkdir -p "$WORK_DIR/web/html"
    printf "%s\n" "<?php echo 'Test local PHP OK';" \
      > "$WORK_DIR/web/html/index.php"
  fi
}

selected_services() {
  if [ "$SERVICE" = all ]; then
    printf '%s\n' "$CORE_SERVICES"
  else
    case "$SERVICE" in
      databases|linkwarden|davis|freshrss|ttrss|kill-newsletter|web)
        printf '%s\n' "$SERVICE"
        ;;
      *)
        echo "Service inconnu : $SERVICE" >&2
        exit 2
        ;;
    esac
  fi
}

compose() {
  name=$1
  shift
  docker compose \
    --project-name "vps-local-$name" \
    --env-file "$CONFIG_FILE" \
    --env-file "$SECRETS_FILE" \
    -f "$WORK_DIR/$name/docker-compose.yml" \
    "$@"
}

validate_all() {
  for name in $MANAGED_STACKS; do
    compose "$name" config --quiet
  done

  docker compose \
    --project-name vps-local-gateway \
    --env-file "$CONFIG_FILE" \
    --env-file "$SECRETS_FILE" \
    -f "$INSTALL_DIR/gateway/docker-compose.yml" \
    --profile manual config --quiet

  docker compose \
    --project-name vps-local-monitoring \
    --env-file "$CONFIG_FILE" \
    --env-file "$SECRETS_FILE" \
    -f "$INSTALL_DIR/monitoring/docker-compose.yml" \
    --profile containers --profile logs config --quiet
}

initialize_local
if [ "$ACTION" != init ]; then
  command -v docker >/dev/null 2>&1 || {
    echo "Docker est introuvable." >&2
    exit 1
  }
  docker compose version >/dev/null
fi

case "$ACTION" in
  init)
    echo "Environnement local préparé dans $WORK_DIR"
    echo "Configuration : $CONFIG_FILE"
    echo "Secrets : $SECRETS_FILE"
    ;;
  validate)
    validate_all
    echo "Tous les projets Compose sont valides."
    ;;
  pull)
    compose databases pull
    for name in $(selected_services); do
      [ "$name" = databases ] && continue
      if [ "$name" = web ]; then
        compose "$name" build --pull
      else
        compose "$name" pull
      fi
    done
    ;;
  restart)
    case "$SERVICE" in
      all|databases) compose databases restart ;;
    esac
    for name in $(selected_services); do
      [ "$name" = databases ] && continue
      compose "$name" restart
    done
    ;;
  ps)
    echo
    echo "### databases"
    compose databases ps
    for name in $(selected_services); do
      [ "$name" = databases ] && continue
      echo
      echo "### $name"
      compose "$name" ps
    done
    ;;
  up)
    compose databases up -d --wait
    for name in $(selected_services); do
      [ "$name" = databases ] && continue
      if [ "$name" = kill-newsletter ] \
        && [ ! -f "$WORK_DIR/kill-newsletter/app/Dockerfile" ]; then
        echo "Cloner Kill the Newsletter dans install/local/work/kill-newsletter/app." >&2
        exit 1
      fi
      compose "$name" up -d
    done
    ;;
  down)
    selected=" $(selected_services) "
    for name in web ttrss freshrss davis linkwarden kill-newsletter; do
      case "$selected" in
        *" $name "*) compose "$name" down --remove-orphans ;;
      esac
    done
    case "$SERVICE" in
      all|databases) compose databases down --remove-orphans ;;
    esac
    ;;
  logs)
    echo
    echo "### databases"
    compose databases logs --tail=100
    for name in $(selected_services); do
      [ "$name" = databases ] && continue
      echo
      echo "### $name"
      compose "$name" logs --tail=100
    done
    ;;
  clean)
    printf "Supprimer tous les conteneurs et les données locales ? Taper OUI : "
    read -r answer
    [ "$answer" = OUI ] || {
      echo "Nettoyage annulé." >&2
      exit 1
    }
    for name in $MANAGED_STACKS; do
      compose "$name" down --volumes --remove-orphans
    done
    case "$WORK_DIR" in
      "$LOCAL_DIR"/work) rm -rf "$WORK_DIR" ;;
      *) echo "Répertoire de travail inattendu." >&2; exit 1 ;;
    esac
    ;;
  *)
    echo "Usage : $0 {init|validate|pull|up|down|restart|ps|logs|clean} [service|all]" >&2
    exit 2
    ;;
esac
