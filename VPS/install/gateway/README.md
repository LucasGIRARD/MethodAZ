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

Dépannage rapide :

```bash
sudo test -f /opt/selfhosted/gateway/docker-compose.yml \
  || sudo vps-install --phase gateway
sudo vps-gateway status
sudo vps-gateway logs
```

Si `WEB_SERVER_NAMES` manque dans les warnings Compose, rejouer
`sudo vps-install --phase gateway`. Si `nginx` n'est pas démarré, utiliser
`sudo vps-gateway start-http` avant le certificat, ou
`sudo vps-gateway enable-tls` après l'émission du certificat.
