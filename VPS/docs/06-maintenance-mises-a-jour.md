# Maintenance et mises à jour

## Objectif

Sauvegarder avant toute modification, maintenir Debian et les services Docker,
puis vérifier l'état du serveur.

## Sauvegardes

L'installateur déploie `/usr/local/sbin/vps-backup`. Il produit :

- un dump logique de l'instance PostgreSQL partagée ;
- une archive des configurations et données applicatives, sans recopier les
  fichiers bruts des bases actives ;
- une archive de la configuration canonique de l'installateur, secrets
  compris ;
- une archive cohérente du volume Grafana après un arrêt bref ;
- un manifeste daté.

```bash
sudo vps-backup
ls -lh /opt/selfhosted/backups/files
```

La rétention locale est de 7 jours par défaut. Elle est définie dans
`/etc/default/vps-maintenance`. La sauvegarde refuse de démarrer s'il reste
moins de 1 Gio libre.

La sauvegarde locale est protégée par les permissions root, mais elle n'est pas
chiffrée au repos. Elle contient notamment les clés privées TLS, les secrets
applicatifs et l'authentification Grafana. Elle ne doit jamais être déposée
dans un dépôt Git.

## Test automatique des restaurations

Le premier jour de chaque mois, la maintenance lance :

```bash
sudo vps-restore-test
```

Le script démarre un conteneur PostgreSQL temporaire, sans réseau, restaure le
dump, vérifie les cinq bases attendues, exécute `vacuumdb -a -z`, puis détruit
le conteneur et son volume. Le résultat est écrit dans :

```text
/var/log/server-checks/restore-test.txt
```

Ce test vérifie les dumps SQL. La procédure complète sur un nouvel hôte reste
nécessaire pour valider le système, TLS et le DNS :
[Restauration complète sur un VPS vierge](procedures/restauration-vps-vierge.md).

## Copie externe chiffrée

Restic et rclone sont installés uniquement si `ENABLE_REMOTE_BACKUP=true`.
Restic chiffre et déduplique les données avant leur envoi. Le backend
recommandé est le compte gratuit Koofr, utilisé par l'intermédiaire de rclone.
Le mot de passe d'application Koofr n'est donc jamais transmis à Restic.

### Préparer Koofr

Créer un compte Koofr, puis ouvrir les préférences du compte et générer un
mot de passe d'application nommé par exemple `vps-rclone`. Ne pas utiliser le
mot de passe principal du compte.

Activer la sauvegarde dans `install/config/vps.env` avant d'appliquer
l'installation :

```bash
ENABLE_REMOTE_BACKUP=true
```

Réappliquer les phases `base` et `docker`. Elles installent `restic` et
`rclone` :

```bash
sudo vps-install --phase base
sudo vps-install --phase docker
```

Créer ensuite le remote rclone avec le compte Koofr et son mot de passe
d'application :

```bash
sudo install -d -m 0700 /etc/vps-backup
sudo rclone config --config /etc/vps-backup/rclone.conf
```

Dans l'assistant :

1. choisir `n` pour créer un remote ;
2. le nommer exactement `koofr` ;
3. choisir le type de stockage `koofr` ;
4. choisir le fournisseur `Koofr` ;
5. saisir l'adresse électronique du compte et le mot de passe d'application ;
6. refuser la configuration avancée et confirmer le remote.

Protéger puis tester cette configuration :

```bash
sudo chmod 0600 /etc/vps-backup/rclone.conf
sudo rclone lsd koofr: --config /etc/vps-backup/rclone.conf
```

### Préparer Restic

Créer le dépôt et les secrets root :

```bash
sudo install -d -m 0700 /etc/vps-backup
printf '%s\n' 'rclone:koofr:vps-restic' \
  | sudo tee /etc/vps-backup/restic-repository >/dev/null
openssl rand -base64 48 \
  | sudo tee /etc/vps-backup/restic-password >/dev/null
sudo install -m 0600 install/config/restic.env.example \
  /etc/vps-backup/restic.env
sudo nano /etc/vps-backup/restic.env
sudo chmod 0600 /etc/vps-backup/restic-*
```

Le fichier `restic.env` doit contenir :

```bash
RCLONE_CONFIG=/etc/vps-backup/rclone.conf
```

Conserver hors du VPS une copie chiffrée de `restic-repository`,
`restic-password`, `restic.env` et `rclone.conf`. Sans le mot de passe Restic,
la sauvegarde est irrécupérable. La configuration rclone peut être recréée si
l'accès au compte Koofr est encore disponible.

Initialiser une seule fois, puis vérifier une première sauvegarde :

```bash
sudo vps-backup
sudo vps-backup-remote init
sudo vps-backup-remote backup
sudo vps-backup-remote snapshots
```

