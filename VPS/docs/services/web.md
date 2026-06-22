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

## Ajouter un sous-domaine après installation

1. Créer l'entrée DNS du nouveau sous-domaine vers le VPS.
2. Modifier la configuration canonique :

```bash
sudo nano /opt/vps-install/config/vps.env
```

Exemple :

```bash
WEB_DOMAIN=example.fr
WEB_SUBDOMAINS=www,blog
```

3. Réappliquer le service web. Cette phase met à jour la configuration Apache
   et crée automatiquement les dossiers déclarés dans `WEB_SUBDOMAINS` :

```bash
sudo vps-install --phase services
sudo vps-compose web up -d --build
```

4. Réappliquer le gateway, étendre le certificat puis recharger TLS :

```bash
sudo vps-install --phase gateway
sudo vps-gateway issue-certificate
sudo vps-gateway enable-tls
```

Pour `WEB_SUBDOMAINS=www,blog`, les dossiers créés sont :

```text
/opt/selfhosted/web/html/www
/opt/selfhosted/web/html/blog
```

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

Avec le compte SFTP `depot`, ce même dossier est exposé sous :

```text
/html
```

Le dépôt SFTP dans `/html/www` écrit donc dans
`/opt/selfhosted/web/html/www`.

Les fichiers web sont détenus par `depot:sftp-only`. Les dossiers doivent
rester en `0755` et les fichiers en `0644` pour permettre au conteneur Apache
de les lire. Les secrets et fichiers privés ne doivent pas être placés dans ce
document root.

## Dépannage

### `403 Forbidden` dans Apache

Si le test local retourne :

```bash
curl -i -H 'Host: www.example.fr' http://127.0.0.1:3006/
```

avec `Server unable to read htaccess file`, corriger les droits du document
root :

```bash
sudo chown -R depot:sftp-only /opt/selfhosted/web/html
sudo find /opt/selfhosted/web/html -type d -exec chmod 0755 {} \;
sudo find /opt/selfhosted/web/html -type f -exec chmod 0644 {} \;
sudo vps-compose web up -d --force-recreate
```

### `502 Bad Gateway` sur un sous-domaine

Si le test local sur `127.0.0.1:3006` répond `200 OK`, mais HTTPS répond `502`,
le conteneur web est bon et le problème est côté gateway. Vérifier que le
sous-domaine est dans `WEB_SUBDOMAINS`, puis régénérer :

```bash
sudo grep -E '^(WEB_DOMAIN|WEB_SUBDOMAINS|WEB_SERVER_NAMES)=' \
  /opt/selfhosted/gateway/.env
sudo docker exec gateway-nginx-1 nginx -T | grep -A8 -B4 'www.example.fr'

sudo vps-install --phase gateway
sudo vps-gateway enable-tls
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
