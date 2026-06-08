# Automatiser les rapports avec cron

Éditer le cron root :

```Bash
sudo crontab -e
```

Ajouter :

```cron
# Rapport santé serveur tous les jours à 06:10
10 6 * * * /usr/local/sbin/server-health-report.sh >/dev/null 2>&1

# Vérification kernel / reboot requis tous les jours à 06:15
15 6 * * * /usr/local/sbin/check-kernel-reboot.sh >/dev/null 2>&1

# Vérification certificats tous les jours à 06:20
20 6 * * * /usr/local/sbin/check-certificates.sh >/dev/null 2>&1

# Vérification images Docker, sans redémarrage  
25 6 * * * /usr/local/sbin/check-docker-image-updates.sh >/dev/null 2>&1

# Scan CVE Docker tous les dimanches à 04:30
30 4 * * 0 /usr/local/sbin/scan-docker-cves.sh >/dev/null 2>&1

# Test renouvellement Certbot hebdomadaire  
45 4 * * 0 certbot renew --dry-run >/var/log/server-checks/certbot-dry-run.txt 2>&1
```