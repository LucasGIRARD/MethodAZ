# Tiny Tiny RSS

## Fichiers

- Modèle : `install/services/ttrss/docker-compose.yml`
- Nginx interne : `install/services/ttrss/nginx.conf`
- Installation : `/opt/selfhosted/ttrss`
- Port : `127.0.0.1:3004`
- Domaine : `ttrss.example.fr`

Le projet contient l'application, son processus de mise à jour et un Nginx
interne. La base `ttrss` utilise l'instance PostgreSQL partagée.

## Version de l'image

Le projet amont utilise un modèle de publication continu. La valeur
`TTRSS_IMAGE` doit être contrôlée avant chaque mise à jour. La commande
suivante télécharge l'image puis écrit son digest dans
`docker-compose.lock.yml` :

```bash
sudo vps-compose databases up -d --wait
sudo vps-image-lock ttrss
```

Ne pas démarrer Tiny Tiny RSS sans ce verrou : le tag amont `latest` est
mutable.

## Premier démarrage

```bash
sudo vps-image-lock ttrss
sudo vps-compose ttrss config --quiet
sudo vps-compose ttrss up -d
sudo vps-compose ttrss logs --tail=100
curl -fsSI http://127.0.0.1:3004
```

## Données

```text
/opt/selfhosted/ttrss/app
/opt/selfhosted/databases/postgres
```
