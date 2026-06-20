# Dashboard d'observabilité

## Objectif

Déployer un tableau de bord Grafana en lecture seule couvrant :

- Debian, le processeur, la mémoire, le réseau et la partition racine ;
- le démon Docker et les conteneurs ;
- les besoins de maintenance locale ;
- les derniers succès des sauvegardes et du test de restauration ;
- les journaux systemd, Docker et Nginx, de manière facultative.

La configuration prête à déployer se trouve dans
[`install/monitoring`](../install/monitoring/README.md). Elle remplace les
extraits Compose minimaux de
[Supervision et rapports](10-supervision-rapports.md).

## Architecture

```text
Nginx public :443
  |
  v
Grafana 127.0.0.1:3000
  |
  +-- Prometheus 127.0.0.1:9090
  |     +-- Node Exporter 127.0.0.1:9100
  |     +-- Docker 127.0.0.1:9323
  |     +-- cAdvisor 127.0.0.1:8080, facultatif
  |
  +-- Loki 127.0.0.1:3100         facultatif
        ^
        |
      Alloy 127.0.0.1:12345       facultatif
        +-- journald : système et conteneurs
        +-- fichiers Nginx
```

Tous les ports techniques écoutent exclusivement sur `127.0.0.1`. Seul
Grafana est publié par le proxy Nginx en HTTPS avec authentification HTTP.

## Sources de données

| Source | Données | Rétention |
| --- | --- | --- |
| Node Exporter | CPU, mémoire, charge, disques, racine, inodes, réseau, processus | Prometheus, 7 jours et 512 Mio |
| Docker | état interne du démon | Prometheus, 7 jours et 512 Mio |
| cAdvisor, facultatif | CPU, mémoire, réseau et E/S par conteneur | Prometheus, 7 jours et 512 Mio |
| Script local | mises à jour APT, redémarrage, systemd, Fail2ban, conteneurs défaillants, sauvegardes et test de restauration | Prometheus, 7 jours et 512 Mio |
| Alloy et Loki | journald, conteneurs Docker et fichiers Nginx | 7 jours |

Le tableau de bord contient une section de journaux repliée par défaut. Si
Loki est désactivé, les autres panneaux continuent de fonctionner.

Les healthchecks Docker restent visibles dans le panneau « Conteneurs
défaillants » même lorsque cAdvisor est désactivé.

## Déployer les fichiers

Depuis la racine du dépôt copiée ou clonée sur Debian :

```bash
sudo install -d -m 0755 /opt/selfhosted/monitoring
sudo cp -a install/monitoring/. /opt/selfhosted/monitoring/
cd /opt/selfhosted/monitoring
sudo cp .env.example .env
sudo chown -R root:root /opt/selfhosted/monitoring
```

Modifier uniquement les valeurs locales :

```bash
sudo nano /opt/selfhosted/monitoring/.env
```

Le domaine doit correspondre au serveur Nginx :

```text
MONITORING_DOMAIN=monitoring.example.fr
```

Préparer le répertoire du collecteur textfile :

```bash
sudo install -d -m 0755 /var/lib/node-exporter/textfile
```

Installer les commandes et le flag :

```bash
sudo install -m 0755 \
  /opt/selfhosted/monitoring/scripts/vps-monitoring \
  /usr/local/sbin/vps-monitoring

sudo install -m 0755 \
  /opt/selfhosted/monitoring/scripts/vps-local-metrics \
  /usr/local/sbin/vps-local-metrics

sudo install -m 0644 \
  /opt/selfhosted/monitoring/etc/vps-monitoring \
  /etc/default/vps-monitoring

sudo install -m 0644 \
  /opt/selfhosted/monitoring/etc/systemd/vps-local-metrics.service \
  /etc/systemd/system/vps-local-metrics.service

sudo install -m 0644 \
  /opt/selfhosted/monitoring/etc/systemd/vps-local-metrics.timer \
  /etc/systemd/system/vps-local-metrics.timer

sudo systemctl daemon-reload
sudo systemctl enable --now vps-local-metrics.timer
```

## Configurer Docker

Le démon doit exposer ses métriques localement et envoyer les sorties des
conteneurs vers journald. Créer ou fusionner avec précaution
`/etc/docker/daemon.json` :

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

Ne pas écraser d'autres options existantes. Valider et appliquer :

```bash
sudo dockerd --validate --config-file=/etc/docker/daemon.json
sudo systemctl restart docker
docker info --format '{{.LoggingDriver}}'
curl -fsS http://127.0.0.1:9323/metrics >/dev/null
```

Le résultat du pilote doit être `journald`. Cette modification ne s'applique
qu'aux nouveaux conteneurs. Recréer progressivement les conteneurs existants
après sauvegarde :

```bash
cd /opt/selfhosted/NOM_DU_SERVICE
docker compose up -d --force-recreate
```

## Activer ou désactiver les journaux Grafana

Le fichier de contrôle est :

```text
/etc/default/vps-monitoring
```

Configuration sans indexation Loki :

```bash
ENABLE_LOGS=false
ENABLE_CONTAINER_METRICS=false
ENABLE_LOCAL_METRICS=true
```

