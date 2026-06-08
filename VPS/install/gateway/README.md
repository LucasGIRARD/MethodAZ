# Gateway Nginx et Certbot

Le projet suit trois étapes :

1. `sudo vps-gateway start-http`
2. `sudo vps-gateway issue-certificate`
3. `sudo vps-gateway enable-tls`

La première étape sert les challenges ACME sur le port 80. La deuxième doit
être lancée seulement après propagation DNS. La troisième active les proxys
HTTPS vers les ports locaux `3000` à `3006`.

Commandes d'exploitation :

```bash
sudo vps-gateway test
sudo vps-gateway status
sudo vps-gateway logs
sudo vps-gateway renew
```
