#!/bin/sh
set -eu
export LC_ALL=C

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
INSTALL_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
CONFIG="$INSTALL_DIR/config/vps.env"
SECRETS="$INSTALL_DIR/config/secrets.env"
PHASE=all
FINALIZE_SSH=false

usage() {
  cat <<'EOF'
Usage : vps-install.sh [options]

Options :
  --config FICHIER       Configuration publique.
  --secrets FICHIER      Fichier de secrets.
  --phase PHASE          all, base, ssh, firewall, docker, databases, services, gateway, monitoring.
  --finalize-ssh         Retire l'écoute temporaire sur le port 22.
  --help                 Affiche cette aide.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --config)
      CONFIG=$2
      shift 2
      ;;
    --secrets)
      SECRETS=$2
      shift 2
      ;;
    --phase)
      PHASE=$2
      shift 2
      ;;
    --finalize-ssh)
      FINALIZE_SSH=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Option inconnue : $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

log() {
  printf '\n==> %s\n' "$*"
}

die() {
  echo "Erreur : $*" >&2
  exit 1
}

require_root() {
  [ "$(id -u)" -eq 0 ] || die "exécuter ce script avec sudo ou comme root"
}

resolve_from_install() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    install/*) printf '%s\n' "$INSTALL_DIR/${1#install/}" ;;
    *) printf '%s\n' "$INSTALL_DIR/$1" ;;
  esac
}

validate_key_path() {
  name=$1
  value=$2

  case "$value" in
    /*|install/keys/*|keys/*) ;;
    *)
      die "$name doit pointer vers install/keys/... ou vers un chemin absolu, pas vers '$value'. Les chemins ../ changent après copie dans /opt/vps-install."
      ;;
  esac
}

load_configuration() {
  [ -r "$CONFIG" ] || die "configuration absente : $CONFIG"
  [ -r "$SECRETS" ] || die "secrets absents : $SECRETS"

  secret_mode=$(stat -c '%a' "$SECRETS")
  case "$secret_mode" in
    400|600) ;;
    *) die "le fichier $SECRETS doit avoir le mode 0600 ou 0400" ;;
  esac

  if grep -Eq '^ADMIN_PASSWORD_HASH=\$' "$SECRETS"; then
    die "ADMIN_PASSWORD_HASH doit être entre quotes simples dans $SECRETS, par exemple ADMIN_PASSWORD_HASH='\$6\$...'"
  fi

  # shellcheck disable=SC1090
  . "$CONFIG"
  # shellcheck disable=SC1090
  . "$SECRETS"

  case "${SSH_PORT:-}" in
    ''|*[!0-9]*) die "SSH_PORT doit être un nombre réel, jamais **000" ;;
  esac
  if [ "$SSH_PORT" -lt 1024 ] || [ "$SSH_PORT" -gt 65535 ]; then
    die "SSH_PORT doit être compris entre 1024 et 65535"
  fi

  : "${ADMIN_USER:?ADMIN_USER manquant}"
  : "${ADMIN_SSH_KEY_FILE:?ADMIN_SSH_KEY_FILE manquant}"
  validate_key_path ADMIN_SSH_KEY_FILE "$ADMIN_SSH_KEY_FILE"
  if [ "${ENABLE_SFTP:-true}" = true ]; then
    : "${SFTP_SSH_KEY_FILE:?SFTP_SSH_KEY_FILE manquant}"
    validate_key_path SFTP_SSH_KEY_FILE "$SFTP_SSH_KEY_FILE"
  fi
  : "${ADMIN_PASSWORD_HASH:?ADMIN_PASSWORD_HASH manquant}"
  : "${TIMEZONE:?TIMEZONE manquant}"
}

apply_resource_profile() {
  case "${RESOURCE_PROFILE:-VPS_4G}" in
    VPS_2G)
      : "${POSTGRES_MEMORY_LIMIT:=320m}"
      : "${LINKWARDEN_MEMORY_LIMIT:=384m}"
      : "${DAVIS_MEMORY_LIMIT:=192m}"
      : "${DAVIS_NGINX_MEMORY_LIMIT:=64m}"
      : "${DAVIS_MIGRATE_MEMORY_LIMIT:=128m}"
      : "${FRESHRSS_MEMORY_LIMIT:=192m}"
      : "${TTRSS_APP_MEMORY_LIMIT:=256m}"
      : "${TTRSS_UPDATER_MEMORY_LIMIT:=128m}"
      : "${TTRSS_NGINX_MEMORY_LIMIT:=64m}"
      : "${KILL_NEWSLETTER_MEMORY_LIMIT:=192m}"
      : "${WEB_MEMORY_LIMIT:=192m}"
      : "${NGINX_MEMORY_LIMIT:=96m}"
      : "${CERTBOT_MEMORY_LIMIT:=128m}"
      : "${GRAFANA_MEMORY_LIMIT:=256m}"
      : "${PROMETHEUS_MEMORY_LIMIT:=256m}"
      : "${NODE_EXPORTER_MEMORY_LIMIT:=64m}"
      : "${CADVISOR_MEMORY_LIMIT:=192m}"
      : "${LOKI_INIT_MEMORY_LIMIT:=64m}"
      : "${LOKI_MEMORY_LIMIT:=256m}"
      : "${ALLOY_MEMORY_LIMIT:=192m}"
      ;;
    VPS_4G)
      : "${POSTGRES_MEMORY_LIMIT:=512m}"
      : "${LINKWARDEN_MEMORY_LIMIT:=768m}"
      : "${DAVIS_MEMORY_LIMIT:=384m}"
      : "${DAVIS_NGINX_MEMORY_LIMIT:=96m}"
      : "${DAVIS_MIGRATE_MEMORY_LIMIT:=256m}"
      : "${FRESHRSS_MEMORY_LIMIT:=384m}"
      : "${TTRSS_APP_MEMORY_LIMIT:=512m}"
      : "${TTRSS_UPDATER_MEMORY_LIMIT:=256m}"
      : "${TTRSS_NGINX_MEMORY_LIMIT:=96m}"
      : "${KILL_NEWSLETTER_MEMORY_LIMIT:=384m}"
      : "${WEB_MEMORY_LIMIT:=384m}"
      : "${NGINX_MEMORY_LIMIT:=128m}"
      : "${CERTBOT_MEMORY_LIMIT:=128m}"
      : "${GRAFANA_MEMORY_LIMIT:=384m}"
      : "${PROMETHEUS_MEMORY_LIMIT:=512m}"
      : "${NODE_EXPORTER_MEMORY_LIMIT:=96m}"
      : "${CADVISOR_MEMORY_LIMIT:=384m}"
      : "${LOKI_INIT_MEMORY_LIMIT:=64m}"
      : "${LOKI_MEMORY_LIMIT:=512m}"
      : "${ALLOY_MEMORY_LIMIT:=384m}"
      ;;
    *)
      die "RESOURCE_PROFILE doit valoir VPS_2G ou VPS_4G"
      ;;
  esac
}

compose_env_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/\\\\'/g")"
}

ensure_authorized_key() {
  key_file=$1
  authorized_keys=$2
  owner=$3
  group=$4

  install -d -m 0700 -o "$owner" -g "$group" "$(dirname "$authorized_keys")"
  touch "$authorized_keys"
  chown "$owner:$group" "$authorized_keys"
  chmod 0600 "$authorized_keys"

  if ! grep -qxF -f "$key_file" "$authorized_keys"; then
    printf '\n' >> "$authorized_keys"
    cat "$key_file" >> "$authorized_keys"
  fi
}

set_random_disabled_password() {
  user=$1

  if ! command -v openssl >/dev/null 2>&1; then
    die "OpenSSL est requis pour préparer le compte $user"
  fi

  random_password=$(openssl rand -base64 48)
  random_hash=$(openssl passwd -6 "$random_password")
  usermod --password "$random_hash" "$user"
}

web_server_names() {
  names=$WEB_DOMAIN
  old_ifs=$IFS
  IFS=,
  for subdomain in ${WEB_SUBDOMAINS:-}; do
    IFS=$old_ifs
    [ -n "$subdomain" ] || continue
    case "$subdomain" in
      *[!A-Za-z0-9-]*|-*|*-)
        die "WEB_SUBDOMAINS contient un label invalide : $subdomain"
        ;;
    esac
    names="$names $subdomain.$WEB_DOMAIN"
    IFS=,
  done
  IFS=$old_ifs
  printf '%s\n' "$names"
}

create_web_subdomain_directories() {
  install -d -m 0755 /opt/selfhosted/web/html

  old_ifs=$IFS
  IFS=,
  for subdomain in ${WEB_SUBDOMAINS:-}; do
    IFS=$old_ifs
    [ -n "$subdomain" ] || continue
    case "$subdomain" in
      *[!A-Za-z0-9-]*|-*|*-)
        die "WEB_SUBDOMAINS contient un label invalide : $subdomain"
        ;;
    esac
    install -d -m 0755 "/opt/selfhosted/web/html/$subdomain"
    IFS=,
  done
  IFS=$old_ifs
}

check_debian() {
  [ -r /etc/os-release ] || die "/etc/os-release absent"
  # shellcheck disable=SC1091
  . /etc/os-release
  [ "${ID:-}" = debian ] || die "cette procédure cible Debian"
  [ "${VERSION_ID:-}" = 13 ] || die "Debian 13 est requis, version détectée : ${VERSION_ID:-inconnue}"
}

stage_installer() {
  staged=/opt/vps-install
  if [ "$INSTALL_DIR" != "$staged" ]; then
    install -d -m 0700 "$staged"
    rsync -a --exclude 'config/vps.env' --exclude 'config/secrets.env' \
      "$INSTALL_DIR/" "$staged/"
    install -m 0600 "$CONFIG" "$staged/config/vps.env"
    install -m 0600 "$SECRETS" "$staged/config/secrets.env"
    chown -R root:root "$staged"
    find "$staged/scripts" -type f -exec chmod 0755 {} \;
  fi

  cat > /usr/local/sbin/vps-install <<'EOF'
#!/bin/sh
exec sh /opt/vps-install/scripts/vps-install.sh "$@"
EOF
  chmod 0755 /usr/local/sbin/vps-install
}

install_base() {
  log "Paquets de base et compte administrateur"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates curl fail2ban git iptables iptables-persistent jq \
    logrotate nano needrestart openssh-server openssl rsync sudo \
    unattended-upgrades
  case "${ENABLE_REMOTE_BACKUP:-false}" in
    true|TRUE|1|yes|YES)
      DEBIAN_FRONTEND=noninteractive apt-get install -y restic rclone
      ;;
  esac

  stage_installer

  install -d -m 0755 /var/log/journal /etc/systemd/journald.conf.d
  install -m 0644 "$INSTALL_DIR/system/journald/10-retention.conf" \
    /etc/systemd/journald.conf.d/10-retention.conf
  install -m 0644 "$INSTALL_DIR/system/logrotate/server-checks" \
    /etc/logrotate.d/server-checks
  install -m 0644 "$INSTALL_DIR/system/apt/20auto-upgrades" \
    /etc/apt/apt.conf.d/20auto-upgrades
  install -m 0644 "$INSTALL_DIR/system/apt/52unattended-upgrades-local" \
    /etc/apt/apt.conf.d/52unattended-upgrades-local

  [ -f "/usr/share/zoneinfo/$TIMEZONE" ] \
    || die "fuseau horaire inconnu : $TIMEZONE"
  timedatectl set-timezone "$TIMEZONE"

  install -d -m 0755 \
    /etc/systemd/system/apt-daily.timer.d \
    /etc/systemd/system/apt-daily-upgrade.timer.d
  install -m 0644 \
    "$INSTALL_DIR/system/systemd/apt-daily.timer.override.conf" \
    /etc/systemd/system/apt-daily.timer.d/override.conf
  install -m 0644 \
    "$INSTALL_DIR/system/systemd/apt-daily-upgrade.timer.override.conf" \
    /etc/systemd/system/apt-daily-upgrade.timer.d/override.conf

  systemd-tmpfiles --create --prefix /var/log/journal
  systemctl restart systemd-journald
  systemctl daemon-reload
  systemctl enable --now apt-daily.timer apt-daily-upgrade.timer

  if ! id "$ADMIN_USER" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash "$ADMIN_USER"
  fi
  usermod -aG sudo "$ADMIN_USER"
  usermod --password "$ADMIN_PASSWORD_HASH" "$ADMIN_USER"

  admin_key=$(resolve_from_install "$ADMIN_SSH_KEY_FILE")
  [ -s "$admin_key" ] || die "clé publique administrateur absente : $admin_key"
  ensure_authorized_key \
    "$admin_key" "/home/$ADMIN_USER/.ssh/authorized_keys" "$ADMIN_USER" "$ADMIN_USER"
  if [ "${KEEP_SSH_PORT_22:-true}" = true ]; then
    ensure_authorized_key "$admin_key" /root/.ssh/authorized_keys root root
  fi

  if [ "${ENABLE_SWAP:-true}" = true ] && ! swapon --show=NAME | grep -qx /swapfile; then
    fallocate -l "${SWAP_SIZE:-2G}" /swapfile
    chmod 0600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    grep -q '^/swapfile ' /etc/fstab \
      || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  fi
}

write_ssh_configuration() {
  log "Configuration SSH renforcée"
  install -d -m 0755 /etc/ssh/sshd_config.d /etc/ssh/authorized_keys

  permit_root_login=no
  if [ "${KEEP_SSH_PORT_22:-true}" = true ] && [ "$FINALIZE_SSH" != true ]; then
    permit_root_login=prohibit-password
  fi

  cat > /etc/ssh/sshd_config.d/20-vps-hardening.conf <<EOF
Port $SSH_PORT
PermitRootLogin $permit_root_login
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys /etc/ssh/authorized_keys/%u
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2

Match Group sftp-only
    ChrootDirectory ${SFTP_ROOT:-/srv/sftp}/%u
    ForceCommand internal-sftp -d /upload -u 0027
    AllowAgentForwarding no
    AllowTcpForwarding no
    PermitTunnel no
    X11Forwarding no

Match all
EOF

  if [ "${KEEP_SSH_PORT_22:-true}" = true ] && [ "$FINALIZE_SSH" != true ]; then
    cat > /etc/ssh/sshd_config.d/21-vps-bootstrap-port.conf <<'EOF'
# Port temporaire à retirer avec : vps-install --finalize-ssh
Port 22
EOF
  else
    rm -f /etc/ssh/sshd_config.d/21-vps-bootstrap-port.conf
  fi

  if [ "${ENABLE_SFTP:-true}" = true ]; then
    sftp_key=$(resolve_from_install "${SFTP_SSH_KEY_FILE:?SFTP_SSH_KEY_FILE manquant}")
    [ -s "$sftp_key" ] || die "clé publique SFTP absente : $sftp_key"

    getent group sftp-only >/dev/null 2>&1 || groupadd --system sftp-only
    if ! id "${SFTP_USER:?SFTP_USER manquant}" >/dev/null 2>&1; then
      useradd --no-create-home --home-dir /upload --shell /usr/sbin/nologin \
        --gid sftp-only "$SFTP_USER"
    fi
    usermod --gid sftp-only --home /upload --shell /usr/sbin/nologin "$SFTP_USER"
    set_random_disabled_password "$SFTP_USER"

    chroot="${SFTP_ROOT:-/srv/sftp}/$SFTP_USER"
    install -d -m 0755 -o root -g root "$chroot"
    install -d -m 0750 -o "$SFTP_USER" -g sftp-only "$chroot/upload"
    install -m 0644 -o root -g root \
      "$sftp_key" "/etc/ssh/authorized_keys/$SFTP_USER"
  fi

  sshd -t
  if systemctl cat ssh.socket >/dev/null 2>&1; then
    # La socket systemd peut conserver une écoute sur 22 hors sshd_config.
    systemctl disable --now ssh.socket >/dev/null 2>&1 || true
  fi
  systemctl enable ssh >/dev/null 2>&1 || true
  systemctl restart ssh
}

write_firewall() {
  log "Pare-feu IPv4 et IPv6"
  update-alternatives --set iptables /usr/sbin/iptables-nft
  update-alternatives --set ip6tables /usr/sbin/ip6tables-nft

  ssh_rules="-A INPUT -p tcp --dport $SSH_PORT -m conntrack --ctstate NEW -j ACCEPT"
  if [ "${KEEP_SSH_PORT_22:-true}" = true ] && [ "$FINALIZE_SSH" != true ] \
    && [ "$SSH_PORT" -ne 22 ]; then
    ssh_rules="$ssh_rules
-A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -j ACCEPT"
  fi

  cat > /etc/iptables/rules.v4 <<EOF
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A INPUT -m conntrack --ctstate INVALID -j DROP
-A INPUT -p icmp -j ACCEPT
$ssh_rules
-A INPUT -p tcp -m multiport --dports 80,443 -m conntrack --ctstate NEW -j ACCEPT
-A INPUT -p tcp --syn -m hashlimit --hashlimit-above 15/minute --hashlimit-burst 20 --hashlimit-mode srcip --hashlimit-name portscan4 -m limit --limit 10/second --limit-burst 20 -j LOG --log-prefix "IPT_PORTSCAN " --log-level 6
-A INPUT -p udp -m hashlimit --hashlimit-above 30/minute --hashlimit-burst 30 --hashlimit-mode srcip --hashlimit-name udpscan4 -m limit --limit 10/second --limit-burst 20 -j LOG --log-prefix "IPT_UDPSCAN " --log-level 6
COMMIT
EOF

  cat > /etc/iptables/rules.v6 <<EOF
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A INPUT -m conntrack --ctstate INVALID -j DROP
-A INPUT -p ipv6-icmp -j ACCEPT
$ssh_rules
-A INPUT -p tcp -m multiport --dports 80,443 -m conntrack --ctstate NEW -j ACCEPT
-A INPUT -p tcp --syn -m hashlimit --hashlimit-above 15/minute --hashlimit-burst 20 --hashlimit-mode srcip --hashlimit-name portscan6 -m limit --limit 10/second --limit-burst 20 -j LOG --log-prefix "IPT_PORTSCAN " --log-level 6
-A INPUT -p udp -m hashlimit --hashlimit-above 30/minute --hashlimit-burst 30 --hashlimit-mode srcip --hashlimit-name udpscan6 -m limit --limit 10/second --limit-burst 20 -j LOG --log-prefix "IPT_UDPSCAN " --log-level 6
COMMIT
EOF

  iptables-restore --test /etc/iptables/rules.v4
  ip6tables-restore --test /etc/iptables/rules.v6

  docker_was_active=false
  if systemctl is-active --quiet docker 2>/dev/null; then
    docker_was_active=true
  fi

  iptables-restore < /etc/iptables/rules.v4
  if [ "${ENABLE_IPV6:-true}" = true ]; then
    ip6tables-restore < /etc/iptables/rules.v6
  fi
  systemctl enable netfilter-persistent
  netfilter-persistent save

  if [ "$docker_was_active" = true ]; then
    systemctl restart docker
  fi
}

install_fail2ban() {
  log "Fail2ban pour SSH et scans rapides"
  install -d -m 0755 /etc/fail2ban/filter.d /etc/fail2ban/jail.d

  ssh_ports=$SSH_PORT
  if [ "${KEEP_SSH_PORT_22:-true}" = true ] && [ "$FINALIZE_SSH" != true ] \
    && [ "$SSH_PORT" -ne 22 ]; then
    ssh_ports="22,$SSH_PORT"
  fi

  cat > /etc/fail2ban/filter.d/iptables-portscan.conf <<'EOF'
[Definition]
failregex = ^.*IPT_(?:PORT|UDP)SCAN .*SRC=<HOST>\s.*$
ignoreregex =
journalmatch = _TRANSPORT=kernel
EOF

  cat > /etc/fail2ban/jail.d/vps.local <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
backend = systemd
ignoreip = 127.0.0.1/8 ::1
banaction = iptables-multiport
banaction_allports = iptables-allports

[sshd]
enabled = true
port = $ssh_ports
backend = systemd

[iptables-portscan]
enabled = true
filter = iptables-portscan
backend = systemd
maxretry = 3
findtime = 2m
bantime = 24h
banaction = iptables-allports
EOF

  cat > /etc/fail2ban/fail2ban.local <<'EOF'
[Definition]
logtarget = SYSTEMD-JOURNAL
loglevel = INFO
dbpurgeage = 7d
EOF

  fail2ban-client -t
  systemctl enable --now fail2ban
  systemctl restart fail2ban
}

install_docker() {
  [ "${INSTALL_DOCKER:-true}" = true ] || return 0
  log "Docker depuis le dépôt officiel"

  case "${ENABLE_REMOTE_BACKUP:-false}" in
    true|TRUE|1|yes|YES)
      if ! command -v restic >/dev/null 2>&1 \
        || ! command -v rclone >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y restic rclone
      fi
      ;;
  esac

  for package in docker.io docker-doc docker-compose podman-docker containerd runc; do
    apt-get remove -y "$package" >/dev/null 2>&1 || true
  done

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg \
    -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  architecture=$(dpkg --print-architecture)
  # shellcheck disable=SC1091
  . /etc/os-release
  cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $VERSION_CODENAME
Components: stable
Architectures: $architecture
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin \
    docker-compose-plugin

  daemon_fragment=$(mktemp)
  daemon_merged=$(mktemp)
  trap 'rm -f "$daemon_fragment" "$daemon_merged"' EXIT HUP INT TERM
  cat > "$daemon_fragment" <<'EOF'
{
  "log-driver": "journald",
  "log-opts": {
    "tag": "{{.Name}}",
    "labels": "com.docker.compose.project,com.docker.compose.service"
  },
  "metrics-addr": "127.0.0.1:9323",
  "experimental": true
}
EOF

  if [ -s /etc/docker/daemon.json ]; then
    jq -s '.[0] * .[1]' /etc/docker/daemon.json "$daemon_fragment" > "$daemon_merged"
  else
    cp "$daemon_fragment" "$daemon_merged"
  fi
  install -d -m 0755 /etc/docker
  install -m 0644 "$daemon_merged" /etc/docker/daemon.json
  dockerd --validate --config-file=/etc/docker/daemon.json
  systemctl enable --now docker
  systemctl restart docker
  usermod -aG docker "$ADMIN_USER"
  install -m 0755 "$SCRIPT_DIR/vps-compose" /usr/local/sbin/vps-compose
  install -m 0755 "$SCRIPT_DIR/vps-image-lock" /usr/local/sbin/vps-image-lock
  install -m 0755 "$SCRIPT_DIR/vps-image-audit" /usr/local/sbin/vps-image-audit
  install -m 0755 "$SCRIPT_DIR/vps-backup" /usr/local/sbin/vps-backup
  install -m 0755 "$SCRIPT_DIR/vps-backup-remote" \
    /usr/local/sbin/vps-backup-remote
  install -m 0755 "$SCRIPT_DIR/vps-restore-test" \
    /usr/local/sbin/vps-restore-test
  install -m 0755 "$SCRIPT_DIR/vps-secret-audit" \
    /usr/local/sbin/vps-secret-audit
  install -m 0755 "$SCRIPT_DIR/vps-health-report" \
    /usr/local/sbin/vps-health-report
  install -m 0755 "$SCRIPT_DIR/vps-nightly-maintenance" \
    /usr/local/sbin/vps-nightly-maintenance
  install -m 0644 \
    "$INSTALL_DIR/system/systemd/vps-nightly-maintenance.service" \
    /etc/systemd/system/vps-nightly-maintenance.service
  install -m 0644 \
    "$INSTALL_DIR/system/systemd/vps-nightly-maintenance.timer" \
    /etc/systemd/system/vps-nightly-maintenance.timer

  cat > /etc/default/vps-maintenance <<EOF
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}
BACKUP_MIN_FREE_MB=${BACKUP_MIN_FREE_MB:-1024}
ENABLE_REMOTE_BACKUP=${ENABLE_REMOTE_BACKUP:-false}
RESTIC_REPOSITORY_FILE=${RESTIC_REPOSITORY_FILE:-/etc/vps-backup/restic-repository}
RESTIC_PASSWORD_FILE=${RESTIC_PASSWORD_FILE:-/etc/vps-backup/restic-password}
RESTIC_ENV_FILE=${RESTIC_ENV_FILE:-/etc/vps-backup/restic.env}
REMOTE_BACKUP_KEEP_DAILY=${REMOTE_BACKUP_KEEP_DAILY:-7}
REMOTE_BACKUP_KEEP_WEEKLY=${REMOTE_BACKUP_KEEP_WEEKLY:-5}
REMOTE_BACKUP_KEEP_MONTHLY=${REMOTE_BACKUP_KEEP_MONTHLY:-12}
EOF
  chmod 0644 /etc/default/vps-maintenance
  install -d -m 0700 /opt/selfhosted/backups/files
  install -d -m 0700 /var/lib/vps-maintenance
  case "${ENABLE_REMOTE_BACKUP:-false}" in
    true|TRUE|1|yes|YES)
      install -d -m 0700 /etc/vps-backup /var/cache/restic
      install -m 0600 "$INSTALL_DIR/config/restic.env.example" \
        /etc/vps-backup/restic.env.example
      ;;
  esac
  systemctl daemon-reload
  systemctl enable --now vps-nightly-maintenance.timer
  rm -f "$daemon_fragment" "$daemon_merged"
  trap - EXIT HUP INT TERM
}

copy_stack() {
  name=$1
  source=$2
  target="/opt/selfhosted/$name"

  [ -d "$source" ] || die "modèle de projet absent : $source"
  [ -f "$source/docker-compose.yml" ] \
    || die "fichier Compose absent dans le modèle : $source/docker-compose.yml"

  install -d -m 0750 "$target"
  rsync -a --exclude '.env' "$source/" "$target/"
  [ -f "$target/docker-compose.yml" ] \
    || die "copie incomplète du projet $name : $target/docker-compose.yml absent"
}

service_uses_database() {
  case "$1" in
    linkwarden|davis|freshrss|ttrss|web) return 0 ;;
    *) return 1 ;;
  esac
}

database_network_exists() {
  docker network inspect "${DATABASE_NETWORK_PREFIX:-vps-db}-$1" >/dev/null 2>&1
}

ensure_database_network_for_service() {
  service=$1
  service_uses_database "$service" || return 0

  if database_network_exists "$service"; then
    return 0
  fi

  if [ "${INSTALL_DATABASES:-true}" = true ]; then
    log "Réseau base absent pour $service, préparation du stack databases"
    install_databases
  fi

  database_network_exists "$service" \
    || die "réseau Docker absent : ${DATABASE_NETWORK_PREFIX:-vps-db}-$service. Lancer d'abord : vps-install --phase databases"
}

prepare_kill_newsletter_source() {
  target=/opt/selfhosted/kill-newsletter/app
  repository=${KILL_NEWSLETTER_REPOSITORY:-https://github.com/leafac/kill-the-newsletter.git}
  reference=${KILL_NEWSLETTER_REF:-a7bb41c2f483db33f4516c1c56f3db3d43fc959a}

  if [ ! -d "$target/.git" ]; then
    if [ -d "$target" ] \
      && find "$target" -mindepth 1 -print -quit | grep -q .; then
      die "$target existe mais n'est pas un dépôt Git"
    fi
    git clone --filter=blob:none "$repository" "$target"
  else
    if [ -n "$(git -C "$target" status --porcelain)" ]; then
      die "le dépôt Kill the Newsletter contient des modifications locales"
    fi
    git -C "$target" remote set-url origin "$repository"
  fi

  git -C "$target" fetch --depth 1 origin "$reference"
  git -C "$target" checkout --detach FETCH_HEAD
  [ -f "$target/package.json" ] \
    || die "package.json absent du dépôt Kill the Newsletter"
}

install_databases() {
  [ "${INSTALL_DATABASES:-true}" = true ] || return 0
  log "Bases de données partagées"

  legacy_mariadb=/opt/selfhosted/databases/mariadb
  if find "$legacy_mariadb" -mindepth 1 -print -quit 2>/dev/null \
    | grep -q .; then
    die "données MariaDB détectées dans $legacy_mariadb ; migrer les bases vers PostgreSQL puis déplacer ce répertoire avant de rejouer cette phase"
  fi

  : "${POSTGRES_ADMIN_PASSWORD:?POSTGRES_ADMIN_PASSWORD manquant}"
  : "${LINKWARDEN_DB_PASSWORD:?LINKWARDEN_DB_PASSWORD manquant}"
  : "${DAVIS_DB_PASSWORD:?DAVIS_DB_PASSWORD manquant}"
  : "${FRESHRSS_DB_PASSWORD:?FRESHRSS_DB_PASSWORD manquant}"
  : "${TTRSS_DB_PASSWORD:?TTRSS_DB_PASSWORD manquant}"
  : "${WEB_DB_PASSWORD:?WEB_DB_PASSWORD manquant}"

  copy_stack databases "$INSTALL_DIR/databases"
  rm -f /opt/selfhosted/databases/init-mariadb.sh
  chmod 0555 /opt/selfhosted/databases/init-postgres.sh

  umask 077
  cat > /opt/selfhosted/databases/.env <<EOF
DATABASE_NETWORK_PREFIX=${DATABASE_NETWORK_PREFIX:-vps-db}
POSTGRES_VERSION=$POSTGRES_VERSION
POSTGRES_ADMIN_PASSWORD=$(compose_env_quote "$POSTGRES_ADMIN_PASSWORD")
POSTGRES_MEMORY_LIMIT=$POSTGRES_MEMORY_LIMIT
LINKWARDEN_DB_PASSWORD=$(compose_env_quote "$LINKWARDEN_DB_PASSWORD")
DAVIS_DB_PASSWORD=$(compose_env_quote "$DAVIS_DB_PASSWORD")
FRESHRSS_DB_PASSWORD=$(compose_env_quote "$FRESHRSS_DB_PASSWORD")
TTRSS_DB_PASSWORD=$(compose_env_quote "$TTRSS_DB_PASSWORD")
WEB_DB_PASSWORD=$(compose_env_quote "$WEB_DB_PASSWORD")
EOF
  chmod 0600 /opt/selfhosted/databases/.env

  /usr/local/sbin/vps-image-lock databases
  /usr/local/sbin/vps-compose databases up -d --wait --remove-orphans
  /usr/local/sbin/vps-compose databases exec -T postgres \
    sh /usr/local/sbin/reconcile-applications
}

write_service_env() {
  name=$1
  target="/opt/selfhosted/$name/.env"
  umask 077

  case "$name" in
    linkwarden)
      cat > "$target" <<EOF
LINKWARDEN_VERSION=$LINKWARDEN_VERSION
DATABASE_NETWORK_PREFIX=${DATABASE_NETWORK_PREFIX:-vps-db}
LINKWARDEN_DOMAIN=$LINKWARDEN_DOMAIN
LINKWARDEN_URL=${LINKWARDEN_URL:-https://$LINKWARDEN_DOMAIN}
LINKWARDEN_DISABLE_REGISTRATION=${LINKWARDEN_DISABLE_REGISTRATION:-false}
TIMEZONE=$TIMEZONE
LINKWARDEN_DB_PASSWORD=$(compose_env_quote "$LINKWARDEN_DB_PASSWORD")
LINKWARDEN_NEXTAUTH_SECRET=$(compose_env_quote "$LINKWARDEN_NEXTAUTH_SECRET")
LINKWARDEN_MEMORY_LIMIT=$LINKWARDEN_MEMORY_LIMIT
EOF
      ;;
    davis)
      cat > "$target" <<EOF
DAVIS_VERSION=$DAVIS_VERSION
NGINX_ALPINE_VERSION=$NGINX_ALPINE_VERSION
POSTGRES_MAJOR_VERSION=${POSTGRES_MAJOR_VERSION:-16}
DATABASE_NETWORK_PREFIX=${DATABASE_NETWORK_PREFIX:-vps-db}
DAVIS_DOMAIN=$DAVIS_DOMAIN
TIMEZONE=$TIMEZONE
DAVIS_DB_PASSWORD=$(compose_env_quote "$DAVIS_DB_PASSWORD")
DAVIS_APP_SECRET=$(compose_env_quote "$DAVIS_APP_SECRET")
DAVIS_ADMIN_PASSWORD=$(compose_env_quote "$DAVIS_ADMIN_PASSWORD")
DAVIS_MEMORY_LIMIT=$DAVIS_MEMORY_LIMIT
DAVIS_NGINX_MEMORY_LIMIT=${DAVIS_NGINX_MEMORY_LIMIT:-96m}
DAVIS_MIGRATE_MEMORY_LIMIT=$DAVIS_MIGRATE_MEMORY_LIMIT
EOF
      ;;
    freshrss)
      cat > "$target" <<EOF
FRESHRSS_VERSION=$FRESHRSS_VERSION
DATABASE_NETWORK_PREFIX=${DATABASE_NETWORK_PREFIX:-vps-db}
TIMEZONE=$TIMEZONE
FRESHRSS_DB_PASSWORD=$(compose_env_quote "$FRESHRSS_DB_PASSWORD")
FRESHRSS_MEMORY_LIMIT=$FRESHRSS_MEMORY_LIMIT
EOF
      ;;
    ttrss)
      cat > "$target" <<EOF
TTRSS_IMAGE=$TTRSS_IMAGE
NGINX_ALPINE_VERSION=$NGINX_ALPINE_VERSION
DATABASE_NETWORK_PREFIX=${DATABASE_NETWORK_PREFIX:-vps-db}
TTRSS_DOMAIN=$TTRSS_DOMAIN
TTRSS_URL=${TTRSS_URL:-https://$TTRSS_DOMAIN/}
TTRSS_DB_PASSWORD=$(compose_env_quote "$TTRSS_DB_PASSWORD")
TTRSS_ADMIN_PASSWORD=$(compose_env_quote "$TTRSS_ADMIN_PASSWORD")
TTRSS_APP_MEMORY_LIMIT=$TTRSS_APP_MEMORY_LIMIT
TTRSS_UPDATER_MEMORY_LIMIT=$TTRSS_UPDATER_MEMORY_LIMIT
TTRSS_NGINX_MEMORY_LIMIT=$TTRSS_NGINX_MEMORY_LIMIT
EOF
      ;;
    web)
      cat > "$target" <<EOF
PHP_BASE_IMAGE=$PHP_BASE_IMAGE
WEB_IMAGE_TAG=$WEB_IMAGE_TAG
DATABASE_NETWORK_PREFIX=${DATABASE_NETWORK_PREFIX:-vps-db}
WEB_DOMAIN=$WEB_DOMAIN
WEB_SUBDOMAINS=${WEB_SUBDOMAINS:-}
WEB_DB_PASSWORD=$(compose_env_quote "$WEB_DB_PASSWORD")
WEB_MEMORY_LIMIT=$WEB_MEMORY_LIMIT
EOF
      ;;
    kill-newsletter)
      cat > "$target" <<EOF
KILL_NEWSLETTER_MEMORY_LIMIT=$KILL_NEWSLETTER_MEMORY_LIMIT
KILL_NEWSLETTER_NODE_IMAGE=${KILL_NEWSLETTER_NODE_IMAGE:-node:24-bookworm-slim}
KILL_NEWSLETTER_REPOSITORY=${KILL_NEWSLETTER_REPOSITORY:-https://github.com/leafac/kill-the-newsletter.git}
KILL_NEWSLETTER_REF=${KILL_NEWSLETTER_REF:-a7bb41c2f483db33f4516c1c56f3db3d43fc959a}
KILL_NEWSLETTER_HOSTNAME=$NEWSLETTER_DOMAIN
KILL_NEWSLETTER_ADMIN_EMAIL=$ADMIN_EMAIL
EOF
      ;;
  esac
  chmod 0600 "$target" 2>/dev/null || true
}

wait_for_linkwarden() {
  attempts=60
  while [ "$attempts" -gt 0 ]; do
    if curl -fsS -o /dev/null http://127.0.0.1:3001/; then
      return 0
    fi
    attempts=$((attempts - 1))
    sleep 2
  done

  return 1
}

bootstrap_linkwarden_user() {
  [ "${LINKWARDEN_DISABLE_REGISTRATION:-false}" = true ] || return 0
  [ -n "${LINKWARDEN_BOOTSTRAP_USER:-}" ] || return 0

  : "${LINKWARDEN_BOOTSTRAP_PASSWORD:?LINKWARDEN_BOOTSTRAP_PASSWORD manquant}"
  command -v jq >/dev/null 2>&1 || die "jq est requis pour créer le compte Linkwarden"
  case "$LINKWARDEN_BOOTSTRAP_USER" in
    *[!a-z0-9_-]*)
      die "LINKWARDEN_BOOTSTRAP_USER doit contenir seulement a-z, 0-9, _ ou -"
      ;;
  esac
  if [ "${#LINKWARDEN_BOOTSTRAP_USER}" -lt 3 ] \
    || [ "${#LINKWARDEN_BOOTSTRAP_USER}" -gt 50 ]; then
    die "LINKWARDEN_BOOTSTRAP_USER doit contenir entre 3 et 50 caractères"
  fi
  if [ "${#LINKWARDEN_BOOTSTRAP_PASSWORD}" -lt 8 ]; then
    die "LINKWARDEN_BOOTSTRAP_PASSWORD doit contenir au moins 8 caractères"
  fi

  log "Compte initial Linkwarden"

  final_disable_registration=$LINKWARDEN_DISABLE_REGISTRATION
  LINKWARDEN_DISABLE_REGISTRATION=false
  write_service_env linkwarden
  LINKWARDEN_DISABLE_REGISTRATION=$final_disable_registration

  /usr/local/sbin/vps-image-lock linkwarden
  /usr/local/sbin/vps-compose linkwarden up -d
  wait_for_linkwarden \
    || die "Linkwarden ne répond pas sur http://127.0.0.1:3001"

  response_file=$(mktemp)
  status=$(
    jq -n \
      --arg username "$LINKWARDEN_BOOTSTRAP_USER" \
      --arg name "${LINKWARDEN_BOOTSTRAP_NAME:-$LINKWARDEN_BOOTSTRAP_USER}" \
      --arg password "$LINKWARDEN_BOOTSTRAP_PASSWORD" \
      '{
        username: $username,
        name: $name,
        password: $password,
        invite: false,
        acceptPromotionalEmails: false
      }' \
      | curl -sS -o "$response_file" -w '%{http_code}' \
          -H 'Content-Type: application/json' \
          --data-binary @- \
          http://127.0.0.1:3001/api/v1/users
  )

  case "$status:$(cat "$response_file")" in
    201:*)
      echo "Compte Linkwarden créé : $LINKWARDEN_BOOTSTRAP_USER"
      ;;
    400:*"Email or Username already exists"*)
      echo "Compte Linkwarden déjà présent : $LINKWARDEN_BOOTSTRAP_USER"
      ;;
    *)
      cat "$response_file" >&2
      rm -f "$response_file"
      die "création du compte Linkwarden impossible, statut HTTP $status"
      ;;
  esac
  rm -f "$response_file"

  write_service_env linkwarden
  /usr/local/sbin/vps-compose linkwarden up -d
}

install_services() {
  log "Projets Docker applicatifs"
  if [ "${INSTALL_DATABASES:-true}" = true ] \
    && [ ! -f /opt/selfhosted/databases/docker-compose.yml ]; then
    install_databases
  fi
  old_ifs=$IFS
  IFS=,
  for service in ${SERVICES:-}; do
    IFS=$old_ifs
    [ -n "$service" ] || continue
    source="$INSTALL_DIR/services/$service"
    [ -d "$source" ] || die "modèle de service absent : $service"
    ensure_database_network_for_service "$service"
    copy_stack "$service" "$source"
    if [ "$service" = kill-newsletter ]; then
      prepare_kill_newsletter_source
    fi
    write_service_env "$service"
    if [ "$service" = web ]; then
      create_web_subdomain_directories
    fi
    chown root:root "/opt/selfhosted/$service"
    chown root:root "/opt/selfhosted/$service/docker-compose.yml"
    if [ "$service" = linkwarden ]; then
      bootstrap_linkwarden_user
    fi
    if [ "${AUTO_START_SERVICES:-false}" = true ]; then
      /usr/local/sbin/vps-image-lock "$service"
      /usr/local/sbin/vps-compose "$service" up -d
    fi
    IFS=,
  done
  IFS=$old_ifs
}

install_gateway() {
  [ "${INSTALL_GATEWAY:-true}" = true ] || return 0
  log "Nginx et Certbot dans Docker"
  DEBIAN_FRONTEND=noninteractive apt-get install -y apache2-utils
  copy_stack gateway "$INSTALL_DIR/gateway"

  umask 077
  cat > /opt/selfhosted/gateway/.env <<EOF
NGINX_VERSION=$NGINX_VERSION
CERTBOT_VERSION=$CERTBOT_VERSION
ADMIN_EMAIL=$ADMIN_EMAIL
LINKWARDEN_DOMAIN=$LINKWARDEN_DOMAIN
DAVIS_DOMAIN=$DAVIS_DOMAIN
FRESHRSS_DOMAIN=$FRESHRSS_DOMAIN
TTRSS_DOMAIN=$TTRSS_DOMAIN
NEWSLETTER_DOMAIN=$NEWSLETTER_DOMAIN
WEB_DOMAIN=$WEB_DOMAIN
WEB_SUBDOMAINS=${WEB_SUBDOMAINS:-}
WEB_SERVER_NAMES=$(compose_env_quote "$(web_server_names)")
MONITORING_DOMAIN=$MONITORING_DOMAIN
NGINX_MEMORY_LIMIT=$NGINX_MEMORY_LIMIT
CERTBOT_MEMORY_LIMIT=$CERTBOT_MEMORY_LIMIT
EOF
  chmod 0600 /opt/selfhosted/gateway/.env

  install -d -m 0750 /opt/selfhosted/gateway/nginx/auth
  htpasswd -bcB \
    /opt/selfhosted/gateway/nginx/auth/.htpasswd-monitoring \
    observateur "$GRAFANA_HTTP_PASSWORD"
  chmod 0640 /opt/selfhosted/gateway/nginx/auth/.htpasswd-monitoring
  install -m 0644 "$INSTALL_DIR/system/logrotate/nginx-container" \
    /etc/logrotate.d/nginx-container

  install -m 0755 /opt/selfhosted/gateway/scripts/vps-gateway \
    /usr/local/sbin/vps-gateway
  /usr/local/sbin/vps-image-lock gateway
  /usr/local/sbin/vps-gateway start-http
}

install_monitoring() {
  [ "${INSTALL_MONITORING:-true}" = true ] || return 0
  log "Supervision Docker"
  copy_stack monitoring "$INSTALL_DIR/monitoring"

  umask 077
  cat > /opt/selfhosted/monitoring/.env <<EOF
GRAFANA_VERSION=$GRAFANA_VERSION
PROMETHEUS_VERSION=$PROMETHEUS_VERSION
PROMETHEUS_RETENTION_TIME=${PROMETHEUS_RETENTION_TIME:-7d}
PROMETHEUS_RETENTION_SIZE=${PROMETHEUS_RETENTION_SIZE:-512MB}
NODE_EXPORTER_VERSION=$NODE_EXPORTER_VERSION
CADVISOR_IMAGE=${CADVISOR_IMAGE:-ghcr.io/google/cadvisor:v0.57.0}
LOKI_VERSION=$LOKI_VERSION
ALLOY_VERSION=$ALLOY_VERSION
ALPINE_VERSION=$ALPINE_VERSION
MONITORING_DOMAIN=$MONITORING_DOMAIN
GRAFANA_MEMORY_LIMIT=$GRAFANA_MEMORY_LIMIT
PROMETHEUS_MEMORY_LIMIT=$PROMETHEUS_MEMORY_LIMIT
NODE_EXPORTER_MEMORY_LIMIT=$NODE_EXPORTER_MEMORY_LIMIT
CADVISOR_MEMORY_LIMIT=$CADVISOR_MEMORY_LIMIT
LOKI_INIT_MEMORY_LIMIT=$LOKI_INIT_MEMORY_LIMIT
LOKI_MEMORY_LIMIT=$LOKI_MEMORY_LIMIT
ALLOY_MEMORY_LIMIT=$ALLOY_MEMORY_LIMIT
EOF
  chmod 0600 /opt/selfhosted/monitoring/.env

  install -d -m 0755 /var/lib/node-exporter/textfile
  install -m 0755 /opt/selfhosted/monitoring/scripts/vps-monitoring \
    /usr/local/sbin/vps-monitoring
  install -m 0755 /opt/selfhosted/monitoring/scripts/vps-local-metrics \
    /usr/local/sbin/vps-local-metrics
  install -m 0644 \
    /opt/selfhosted/monitoring/etc/systemd/vps-local-metrics.service \
    /etc/systemd/system/vps-local-metrics.service
  install -m 0644 \
    /opt/selfhosted/monitoring/etc/systemd/vps-local-metrics.timer \
    /etc/systemd/system/vps-local-metrics.timer

  cat > /etc/default/vps-monitoring <<EOF
ENABLE_LOGS=${ENABLE_LOGS:-false}
ENABLE_CONTAINER_METRICS=${ENABLE_CONTAINER_METRICS:-false}
ENABLE_LOCAL_METRICS=true
EOF
  chmod 0644 /etc/default/vps-monitoring
  /usr/local/sbin/vps-image-lock monitoring
  /usr/local/sbin/vps-monitoring apply
  systemctl daemon-reload
  systemctl enable --now vps-local-metrics.timer
}

finalize_ssh() {
  log "Finalisation du port SSH"
  echo "Cette étape ferme le port 22 et conserve uniquement le port $SSH_PORT."
  printf "Une connexion SSH et SFTP sur le nouveau port a-t-elle été testée ? [oui/N] "
  read -r answer
  [ "$answer" = oui ] || die "finalisation annulée"
  FINALIZE_SSH=true
  write_ssh_configuration
  write_firewall
  install_fail2ban
  echo "Le port 22 temporaire a été retiré."
}

run_phase() {
  case "$1" in
    all)
      install_base
      write_ssh_configuration
      write_firewall
      install_fail2ban
      install_docker
      install_databases
      install_services
      install_gateway
      install_monitoring
      ;;
    base) install_base ;;
    ssh) write_ssh_configuration ;;
    firewall)
      write_firewall
      install_fail2ban
      ;;
    docker) install_docker ;;
    databases) install_databases ;;
    services) install_services ;;
    gateway) install_gateway ;;
    monitoring) install_monitoring ;;
    *) die "phase inconnue : $1" ;;
  esac
}

require_root
load_configuration
apply_resource_profile
check_debian

if [ "$FINALIZE_SSH" = true ]; then
  finalize_ssh
else
  run_phase "$PHASE"
fi

log "Installation terminée"
echo "Tester dans un second terminal :"
echo "  ssh -p $SSH_PORT $ADMIN_USER@IP_DU_SERVEUR"
if [ "${ENABLE_SFTP:-true}" = true ]; then
  echo "  sftp -P $SSH_PORT $SFTP_USER@IP_DU_SERVEUR"
fi
