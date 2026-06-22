# Nginx et Certbot dans Docker

## Objectif

Publier les applications locales avec un unique frontal Nginx et gérer les
certificats avec Certbot. Ce document résume le cycle de vie du projet
`gateway`.

## Architecture

```text
Internet :80/:443
        |
        v
Nginx avec network_mode: host
        |
        +-- 127.0.0.1:3000  Grafana
        +-- 127.0.0.1:3001  Linkwarden
        +-- 127.0.0.1:3002  Davis
        +-- 127.0.0.1:3003  FreshRSS
        +-- 127.0.0.1:3004  Tiny Tiny RSS
        +-- 127.0.0.1:3005  Kill the Newsletter
        +-- 127.0.0.1:3006  Apache/PHP
```

Le détail des choix Nginx est dans
[Proxy inverse et sécurité HTTP](gateway/proxy-inverse.md). Le cycle ACME est
dans [Certificats TLS](gateway/certificats-tls.md).

## Fichiers

| Élément | Source versionnée | Installation |
| --- | --- | --- |
| Compose | `install/gateway/docker-compose.yml` | `/opt/selfhosted/gateway/docker-compose.yml` |
| Nginx | `install/gateway/nginx` | `/opt/selfhosted/gateway/nginx` |
| Certbot | `install/gateway/certbot` | `/opt/selfhosted/gateway/certbot` |
| Commande | `install/gateway/scripts/vps-gateway` | `/usr/local/sbin/vps-gateway` |

Le projet est copié par :

```bash
sudo vps-install --phase gateway
```

## Déploiement en trois étapes

### 1. HTTP pour ACME

```bash
sudo vps-gateway start-http
```

Nginx écoute sur le port 80, sert uniquement
`/.well-known/acme-challenge/` et retourne `404` ailleurs. Aucun faux HTTPS
n'est annoncé avant l'existence du certificat.

### 2. Certificat

Après propagation de tous les enregistrements DNS :

```bash
sudo vps-gateway issue-certificate
```

### 3. TLS et proxys

```bash
sudo vps-gateway enable-tls
```

La commande vérifie la présence du certificat, remplace le profil HTTP
d'amorçage par la redirection HTTPS, active les serveurs virtuels et valide la
configuration Nginx.

## Commandes courantes

```bash
sudo vps-gateway test
sudo vps-gateway status
sudo vps-gateway logs
sudo vps-gateway renew
```

## Dépannage

### Ports 80/443 inaccessibles depuis Internet

Avant Certbot, le port 80 doit être joignable publiquement. Depuis le poste
client :

```powershell
Test-NetConnection IP_DU_SERVEUR -Port 80
Test-NetConnection IP_DU_SERVEUR -Port 443
```

Si `TcpTestSucceeded` vaut `False`, vérifier d'abord que Nginx écoute sur le
VPS :

```bash
sudo ss -ltnp | grep -E ':(80|443)\b'
curl -I http://127.0.0.1
sudo docker inspect gateway-nginx-1 --format '{{.HostConfig.NetworkMode}}'
```

La valeur attendue pour le conteneur est `host`, et `ss` doit montrer
`0.0.0.0:80` ou `[::]:80`. Si le VPS répond localement mais pas depuis
Internet, ouvrir les ports entrants TCP `80` et `443` dans le pare-feu réseau du
fournisseur, en plus du pare-feu Linux.

### DNS, IPv4 et IPv6

Tous les domaines demandés au certificat doivent pointer vers le VPS. Vérifier
les enregistrements `A` et `AAAA` :

```powershell
Resolve-DnsName example.fr -Type A
Resolve-DnsName example.fr -Type AAAA
```

Si le VPS n'est pas configuré en IPv6, supprimer les enregistrements `AAAA` des
domaines concernés. Let's Encrypt peut tenter IPv6 ; un ancien `AAAA` vers un
autre serveur peut provoquer :

```text
The key authorization file from the server did not match this challenge
```

Pour tester l'IPv4 en forçant la cible :

