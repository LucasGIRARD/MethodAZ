# Certificats TLS

## Prérequis DNS

Tous les domaines présents dans `/opt/selfhosted/gateway/.env` doivent pointer
vers le VPS avant l'émission :

```bash
dig +short links.example.fr A
dig +short monitoring.example.fr A
```

Si un domaine n'est pas utilisé, il faut le retirer de la commande
`issue_certificate` avant de lancer Certbot.

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
