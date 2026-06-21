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