```powershell
curl.exe --resolve example.fr:80:IP_DU_SERVEUR `
  http://example.fr/.well-known/acme-challenge/ping
```

### `WEB_SERVER_NAMES` non défini

Si Docker Compose affiche :

```text
The "WEB_SERVER_NAMES" variable is not set. Defaulting to a blank string.
```

recréer la configuration gateway depuis le fichier public :

```bash
sudo vps-install --phase gateway
```

La phase régénère `/opt/selfhosted/gateway/.env` avec `WEB_DOMAIN`,
`WEB_SUBDOMAINS` et `WEB_SERVER_NAMES`.

### Fichier Compose gateway absent

Si Docker Compose affiche :

```text
no configuration file provided: not found
```

vérifier que le projet gateway a bien été copié :

```bash
sudo ls -l /opt/selfhosted/gateway/docker-compose.yml
sudo ls -l /opt/vps-install/gateway/docker-compose.yml
```

Si le modèle existe sous `/opt/vps-install`, rejouer :

```bash
sudo vps-install --phase gateway
```

Si le modèle manque aussi sous `/opt/vps-install`, le bundle installé est
incomplet ou ancien ; retélécharger une release propre avant de rejouer la
phase gateway.

### Nginx non démarré

Si `sudo vps-gateway test` affiche :

```text
service "nginx" is not running
```

contrôler l'état et les logs :

```bash
sudo vps-gateway status
sudo docker compose \
  --project-directory /opt/selfhosted/gateway \
  -f /opt/selfhosted/gateway/docker-compose.yml \
  ps -a
sudo vps-gateway logs
```

Avant l'émission du certificat, relancer l'amorçage HTTP :

```bash
sudo vps-gateway start-http
```

Après émission du certificat, relancer plutôt l'activation TLS :

```bash
sudo vps-gateway enable-tls
```

### `502 Bad Gateway` sur une application

Un `502` depuis HTTPS signifie généralement que Nginx fonctionne, mais que le
service local derrière le proxy ne répond pas. Les ports attendus sont :

```text
127.0.0.1:3001  Linkwarden
127.0.0.1:3002  Davis
127.0.0.1:3003  FreshRSS
127.0.0.1:3004  Tiny Tiny RSS
127.0.0.1:3005  Kill the Newsletter
127.0.0.1:3006  Apache/PHP
```

Contrôler d'abord les projets et les ports locaux :

```bash
sudo vps-compose all ps
sudo ss -ltnp | grep -E ':(3001|3002|3003|3004|3005|3006)\b'

curl -i --max-time 5 http://127.0.0.1:3001/
curl -i --max-time 5 http://127.0.0.1:3002/
curl -i --max-time 5 -H 'Host: newsletter.example.fr' http://127.0.0.1:3005/
```

Le test newsletter est volontairement en HTTP. TLS est terminé par Nginx ; un
test direct en HTTPS sur `127.0.0.1:3005` n'est pas attendu fonctionnel. Comme
le service utilise `network_mode: host`, le port `3005` doit être porté par le
processus applicatif, pas par `docker-proxy`.

Si un port ne répond pas, regarder le service correspondant puis le relancer :

```bash
sudo vps-compose linkwarden logs --tail=100 app
sudo vps-compose davis logs --tail=100 app nginx migrate
sudo vps-compose kill-newsletter logs --tail=100 app

sudo vps-compose databases up -d
sudo vps-compose linkwarden up -d
sudo vps-compose davis up -d
sudo vps-compose kill-newsletter up -d --build
```

Après correction, recharger le gateway :

```bash
sudo vps-gateway test
sudo vps-gateway enable-tls
```

### `500` sur le monitoring

Pour le monitoring, distinguer d'abord un problème Grafana d'un problème
d'authentification Nginx :

```bash
curl -i --max-time 5 http://127.0.0.1:3000/api/health
sudo vps-monitoring status
sudo vps-monitoring logs grafana
sudo docker logs gateway-nginx-1 --tail=100
```

Si l'API locale Grafana répond `200` mais que HTTPS répond `500`, vérifier le
fichier htpasswd monté dans Nginx. Le conteneur doit pouvoir traverser le
dossier et lire le fichier :

```bash
sudo ls -ld /opt/selfhosted/gateway/nginx/auth
sudo ls -l /opt/selfhosted/gateway/nginx/auth/.htpasswd-monitoring

