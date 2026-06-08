## Arborescence serveur

Créer l’arborescence :

```Bash
sudo mkdir -p /opt/selfhosted/{proxy,linkwarden,davis,kill-newsletter,freshrss,ttrss,web,backups}
sudo chown -R lucas:lucas /opt/selfhosted
cd /opt/selfhosted
```

Créer un réseau Docker commun :

```Bash
docker network create proxy
```

---

## Reverse proxy HTTPS avec Caddy

Caddy gère automatiquement les certificats HTTPS Let’s Encrypt si les DNS pointent bien vers le serveur.

Créer :

```Bash
cd /opt/selfhosted/proxy
nano docker-compose.yml
```

Contenu :

```YAML
services:
  caddy:
    image: caddy:2
    container_name: caddy
    restart: unless-stopped
    networks:
      - proxy
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./data:/data
      - ./config:/config

networks:
  proxy:
    external: true
```

Créer le Caddyfile :

```Bash
nano Caddyfile
```

Contenu initial :

```caddy
{
  email contact@example.fr
}

links.example.fr {
  reverse_proxy linkwarden:3000
}

dav.example.fr {
  reverse_proxy davis:80
}

newsletter.example.fr {
  reverse_proxy kill-newsletter:8000
}

freshrss.example.fr {
  reverse_proxy freshrss:80
}

ttrss.example.fr {
  reverse_proxy ttrss-nginx:80
}

web.example.fr {
  reverse_proxy php-web-nginx:80
}
```

Démarrer :

```Bash
docker compose up -d
docker logs -f caddy
```

---

## Linkwarden

Linkwarden indique des besoins modestes mais recommande environ 4 Go de mémoire pour un usage VPS confortable. Son installation self-hosted repose sur Docker, avec Docker, curl et nano comme prérequis.

Créer :

```Bash
cd /opt/selfhosted/linkwarden
nano docker-compose.yml
```

Contenu :

```YAML
services:
  linkwarden:
    image: ghcr.io/linkwarden/linkwarden:latest
    container_name: linkwarden
    restart: unless-stopped
    depends_on:
      - linkwarden-db
    networks:
      - proxy
      - linkwarden-internal
    environment:
      - DATABASE_URL=postgresql://linkwarden:CHANGE_ME_DB_PASSWORD@linkwarden-db:5432/linkwarden
      - NEXTAUTH_SECRET=CHANGE_ME_NEXTAUTH_SECRET
      - NEXTAUTH_URL=https://links.example.fr
      - NEXT_PUBLIC_DISABLE_REGISTRATION=false
      - TZ=Europe/Paris
    volumes:
      - ./data:/data/data

  linkwarden-db:
    image: postgres:16-alpine
    container_name: linkwarden-db
    restart: unless-stopped
    networks:
      - linkwarden-internal
    environment:
      - POSTGRES_DB=linkwarden
      - POSTGRES_USER=linkwarden
      - POSTGRES_PASSWORD=CHANGE_ME_DB_PASSWORD
    volumes:
      - ./postgres:/var/lib/postgresql/data

networks:
  proxy:
    external: true
  linkwarden-internal:
    internal: true
```

Générer les secrets :

```Bash
openssl rand -base64 32
openssl rand -base64 32
```

Remplacer :

```
CHANGE_ME_DB_PASSWORD
CHANGE_ME_NEXTAUTH_SECRET
links.example.fr
```

Démarrer :

```Bash
docker compose up -d
docker logs -f linkwarden
```

Accès :

```
https://links.example.fr
```

Après création du premier compte, désactiver les inscriptions :

```YAML
NEXT_PUBLIC_DISABLE_REGISTRATION=true
```

Puis :

```Bash
docker compose down
docker compose up -d
```

La documentation Linkwarden précise qu’après modification du `.env` ou des variables Docker, il faut recréer les conteneurs avec `docker compose down` puis `docker compose up -d`, un simple restart ne suffisant pas toujours.

---

## Davis pour CalDAV / CardDAV / WebDAV

Davis expose une page d’état à la racine, une interface d’administration sur `/dashboard`, et le point d’accès CalDAV/CardDAV/WebDAV principal sur `/dav`.

Créer :

```Bash
cd /opt/selfhosted/davis
nano docker-compose.yml
```

Contenu :

