# Proxy inverse et sécurité HTTP

## Réseau

Nginx utilise `network_mode: host` pour joindre les applications publiées
uniquement sur `127.0.0.1`. Le projet Compose ne déclare donc aucun bloc
`ports`.

## Configuration versionnée

```text
install/gateway/nginx/nginx.conf
install/gateway/nginx/proxy-common.conf
install/gateway/nginx/templates/
install/gateway/nginx/templates-disabled/
```

L'image officielle Nginx transforme les fichiers `.template` avec les domaines
de `.env`. Les variables Nginx telles que `$host` restent dans le résultat.

## Limites de débit

Le profil commun définit :

```nginx
limit_req_zone $binary_remote_addr zone=per_ip_general:20m rate=10r/s;
limit_req_zone $binary_remote_addr zone=per_ip_dav:20m rate=30r/s;
limit_conn_zone $binary_remote_addr zone=per_ip_conn:20m;
```

Davis utilise le profil DAV plus permissif. Les autres applications utilisent
le profil général. Les réponses de dépassement utilisent le statut `429`.

## Grafana

Grafana reste anonyme en rôle `Viewer` derrière Nginx, mais Nginx impose une
authentification HTTP :

```text
/opt/selfhosted/gateway/nginx/auth/.htpasswd-monitoring
```

L'installateur génère ce fichier à partir de `GRAFANA_HTTP_PASSWORD` sans
exposer le mot de passe dans le fichier Compose.

## En-têtes proxy

Le fichier commun transmet :

```text
Host
X-Real-IP
X-Forwarded-For
X-Forwarded-Host
X-Forwarded-Proto
```

Grafana reçoit aussi les en-têtes nécessaires aux WebSockets.

## Vérification

```bash
sudo vps-gateway test
sudo docker compose \
  -f /opt/selfhosted/gateway/docker-compose.yml \
  exec nginx nginx -T
```

La sortie complète peut contenir les domaines réels. Ne pas la publier sans
relecture.
