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

## Domaines et sous-domaines

`WEB_DOMAIN` sert le dossier racine :

```bash
WEB_DOMAIN=example.fr
```

Dans ce cas, `https://example.fr` pointe vers :

```text
/opt/selfhosted/web/html
```

`WEB_SUBDOMAINS` ajoute des sous-domaines explicites au même service web. Chaque
label pointe vers un dossier du même nom :

```bash
WEB_SUBDOMAINS=www,blog,docs
```

Routage obtenu :

```text
https://www.example.fr   -> /opt/selfhosted/web/html/www
https://blog.example.fr  -> /opt/selfhosted/web/html/blog
https://docs.example.fr  -> /opt/selfhosted/web/html/docs
```

Les sous-domaines doivent aussi exister en DNS avant l'émission du certificat.
Le mode Certbot HTTP actuel ne prend pas en charge un wildcard `*.example.fr` ;
ajouter les sous-domaines voulus dans `WEB_SUBDOMAINS`.

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

Pour un sous-domaine, déposer son contenu dans le dossier correspondant, par
exemple `/opt/selfhosted/web/html/www` pour `www.example.fr`.

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
/opt/selfhosted/databases/postgres
```

Les variables `DB_DRIVER`, `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER` et
`DB_PASSWORD_FILE` sont fournies au conteneur PHP. Le mot de passe est monté
dans `/run/secrets/web_db_password`.

Exemple PHP :

```php
$password = trim(file_get_contents(getenv('DB_PASSWORD_FILE')));
```

L'application ne doit pas recopier cette valeur dans son code source ni dans
ses journaux.

L'image ajoute uniquement `pgsql`, `pdo_pgsql` et OPcache à la base PHP
officielle. Le digest de cette base est inscrit dans
`docker-compose.lock.yml` par `vps-image-lock web`.
