# Option : recevoir les rapports par email

Installer un client mail simple :

```Bash
sudo apt install -y bsd-mailx msmtp msmtp-mta
```

Configurer `msmtp` avec un SMTP externe, par exemple IONOS :

```Bash
sudo nano /etc/msmtprc
```

Exemple :

```
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account ionos
host smtp.ionos.fr
port 587
from contact@example.fr
user contact@example.fr
password MOT_DE_PASSE_SMTP

account default : ionos
```

Permissions :

```Bash
sudo chmod 600 /etc/msmtprc
```

Test :

```Bash
echo "Test mail serveur" | mail -s "Test VPS" contact@example.fr
```

Modifier le cron :

```cron
10 6 * * * /usr/local/sbin/server-health-report.sh | mail -s "[VPS] Rapport santé" contact@example.fr
20 6 * * * /usr/local/sbin/check-certificates.sh | mail -s "[VPS] Certificats TLS" contact@example.fr
30 4 * * 0 /usr/local/sbin/scan-docker-cves.sh | mail -s "[VPS] Rapport CVE Docker" contact@example.fr
```