```YAML
services:
  davis:
    image: ghcr.io/tchapi/davis:latest
    container_name: davis
    restart: unless-stopped
    depends_on:
      - davis-db
    networks:
      - proxy
      - davis-internal
    environment:
      - APP_ENV=prod
      - APP_SECRET=CHANGE_ME_APP_SECRET
      - DATABASE_URL=mysql://davis:CHANGE_ME_DB_PASSWORD@davis-db:3306/davis
      - ADMIN_LOGIN=admin
      - ADMIN_PASSWORD=CHANGE_ME_ADMIN_PASSWORD
      - AUTH_REALM=Davis
      - TZ=Europe/Paris
    volumes:
      - ./data:/data

  davis-db:
    image: mariadb:11
    container_name: davis-db
    restart: unless-stopped
    networks:
      - davis-internal
    environment:
      - MARIADB_DATABASE=davis
      - MARIADB_USER=davis
      - MARIADB_PASSWORD=CHANGE_ME_DB_PASSWORD
      - MARIADB_ROOT_PASSWORD=CHANGE_ME_ROOT_PASSWORD
    volumes:
      - ./db:/var/lib/mysql

networks:
  proxy:
    external: true
  davis-internal:
    internal: true
```

Générer secrets :

```Bash
openssl rand -hex 32
openssl rand -base64 32
openssl rand -base64 32
openssl rand -base64 32
```

Démarrer :

```Bash
docker compose up -d
docker logs -f davis
```

Accès :

```
Interface admin : https://dav.example.fr/dashboard
Endpoint DAV    : https://dav.example.fr/dav
```

Pour floccus en mode WebDAV, utiliser :

```
URL WebDAV : https://dav.example.fr/dav
```

Ou utiliser directement Linkwarden comme backend de synchronisation floccus.

---

## Kill the Newsletter

Kill the Newsletter transforme des emails de newsletters en flux Atom. Le dépôt officiel indique que le serveur web écoute sur `8000` et le serveur SMTP sur `2525` dans l’exemple Docker.

Créer :

```Bash
cd /opt/selfhosted/kill-newsletter
git clone https://github.com/3nprob/kill-the-newsletter.com.git app
cd app
```

Créer un `docker-compose.yml` :

```Bash
nano docker-compose.yml
```

Contenu :

```YAML
services:
  kill-newsletter:
    build: .
    container_name: kill-newsletter
    restart: unless-stopped
    networks:
      - proxy
    volumes:
      - ./data:/app/data
    ports:
      - "127.0.0.1:2525:2525"

networks:
  proxy:
    external: true
```

Démarrer :

```Bash
docker compose up -d --build
docker logs -f kill-newsletter
```

Accès :

```
https://newsletter.example.fr
```

Attention : pour recevoir réellement des emails depuis Internet, il faut configurer le DNS MX et exposer le port SMTP nécessaire. Pour un usage simple, je recommande de commencer en local ou derrière un relais mail, car l’auto-hébergement SMTP demande une configuration stricte : SPF, DKIM, DMARC, reverse DNS, réputation IP.

procédure :

1. Crée une adresse newsletter dans l’interface.
2. Inscris cette adresse à tes newsletters.
3. Récupère le flux Atom généré.
4. Ajoute ce flux dans FreshRSS.

---

## FreshRSS

FreshRSS fournit des images Docker officielles sur Docker Hub et GitHub Container Registry.

Créer :

```Bash
cd /opt/selfhosted/freshrss
nano docker-compose.yml
```

Contenu :

```YAML
services:
  freshrss:
    image: freshrss/freshrss:latest
    container_name: freshrss
    restart: unless-stopped
    depends_on:
      - freshrss-db
    networks:
      - proxy
      - freshrss-internal
    environment:
      - TZ=Europe/Paris
      - CRON_MIN=*/20
    volumes:
      - ./data:/var/www/FreshRSS/data
      - ./extensions:/var/www/FreshRSS/extensions

  freshrss-db:
    image: mariadb:11
    container_name: freshrss-db
    restart: unless-stopped
    networks:
      - freshrss-internal
    environment:
      - MARIADB_DATABASE=freshrss
      - MARIADB_USER=freshrss
      - MARIADB_PASSWORD=CHANGE_ME_DB_PASSWORD
      - MARIADB_ROOT_PASSWORD=CHANGE_ME_ROOT_PASSWORD
    volumes:
      - ./db:/var/lib/mysql

networks:
  proxy:
    external: true
  freshrss-internal:
    internal: true
```

Démarrer :

```Bash
docker compose up -d
docker logs -f freshrss
```

Accès :

```
https://freshrss.example.fr
```

Pendant l’installation web, utiliser :

```
Type BDD : MySQL / MariaDB
Host     : freshrss-db
Base     : freshrss
User     : freshrss
Password : CHANGE_ME_DB_PASSWORD
```

Procédure :

1. Crée ton compte admin.
2. Active l’API :
    - Paramètres
    - Authentification
    - Autoriser l’accès API
3. Dans FeedMe Android :
    - Type de compte : **FreshRSS / Google Reader API**
    - URL : `https://ton-domaine-freshrss/api/greader.php`
    - ou en local : `http://ip-du-serveur:8080/api/greader.php`

