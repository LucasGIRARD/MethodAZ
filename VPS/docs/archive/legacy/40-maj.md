# Mise à jour manuelle propre d’un service

Exemple Linkwarden :

```Bash
cd /opt/selfhosted/linkwarden

/opt/selfhosted/backups/backup.sh

docker compose pull
docker compose up -d

docker logs --tail=100 linkwarden
curl -I https://links.example.fr
```

Exemple hébergement Apache/PHP :

```Bash
cd /opt/selfhosted/web

/opt/selfhosted/backups/backup.sh

docker compose pull
docker compose up -d

docker logs --tail=100 apache-php-web
curl -I https://web.example.fr
```