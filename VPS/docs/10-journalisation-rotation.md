# Journalisation, rotation et rétention

## Objectif

Empêcher tout journal persistant de croître sans limite. Cette politique couvre :

- le journal systemd et les messages du noyau ;
- Fail2ban ;
- Nginx ;
- Certbot ;
- Grafana, Prometheus et Node Exporter ;
- les journaux des conteneurs Docker ;
- les rapports sous `/var/log/server-checks` ;
- msmtp ;
- les journaux standards gérés par les paquets Debian.

Les sauvegardes applicatives ne sont pas des journaux. Leur rétention est gérée
séparément dans [Maintenance et mises à jour](06-maintenance-mises-a-jour.md).

## Règle pour tout nouveau service

- Un service systemd doit écrire dans stdout/stderr afin d'être collecté par
  journald.
- Un conteneur doit écrire dans stdout/stderr afin d'être collecté par le
  pilote Docker `journald`.
- Un fichier écrit directement sous `/var/log` doit avoir exactement une règle
  `logrotate`, fournie par Debian ou ajoutée localement.
- Un journal écrit dans un volume Docker n'est pas couvert par le pilote
  Docker. Il faut activer la rotation interne de l'application ou ajouter une
  règle dédiée sur le chemin monté depuis l'hôte.
- Aucun journal persistant ne doit être écrit sous `/tmp`.

Cette règle évite qu'un futur service contourne silencieusement la politique.

## Politique de rétention

| Source | Rotation | Rétention maximale |
| --- | --- | --- |
| journald, noyau, services systemd, Fail2ban et Docker | Automatique par taille et durée | 250 Mio et 14 jours au total |
| Nginx | Quotidienne, compressée | 14 rotations |
| Certbot | Rotation interne du conteneur | 30 archives maximum |
| Rapports généraux | Quotidienne, compressée | 14 rotations, 30 jours maximum |
| Rapports Docker Scout | Hebdomadaire, compressée | 8 rotations, 60 jours maximum |
| msmtp | Hebdomadaire, compressée | 8 rotations, 60 jours maximum |
| Loki, si activé | Compaction interne | 7 jours |

Adapter `SystemMaxUse` aux ressources du VPS. Les valeurs ci-dessus
privilégient un petit serveur.

## Installer et activer logrotate

```bash
sudo apt update
sudo apt install -y logrotate
sudo systemctl enable --now logrotate.timer
systemctl list-timers logrotate.timer
```

`logrotate` est lancé quotidiennement par systemd sur Debian.

## Rotation de journald

Créer le répertoire de journal persistant :

```bash
sudo mkdir -p /var/log/journal
sudo systemd-tmpfiles --create --prefix /var/log/journal
```

Créer :

```bash
sudo mkdir -p /etc/systemd/journald.conf.d
sudo nano /etc/systemd/journald.conf.d/10-retention.conf
```

Contenu :

```ini
[Journal]
Storage=persistent
Compress=yes
SystemMaxUse=250M
SystemKeepFree=1G
SystemMaxFileSize=25M
RuntimeMaxUse=50M
RuntimeMaxFileSize=10M
MaxFileSec=1day
MaxRetentionSec=14day
RateLimitIntervalSec=30s
RateLimitBurst=10000
```

Appliquer et nettoyer immédiatement l'historique dépassant les limites :

```bash
sudo systemctl restart systemd-journald
sudo journalctl --flush
sudo journalctl --rotate
sudo journalctl --vacuum-time=14d
sudo journalctl --vacuum-size=250M
journalctl --disk-usage
```

Les messages du noyau produits par les règles `IPT_PORTSCAN` sont inclus dans
journald et suivent donc cette rétention.

