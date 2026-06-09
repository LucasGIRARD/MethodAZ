# Conventions des services Docker

## Règles communes

- Un projet Compose indépendant par application.
- Aucun `container_name`, afin de conserver la gestion native de Compose.
- Ports HTTP publiés uniquement sur `127.0.0.1`.
- Deux moteurs SQL partagés, sans port publié.
- Un réseau SQL interne distinct par application.
- Un utilisateur et une base distincts par application.
- Versions d'images définies dans `.env`.
- Secrets distincts, générés aléatoirement et stockés dans un `.env` en mode
  `0600`. Ils sont montés comme secrets Compose lorsque l'image sait lire un
  fichier.
- Limite mémoire issue de `RESOURCE_PROFILE`.
- Healthcheck applicatif lorsque l'image fournit déjà l'outil nécessaire.
- Journaux applicatifs écrits dans stdout/stderr et collectés par journald.
- Données applicatives sous le répertoire du service et données SQL sous
  `/opt/selfhosted/databases`.
- Mise à jour service par service après sauvegarde.

## Contrôle avant démarrage

```bash
cd /opt/selfhosted/NOM_DU_SERVICE
sudo test "$(stat -c '%a' .env)" = 600
sudo docker compose config --quiet
sudo vps-image-lock NOM_DU_SERVICE
```

La sortie de `docker compose config` contient les variables interpolées. Ne
pas la copier dans un ticket ou un journal public, car elle peut révéler les
secrets.

## Premier démarrage

```bash
sudo vps-compose databases up -d --wait
sudo vps-compose NOM_DU_SERVICE up -d
sudo docker compose ps
sudo docker compose logs --tail=100
```

Ne passer au service suivant qu'après validation de son état et de son port
local.

## Sauvegarde

Sauvegarder ensemble :

- le fichier Compose ;
- le `.env` secret par un canal chiffré ;
- les répertoires de données ;
- les dumps cohérents MariaDB et PostgreSQL produits par `vps-backup`.

Une copie brute d'une base active n'est pas automatiquement une sauvegarde
cohérente.

## Périmètre des secrets Compose

| Composant | Secret monté sous `/run/secrets` | Limite |
| --- | --- | --- |
| PostgreSQL officiel | Mot de passe administrateur | Support natif `POSTGRES_PASSWORD_FILE` |
| MariaDB officielle | Mot de passe administrateur | Support natif `MARIADB_ROOT_PASSWORD_FILE` |
| Scripts d'initialisation SQL | Mots de passe des cinq bases | Lecture explicite des fichiers montés |
| Hébergement PHP | Mot de passe de la base web | L'application doit lire `DB_PASSWORD_FILE` |
| Linkwarden | Non | `DATABASE_URL` et `NEXTAUTH_SECRET` attendus en variables |
| Davis | Non | `DATABASE_URL`, `APP_SECRET` et `ADMIN_PASSWORD` attendus en variables |
| Tiny Tiny RSS | Non | `TTRSS_DB_PASS` et `ADMIN_USER_PASS` attendus en variables |

Forcer un wrapper autour d'une image tierce rendrait son démarrage plus
fragile et replacerait de toute façon le secret dans l'environnement du
processus. Les fichiers `.env` root en mode `0600` restent donc la solution
retenue pour les interfaces non compatibles.

La vérification hebdomadaire suivante couvre PostgreSQL, MariaDB et
l'hébergement PHP :

```bash
sudo vps-secret-audit
less /var/log/server-checks/secret-audit.txt
```

Elle contrôle l'absence du nom et de la valeur du secret dans `Config.Env`,
puis la présence du fichier monté. Elle ne prétend pas masquer un secret à
root ni à un membre du groupe Docker.

Références :

- [Secrets Docker Compose](https://docs.docker.com/reference/compose-file/secrets/)
- [Image officielle PostgreSQL et variables `_FILE`](https://github.com/docker-library/docs/blob/master/postgres/README.md#docker-secrets)
- [Configuration Davis](https://github.com/tchapi/davis#configuration)
- [Installation Tiny Tiny RSS](https://github.com/tt-rss/tt-rss/wiki/Installation-Guide)
