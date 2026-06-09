# Maintenance et mises à jour

## Objectif

Sauvegarder avant toute modification, maintenir Debian et les services Docker,
puis vérifier l'état du serveur.

## Sauvegardes

L'installateur déploie `/usr/local/sbin/vps-backup`. Il produit :

- un dump logique de l'instance PostgreSQL et de l'instance MariaDB ;
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

Le script démarre des conteneurs PostgreSQL et MariaDB temporaires, sans
réseau, restaure les deux dumps, vérifie les cinq bases attendues, exécute
`vacuumdb -a -z` sur PostgreSQL, puis détruit les conteneurs et volumes de
test. Le résultat est écrit dans :

```text
/var/log/server-checks/restore-test.txt
```

Ce test vérifie les dumps SQL. La procédure complète sur un nouvel hôte reste
nécessaire pour valider le système, TLS et le DNS :
[Restauration complète sur un VPS vierge](procedures/restauration-vps-vierge.md).

## Copie externe chiffrée

Restic est installé uniquement si `ENABLE_REMOTE_BACKUP=true`. Il chiffre les
données avant leur envoi vers un stockage S3 compatible.

Préparer trois fichiers root :

```bash
sudo install -d -m 0700 /etc/vps-backup
printf '%s\n' 's3:https://ENDPOINT/BUCKET/vps' \
  | sudo tee /etc/vps-backup/restic-repository >/dev/null
openssl rand -base64 48 \
  | sudo tee /etc/vps-backup/restic-password >/dev/null
sudo install -m 0600 install/config/restic.env.example \
  /etc/vps-backup/restic.env
sudo nano /etc/vps-backup/restic.env
sudo chmod 0600 /etc/vps-backup/restic-*
```

Conserver une copie hors du VPS du mot de passe Restic. Sans ce mot de passe,
la sauvegarde est irrécupérable.

Activer ensuite dans `install/config/vps.env` :

```bash
ENABLE_REMOTE_BACKUP=true
```

Réappliquer les phases `base` et `docker`, puis initialiser une seule fois :

```bash
sudo vps-install --phase base
sudo vps-install --phase docker
sudo vps-backup
sudo vps-backup-remote init
sudo vps-backup-remote backup
sudo vps-backup-remote snapshots
```

La rétention distante conserve par défaut 7 sauvegardes quotidiennes, 5
hebdomadaires et 12 mensuelles. Le dimanche, Restic exécute `prune` et
`check`. Les identifiants S3 doivent être limités au bucket ; activer aussi le
versionnement ou la rétention immuable proposée par le fournisseur.

## Fenêtre nocturne

Le fuseau du serveur est configuré avec la valeur `TIMEZONE`, par défaut
`Europe/Paris`.

| Heure locale | Tâche |
| --- | --- |
| `02:15` à `02:25` | Démarrage aléatoire de la sauvegarde, renouvellement Certbot et rapports |
| Après la sauvegarde | Copie Restic si elle est activée |
| Le premier jour du mois | Test isolé de restauration des deux moteurs SQL |
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

- [Restic : préparer un dépôt S3](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html)
- [Restic : rétention et suppression](https://restic.readthedocs.io/en/stable/060_forget.html)
- [PostgreSQL : sauvegarde et restauration SQL](https://www.postgresql.org/docs/current/backup-dump.html)
