# Supervision et rapports

## Objectif

Installer une supervision web en lecture seule, les contrôles périodiques,
l'analyse des CVE avec Docker Scout, le contrôle des certificats TLS et les
rapports.

## Supervision web en lecture seule

### Architecture retenue

```text
Navigateur
  |
  | HTTPS et authentification HTTP Nginx
  v
Nginx
  |
  | 127.0.0.1:3000
  v
Grafana en conteneur, rôle Viewer
  |
  | 127.0.0.1:9090
  v
Prometheus en conteneur
  |
  +-- 127.0.0.1:9100 : Node Exporter
  +-- 127.0.0.1:9323 : métriques Docker
  +-- 127.0.0.1:8080 : cAdvisor, facultatif

Grafana
  |
  +-- 127.0.0.1:3100 : Loki, facultatif
       ^
       |
     Alloy, facultatif
```

Cette chaîne affiche les métriques de l'hôte sans fournir de terminal, de
gestionnaire de paquets, de bouton de redémarrage ou de contrôle des services.
Grafana, Prometheus, Node Exporter, Loki et Alloy n'accèdent pas au socket
Docker. cAdvisor, lorsqu'il est activé, monte `/var/run` et accède donc au socket Docker afin de
produire les métriques par conteneur. Le montage de fichier est en lecture
seule, mais cela ne rend pas l'API du socket Docker elle-même non modifiable.
Son port reste strictement local et il est désactivé par défaut. L'analyse des
CVE utilise le binaire Docker Scout sur l'hôte et ne transmet pas le socket à
un conteneur d'analyse.

Grafana et cAdvisor restent des composants à maintenir à jour : cette
architecture réduit les privilèges et l'exposition, mais ne supprime pas toute
surface d'attaque.

