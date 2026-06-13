# Retour arrière après une mise à jour

## Principe

Un retour arrière remet ensemble :

- l'ancien fichier Compose et son verrou d'images ;
- l'ancien `.env` ;
- les données applicatives compatibles ;
- le dump SQL antérieur si une migration de schéma a été exécutée.

Toujours lancer `sudo vps-backup` avant une mise à jour.

## Régression sans migration SQL

Arrêter uniquement le service concerné :

```bash
sudo vps-compose linkwarden down
```

Extraire `configurations-et-donnees.tar.gz` dans un répertoire temporaire,
puis remettre les fichiers du projet concerné :

```bash
mkdir -p /root/rollback
tar -xzf configurations-et-donnees.tar.gz -C /root/rollback
sudo rsync -a /root/rollback/linkwarden/ /opt/selfhosted/linkwarden/
sudo vps-compose linkwarden config --quiet
sudo vps-compose linkwarden up -d
sudo vps-compose linkwarden logs --tail=200
```

Le fichier `docker-compose.lock.yml` ramène les anciennes images par digest.
Ne pas régénérer le verrou pendant le retour arrière.

## Régression après migration SQL

Arrêter toutes les applications SQL avant de restaurer l'instance PostgreSQL
partagée :

```bash
sudo vps-compose linkwarden down
sudo vps-compose davis down
sudo vps-compose freshrss down
sudo vps-compose ttrss down
sudo vps-compose web down

gunzip -c databases/postgres.sql.gz \
  | sudo vps-compose databases exec -T postgres \
      psql -X --set=ON_ERROR_STOP=1 -U postgres -d postgres

sudo vps-compose databases exec -T postgres \
  vacuumdb -a -z -U postgres
```

Remettre ensuite les anciens projets et redémarrer les applications.

## Mise à jour d'un moteur SQL

Ne jamais rattacher un répertoire de données créé par une version majeure plus
récente à une version majeure plus ancienne. Restaurer le dump logique dans
une instance vide utilisant l'ancienne version compatible.

## Validation

```bash
sudo vps-compose databases ps
sudo vps-compose linkwarden ps
curl -fsSI http://127.0.0.1:3001
sudo vps-health-report
```

Conserver la sauvegarde ayant servi au retour arrière jusqu'à la prochaine
sauvegarde et au prochain test de restauration réussis.
