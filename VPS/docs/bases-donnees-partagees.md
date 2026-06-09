# Bases de données partagées

## Architecture retenue

Le serveur exécute deux moteurs officiels, et non un moteur par application :

| Moteur | Applications | Image |
| --- | --- | --- |
| MariaDB | Davis, FreshRSS, hébergement web | `mariadb` officielle |
| PostgreSQL | Linkwarden, Tiny Tiny RSS | `postgres` officielle |

Chaque application conserve :

- sa propre base ;
- son propre utilisateur SQL ;
- son propre mot de passe ;
- son propre réseau Docker interne.

Les moteurs n'exposent aucun port sur l'hôte. Une application reliée au réseau
`vps-db-davis` ne peut pas joindre le réseau `vps-db-freshrss`, même si les
deux bases sont servies par le même conteneur MariaDB.

## Pourquoi PostgreSQL reste nécessaire

Linkwarden utilise PostgreSQL. La pile Docker officielle de Tiny Tiny RSS est
également construite et documentée avec PostgreSQL. Les forcer sur MariaDB
introduirait une configuration non prise en charge ou moins testée.

La mutualisation réduit donc cinq processus SQL à deux sans remplacer les
technologies attendues par les applications.

Les images applicatives n'embarquaient pas ces moteurs : les anciens fichiers
Compose démarraient des conteneurs SQL séparés. Il n'existe donc aucun
processus MariaDB ou PostgreSQL à désactiver dans Linkwarden, Davis, FreshRSS
ou Tiny Tiny RSS. Les services non SQL requis par une application restent
séparés ; Tiny Tiny RSS conserve notamment son updater et son frontal Nginx.

## Déploiement

Le projet se trouve sous `install/databases`. L'installateur le démarre avant
les applications :

```bash
sudo vps-install --phase databases
sudo vps-compose databases ps
```

Les scripts d'initialisation créent les bases lors du premier démarrage. Ils
sont ensuite rejoués de manière idempotente par l'installateur pour maintenir
les mots de passe applicatifs cohérents avec le fichier de secrets.

Ne pas modifier directement `MARIADB_ADMIN_PASSWORD` après l'initialisation :
le mot de passe enregistré dans MariaDB doit d'abord être changé avec une
session administrateur. Les mots de passe applicatifs peuvent être réconciliés
en rejouant la phase `databases`.

## Identifiants

Les mots de passe administrateurs des moteurs servent uniquement à
l'initialisation, aux sauvegardes et aux restaurations. Les applications
reçoivent uniquement leur compte limité :

```text
linkwarden -> base linkwarden, rôle linkwarden
ttrss      -> base ttrss, rôle ttrss
davis      -> base davis, compte davis
freshrss   -> base freshrss, compte freshrss
web        -> base web, compte web
```

L'accès au groupe Docker et aux fichiers `.env` reste un accès privilégié.

Les mots de passe administrateurs et ceux utilisés par les scripts
d'initialisation sont montés dans les conteneurs avec les secrets Docker
Compose. Ils ne figurent plus dans `docker inspect ... Config.Env`.

## Sauvegarde

`sudo vps-backup` génère :

```text
databases/postgres.sql.gz
databases/mariadb.sql.gz
```

Les répertoires bruts actifs ne sont pas archivés. Cela évite une copie
incohérente des fichiers internes des moteurs.

Une restauration complète écrase l'état SQL courant. Après avoir arrêté les
applications concernées :

```bash
gunzip -c postgres.sql.gz \
  | sudo vps-compose databases exec -T postgres \
      psql -X --set=ON_ERROR_STOP=1 -U postgres -d postgres

sudo vps-compose databases exec -T postgres \
  vacuumdb -a -z -U postgres

gunzip -c mariadb.sql.gz \
  | sudo vps-compose databases exec -T mariadb sh -c \
      'exec mariadb --user=root --password="$(cat /run/secrets/mariadb_admin_password)"'
```

L'option `-X` empêche le chargement d'un éventuel fichier `psqlrc`. L'analyse
PostgreSQL après restauration recalcule les statistiques utilisées par le
planificateur de requêtes.

## Migration d'une ancienne installation

Ne pas déplacer directement les anciens répertoires PostgreSQL ou MariaDB dans
le projet partagé.

1. Sauvegarder l'installation complète.
2. Produire un dump logique de chaque ancienne base.
3. Arrêter les anciens projets.
4. Démarrer le projet `databases`.
5. Importer chaque dump dans la base correspondante.
6. Déployer les nouveaux fichiers Compose applicatifs.
7. Tester avant de supprimer les anciens répertoires.

Une migration entre deux versions majeures d'un moteur doit toujours passer
par un dump logique ou par la procédure officielle du moteur.

## Limite de la mutualisation

Une panne de MariaDB touche trois applications et une panne de PostgreSQL en
touche deux. Ce compromis est acceptable pour un petit VPS personnel et réduit
nettement la mémoire utilisée. Pour un service critique, il faudrait isoler de
nouveau les moteurs ou utiliser une base managée.

## Références

- [Image officielle MariaDB](https://hub.docker.com/_/mariadb)
- [Image officielle PostgreSQL](https://hub.docker.com/_/postgres)
- [FreshRSS : bases externes](https://github.com/FreshRSS/FreshRSS/blob/edge/Docker/README.md#supported-databases)
- [Davis : configuration SQL](https://github.com/tchapi/davis)
- [Tiny Tiny RSS : installation](https://tt-rss.org/docs/Installation-Guide.html)