sudo chmod 0755 /opt/selfhosted/gateway/nginx/auth
sudo chmod 0644 /opt/selfhosted/gateway/nginx/auth/.htpasswd-monitoring
sudo vps-gateway test
sudo vps-gateway enable-tls
```

Si l'API locale Grafana ne répond pas, relancer la supervision :

```bash
sudo vps-monitoring apply
sudo vps-monitoring logs grafana
```

### Certificat absent

Si `sudo vps-gateway enable-tls` affiche :

```text
Certificat absent : certbot/conf/live/vps-services/fullchain.pem
```

le certificat n'a pas encore été émis, ou l'émission a échoué. Reprendre dans
l'ordre :

```bash
sudo vps-gateway start-http

curl -I http://links.example.fr/.well-known/acme-challenge/test
curl -I http://monitoring.example.fr/.well-known/acme-challenge/test

sudo vps-gateway issue-certificate
sudo vps-gateway enable-tls
```

Le test ACME doit répondre depuis le Nginx du VPS avant l'appel Certbot. Un
statut `404` est acceptable pour le fichier `test` inexistant ; un timeout, une
erreur DNS ou une réponse d'un autre serveur ne l'est pas.

### Challenges ACME en `404` ou contenu différent

Si Certbot échoue avec :

```text
Invalid response from http://DOMAINE/.well-known/acme-challenge/...: 404
```

ou :

```text
The key authorization file from the server did not match this challenge
```

remettre le gateway en mode HTTP d'amorçage, nettoyer les anciens challenges,
puis relancer l'émission :

```bash
sudo vps-gateway start-http
sudo rm -rf /opt/selfhosted/gateway/certbot/www/.well-known/acme-challenge
sudo install -d -m 0755 \
  /opt/selfhosted/gateway/certbot/www/.well-known/acme-challenge

echo ok | sudo tee \
  /opt/selfhosted/gateway/certbot/www/.well-known/acme-challenge/ping >/dev/null
curl -s http://links.example.fr/.well-known/acme-challenge/ping

sudo vps-gateway issue-certificate
```

Le `curl` doit afficher `ok` pour chaque domaine demandé au certificat. Si un
domaine répond `404`, pointe vers un autre serveur ou répond avec un autre
contenu, corriger DNS/Nginx avant de relancer Certbot.

Si le `curl` répond `403 Forbidden`, Nginx atteint bien le webroot ACME mais ne
peut pas traverser ou lire les dossiers. Corriger les permissions publiques du
webroot ACME :

```bash
sudo chmod 0755 /opt/selfhosted/gateway/certbot/www
sudo chmod 0755 /opt/selfhosted/gateway/certbot/www/.well-known
sudo chmod 0755 /opt/selfhosted/gateway/certbot/www/.well-known/acme-challenge
sudo find /opt/selfhosted/gateway/certbot/www/.well-known/acme-challenge \
  -type f -exec chmod 0644 {} \;
sudo vps-gateway start-http
```

## Vérification

```bash
curl -I http://links.example.fr
curl -I https://links.example.fr
curl -I https://monitoring.example.fr
sudo ss -ltnp | grep -E ':(80|443)\b'
```

Les ports `80` et `443` sont les seuls ports web publics.

Pour l'hébergement web générique, `WEB_DOMAIN` route le domaine racine vers
`/opt/selfhosted/web/html`. Les labels listés dans `WEB_SUBDOMAINS` sont ajoutés
à Nginx et au certificat, puis routés par Apache vers un dossier du même nom,
par exemple `www.example.fr` vers `/opt/selfhosted/web/html/www`.