La configuration complète, le dashboard provisionné et le flag des journaux
sont décrits dans
[Dashboard d'observabilité](11-dashboard-observabilite.md). Les extraits
Compose ci-dessous constituent uniquement le socle minimal historique. Pour le
déploiement retenu, utiliser les fichiers sous `install/monitoring` et ne pas
fusionner manuellement les deux fichiers Compose.

### Retirer Cockpit

Si Cockpit a déjà été installé :

```bash
sudo systemctl disable --now cockpit.socket 2>/dev/null || true
sudo apt purge -y cockpit cockpit-system cockpit-storaged cockpit-packagekit
```

Supprimer également toute règle autorisant le port Cockpit `9090` depuis
Internet dans `/etc/iptables/rules.v4` et `/etc/iptables/rules.v6`. Tester puis
appliquer les fichiers corrigés :

```bash
sudo iptables-restore --test /etc/iptables/rules.v4
sudo ip6tables-restore --test /etc/iptables/rules.v6
sudo iptables-apply -t 30 /etc/iptables/rules.v4
sudo ip6tables-apply -t 30 /etc/iptables/rules.v6
sudo systemctl restart docker
```

Prometheus réutilise le numéro `9090`, mais écoute uniquement sur
`127.0.0.1`. Aucune règle publique n'est nécessaire.

### Préparer le projet Compose

Créer l'arborescence :

```bash
sudo mkdir -p \
  /opt/selfhosted/monitoring/prometheus \
  /opt/selfhosted/monitoring/grafana/provisioning/datasources \
  /opt/selfhosted/monitoring/grafana/provisioning/dashboards \
  /opt/selfhosted/monitoring/grafana/dashboards
sudo chown -R lucas:lucas /opt/selfhosted/monitoring
cd /opt/selfhosted/monitoring
```

Les versions stables vérifiées le 6 juin 2026 sont inscrites dans `.env`.
Consulter les notes de publication avant chaque changement :

```bash
nano .env
```

Contenu :

```bash
GRAFANA_VERSION=13.0.1-security-01
PROMETHEUS_VERSION=v3.12.0-distroless
NODE_EXPORTER_VERSION=v1.11.1-distroless
MONITORING_DOMAIN=monitoring.example.fr
```

Ne pas utiliser `latest` : des tags explicites rendent le déploiement
reproductible et permettent un retour à la version précédente.

### Configurer Prometheus

Créer `prometheus/prometheus.yml` :

```bash
nano prometheus/prometheus.yml
```

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets:
          - 127.0.0.1:9090

  - job_name: node
    static_configs:
      - targets:
          - 127.0.0.1:9100
```

### Provisionner Grafana

Créer `grafana/provisioning/datasources/prometheus.yml` :

```bash
nano grafana/provisioning/datasources/prometheus.yml
```

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    uid: prometheus
    type: prometheus
    access: proxy
    url: http://127.0.0.1:9090
    isDefault: true
    editable: false
```

Créer `grafana/provisioning/dashboards/default.yml` :

```bash
nano grafana/provisioning/dashboards/default.yml
```

```yaml
apiVersion: 1

providers:
  - name: Supervision
    orgId: 1
    folder: Serveur
    type: file
    disableDeletion: true
    editable: false
    options:
      path: /etc/grafana/dashboards
```

Télécharger le tableau de bord Node Exporter Full dans le projet :

```bash
curl -fL -o grafana/dashboards/node-exporter-full.json \
  https://grafana.com/api/dashboards/1860/revisions/latest/download
sed -i 's/${ds_prometheus}/prometheus/g' \
  grafana/dashboards/node-exporter-full.json
```

Le tableau de bord est provisionné en lecture seule. Aucun compte
administrateur Grafana n'est nécessaire pour l'exploitation courante.

### Créer le fichier Compose

Créer `docker-compose.yml` :

```bash
nano docker-compose.yml
```

```yaml
services:
  grafana:
    image: grafana/grafana:${GRAFANA_VERSION}
    container_name: grafana
    user: "472"
    restart: unless-stopped
    network_mode: host
    depends_on:
      - prometheus
    environment:
      GF_SERVER_HTTP_ADDR: 127.0.0.1
      GF_SERVER_HTTP_PORT: "3000"
      GF_SERVER_DOMAIN: ${MONITORING_DOMAIN}
      GF_SERVER_ROOT_URL: https://${MONITORING_DOMAIN}/
      GF_SECURITY_DISABLE_INITIAL_ADMIN_CREATION: "true"
      GF_SECURITY_DISABLE_GRAVATAR: "true"
      GF_SECURITY_COOKIE_SECURE: "true"
      GF_SECURITY_COOKIE_SAMESITE: strict
      GF_SECURITY_ALLOW_EMBEDDING: "false"
      GF_SECURITY_DATA_SOURCE_PROXY_WHITELIST: 127.0.0.1:9090
      GF_USERS_ALLOW_SIGN_UP: "false"
      GF_USERS_ALLOW_ORG_CREATE: "false"
      GF_USERS_VIEWERS_CAN_EDIT: "false"
      GF_AUTH_DISABLE_LOGIN_FORM: "true"
      GF_AUTH_BASIC_ENABLED: "false"
      GF_AUTH_ANONYMOUS_ENABLED: "true"
      GF_AUTH_ANONYMOUS_ORG_NAME: Main Org.
      GF_AUTH_ANONYMOUS_ORG_ROLE: Viewer
      GF_AUTH_ANONYMOUS_HIDE_VERSION: "true"
      GF_EXPLORE_ENABLED: "false"
      GF_QUERY_HISTORY_ENABLED: "false"
      GF_PLUGINS_PLUGIN_ADMIN_ENABLED: "false"
      GF_PANELS_DISABLE_SANITIZE_HTML: "false"
      GF_ANALYTICS_REPORTING_ENABLED: "false"
      GF_ANALYTICS_CHECK_FOR_UPDATES: "false"
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - ./grafana/dashboards:/etc/grafana/dashboards:ro
    read_only: true
    tmpfs:
      - /tmp:size=64m,mode=1777
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true

  prometheus:
    image: prom/prometheus:${PROMETHEUS_VERSION}
    container_name: prometheus
    user: "65534:65534"
    restart: unless-stopped
    network_mode: host
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --web.listen-address=127.0.0.1:9090
      - --storage.tsdb.path=/prometheus
      - --storage.tsdb.retention.time=7d
      - --storage.tsdb.retention.size=512MB
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    read_only: true
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true

  node-exporter:
    image: prom/node-exporter:${NODE_EXPORTER_VERSION}
    container_name: node-exporter
    user: "65534:65534"
    restart: unless-stopped
    network_mode: host
    pid: host
    command:
      - --path.rootfs=/host
      - --web.listen-address=127.0.0.1:9100
      - --collector.processes
      - --collector.filesystem.mount-points-exclude=^/(dev|proc|sys|run|var/lib/docker/.+)($|/)
    volumes:
      - /:/host:ro,rslave
    read_only: true
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true

volumes:
  grafana_data:
    name: monitoring_grafana_data
  prometheus_data:
    name: monitoring_prometheus_data
```

Le mode réseau `host` est nécessaire à Node Exporter pour observer correctement
les interfaces réseau de l'hôte. Les trois services imposent néanmoins une
écoute sur `127.0.0.1`; aucun port Compose n'est publié.

Node Exporter reçoit une vue en lecture seule de la racine et de l'espace PID
de l'hôte. Cela lui permet de lire les métriques, mais pas d'administrer le
système. Il n'a aucune capacité Linux additionnelle et ne reçoit jamais le
socket Docker.

### Valider et démarrer

```bash
cd /opt/selfhosted/monitoring
docker compose config
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100
```

Vérifier les écoutes :

```bash
curl -fsS http://127.0.0.1:3000/api/health
curl -fsS http://127.0.0.1:9090/-/ready
curl -fsS http://127.0.0.1:9100/metrics >/dev/null
sudo ss -ltnp | grep -E ':(3000|9090|9100)\b'
```

Les trois adresses doivent commencer par `127.0.0.1`.

### Publier Grafana derrière Nginx

Créer un mot de passe distinct du compte système et du compte administrateur
Grafana :

```bash
sudo apt install -y apache2-utils
sudo htpasswd -B -C 12 -c \
  /opt/selfhosted/gateway/nginx/auth/.htpasswd-monitoring \
  observateur
sudo chown root:root \
  /opt/selfhosted/gateway/nginx/auth/.htpasswd-monitoring
sudo chmod 0640 \
  /opt/selfhosted/gateway/nginx/auth/.htpasswd-monitoring
```

Créer
`/opt/selfhosted/gateway/nginx/conf.d/70-monitoring.conf` :

```nginx
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name monitoring.example.fr;

    location / {
        auth_basic "Supervision";
        auth_basic_user_file /etc/nginx/auth/.htpasswd-monitoring;

        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

Le domaine `monitoring.example.fr` est déjà inclus dans le certificat SAN
obtenu dans [Nginx et Certbot dans Docker](09-nginx-certbot.md). Vérifier et
recharger :

```bash
cd /opt/selfhosted/gateway
docker compose exec nginx nginx -t
docker compose exec nginx nginx -s reload
```

Ne jamais saisir le mot de passe de supervision sur une URL en HTTP.

Ajouter la protection contre les essais de mot de passe dans
`/etc/fail2ban/jail.d/monitoring-nginx.local` :

```ini
[nginx-http-auth]
enabled = true
port = http,https
logpath = /opt/selfhosted/gateway/logs/nginx/error.log
maxretry = 5
findtime = 10m
bantime = 1h
```

Tester et appliquer :

```bash
sudo fail2ban-client -t
sudo systemctl restart fail2ban
sudo fail2ban-client status nginx-http-auth
sudo ss -ltnp | grep -E ':(3000|9090|9100)\b'
```

Les trois adresses doivent commencer par `127.0.0.1`. L'accès utilisateur est :

```text
https://monitoring.example.fr
```

Un utilisateur `Viewer` peut exécuter des requêtes de lecture sur la seule
source Prometheus autorisée. Cette source ne doit donc contenir ni secret ni
donnée applicative sensible. Toute modification des tableaux de bord doit être
faite dans les fichiers provisionnés, puis appliquée avec :

```bash
cd /opt/selfhosted/monitoring
docker compose restart grafana
```

### Mettre à jour la supervision

Ne pas exécuter une mise à jour automatique aveugle. Lire les notes de
publication, sauvegarder, puis modifier les versions dans `.env` :

```bash
cd /opt/selfhosted/monitoring
docker compose config
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100
curl -fsS http://127.0.0.1:3000/api/health
curl -fsS http://127.0.0.1:9090/-/ready
```

En cas de régression, remettre les anciens tags dans `.env` puis relancer
`docker compose up -d`.

### Migrer vers un autre VPS

Copier sur le nouvel hôte :

- le dossier `/opt/selfhosted/monitoring` ;
- la dernière archive `grafana-data_*.tar.gz` ;
- la configuration Nginx et le fichier d'authentification, par un canal sûr.

Restaurer le volume Grafana avant le premier démarrage :

```bash
docker volume create monitoring_grafana_data
docker run --rm \
  -v monitoring_grafana_data:/target \
  -v /CHEMIN_DES_SAUVEGARDES:/backup:ro \
  alpine:3.22 \
  tar -xzf /backup/grafana-data_DATE.tar.gz -C /target

cd /opt/selfhosted/monitoring
docker compose config
docker compose pull
docker compose up -d
```

Ne pas copier le fichier `.htpasswd-monitoring` dans un dépôt public.
Prometheus recrée son volume et son historique de métriques sur le nouvel hôte.

## Répertoire des rapports

```bash
sudo mkdir -p /var/log/server-checks/docker-images
sudo chown -R root:adm /var/log/server-checks
sudo chmod 0750 /var/log/server-checks /var/log/server-checks/docker-images
```

Ces fichiers sont gérés par la politique
[Journalisation, rotation et rétention](16-journalisation-rotation.md).

## Vérification du noyau et du redémarrage

```bash
sudo nano /usr/local/sbin/check-kernel-reboot.sh
```

```bash
#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="/var/log/server-checks"
REPORT="$REPORT_DIR/kernel-check.txt"

mkdir -p "$REPORT_DIR"

{
  echo "===== Vérification du noyau ====="
  date -Is
  echo
  echo "Noyau actif :"
  uname -r
  echo
  echo "Derniers noyaux installés :"
  dpkg -l 'linux-image-*' 2>/dev/null | awk '/^ii/ {print $2}' | sort -V | tail -n 5
  echo
  echo "Redémarrage requis :"
  if [ -f /var/run/reboot-required ]; then
    cat /var/run/reboot-required
    [ -f /var/run/reboot-required.pkgs ] && cat /var/run/reboot-required.pkgs
  else
    echo "Non"
  fi
  echo
  echo "Paquets à mettre à jour :"
  apt list --upgradable 2>/dev/null || true
} > "$REPORT"

cat "$REPORT"
```

```bash
sudo chmod +x /usr/local/sbin/check-kernel-reboot.sh
sudo /usr/local/sbin/check-kernel-reboot.sh
```

## Vérification des images Docker

Ce script télécharge les nouvelles images pour comparaison, mais ne recrée pas
les conteneurs.

```bash
sudo nano /usr/local/sbin/check-docker-image-updates.sh
```

```bash
#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="/var/log/server-checks"
REPORT="$REPORT_DIR/docker-image-updates.txt"
PULL_LOG="$(mktemp)"

trap 'rm -f "$PULL_LOG"' EXIT

mkdir -p "$REPORT_DIR"

{
  echo "===== Vérification des mises à jour des images Docker ====="
  date -Is
  echo

  docker ps --format '{{.Image}}' | sort -u | while read -r IMAGE; do
    echo "### $IMAGE"

    BEFORE_ID="$(docker image inspect "$IMAGE" --format '{{.Id}}' 2>/dev/null || true)"
    echo "Image locale avant téléchargement : $BEFORE_ID"

    : > "$PULL_LOG"
    docker pull "$IMAGE" >"$PULL_LOG" 2>&1 || {
      echo "Erreur pendant la commande docker pull :"
      cat "$PULL_LOG"
      echo
      continue
    }

    AFTER_ID="$(docker image inspect "$IMAGE" --format '{{.Id}}' 2>/dev/null || true)"
    echo "Image locale après téléchargement : $AFTER_ID"

    if [ "$BEFORE_ID" != "$AFTER_ID" ]; then
      echo "MISE À JOUR DISPONIBLE / IMAGE TÉLÉCHARGÉE"
      echo "Action requise : redémarrer le service concerné après sauvegarde."
    else
      echo "OK : image déjà à jour"
    fi

    echo
  done

  echo "===== Conteneurs actifs ====="
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
} > "$REPORT"

cat "$REPORT"
```

```bash
sudo chmod +x /usr/local/sbin/check-docker-image-updates.sh
sudo /usr/local/sbin/check-docker-image-updates.sh
```

## Analyse des CVE avec Docker Scout

L'installateur déploie `/usr/local/sbin/vps-image-audit`. Docker Scout doit
être installé sur l'hôte selon sa
[procédure officielle](https://docs.docker.com/scout/install/).

```bash
sudo vps-image-audit
less /var/log/server-checks/docker-images/cve-report.txt
```

Le script analyse les images locales configurées par les projets Compose. Il
n'exécute pas de conteneur d'analyse avec `/var/run/docker.sock`.

## Vérification des certificats

```bash
sudo nano /usr/local/sbin/check-certificates.sh
```

```bash
#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="/var/log/server-checks"
REPORT="$REPORT_DIR/certificates.txt"

DOMAINS=(
  "links.example.fr"
  "dav.example.fr"
  "newsletter.example.fr"
  "freshrss.example.fr"
  "ttrss.example.fr"
  "web.example.fr"
  "monitoring.example.fr"
)

mkdir -p "$REPORT_DIR"

{
  echo "===== Vérification des certificats ====="
  date -Is
  echo

  docker compose \
    -f /opt/selfhosted/gateway/docker-compose.yml \
    run --rm certbot certificates || true
  echo

  for DOMAIN in "${DOMAINS[@]}"; do
    echo "### $DOMAIN"

    EXPIRY_RAW="$(
      echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN:443" 2>/dev/null \
      | openssl x509 -noout -enddate 2>/dev/null \
      | cut -d= -f2 || true
    )"

    if [ -z "$EXPIRY_RAW" ]; then
      echo "Erreur : certificat non récupérable"
      echo
      continue
    fi

    EXPIRY_EPOCH="$(date -d "$EXPIRY_RAW" +%s)"
    NOW_EPOCH="$(date +%s)"
    DAYS_LEFT="$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))"

    echo "Expiration : $EXPIRY_RAW"
    echo "Jours restants : $DAYS_LEFT"

    if [ "$DAYS_LEFT" -lt 15 ]; then
      echo "ALERTE : certificat proche de l'expiration"
    else
      echo "OK"
    fi

    echo
  done
} > "$REPORT"