Grafana, Prometheus, Node Exporter, cAdvisor, Loki et Alloy sont des
conteneurs. Leurs messages écrits dans stdout/stderr rejoignent journald. La
base de métriques Prometheus et l'index Loki ont leurs propres rétentions
bornées dans [Dashboard d'observabilité](05-dashboard-observabilite.md).

## Journaux Fail2ban

Faire écrire Fail2ban directement dans journald plutôt que dans un fichier
séparé :

```bash
sudo nano /etc/fail2ban/fail2ban.local
```

Contenu :

```ini
[Definition]
logtarget = SYSTEMD-JOURNAL
loglevel = INFO
dbpurgeage = 7d
```

Vérifier :

```bash
sudo fail2ban-client -t
sudo systemctl restart fail2ban
sudo fail2ban-client get logtarget
sudo fail2ban-client get dbpurgeage
journalctl -u fail2ban --since today
```

La base SQLite de Fail2ban n'est pas un journal texte. `dbpurgeage` supprime
l'historique ancien des bannissements.

## Journaux Docker

Docker utilise par défaut le pilote `json-file`, sans rotation. La procédure
[Docker](02-docker.md) configure donc le pilote `journald` :

```json
{
  "log-driver": "journald",
  "log-opts": {
    "tag": "{{.Name}}",
    "labels": "com.docker.compose.project,com.docker.compose.service"
  },
  "metrics-addr": "127.0.0.1:9323",
  "experimental": true
}
```

Vérifier :

```bash
docker info --format '{{.LoggingDriver}}'
docker inspect --format '{{.Name}} {{.HostConfig.LogConfig.Type}} {{json .HostConfig.LogConfig.Config}}' $(docker ps -q)
```

La modification du pilote par défaut ne touche pas les conteneurs existants.
Après une sauvegarde, les recréer service par service :

```bash
cd /opt/selfhosted/NOM_DU_SERVICE
docker compose up -d --force-recreate
```

Ne jamais utiliser `logrotate` directement sur les fichiers internes de
`/var/lib/docker`. Seul le démon Docker doit les manipuler. Les journaux Docker
sont désormais inclus dans la limite globale de journald.

La centralisation dans Loki est facultative. Lorsque `ENABLE_LOGS=false`,
Alloy et Loki sont arrêtés, mais les journaux locaux restent disponibles avec
`journalctl` et continuent de respecter les limites de journald.

## Journaux Nginx

Le conteneur Nginx écrit ses journaux dans le répertoire bind-monté
`/opt/selfhosted/gateway/logs/nginx`.

Préparer les fichiers :

```bash
sudo install -d -m 0750 -o root -g adm \
  /opt/selfhosted/gateway/logs/nginx
sudo touch \
  /opt/selfhosted/gateway/logs/nginx/access.log \
  /opt/selfhosted/gateway/logs/nginx/error.log
sudo chown root:adm /opt/selfhosted/gateway/logs/nginx/*.log
sudo chmod 0640 /opt/selfhosted/gateway/logs/nginx/*.log
```

Créer `/etc/logrotate.d/nginx-container` :

```text
/opt/selfhosted/gateway/logs/nginx/*.log {
    daily
    rotate 14
    maxage 30
    maxsize 50M
    missingok
    notifempty
    compress
    delaycompress
    dateext
    create 0640 root adm
    su root adm
    sharedscripts
    postrotate
        /usr/bin/docker compose -f /opt/selfhosted/gateway/docker-compose.yml kill -s USR1 nginx >/dev/null 2>&1 || true
    endscript
}
```

Le signal `USR1` demande au processus maître Nginx de rouvrir ses fichiers sans
interrompre les connexions.

## Journaux Certbot

Le conteneur Certbot écrit dans le répertoire bind-monté
`/opt/selfhosted/gateway/certbot/logs`. Sa rotation interne est conservée.

Créer `/opt/selfhosted/gateway/certbot/conf/cli.ini` :

```ini
max-log-backups = 30
```

Vérifier depuis le conteneur :

```bash
docker compose \
  -f /opt/selfhosted/gateway/docker-compose.yml \
  run --rm certbot --help all | grep -A2 max-log-backups
```

Ne pas mettre `max-log-backups = 0` : cette valeur désactive la rotation
interne.

## Rapports personnalisés

Préparer les répertoires et fichiers :

```bash
sudo install -d -m 0750 -o root -g adm /var/log/server-checks
sudo install -d -m 0750 -o root -g adm /var/log/server-checks/docker-images

sudo touch \
  /var/log/server-checks/health-report.txt \
  /var/log/server-checks/kernel-check.txt \
  /var/log/server-checks/certificates.txt \
  /var/log/server-checks/docker-image-updates.txt \
  /var/log/server-checks/certbot-dry-run.txt \
  /var/log/server-checks/docker-images/cve-report.txt

sudo chown root:adm /var/log/server-checks/*.txt
sudo chown root:adm /var/log/server-checks/docker-images/*
sudo chmod 0640 /var/log/server-checks/*.txt
sudo chmod 0640 /var/log/server-checks/docker-images/*
```

Créer :

```bash
sudo nano /etc/logrotate.d/server-checks
```

Contenu :

```text
/var/log/server-checks/*.txt /var/log/server-checks/*.log {
    daily
    rotate 14
    maxage 30
    maxsize 10M
    missingok
    notifempty
    compress
    delaycompress
    dateext
    create 0640 root adm
    su root adm
}

/var/log/server-checks/docker-images/*.txt {
    weekly
    rotate 8
    maxage 60
    maxsize 50M
    missingok
    notifempty
    compress
    delaycompress
    dateext
    create 0640 root adm
    su root adm
}
```

Les scripts ouvrent les rapports à chaque exécution et ne gardent pas les
descripteurs ouverts. `copytruncate` n'est donc pas nécessaire.

La sauvegarde et la maintenance nocturne écrivent dans journald via leur
service systemd. Elles suivent donc la limite globale de 250 Mio et 14 jours.

Les motifs prennent aussi en charge les futurs rapports ayant les mêmes
extensions. Toute nouvelle extension doit être ajoutée explicitement à cette
règle.

## Journal msmtp

Créer le fichier avec des droits restrictifs :

```bash
sudo touch /var/log/msmtp.log
sudo chown root:adm /var/log/msmtp.log
sudo chmod 0640 /var/log/msmtp.log
```

Créer :

```bash
sudo nano /etc/logrotate.d/msmtp-local
```

Contenu :

```text
/var/log/msmtp.log {
    weekly
    rotate 8
    maxage 60
    maxsize 10M
    missingok
    notifempty
    compress
    delaycompress
    dateext
    create 0640 root adm
    su root adm
}
```

Chaque exécution de msmtp ouvre puis ferme le fichier ; aucun signal de
réouverture n'est nécessaire.

## Journaux standards Debian

Les paquets Debian installent normalement leurs propres fichiers sous
`/etc/logrotate.d`, notamment pour APT, dpkg, alternatives, `wtmp`, `btmp`,
rsyslog s'il est installé et parfois Fail2ban.

Lister les règles :

```bash
sudo ls -1 /etc/logrotate.d/
sudo logrotate --debug /etc/logrotate.conf
```

Ne pas dupliquer une règle fournie par un paquet. Une double déclaration peut
provoquer une erreur ou une rotation incohérente.

## Test complet

Tester la configuration sans modifier les fichiers :

```bash
sudo logrotate --debug /etc/logrotate.conf
```

Forcer une rotation de test après vérification de la sortie :

```bash
sudo logrotate --force --verbose /etc/logrotate.conf
```

Vérifier :

```bash
systemctl status logrotate.timer --no-pager
journalctl --disk-usage
docker info --format '{{.LoggingDriver}}'
sudo find /var/log -xdev -type f -size +50M -printf '%s %p\n' | sort -nr
sudo du -sh /var/log /var/lib/docker
```

## Audit périodique

Ajouter au rapport mensuel ou exécuter manuellement :

```bash
sudo find /var/log -xdev -type f -size +100M -printf '%TY-%Tm-%Td %s %p\n'
docker ps --format '{{.Names}}' | while read -r CONTAINER; do
  docker inspect --format '{{.Name}} {{.HostConfig.LogConfig.Type}} {{json .HostConfig.LogConfig.Config}}' "$CONTAINER"
done
```

Un fichier dépassant 100 Mio doit être expliqué, rattaché à une règle de
rotation et ramené à une taille compatible avec l'espace disque disponible.

## Références

- [Debian : logrotate](https://manpages.debian.org/logrotate)
- [Debian : journald.conf](https://manpages.debian.org/trixie/systemd/journald.conf.5.en.html)
- [Docker : configuration des pilotes de journalisation](https://docs.docker.com/engine/logging/configure/)
- [Docker : pilote journald](https://docs.docker.com/engine/logging/drivers/journald/)
- [Nginx : rotation et réouverture des journaux](https://nginx.org/en/docs/control.html#logs)
- [Certbot : rotation des journaux](https://eff-certbot.readthedocs.io/en/stable/using.html#log-rotation)
