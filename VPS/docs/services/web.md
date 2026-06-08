# Hébergement Apache et PHP

## Fichiers

- Modèle : `install/services/web/docker-compose.yml`
- Image applicative : construite depuis l'image officielle
  `php:8.4.21-apache-trixie`
- Apache : `install/services/web/apache/000-default.conf`
- Contenu initial : `install/services/web/html`
- Installation : `/opt/selfhosted/web`
- Port : `127.0.0.1:3006`
- Domaine : `web.example.fr`

## Premier démarrage

```bash
sudo vps-compose databases up -d --wait
sudo vps-image-lock web
sudo vps-compose web config --quiet
sudo vps-compose web up -d
sudo vps-compose web logs --tail=100
curl -fsS http://127.0.0.1:3006
```

Déposer ensuite l'application dans :

```text
/opt/selfhosted/web/html
```

## Journaux

Apache écrit vers stdout et stderr :

```apache
ErrorLog /proc/self/fd/2
CustomLog /proc/self/fd/1 combined
```

Les messages rejoignent journald par le pilote Docker et suivent sa rétention.

## Données

```text
/opt/selfhosted/web/html
/opt/selfhosted/databases/mariadb
```

Les variables `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER` et `DB_PASSWORD`
sont fournies au conteneur PHP. L'application doit les lire sans recopier le
mot de passe dans son code source.

L'image ajoute uniquement `mysqli`, `pdo_mysql` et OPcache à la base PHP
officielle. Le digest de cette base est inscrit dans
`docker-compose.lock.yml` par `vps-image-lock web`.
