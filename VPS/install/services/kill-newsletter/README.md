# Kill the Newsletter

Le code amont doit être placé dans `app/` avant le premier démarrage :

```bash
git clone https://github.com/3nprob/kill-the-newsletter.com.git \
  /opt/selfhosted/kill-newsletter/app
sudo vps-compose kill-newsletter up -d --build
```

Ce service reste absent de la liste activée par défaut, car son exposition
SMTP nécessite une stratégie DNS et de réputation distincte.
