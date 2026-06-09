# Restauration complète sur un VPS vierge

## Périmètre

Cette procédure reconstruit Debian, Docker, les projets Compose, les bases SQL,
les données applicatives, Grafana, Nginx et les certificats. Elle nécessite :

- un VPS Debian 13 vierge ;
- la clé privée SSH administrateur conservée sur le poste client ;
- une sauvegarde produite par `vps-backup` ;
- le mot de passe et les identifiants Restic conservés hors du VPS si la
  sauvegarde externe est utilisée.

Ne pas supprimer l'ancien serveur avant validation fonctionnelle du nouveau.

## Récupérer la sauvegarde

Avec Restic :

```bash
sudo install -d -m 0700 /etc/vps-backup /root/restauration
sudo install -m 0600 restic-repository restic-password restic.env \
  /etc/vps-backup/
sudo RESTIC_REPOSITORY_FILE=/etc/vps-backup/restic-repository \
  RESTIC_PASSWORD_FILE=/etc/vps-backup/restic-password \
  sh -c '. /etc/vps-backup/restic.env; export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION; restic snapshots'
sudo RESTIC_REPOSITORY_FILE=/etc/vps-backup/restic-repository \
  RESTIC_PASSWORD_FILE=/etc/vps-backup/restic-password \
  sh -c '. /etc/vps-backup/restic.env; export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION; restic restore latest --target /root/restauration'
```

Identifier le répertoire daté contenant :

```text
configuration-installateur.tar.gz
configurations-et-donnees.tar.gz
databases/postgres.sql.gz
databases/mariadb.sql.gz
grafana-data.tar.gz
manifest.txt
```

## Retrouver la version installée

```bash
mkdir -p /root/configuration-restauree
tar -xzf configuration-installateur.tar.gz \
  -C /root/configuration-restauree
cat /root/configuration-restauree/source-version.txt
```

Télécharger le bundle `VPS` au commit indiqué dans `source-version.txt`, puis
restaurer sa configuration :

```bash
install -m 0600 /root/configuration-restauree/config/vps.env \
  install/config/vps.env
install -m 0600 /root/configuration-restauree/config/secrets.env \
  install/config/secrets.env
cp -a /root/configuration-restauree/keys/. install/keys/
```

## Reconstruire le socle

```bash
sudo sh install/scripts/validate-bundle.sh
sudo sh install/scripts/vps-install.sh --phase all
sudo vps-compose gateway down
sudo vps-monitoring stop
```

L'installation crée des bases vides. Elles seront remplacées par les dumps.

## Restaurer les projets et données

```bash
sudo tar -xzf configurations-et-donnees.tar.gz -C /opt/selfhosted
```

L'extraction root conserve les propriétaires numériques enregistrés. Ne pas
appliquer un `chown` récursif global et ne pas restaurer de copie brute des
répertoires PostgreSQL ou MariaDB.

## Restaurer les bases

```bash
gunzip -c databases/postgres.sql.gz \
  | sudo vps-compose databases exec -T postgres \
      psql -X --set=ON_ERROR_STOP=1 -U postgres -d postgres

sudo vps-compose databases exec -T postgres \
  vacuumdb -a -z -U postgres

gunzip -c databases/mariadb.sql.gz \
  | sudo vps-compose databases exec -T mariadb sh -c \
      'exec mariadb --user=root --password="$(cat /run/secrets/mariadb_admin_password)"'
```

## Restaurer Grafana

```bash
sudo docker volume create monitoring_grafana_data
sudo docker run --rm \
  -v monitoring_grafana_data:/target \
  -v "$PWD:/backup:ro" \
  alpine:3.22.4 \
  tar -xzf /backup/grafana-data.tar.gz -C /target
```

Utiliser de préférence le digest Alpine enregistré dans le verrou du projet
monitoring plutôt qu'un tag lors d'une restauration réelle.

## Redémarrer et contrôler

```bash
sudo vps-compose databases up -d --wait
for service in linkwarden davis freshrss ttrss web; do
  sudo vps-compose "$service" up -d
done
sudo vps-monitoring apply
sudo vps-gateway start-http
sudo vps-health-report
sudo vps-restore-test
```

Tester les URLs, SSH et SFTP avant de basculer le DNS. Fermer le port 22
temporaire uniquement après ces contrôles :

```bash
sudo vps-install --finalize-ssh
```
