Installer Nginx et Certbot :

```Bash
sudo apt updatesudo apt install -y nginx certbot python3-certbot-nginx
```

Certbot est disponible dans les dépôts Debian, avec des plugins utiles pour Nginx et Apache.

Firewall :

```Bash
sudo ufw allow 80/tcp comment "HTTP"
sudo ufw allow 443/tcp comment "HTTPS"
sudo systemctl enable --now nginx
```

Supprimer le bloc Caddy de la procédure précédente :

```Bash
cd /opt/selfhosted/proxy
docker compose down
cd /opt/selfhosted
rm -rf proxy
```

Créer les fichiers Nginx :

```Bash
sudo mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
```

# Réseau Docker sans publication publique

Créer le réseau Docker commun :

```Bash
docker network create proxy
```

Les conteneurs ne doivent pas publier `80:80` ou `443:443`. Ils doivent seulement utiliser `expose`.

Exemple :

```YAML
networks:
  - proxy

expose:
  - "3000"
```

Nginx hôte Debian appellera les conteneurs via `127.0.0.1:PORT_LOCAL`, donc je recommande de publier les ports applicatifs seulement en localhost.

Exemple :

```YAML
ports:
  - "127.0.0.1:3001:3000"
```

---

# Nginx reverse proxy pour les services Docker

Créer un fichier par service.

## Linkwarden

Dans le `docker-compose.yml` de Linkwarden, remplacer l’exposition par :

```YAML
ports:
  - "127.0.0.1:3001:3000"
```

Créer :

```Bash
sudo nano /etc/nginx/sites-available/links.example.fr
```

Contenu :

```Nginx
server {
    listen 80;
    server_name links.example.fr;

    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:3001;
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

Activer :

```Bash
sudo ln -s /etc/nginx/sites-available/links.example.fr /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

Certificat :

```Bash
sudo certbot --nginx -d links.example.fr
```


## Davis

Dans Davis :

```YAML
ports:
  - "127.0.0.1:3002:80"
```

Créer :

```Bash
sudo nano /etc/nginx/sites-available/dav.example.fr
```

Contenu :

```Nginx
server {
    listen 80;
    server_name dav.example.fr;

    client_max_body_size 512M;

    location / {
        proxy_pass http://127.0.0.1:3002;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_set_header Depth $http_depth;
        proxy_set_header Destination $http_destination;
        proxy_set_header Overwrite $http_overwrite;
        proxy_set_header Authorization $http_authorization;

        proxy_request_buffering off;
        proxy_buffering off;
    }
}
```

Activer :

```Bash
sudo ln -s /etc/nginx/sites-available/dav.example.fr /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
sudo certbot --nginx -d dav.example.fr
```

---

## FreshRSS

Dans FreshRSS :

```YAML
ports:
  - "127.0.0.1:3003:80"
```

Nginx :

```Bash
sudo nano /etc/nginx/sites-available/freshrss.example.fr
```

```Nginx
server {
    listen 80;
    server_name freshrss.example.fr;

    client_max_body_size 64M;

    location / {
        proxy_pass http://127.0.0.1:3003;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Activer :

```Bash
sudo ln -s /etc/nginx/sites-available/freshrss.example.fr /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
sudo certbot --nginx -d freshrss.example.fr
```

---

## Tiny Tiny RSS

Dans tt-rss :

```YAML
ports:
  - "127.0.0.1:3004:80"