cat "$REPORT"
```

```bash
sudo chmod +x /usr/local/sbin/check-certificates.sh
sudo /usr/local/sbin/check-certificates.sh
```

## Rapport global

```bash
sudo nano /usr/local/sbin/server-health-report.sh
```

```bash
#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="/var/log/server-checks"
REPORT="$REPORT_DIR/health-report.txt"

mkdir -p "$REPORT_DIR"

{
  echo "===== RAPPORT D'ÉTAT DU SERVEUR ====="
  date -Is
  echo

  echo "===== Hôte ====="
  hostnamectl || true
  echo

  echo "===== Durée de fonctionnement ====="
  uptime
  echo

  echo "===== Disque ====="
  df -h
  echo

  echo "===== Mémoire ====="
  free -h
  echo

  echo "===== Noyau ====="
  uname -a
  if [ -f /var/run/reboot-required ]; then
    echo "Redémarrage requis : OUI"
    cat /var/run/reboot-required.pkgs 2>/dev/null || true
  else
    echo "Redémarrage requis : NON"
  fi
  echo

  echo "===== Mises à jour APT ====="
  apt list --upgradable 2>/dev/null || true
  echo

  echo "===== Nginx ====="
  docker compose -f /opt/selfhosted/gateway/docker-compose.yml ps || true
  docker compose -f /opt/selfhosted/gateway/docker-compose.yml exec -T nginx nginx -t || true
  echo

  echo "===== Certbot ====="
  docker compose -f /opt/selfhosted/gateway/docker-compose.yml run --rm certbot certificates || true
  echo

  echo "===== iptables IPv4 ====="
  iptables -L INPUT -n -v --line-numbers || true
  echo

  echo "===== iptables IPv6 ====="
  ip6tables -L INPUT -n -v --line-numbers || true
  echo

  echo "===== Persistance Netfilter ====="
  systemctl status netfilter-persistent --no-pager || true
  echo

  echo "===== Fail2ban ====="
  fail2ban-client status || true
  fail2ban-client status sshd || true
  echo

  echo "===== Conteneurs Docker ====="
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
  echo

  echo "===== Espace disque utilisé par Docker ====="
  docker system df || true
  echo

  echo "===== Rotation et volume des journaux ====="
  systemctl status logrotate.timer --no-pager || true
  journalctl --disk-usage || true
  docker info --format 'Pilote de journalisation Docker : {{.LoggingDriver}}' || true
  echo "Fichiers de plus de 100 Mio sous /var/log :"
  find /var/log -xdev -type f -size +100M -printf '%s %p\n' | sort -nr || true
  echo

  echo "===== Rapport de mise à jour des images Docker ====="
  if [ -f /var/log/server-checks/docker-image-updates.txt ]; then
    cat /var/log/server-checks/docker-image-updates.txt
  else
    echo "Pas encore généré"
  fi
  echo

  echo "===== Erreurs Nginx récentes ====="
  tail -n 100 /opt/selfhosted/gateway/logs/nginx/error.log 2>/dev/null || true
  echo

  echo "===== Supervision Prometheus et Grafana ====="
  docker compose -f /opt/selfhosted/monitoring/docker-compose.yml ps || true
  curl -fsS http://127.0.0.1:9090/-/ready || true
  curl -fsS http://127.0.0.1:3000/api/health || true
  docker system df -v || true
} > "$REPORT"

