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

## Dépannage

### Migration bloquée sur PostgreSQL

Si `migrate` échoue avec :

```text
FATAL: password authentication failed for user "davis"
```

resynchroniser les mots de passe PostgreSQL depuis les secrets canoniques, puis
regénérer la configuration applicative :

```bash
sudo vps-install --phase databases
sudo vps-install --phase services
sudo vps-compose davis up -d --force-recreate
sudo vps-compose davis logs --tail=100 migrate app nginx
```

`DAVIS_DATABASE_URL` contient le mot de passe PostgreSQL encodé pour être
valide dans une URL. Comme Davis passe par Symfony, les caractères `%` issus du
percent-encoding sont doublés dans le fichier `.env`; Symfony les réduit ensuite
en `%` au moment de résoudre la variable.

Si `migrate` échoue avec :

```text
You have requested a non-existent parameter "..."
```

la valeur de `DAVIS_DATABASE_URL` contient probablement des `%` non doublés.
Rejouer :

```bash
sudo vps-install --phase services
sudo vps-compose davis up -d --force-recreate
```

### Permission refusée sur `/var/www/davis/var/log`

Si les logs affichent :

```text
There is no existing directory at "/var/www/davis/var/log" and it could not be created: Permission denied
```

le volume applicatif Davis n'a pas encore les dossiers runtime attendus. Le
service ponctuel `init` les crée automatiquement. Pour réparer une installation
existante sans attendre une recopie du bundle :

```bash
sudo vps-compose davis run --rm --no-deps --user 0:0 \
  --entrypoint sh migrate -c \
  'mkdir -p /var/www/davis/var/cache /var/www/davis/var/log /data \
  && chown -R www-data:www-data /var/www/davis/var /data'

sudo vps-compose davis up -d --force-recreate
```
