# Kill the Newsletter

## Fichiers

- Modèle : `install/services/kill-newsletter/docker-compose.yml`
- Installation : `/opt/selfhosted/kill-newsletter`
- Port HTTP : `127.0.0.1:3005`
- Domaine : `newsletter.example.fr`

Le service est construit depuis son dépôt source :

```bash
sudo git clone https://github.com/3nprob/kill-the-newsletter.com.git \
  /opt/selfhosted/kill-newsletter/app
sudo vps-compose kill-newsletter up -d --build
```

Il n'est pas activé par défaut. La réception de courriels depuis Internet
nécessite une conception séparée pour SMTP, MX, SPF, DKIM, DMARC, DNS inverse
et réputation IP. Ne pas ouvrir un port SMTP à partir de ce seul modèle.

## Données

```text
/opt/selfhosted/kill-newsletter/data
```