---

## Tiny Tiny RSS

La documentation tt-rss recommande Docker comme méthode principale d’installation. Elle indique de placer `.env` et `docker-compose.yml` dans un répertoire, de les adapter, puis d’exécuter `docker compose up -d`.

Créer :

```Bash
cd /opt/selfhosted/ttrss
nano .env
```

Contenu :

```env
TTRSS_DB_TYPE=pgsql
TTRSS_DB_HOST=ttrss-db
TTRSS_DB_NAME=ttrss
TTRSS_DB_USER=ttrss
TTRSS_DB_PASS=CHANGE_ME_DB_PASSWORD

TTRSS_SELF_URL_PATH=https://ttrss.example.fr/tt-rss
ADMIN_USER_PASS=CHANGE_ME_ADMIN_PASSWORD

OWNER_UID=1000
OWNER_GID=1000
```

Créer :

```Bash
nano docker-compose.yml
```

Contenu :

```YAML
services:
  ttrss-db:
    image: postgres:16-alpine
    container_name: ttrss-db
    restart: unless-stopped
    networks:
      - ttrss-internal
    environment:
      - POSTGRES_DB=ttrss
      - POSTGRES_USER=ttrss
      - POSTGRES_PASSWORD=CHANGE_ME_DB_PASSWORD
    volumes:
      - ./db:/var/lib/postgresql/data

  ttrss-app:
    image: ghcr.io/tt-rss/tt-rss:latest
    container_name: ttrss-app
    restart: unless-stopped
    depends_on:
      - ttrss-db
    networks:
      - ttrss-internal
    env_file:
      - .env
    volumes:
      - ./app:/var/www/html

  ttrss-updater:
    image: ghcr.io/tt-rss/tt-rss:latest
    container_name: ttrss-updater
    restart: unless-stopped
    depends_on:
      - ttrss-app
    networks:
      - ttrss-internal
    env_file:
      - .env
    command: /opt/tt-rss/updater.sh
    volumes:
      - ./app:/var/www/html

  ttrss-nginx:
    image: nginx:alpine
    container_name: ttrss-nginx
    restart: unless-stopped
    depends_on:
      - ttrss-app
    networks:
      - proxy
      - ttrss-internal
    volumes:
      - ./app:/var/www/html:ro
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro

networks:
  proxy:
    external: true
  ttrss-internal:
    internal: true
```

Créer la config nginx :

```Bash
nano nginx.conf
```

Contenu :

```Nginx
server {
    listen 80;
    server_name _;

    root /var/www/html;
    index index.php index.html;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        fastcgi_pass ttrss-app:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
    }
}
```

Démarrer :

```Bash
docker compose up -d
docker compose logs -f
```

Accès :

```
https://ttrss.example.fr/tt-rss
```

Compte initial :

```
Utilisateur : admin
Mot de passe : valeur de ADMIN_USER_PASS
```

---

## Hébergement PHP / MySQL / HTML

Créer :

```Bash
cd /opt/selfhosted/web
mkdir -p html db
nano docker-compose.yml
```

Contenu :

```YAML
services:
  php-web-nginx:
    image: nginx:alpine
    container_name: php-web-nginx
    restart: unless-stopped
    depends_on:
      - php-web-php
    networks:
      - proxy
      - php-web-internal
    volumes:
      - ./html:/var/www/html
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro

  php-web-php:
    image: php:8.3-fpm
    container_name: php-web-php
    restart: unless-stopped
    networks:
      - php-web-internal
    volumes:
      - ./html:/var/www/html

  php-web-db:
    image: mariadb:11
    container_name: php-web-db
    restart: unless-stopped
    networks:
      - php-web-internal
    environment:
      - MARIADB_DATABASE=web
      - MARIADB_USER=web
      - MARIADB_PASSWORD=CHANGE_ME_DB_PASSWORD
      - MARIADB_ROOT_PASSWORD=CHANGE_ME_ROOT_PASSWORD
    volumes:
      - ./db:/var/lib/mysql

networks:
  proxy:
    external: true
  php-web-internal:
    internal: true
```

Créer la config nginx :

```Bash
nano nginx.conf
```

Contenu :

```Nginx
server {
    listen 80;
    server_name _;

    root /var/www/html;
    index index.php index.html index.htm;

    client_max_body_size 64M;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass php-web-php:9000;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }

    location ~ /\. {
        deny all;
    }
}
```

Créer une page de test :

```Bash
cat > html/index.php <<'EOF'
<?php
phpinfo();
EOF
```

Démarrer :

```Bash
docker compose up -d
```

Accès :

```
https://web.example.fr
```

Après test, supprimer `phpinfo()` :

```Bash
rm html/index.php
```

