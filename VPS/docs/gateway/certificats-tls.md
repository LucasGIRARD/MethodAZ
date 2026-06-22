# Certificats TLS

## Prérequis DNS

Tous les domaines présents dans `/opt/selfhosted/gateway/.env` doivent pointer
vers le VPS avant l'émission :

```bash
dig +short links.example.fr A
dig +short monitoring.example.fr A
dig +short links.example.fr AAAA
```

Si le VPS n'est pas configuré et ouvert en IPv6, ne pas publier
d'enregistrement `AAAA` pour ces domaines. Let's Encrypt peut utiliser IPv6
même si l'IPv4 est correcte.

Si un domaine n'est pas utilisé, il faut le retirer de la commande
`issue_certificate` avant de lancer Certbot.

Le port 80 doit aussi être joignable depuis Internet avant l'émission. Depuis
un poste client :

```powershell
Test-NetConnection IP_DU_SERVEUR -Port 80
```

Si le VPS répond localement (`curl -I http://127.0.0.1`) mais pas depuis le
client, ouvrir TCP `80` et `443` dans le pare-feu réseau du fournisseur.

## Amorçage HTTP

```bash
sudo vps-gateway start-http
```

Tester le chemin ACME :

```bash
curl -I \
  http://links.example.fr/.well-known/acme-challenge/test
```

Un statut `404` confirme que la requête atteint le bon Nginx.

## Émission

```bash
sudo vps-gateway issue-certificate
```

Le certificat SAN est nommé `vps-services` et couvre les domaines configurés.

## Activation TLS

```bash
sudo vps-gateway enable-tls
```

Les paramètres actifs imposent TLS 1.2 ou 1.3, désactivent les tickets de
session et utilisent un cache de session partagé.

Si la commande affiche :

```text
Certificat absent : certbot/conf/live/vps-services/fullchain.pem
```

ne pas forcer TLS. Revenir à l'amorçage HTTP, vérifier les domaines, puis
émettre le certificat :

```bash
sudo vps-gateway start-http
curl -I http://links.example.fr/.well-known/acme-challenge/test
sudo vps-gateway issue-certificate
sudo vps-gateway enable-tls
```

Le chemin ACME peut répondre `404` pour le fichier `test`, mais il doit être
servi par le Nginx du VPS.

Si Certbot reçoit `404` sur ses propres fichiers de challenge, ou si Let's
Encrypt indique que le contenu servi ne correspond pas au challenge attendu,
nettoyer le webroot ACME puis tester avec un fichier réel :

```bash
sudo vps-gateway start-http
sudo rm -rf /opt/selfhosted/gateway/certbot/www/.well-known/acme-challenge
sudo install -d -m 0755 \
  /opt/selfhosted/gateway/certbot/www/.well-known/acme-challenge
echo ok | sudo tee \
  /opt/selfhosted/gateway/certbot/www/.well-known/acme-challenge/ping >/dev/null
curl -s http://links.example.fr/.well-known/acme-challenge/ping
```

Le `curl` doit retourner `ok` avant de relancer
`sudo vps-gateway issue-certificate`.

Si le `curl` retourne `403 Forbidden`, rendre le webroot ACME traversable par
le worker Nginx :

```bash
sudo chmod 0755 /opt/selfhosted/gateway/certbot/www
sudo chmod 0755 /opt/selfhosted/gateway/certbot/www/.well-known
sudo chmod 0755 /opt/selfhosted/gateway/certbot/www/.well-known/acme-challenge
sudo find /opt/selfhosted/gateway/certbot/www/.well-known/acme-challenge \
  -type f -exec chmod 0644 {} \;
```

## Renouvellement

Test :

```bash
sudo docker compose \
  -f /opt/selfhosted/gateway/docker-compose.yml \
  run --rm certbot renew --dry-run
```

Renouvellement réel :

```bash
sudo vps-gateway renew
```

La commande recharge Nginx après le renouvellement.

## Rétention

Certbot conserve au maximum 30 archives selon :

```text
/opt/selfhosted/gateway/certbot/conf/cli.ini
```