```

Nginx :

```Bash
sudo nano /etc/nginx/sites-available/ttrss.example.fr
```

```Nginx
server {
    listen 80;
    server_name ttrss.example.fr;

    client_max_body_size 64M;

    location / {
        proxy_pass http://127.0.0.1:3004;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Activer :

```Bash
sudo ln -s /etc/nginx/sites-available/ttrss.example.fr /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
sudo certbot --nginx -d ttrss.example.fr
```

---

## Kill the Newsletter

Dans le compose :

```YAML
ports:
  - "127.0.0.1:3005:8000"
```

Nginx :

```Bash
sudo nano /etc/nginx/sites-available/newsletter.example.fr
```

```Nginx
server {
    listen 80;
    server_name newsletter.example.fr;

    location / {
        proxy_pass http://127.0.0.1:3005;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Activer :

```Bash
sudo ln -s /etc/nginx/sites-available/newsletter.example.fr /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
sudo certbot --nginx -d newsletter.example.fr
```

---

# Hébergement PHP/MySQL/HTML avec Apache

Ici, Apache est dans Docker, derrière Nginx.

Créer :

```Bash
cd /opt/selfhosted/web
mkdir -p html db apache
nano docker-compose.yml
```

Contenu :

```YAML
services:
  apache-php:
    image: php:8.3-apache
    container_name: apache-php-web
    restart: unless-stopped
    ports:
      - "127.0.0.1:3006:80"
    networks:
      - web-internal
    volumes:
      - ./html:/var/www/html
      - ./apache/000-default.conf:/etc/apache2/sites-available/000-default.conf:ro
    depends_on:
      - web-db

  web-db:
    image: mariadb:11
    container_name: apache-web-db
    restart: unless-stopped
    networks:
      - web-internal
    environment:
      - MARIADB_DATABASE=web
      - MARIADB_USER=web
      - MARIADB_PASSWORD=CHANGE_ME_DB_PASSWORD
      - MARIADB_ROOT_PASSWORD=CHANGE_ME_ROOT_PASSWORD
    volumes:
      - ./db:/var/lib/mysql

networks:
  web-internal:
    internal: true
```

Créer la configuration Apache :

```Bash
nano apache/000-default.conf
```

```apache
<VirtualHost *:80>
    ServerName web.example.fr
    DocumentRoot /var/www/html

    <Directory /var/www/html>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/web_error.log
    CustomLog ${APACHE_LOG_DIR}/web_access.log combined
</VirtualHost>
```

Créer une page de test :

```Bash
cat > html/index.php <<'EOF'
<?php
echo "Apache PHP OK";
EOF
```

Démarrer :

```Bash
docker compose up -d
```

Nginx frontal :

```Bash
sudo nano /etc/nginx/sites-available/web.example.fr
```

```Nginx
server {
    listen 80;
    server_name web.example.fr;

    client_max_body_size 128M;

    location / {
        proxy_pass http://127.0.0.1:3006;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Activer HTTPS :

```Bash
sudo ln -s /etc/nginx/sites-available/web.example.fr /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
sudo certbot --nginx -d web.example.fr
```

---

# Renouvellement certificats

Certbot installe normalement une tâche systemd/cron de renouvellement. Vérifier :

```Bash
systemctl list-timers | grep certbot
```

Test de renouvellement :

```Bash
sudo certbot renew --dry-run
```

Contrôle manuel des certificats :

```Bash
sudo certbot certificates
```

Script de vérification :

```Bash
sudo nano /usr/local/sbin/check-certificates.sh
```

```Bash
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
)

mkdir -p "$REPORT_DIR"

{
  echo "===== Certificate check ====="
  date -Is
  echo

  certbot certificates || true
  echo

  for DOMAIN in "${DOMAINS[@]}"; do
    echo "### $DOMAIN"

    EXPIRY_RAW="$(
      echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN:443" 2>/dev/null \
      | openssl x509 -noout -enddate 2>/dev/null \
      | cut -d= -f2 || true
    )"

    if [ -z "$EXPIRY_RAW" ]; then
      echo "Erreur: certificat non récupérable"
      echo
      continue
    fi

    EXPIRY_EPOCH="$(date -d "$EXPIRY_RAW" +%s)"
    NOW_EPOCH="$(date +%s)"
    DAYS_LEFT="$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))"

    echo "Expiration : $EXPIRY_RAW"
    echo "Jours restants : $DAYS_LEFT"

    if [ "$DAYS_LEFT" -lt 15 ]; then
      echo "ALERTE: certificat proche expiration"
    else
      echo "OK"
    fi

    echo
  done
} > "$REPORT"

cat "$REPORT"
```

```Bash
sudo chmod +x /usr/local/sbin/check-certificates.sh
```