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
DATABASES_OVERRIDE="$LOCAL_DIR/databases.override.yml"
TTRSS_OVERRIDE="$LOCAL_DIR/ttrss.override.yml"
KILL_NEWSLETTER_OVERRIDE="$LOCAL_DIR/kill-newsletter.override.yml"
MONITORING_COMPOSE="$LOCAL_DIR/monitoring.compose.yml"
CORE_SERVICES="linkwarden davis freshrss ttrss web"
ALL_SERVICES="$CORE_SERVICES kill-newsletter"
MANAGED_STACKS="databases $ALL_SERVICES monitoring"

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
    case "$name" in
      databases) source_dir="$INSTALL_DIR/databases" ;;
      monitoring) source_dir="$INSTALL_DIR/monitoring" ;;
      *) source_dir="$INSTALL_DIR/services/$name" ;;
    esac
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

env_value() {
  name=$1
  default_value=$2
  value=$(sed -n "s/^${name}=//p" "$CONFIG_FILE" | tail -n 1)
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$default_value"
  fi
}

env_enabled() {
  value=$(env_value "$1" false | tr '[:upper:]' '[:lower:]')
  case "$value" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

prepare_kill_newsletter_source() {
  repository=$(env_value KILL_NEWSLETTER_REPOSITORY \
    https://github.com/leafac/kill-the-newsletter.git)
  reference=$(env_value KILL_NEWSLETTER_REF \
    a7bb41c2f483db33f4516c1c56f3db3d43fc959a)
  target="$WORK_DIR/kill-newsletter/app"

  command -v git >/dev/null 2>&1 || {
    echo "Git est requis pour récupérer Kill the Newsletter." >&2
    exit 1
  }

  if [ ! -d "$target/.git" ]; then
    if [ -d "$target" ] \
      && find "$target" -mindepth 1 -print -quit | grep -q .; then
      echo "$target existe mais n'est pas un dépôt Git." >&2
      exit 1
    fi
    git clone --filter=blob:none "$repository" "$target"
  fi

  current=$(git -C "$target" rev-parse HEAD)
  if [ "$current" != "$reference" ]; then
    if [ -n "$(git -C "$target" status --porcelain)" ]; then
      echo "Le dépôt Kill the Newsletter contient des modifications locales." >&2
      exit 1
    fi
    git -C "$target" remote set-url origin "$repository"
    git -C "$target" fetch --depth 1 origin "$reference"
    git -C "$target" checkout --detach FETCH_HEAD
  fi

  [ -f "$target/package.json" ] || {
    echo "Le dépôt Kill the Newsletter ne contient pas package.json." >&2
    exit 1
  }
}

selected_services() {
  if [ "$SERVICE" = all ]; then
    printf '%s\n' "$CORE_SERVICES"
  else
    case "$SERVICE" in
      databases|linkwarden|davis|freshrss|ttrss|kill-newsletter|web|monitoring)
        printf '%s\n' "$SERVICE"
        ;;
      *)
        echo "Service inconnu : $SERVICE" >&2
        exit 2
        ;;
    esac
  fi
}

needs_databases() {
  case "$SERVICE" in
    all|databases|linkwarden|davis|freshrss|ttrss|web) return 0 ;;
    *) return 1 ;;
  esac
}

compose() {
  name=$1
  shift
  if [ "$name" = monitoring ]; then
    docker compose \
      --project-name "vps-local-$name" \
      --env-file "$CONFIG_FILE" \
      --env-file "$SECRETS_FILE" \
      -f "$MONITORING_COMPOSE" \
      --profile containers \
      --profile logs \
      "$@"
  elif [ "$name" = databases ]; then
    docker compose \
      --project-name "vps-local-$name" \
      --env-file "$CONFIG_FILE" \
      --env-file "$SECRETS_FILE" \
      -f "$WORK_DIR/$name/docker-compose.yml" \
      -f "$DATABASES_OVERRIDE" \
      "$@"
  elif [ "$name" = ttrss ]; then
    docker compose \
      --project-name "vps-local-$name" \
      --env-file "$CONFIG_FILE" \
      --env-file "$SECRETS_FILE" \
      -f "$WORK_DIR/$name/docker-compose.yml" \
      -f "$TTRSS_OVERRIDE" \
      "$@"
  elif [ "$name" = kill-newsletter ]; then
    docker compose \
      --project-name "vps-local-$name" \
      --env-file "$CONFIG_FILE" \
      --env-file "$SECRETS_FILE" \
      -f "$WORK_DIR/$name/docker-compose.yml" \
      -f "$KILL_NEWSLETTER_OVERRIDE" \
      "$@"
  else
    docker compose \
      --project-name "vps-local-$name" \
      --env-file "$CONFIG_FILE" \
      --env-file "$SECRETS_FILE" \
      -f "$WORK_DIR/$name/docker-compose.yml" \
      "$@"
  fi
}

start_monitoring() {
  compose monitoring up -d --remove-orphans grafana prometheus node-exporter

  if env_enabled ENABLE_CONTAINER_METRICS; then
    compose monitoring up -d cadvisor
  else
    compose monitoring rm --stop --force cadvisor
  fi

  if env_enabled ENABLE_LOGS; then
    compose monitoring up -d loki alloy
  else
    compose monitoring rm --stop --force alloy loki loki-init
  fi
}

pull_monitoring() {
  compose monitoring pull grafana prometheus node-exporter

  if env_enabled ENABLE_CONTAINER_METRICS; then
    compose monitoring pull cadvisor
  fi

  if env_enabled ENABLE_LOGS; then
    compose monitoring pull loki-init loki alloy
  fi
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
    if needs_databases; then
      compose databases pull
    fi
    for name in $(selected_services); do
      [ "$name" = databases ] && continue
      if [ "$name" = kill-newsletter ]; then
        prepare_kill_newsletter_source
        compose "$name" build --pull
      elif [ "$name" = monitoring ]; then
        pull_monitoring
      elif [ "$name" = web ]; then
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
      if [ "$name" = monitoring ]; then
        start_monitoring
      else
        compose "$name" restart
      fi
    done
    ;;
  ps)
    if needs_databases; then
      echo
      echo "### databases"
      compose databases ps
    fi
    for name in $(selected_services); do
      [ "$name" = databases ] && continue
      echo
      echo "### $name"
      compose "$name" ps
    done
    ;;
  up)
    if needs_databases; then
      compose databases up -d --wait
    fi
    for name in $(selected_services); do
      [ "$name" = databases ] && continue
      if [ "$name" = monitoring ]; then
        start_monitoring
        continue
      fi
      if [ "$name" = kill-newsletter ]; then
        prepare_kill_newsletter_source
        compose "$name" up -d --build
        continue
      fi
      compose "$name" up -d
    done
    if [ "$SERVICE" = monitoring ]; then
      echo "Grafana : http://localhost:3000"
      echo "Prometheus : http://localhost:9090"
    fi
    ;;
  down)
    selected=" $(selected_services) "
    for name in monitoring web ttrss freshrss davis linkwarden kill-newsletter; do
      case "$selected" in
        *" $name "*) compose "$name" down --remove-orphans ;;
      esac
    done
    case "$SERVICE" in
      all|databases) compose databases down --remove-orphans ;;
    esac
    ;;
  logs)
    if needs_databases; then
      echo
      echo "### databases"
      compose databases logs --tail=100
    fi
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