La rétention distante conserve par défaut 7 sauvegardes quotidiennes, 5
hebdomadaires et 12 mensuelles. Le dimanche, Restic exécute `prune` et
`check`. Sur l'espace gratuit Koofr, surveiller l'occupation et réduire par
exemple `REMOTE_BACKUP_KEEP_WEEKLY` à `4` et
`REMOTE_BACKUP_KEEP_MONTHLY` à `3` si nécessaire. Restic déduplique les
données : le nombre de snapshots ne correspond pas au volume total multiplié
par ce nombre.

### Conserver un backend S3

S3 reste pris en charge. Utiliser dans `restic-repository` une URL
`s3:https://ENDPOINT/BUCKET/vps`, puis définir `AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY` et, si nécessaire, `AWS_DEFAULT_REGION` dans
`restic.env`. Les identifiants doivent être limités au bucket.

## Fenêtre nocturne

Le fuseau du serveur est configuré avec la valeur `TIMEZONE`, par défaut
`Europe/Paris`.

| Heure locale | Tâche |
| --- | --- |
| `02:15` à `02:25` | Démarrage aléatoire de la sauvegarde, renouvellement Certbot et rapports |
| Après la sauvegarde | Copie Restic si elle est activée |
| Le premier jour du mois | Test isolé de restauration PostgreSQL |
| Après la sauvegarde, le dimanche | Audit Docker Scout |
| Le dimanche | Nettoyage et contrôle du dépôt Restic |
| `04:15` à `04:25` | Mise à jour des listes APT |
| `04:45` à `04:55` | Installation des correctifs Debian de sécurité |
| `05:55` au plus tard | Arrêt forcé de la sauvegarde et des contrôles s'ils dépassent leur fenêtre |

Les travaux nocturnes utilisent une priorité CPU et disque réduite. Ils ne
mettent jamais les images Docker à jour automatiquement. APT démarre dans la
fenêtre indiquée ; une mise à jour exceptionnellement lente peut se terminer
après `06:00` afin de ne jamais interrompre `dpkg` brutalement.

Vérifier les planifications :

```bash
timedatectl
systemctl list-timers vps-nightly-maintenance.timer \
  apt-daily.timer apt-daily-upgrade.timer
```

Suivre la dernière exécution :

```bash
systemctl status vps-nightly-maintenance.service --no-pager
journalctl -u vps-nightly-maintenance.service -n 200
less /var/log/server-checks/health-report.txt
```

## Mises à jour Debian

L'installateur active `unattended-upgrades` uniquement pour les correctifs de
sécurité et désactive les redémarrages automatiques :

```text
Unattended-Upgrade::Origins-Pattern {
        "origin=Debian,codename=${distro_codename},label=Debian-Security";
        "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
};

Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
```

Mise à jour manuelle :

```bash
sudo apt update
sudo apt full-upgrade -y
sudo /usr/local/sbin/check-kernel-reboot.sh
```

Redémarrer manuellement si nécessaire :

```bash
sudo reboot
```

## Mise à jour propre d'un service Docker

Exemple Linkwarden :

```bash
cd /opt/selfhosted/linkwarden
sudo vps-backup
sudo vps-image-lock linkwarden
sudo vps-compose linkwarden up -d
sudo vps-compose linkwarden logs --tail=100
curl -I https://links.example.fr
```

Exemple pour l'hébergement web :

```bash
cd /opt/selfhosted/web
sudo vps-backup
sudo vps-image-lock web
sudo vps-compose web up -d
sudo vps-compose web logs --tail=100
curl -I https://web.example.fr
```

## Mise à jour de tous les services

À utiliser seulement après une sauvegarde.

```bash
sudo vps-backup
sudo vps-image-lock all

sudo vps-compose databases up -d --wait
for service in linkwarden davis freshrss ttrss web; do
  sudo vps-compose "$service" up -d
done

sudo vps-gateway start-http
sudo vps-monitoring apply

docker image prune -f
```

`kill-newsletter` est construit localement. Mettre d'abord son dépôt sur un
commit explicitement choisi, puis reconstruire avec
`sudo vps-compose kill-newsletter up -d --build`.

## Vérification après maintenance

```bash
sudo vps-health-report
docker compose -f /opt/selfhosted/gateway/docker-compose.yml exec nginx nginx -t
docker ps
docker system df
sudo ss -tulpn
```

Les procédures de retour arrière sont décrites dans
[Retour arrière après une mise à jour](procedures/retour-arriere-mise-a-jour.md).

## Références

- [Rclone : configurer Koofr](https://rclone.org/koofr/)
- [Restic : utiliser un backend rclone](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html#other-services-via-rclone)
- [Restic : préparer un dépôt S3](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html)
- [Restic : rétention et suppression](https://restic.readthedocs.io/en/stable/060_forget.html)
- [PostgreSQL : sauvegarde et restauration SQL](https://www.postgresql.org/docs/current/backup-dump.html)
