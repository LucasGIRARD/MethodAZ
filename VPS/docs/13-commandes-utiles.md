# Commandes utiles

## État global

```bash
sudo vps-health-report
less /var/log/server-checks/health-report.txt
```

## Certificats

```bash
cd /opt/selfhosted/gateway
docker compose run --rm certbot certificates
docker compose run --rm certbot renew --dry-run
sudo /usr/local/sbin/check-certificates.sh
less /var/log/server-checks/certificates.txt
```

## Noyau et redémarrage

```bash
sudo /usr/local/sbin/check-kernel-reboot.sh
less /var/log/server-checks/kernel-check.txt
```

## Images Docker

```bash
sudo /usr/local/sbin/check-docker-image-updates.sh
less /var/log/server-checks/docker-image-updates.txt
```

## Analyse des CVE Docker

```bash
sudo vps-image-audit
ls -lh /var/log/server-checks/docker-images/
tail -n 100 /var/log/server-checks/docker-images/cve-report.txt
```

## Journaux Docker

```bash
docker ps
sudo vps-compose databases logs --tail=100
sudo vps-compose linkwarden logs --tail=100
sudo vps-compose davis logs --tail=100
sudo vps-compose freshrss logs --tail=100
```

## Bases de données partagées

```bash
sudo vps-compose databases ps
sudo vps-compose databases exec postgres \
  psql --username postgres
```

## Supervision Grafana et Prometheus

```bash
cd /opt/selfhosted/monitoring
docker compose ps
docker compose logs --tail=100
curl -fsS http://127.0.0.1:3000/api/health
curl -fsS http://127.0.0.1:9090/-/ready
curl -fsS http://127.0.0.1:9100/metrics >/dev/null
docker system df -v
```

## Nginx

```bash
cd /opt/selfhosted/gateway
docker compose exec nginx nginx -t
docker compose exec nginx nginx -s reload
docker compose logs --tail=100 nginx
sudo tail -n 100 /opt/selfhosted/gateway/logs/nginx/error.log
```

## Ports exposés

```bash
sudo ss -tulpn
sudo iptables -L INPUT -n -v --line-numbers
sudo ip6tables -L INPUT -n -v --line-numbers
sudo systemctl status netfilter-persistent --no-pager
```

## Espace utilisé par les journaux

```bash
journalctl --disk-usage
sudo du -sh /var/log /var/lib/docker
sudo find /var/log -xdev -type f -size +50M -printf '%s %p\n' | sort -nr
docker info --format '{{.LoggingDriver}}'
```

## Mise à jour rapide d'un service

```bash
cd /opt/selfhosted/linkwarden
sudo vps-backup
sudo vps-image-lock linkwarden
sudo vps-compose linkwarden up -d
sudo vps-compose linkwarden logs --tail=100
```

## Maintenance nocturne

```bash
systemctl list-timers vps-nightly-maintenance.timer \
  apt-daily.timer apt-daily-upgrade.timer
sudo systemctl start vps-nightly-maintenance.service
journalctl -u vps-nightly-maintenance.service -n 200
```