Configuration avec journaux et métriques détaillées des conteneurs :

```bash
ENABLE_LOGS=true
ENABLE_CONTAINER_METRICS=true
ENABLE_LOCAL_METRICS=true
```

Appliquer après chaque changement :

```bash
sudo vps-monitoring apply
sudo vps-monitoring status
```

Avec `ENABLE_LOGS=false`, les conteneurs Loki et Alloy sont arrêtés et
supprimés. Le volume Loki est conservé afin d'éviter une suppression de
données involontaire. Les journaux locaux continuent d'exister dans journald
et dans les fichiers Nginx avec leur rotation habituelle.

Avec `ENABLE_CONTAINER_METRICS=false`, cAdvisor est arrêté et supprimé. Les
métriques système et celles du démon Docker restent disponibles, mais les
panneaux détaillés par conteneur sont vides.

Pour supprimer volontairement l'historique Loki après désactivation :

```bash
sudo docker volume rm monitoring_loki_data
```

Cette commande est destructive et doit être exécutée uniquement après
vérification que Loki est arrêté.

## Démarrer et vérifier

Lancer la collecte locale puis le projet :

```bash
sudo /usr/local/sbin/vps-local-metrics
cd /opt/selfhosted/monitoring
sudo docker compose config
sudo vps-image-lock monitoring
sudo vps-monitoring apply
```

Vérifier les endpoints :

```bash
curl -fsS http://127.0.0.1:3000/api/health
curl -fsS http://127.0.0.1:9090/-/ready
curl -fsS http://127.0.0.1:9100/metrics >/dev/null
curl -fsS http://127.0.0.1:9323/metrics >/dev/null
sudo ss -ltnp | grep -E ':(3000|9090|9100|9323)\b'
```

Si `ENABLE_CONTAINER_METRICS=true` :

```bash
curl -fsS http://127.0.0.1:8080/metrics >/dev/null
sudo ss -ltnp | grep -E ':8080\b'
```

Si les journaux sont activés :

```bash
curl -fsS http://127.0.0.1:3100/ready
curl -fsS http://127.0.0.1:12345/-/ready
sudo ss -ltnp | grep -E ':(3100|12345)\b'
```

Toutes les écoutes doivent être liées à `127.0.0.1`.

## Contenu du dashboard

Le dashboard `VPS - Système, Docker et journaux` est provisionné
automatiquement. Il affiche :

- disponibilité des collecteurs ;
- CPU, mémoire, charge et durée de fonctionnement ;
- espace et inodes de la partition `/` ;
- débits disque et réseau ;
- CPU, mémoire, réseau et E/S de chaque conteneur ;
- conteneurs actifs et configurés ;
- paquets APT à mettre à jour ;
- demande de redémarrage Debian ;
- unités systemd en échec ;
- adresses actuellement bannies par Fail2ban ;
- état du flag des journaux ;
- journaux système, Docker et Nginx si Loki est activé.

Les métriques locales sont rafraîchies toutes les 15 minutes par
`vps-local-metrics.timer`.

## Sécurité et limites

Grafana est sans formulaire de connexion et n'accorde que le rôle anonyme
`Viewer`. Nginx doit donc conserver l'authentification HTTP décrite dans
[Supervision et rapports](10-supervision-rapports.md).

Node Exporter monte la racine en lecture seule. Alloy, lorsqu'il est activé,
lit le journal et les fichiers Nginx en lecture seule.

cAdvisor est le composant le plus sensible : il monte en lecture seule
`/var/run`, `/sys`, `/var/lib/docker` et la racine. `/var/run` inclut le socket
Docker. Un montage de socket marqué `ro` ne rend pas l'API Docker elle-même
non modifiable ; une compromission de cAdvisor doit donc être considérée comme
critique. Il est donc désactivé par défaut. Lorsqu'il est requis, son interface
reste locale, le conteneur n'a aucune capacité Linux ajoutée et son système de
fichiers est en lecture seule. Il faut maintenir son image à jour et ne jamais
publier son port `8080`.

Le flag désactive la centralisation et les requêtes de journaux dans Grafana,
pas la production minimale de journaux nécessaire au diagnostic, à Fail2ban
et aux audits de sécurité.

## Mise à jour

Les versions sont épinglées dans `.env`. Avant toute mise à jour, lire les
notes de publication puis :

```bash
cd /opt/selfhosted/monitoring
sudo docker compose config
sudo vps-image-lock monitoring
sudo vps-monitoring apply
sudo vps-monitoring status
```

## Références

- [Docker : métriques Prometheus du démon](https://docs.docker.com/engine/daemon/prometheus/)
- [Docker : pilote journald](https://docs.docker.com/engine/logging/drivers/journald/)
- [cAdvisor : exécution en conteneur](https://github.com/google/cadvisor/blob/master/docs/running.md)
- [Grafana Alloy : lecture de journald](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.journal/)
- [Grafana Alloy : lecture de fichiers](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.file/)
- [Grafana Loki : installation avec Docker](https://grafana.com/docs/loki/latest/setup/install/docker/)