cat "$REPORT"
```

```bash
sudo chmod +x /usr/local/sbin/server-health-report.sh
sudo /usr/local/sbin/server-health-report.sh
```

## Planification

Les contrôles sont appelés par
`vps-nightly-maintenance.service` lorsqu'ils sont installés. La maintenance
commence vers `02:15`, l'audit des images est hebdomadaire et les mises à jour
APT sont terminées avant `05:00`.

```bash
systemctl list-timers vps-nightly-maintenance.timer \
  apt-daily.timer apt-daily-upgrade.timer
journalctl -u vps-nightly-maintenance.service -n 200
```

Ne pas ajouter une seconde planification cron pour ces commandes.

## Option de notification par courriel

```bash
sudo apt install -y bsd-mailx msmtp msmtp-mta
sudo nano /etc/msmtprc
```

Exemple :

```text
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account ionos
host smtp.ionos.fr
port 587
from contact@example.fr
user contact@example.fr
password MOT_DE_PASSE_SMTP

account default : ionos
```

```bash
sudo chmod 600 /etc/msmtprc
echo "Test mail serveur" | mail -s "Test VPS" contact@example.fr
```

Le journal `/var/log/msmtp.log` est inclus dans la politique de rotation.

## Références

- [Grafana : installation avec Docker](https://grafana.com/docs/grafana/latest/setup-grafana/installation/docker/)
- [Grafana : configuration de la sécurité](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/)
- [Grafana : configuration générale](https://grafana.com/docs/grafana/latest/installation/configuration/)
- [Grafana : tableau de bord Node Exporter Full](https://grafana.com/grafana/dashboards/1860-node-exporter-full/)
- [Grafana : versions publiées](https://github.com/grafana/grafana/releases)
- [Prometheus : installation avec Docker](https://prometheus.io/docs/prometheus/latest/installation/)
- [Prometheus : supervision avec Node Exporter](https://prometheus.io/docs/guides/node-exporter/)
- [Prometheus : versions publiées](https://github.com/prometheus/prometheus/releases)
- [Node Exporter : exécution avec Docker](https://github.com/prometheus/node_exporter#docker)
- [Docker : métriques Prometheus du démon](https://docs.docker.com/engine/daemon/prometheus/)
- [cAdvisor : exécution en conteneur](https://github.com/google/cadvisor/blob/master/docs/running.md)
- [Grafana Loki : installation avec Docker](https://grafana.com/docs/loki/latest/setup/install/docker/)
