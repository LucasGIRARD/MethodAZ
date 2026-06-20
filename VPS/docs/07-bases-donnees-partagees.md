# Base de données PostgreSQL partagée

## Architecture retenue

Le serveur exécute une seule instance PostgreSQL officielle pour les cinq
applications SQL :

| Base | Application | Rôle |
| --- | --- | --- |
| `linkwarden` | Linkwarden | `linkwarden` |
| `davis` | Davis | `davis` |
| `freshrss` | FreshRSS | `freshrss` |
| `ttrss` | Tiny Tiny RSS | `ttrss` |
| `web` | Hébergement PHP | `web` |

Chaque application conserve sa propre base, son propre rôle, son propre mot de
passe et son propre réseau Docker interne. Aucun port SQL n'est publié sur
l'hôte.

Une application reliée au réseau `vps-db-davis` ne peut pas joindre le réseau
`vps-db-freshrss`, même si les deux bases sont servies par le même conteneur
PostgreSQL.

## Déploiement

Le projet se trouve sous `install/databases`. L'installateur le démarre avant
les applications :

```bash
sudo vps-install --phase databases
sudo vps-compose databases ps
```

Le script `init-postgres.sh` crée les cinq bases lors du premier démarrage.
Il est ensuite rejoué de manière idempotente par l'installateur pour maintenir
les mots de passe applicatifs cohérents avec le fichier de secrets.

Ne pas modifier directement `POSTGRES_ADMIN_PASSWORD` après
l'initialisation : le mot de passe enregistré dans PostgreSQL doit d'abord
être changé avec une session administrateur. Les mots de passe applicatifs
peuvent être réconciliés en rejouant la phase `databases`.

## Identifiants

Le mot de passe administrateur sert uniquement à l'initialisation, aux
sauvegardes et aux restaurations. Les applications reçoivent uniquement leur
rôle limité.

Les mots de passe utilisés par le script d'initialisation sont montés dans le
conteneur avec les secrets Docker Compose. Ils ne figurent pas dans
`docker inspect ... Config.Env`.

L'accès au groupe Docker et aux fichiers `.env` reste un accès privilégié.

## Sauvegarde et restauration

`sudo vps-backup` génère un seul dump logique :

```text
databases/postgres.sql.gz
```

Le répertoire brut actif n'est pas archivé. Cela évite une copie incohérente
des fichiers internes du moteur.

Une restauration complète écrase l'état SQL courant. Arrêter d'abord les cinq
applications, puis restaurer :

```bash
for service in linkwarden davis freshrss ttrss web; do
  sudo vps-compose "$service" down
done

gunzip -c postgres.sql.gz \
  | sudo vps-compose databases exec -T postgres \
      psql -X --set=ON_ERROR_STOP=1 -U postgres -d postgres

sudo vps-compose databases exec -T postgres \
  vacuumdb -a -z -U postgres
```

L'option `-X` empêche le chargement d'un éventuel fichier `psqlrc`.
`vacuumdb` recalcule les statistiques utilisées par le planificateur.

## Migration depuis l'ancienne architecture MariaDB

Une installation qui contient déjà Davis, FreshRSS ou des données `web` dans
MariaDB ne doit pas simplement recevoir la nouvelle configuration.

La phase `databases` refuse de continuer si
`/opt/selfhosted/databases/mariadb` contient encore des données. Après une
migration validée, arrêter l'ancien moteur et déplacer ce répertoire vers un
emplacement d'archive explicite. La phase retire alors l'ancien conteneur
MariaDB devenu orphelin et son ancien script d'initialisation. Elle ne détruit
jamais automatiquement le répertoire de données, qui reste aussi exclu des
archives brutes par `vps-backup`.

1. Conserver l'ancien VPS ou une sauvegarde complète exploitable.
2. Exporter séparément les bases `davis`, `freshrss` et `web`.
3. Créer les bases PostgreSQL cibles avec la nouvelle phase `databases`.
4. Migrer les schémas et données avec un outil adapté, par exemple `pgloader`,
   dans un environnement de test.
5. Exécuter les migrations applicatives de Davis et vérifier FreshRSS.
6. Valider les comptes, les volumes de données et toutes les fonctions métier.
7. Supprimer MariaDB uniquement après une sauvegarde PostgreSQL et un test de
   restauration réussis.

Un dump MariaDB ne peut pas être injecté directement dans PostgreSQL. Pour
FreshRSS, une réinstallation avec import OPML peut être plus simple si
l'historique des articles n'a pas besoin d'être conservé. Le service `web`
dépend du code PHP déployé : celui-ci doit utiliser PostgreSQL et ne plus
contenir de requêtes spécifiques à MySQL.

## Limite de la mutualisation

Une panne PostgreSQL touche les cinq applications SQL. Ce compromis réduit la
mémoire et le nombre de composants à maintenir, mais augmente l'impact d'une
panne moteur. Les comptes séparés, les réseaux isolés, les sauvegardes
nocturnes et les tests de restauration limitent ce risque.

Pour un service critique, utiliser des instances séparées ou une base
PostgreSQL managée.

## Références

- [Image officielle PostgreSQL](https://hub.docker.com/_/postgres)
- [FreshRSS : prérequis SQL](https://github.com/FreshRSS/FreshRSS#requirements)
- [Davis : configuration SQL](https://github.com/tchapi/davis#requirements)
- [Tiny Tiny RSS : installation](https://tt-rss.org/docs/Installation-Guide.html)
- [pgloader](https://pgloader.readthedocs.io/)
