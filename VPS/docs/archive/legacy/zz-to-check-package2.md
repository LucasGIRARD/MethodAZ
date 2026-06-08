Voici une **config Docker Compose minimale** pour :

- **FreshRSS** = serveur RSS
- **Karakeep** = favoris / read-it-later / bibliothèque
- **Meilisearch** = recherche pour Karakeep
- **Chrome/Browserless** = archivage/screenshot pour Karakeep
- **Kill the Newsletter** = newsletters → flux RSS/Atom



## `docker-compose.yml`

```Yaml
services:
  freshrss:
    image: freshrss/freshrss:latest
    container_name: freshrss
    restart: unless-stopped
    ports:
      - "8080:80"
    environment:
      TZ: Europe/Paris
      CRON_MIN: "*/20"
    volumes:
      - ./freshrss/data:/var/www/FreshRSS/data
      - ./freshrss/extensions:/var/www/FreshRSS/extensions

  karakeep:
    image: ghcr.io/karakeep-app/karakeep:release
    container_name: karakeep
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      NEXTAUTH_URL: http://localhost:3000
      NEXTAUTH_SECRET: change-moi-avec-une-valeur-longue
      MEILI_ADDR: http://meilisearch:7700
      MEILI_MASTER_KEY: change-moi-aussi
      BROWSER_WEB_URL: http://chrome:9222
      DATA_DIR: /data
    volumes:
      - ./karakeep/data:/data
    depends_on:
      - meilisearch
      - chrome

  meilisearch:
    image: getmeili/meilisearch:v1.13
    container_name: meilisearch
    restart: unless-stopped
    environment:
      MEILI_MASTER_KEY: change-moi-aussi
      MEILI_NO_ANALYTICS: "true"
    volumes:
      - ./meilisearch:/meili_data

  chrome:
    image: gcr.io/zenika-hub/alpine-chrome:123
    container_name: karakeep-chrome
    restart: unless-stopped
    command:
      - chromium-browser
      - --headless
      - --no-sandbox
      - --disable-gpu
      - --disable-dev-shm-usage
      - --remote-debugging-address=0.0.0.0
      - --remote-debugging-port=9222

  kill-the-newsletter:
    image: leafac/kill-the-newsletter
    container_name: kill-the-newsletter
    restart: unless-stopped
    ports:
      - "8081:8080"
    volumes:
      - ./kill-the-newsletter:/data
```


```
FreshRSS: http://localhost:8080
Karakeep: http://localhost:3000
Kill the Newsletter: http://localhost:8081
```

## À changer impérativement

Dans `docker-compose.yml`, remplace :

```Yaml
NEXTAUTH_SECRET: change-moi-avec-une-valeur-longue
MEILI_MASTER_KEY: change-moi-aussi
```

Par exemple :

```Yaml
openssl rand -base64 32
```

Utilise une valeur différente pour chaque secret.


## Configuration Karakeep minimale

Dans Karakeep :

1. Crée ton compte.
2. Installe l’extension navigateur Karakeep.
3. Installe Floccus dans Chrome.
4. Configure Floccus avec Karakeep comme backend si tu veux synchroniser tes favoris Chrome.

## Variante plus propre derrière reverse proxy

Si tu utilises Caddy, Traefik ou Nginx Proxy Manager, évite d’exposer directement les ports publics. Garde plutôt :

```
ports:
  - "127.0.0.1:8080:80"
  - "127.0.0.1:3000:3000"
  - "127.0.0.1:8081:8080"
```

Et expose ensuite :

```
rss.tondomaine.fr       → freshrss:80
links.tondomaine.fr     → karakeep:3000
newsletter.tondomaine.fr → kill-the-newsletter:8080
```

Dans ce cas, modifie aussi Karakeep :

```
NEXTAUTH_URL: https://links.tondomaine.fr
```

