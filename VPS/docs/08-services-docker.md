# Services Docker

## Objectif

Déployer chaque application comme un projet Docker Compose indépendant sous
`/opt/selfhosted`. Ce document est le récapitulatif ; les paramètres propres à
chaque application sont dans `docs/services/`.

L'instance PostgreSQL est mutualisée dans le projet `databases`, décrit dans
[Bases de données partagées](07-bases-donnees-partagees.md).

## Vue d'ensemble

| Service | Port local | Base | Projet Compose | Documentation |
| --- | ---: | --- | --- | --- |
| Linkwarden | `127.0.0.1:3001` | PostgreSQL | `install/services/linkwarden` | [Linkwarden](services/linkwarden.md) |
| Davis | `127.0.0.1:3002` | PostgreSQL | `install/services/davis` | [Davis](services/davis.md) |
| FreshRSS | `127.0.0.1:3003` | PostgreSQL | `install/services/freshrss` | [FreshRSS](services/freshrss.md) |
| Tiny Tiny RSS | `127.0.0.1:3004` | PostgreSQL | `install/services/ttrss` | [Tiny Tiny RSS](services/ttrss.md) |
| Kill the Newsletter | `127.0.0.1:3005` | Interne | `install/services/kill-newsletter` | [Kill the Newsletter](services/kill-newsletter.md) |
| Apache/PHP | `127.0.0.1:3006` | PostgreSQL | `install/services/web` | [Hébergement web](services/web.md) |

Tous les projets suivent les
[conventions Docker communes](services/00-conventions.md).

Ils peuvent être exécutés sans installation Debian avec la procédure
[Test local avec Docker Compose](03-test-local-docker.md).

## Organisation des fichiers

Les sources versionnées sont séparées des données du VPS :

```text
install/services/                  Modèles suivis dans Git
  linkwarden/docker-compose.yml
  davis/docker-compose.yml
  freshrss/docker-compose.yml
  ttrss/docker-compose.yml
  kill-newsletter/docker-compose.yml
  web/docker-compose.yml
install/databases/                 PostgreSQL partagé

/opt/selfhosted/                   Installation réelle
  databases/
  linkwarden/
  davis/
  freshrss/
  ttrss/
  kill-newsletter/
  web/
```

Chaque installation réelle reçoit un `.env` en mode `0600`, généré à partir du
fichier public `vps.env` et du fichier privé `secrets.env`.

## Déploiement automatisé

La liste est définie dans `install/config/vps.env` :

```bash
SERVICES=linkwarden,davis,freshrss,ttrss,web
AUTO_START_SERVICES=false
```

Déployer ou remettre à jour les fichiers sans démarrer les applications :

```bash
sudo sh install/scripts/vps-install.sh --phase services
```

Le démarrage automatique est volontairement désactivé par défaut. Il faut
valider le fichier Compose et lire la fiche du service avant son premier
démarrage.

## Commandes communes

Le script installe `/usr/local/sbin/vps-compose` :

```bash
sudo vps-compose databases ps
sudo vps-image-lock linkwarden
sudo vps-compose linkwarden config
sudo vps-compose linkwarden up -d
sudo vps-compose linkwarden ps
sudo vps-compose linkwarden logs --tail=100
```

Le premier argument est le nom du répertoire sous `/opt/selfhosted`.
Le verrouillage crée `docker-compose.lock.yml` avec les digests exacts.

## Vérification globale

```bash
docker ps
sudo ss -ltnp | grep -E '127\.0\.0\.1:300[1-6]\b'

for port in 3001 3002 3003 3004 3005 3006; do
  curl -fsSI "http://127.0.0.1:$port" || true
done
```

Une application absente de `SERVICES` ne doit pas écouter sur son port.

## Publication

Les applications ne sont jamais publiées directement. Nginx les joint sur
leur port local, puis fournit HTTPS, les limites de débit et
l'authentification éventuelle. Voir
[Nginx et Certbot dans Docker](09-nginx-certbot.md).
