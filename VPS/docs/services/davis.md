# Davis

## Fichiers

- Modèle : `install/services/davis/docker-compose.yml`
- Installation : `/opt/selfhosted/davis`
- Port : `127.0.0.1:3002`
- Domaine : `dav.example.fr`

Le projet utilise uniquement l'image autonome Davis. Sa base `davis` est
hébergée par l'instance MariaDB partagée. L'interface HTTP interne écoute sur
le port `9000` du conteneur.

## Premier démarrage

```bash
sudo vps-compose databases up -d --wait
sudo vps-image-lock davis
sudo vps-compose davis config --quiet
sudo vps-compose davis up -d
sudo vps-compose davis logs --tail=100
curl -fsSI http://127.0.0.1:3002
```

Au premier démarrage et après une mise à jour qui contient des migrations :

```bash
sudo vps-compose davis exec app \
  sh -c "APP_ENV=prod bin/console doctrine:migrations:migrate --no-interaction"
```

Après publication par Nginx :

```text
Interface : https://dav.example.fr/dashboard
DAV       : https://dav.example.fr/dav
```

## Données

```text
/opt/selfhosted/davis/data
/opt/selfhosted/databases/mariadb
```