Pour la connexion MySQL depuis PHP :

```
Host     : php-web-db
Database : web
User     : web
Password : CHANGE_ME_DB_PASSWORD
Port     : 3306
```

---

## Redémarrer le reverse proxy après ajout des services

```Bash
cd /opt/selfhosted/proxy
docker compose restart caddy
docker logs -f caddy
```

Tester tous les domaines :

```Bash
curl -I https://links.example.fr
curl -I https://dav.example.fr
curl -I https://newsletter.example.fr
curl -I https://freshrss.example.fr
curl -I https://ttrss.example.fr
curl -I https://web.example.fr
```

---

## Sauvegardes

Créer un script :

```Bash
nano /opt/selfhosted/backups/backup.sh
```

Contenu :

```Bash
#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="/opt/selfhosted/backups/files"
DATE="$(date +%F_%H-%M-%S)"

mkdir -p "$BACKUP_DIR"

cd /opt/selfhosted

tar \
  --exclude='backups/files' \
  -czf "$BACKUP_DIR/selfhosted_$DATE.tar.gz" \
  proxy \
  linkwarden \
  davis \
  kill-newsletter \
  freshrss \
  ttrss \
  web

find "$BACKUP_DIR" -type f -name "*.tar.gz" -mtime +14 -delete
```

Rendre exécutable :

```Bash
chmod +x /opt/selfhosted/backups/backup.sh
```

Tester :

```Bash
/opt/selfhosted/backups/backup.sh
ls -lh /opt/selfhosted/backups/files
```

Cron quotidien à 03:30 :

```Bash
crontab -e
```

Ajouter :

```cron
30 3 * * * /opt/selfhosted/backups/backup.sh >/tmp/selfhosted-backup.log 2>&1
```

À faire ensuite : envoyer `/opt/selfhosted/backups/files` vers un stockage externe, par exemple IONOS Backup Cloud, rsync, SFTP, BorgBackup ou Restic.

---

## Mises à jour

Système Debian :

```Bash
sudo apt update
sudo apt full-upgrade -y
sudo reboot
```

Conteneurs Docker, service par service :

```Bash
cd /opt/selfhosted/linkwarden
docker compose pull
docker compose up -d
docker image prune -f
```

Pour tout mettre à jour :

```Bash
for dir in /opt/selfhosted/{proxy,linkwarden,davis,kill-newsletter/freshrss,ttrss,web}; do
  [ -f "$dir/docker-compose.yml" ] || continue
  echo "Updating $dir"
  cd "$dir"
  docker compose pull || true
  docker compose up -d
done

docker image prune -f
```

Correction de la boucle si tu veux l’utiliser telle quelle :

```Bash
for dir in /opt/selfhosted/proxy \
           /opt/selfhosted/linkwarden \
           /opt/selfhosted/davis \
           /opt/selfhosted/kill-newsletter/app \
           /opt/selfhosted/freshrss \
           /opt/selfhosted/ttrss \
           /opt/selfhosted/web; do
  [ -f "$dir/docker-compose.yml" ] || continue
  echo "Updating $dir"
  cd "$dir"
  docker compose pull || true
  docker compose up -d --build
done

docker image prune -f
```

---

## Vérifications sécurité finales

Commandes utiles :

```Bash
sudo ufw status numbered
sudo fail2ban-client status sshd
docker ps
docker network ls
docker logs caddy --tail=100
```

Vérifier les ports exposés :

```Bash
sudo ss -tulpn
```

Tu dois voir principalement :

```
2222/tcp  SSH
80/tcp    Caddy
443/tcp   Caddy
```

Les autres services doivent être uniquement accessibles via le réseau Docker interne ou via Caddy.

---

## Checklist finale

```
[ ] Connexion SSH root désactivée
[ ] Connexion SSH par mot de passe désactivée
[ ] Port SSH changé
[ ] UFW actif
[ ] Fail2ban actif sur sshd
[ ] Docker installé depuis le dépôt officiel
[ ] Aucun service applicatif exposé directement hors Caddy
[ ] HTTPS fonctionnel sur tous les sous-domaines
[ ] Inscriptions Linkwarden désactivées après création du compte
[ ] Sauvegardes testées
[ ] Restauration testée au moins une fois
[ ] DNS SPF/DKIM/DMARC étudiés avant usage SMTP public de Kill the Newsletter
```

Priorité de déploiement recommandée :

```
1. Debian + SSH + UFW + Fail2ban
2. Docker + Caddy
3. Linkwarden
4. Davis pour WebDAV/CalDAV/CardDAV
5. FreshRSS
6. tt-rss uniquement si tu veux comparer avec FreshRSS
7. PHP/MySQL/HTML
8. Kill the Newsletter en dernier, car la partie mail est plus sensible
```