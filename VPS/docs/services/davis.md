# Davis

## Fichiers

- Modèle : `install/services/davis/docker-compose.yml`
- Installation : `/opt/selfhosted/davis`
- Port : `127.0.0.1:3002`
- Domaine : `dav.example.fr`

Le projet utilise l'image PHP-FPM officielle Davis et un frontal Nginx dédié.
Sa base `davis` est hébergée par l'instance PostgreSQL partagée. Nginx publie
l'interface HTTP sur `127.0.0.1:3002`.

Avant le démarrage de PHP-FPM, le conteneur ponctuel `migrate` applique
automatiquement les migrations Doctrine. La commande est idempotente et
s'exécute à chaque `docker compose up`.

## Premier démarrage

```bash
sudo vps-compose databases up -d --wait
sudo vps-image-lock davis
sudo vps-compose davis config --quiet
sudo vps-compose davis up -d
sudo vps-compose davis logs --tail=100
curl -fsSI http://127.0.0.1:3002
```

Pour relancer manuellement les migrations lors d'un diagnostic :

```bash
sudo vps-compose davis run --rm migrate
```

Après publication par Nginx :

```text
Interface : https://dav.example.fr/dashboard
DAV       : https://dav.example.fr/dav
```

## Données

```text
/opt/selfhosted/davis/data
/opt/selfhosted/databases/postgres
```
