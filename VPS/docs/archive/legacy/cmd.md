# Commandes manuelles utiles

État global :

```Bash
sudo /usr/local/sbin/server-health-report.sh
```

Certificats :

```Bash
sudo /usr/local/sbin/check-certificates.sh
```

Noyau / reboot :

```Bash
sudo /usr/local/sbin/check-kernel-reboot.sh
```

CVE Docker :

```Bash
sudo /usr/local/sbin/scan-docker-cves.sh
```

Voir les images obsolètes signalées par Watchtower :

```Bash
docker logs watchtower --tail=200
```

Mettre à jour un service proprement :

```Bash
cd /opt/selfhosted/linkwarden
docker compose pull
docker compose up -d
docker logs -f linkwarden
```

Mettre à jour tous les services après sauvegarde :

```Bash
/opt/selfhosted/backups/backup.sh

for dir in /opt/selfhosted/proxy \
           /opt/selfhosted/linkwarden \
           /opt/selfhosted/davis \
           /opt/selfhosted/kill-newsletter/app \
           /opt/selfhosted/freshrss \
           /opt/selfhosted/ttrss \
           /opt/selfhosted/web \
           /opt/selfhosted/watchtower; do
  [ -f "$dir/docker-compose.yml" ] || continue
  echo "Updating $dir"
  cd "$dir"
  docker compose pull || true
  docker compose up -d --build
done

docker image prune -f
```