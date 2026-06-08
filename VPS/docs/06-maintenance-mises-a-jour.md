# Maintenance et mises à jour

## Objectif

Sauvegarder avant toute modification, maintenir Debian et les services Docker,
puis vérifier l'état du serveur.

## Sauvegardes

L'installateur déploie `/usr/local/sbin/vps-backup`. Il produit :

- un dump logique de l'instance PostgreSQL et de l'instance MariaDB ;
- une archive des configurations et données applicatives, sans recopier les
  fichiers bruts des bases actives ;
- une archive cohérente du volume Grafana après un arrêt bref ;
- un manifeste daté.

```bash
sudo vps-backup
ls -lh /opt/selfhosted/backups/files
```

La rétention locale est de 7 jours par défaut. Elle est définie dans
`/etc/default/vps-maintenance`. La sauvegarde refuse de démarrer s'il reste
moins de 1 Gio libre.

L'archive contient les clés privées TLS et le fichier d'authentification
Grafana. Elle doit rester chiffrée, en mode `0600`, et ne jamais être déposée
dans un dépôt Git.

Prévoir ensuite une copie externe : rsync, SFTP, BorgBackup, Restic ou le
stockage fourni par l'hébergeur.

## Fenêtre nocturne

Le fuseau du serveur est configuré avec la valeur `TIMEZONE`, par défaut
`Europe/Paris`.

| Heure locale | Tâche |
| --- | --- |
| `02:15` à `02:25` | Démarrage aléatoire de la sauvegarde, renouvellement Certbot et rapports |
| Après la sauvegarde, le dimanche | Audit Docker Scout |
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
