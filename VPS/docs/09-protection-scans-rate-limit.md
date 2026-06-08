# Protection contre les scans et limitation Nginx

## Objectif

Ajouter trois couches de protection :

1. `iptables` détecte et journalise les scans TCP ou UDP rapides visant des
   ports fermés.
2. Fail2ban lit ces événements et bannit temporairement leur adresse source sur
   tous les ports.
3. Nginx limite les requêtes et les connexions HTTP par adresse IP.

Ces protections réduisent le bruit et les abus simples. Elles ne bloquent pas
fiablement les scans très lents, distribués ou effectués depuis de nombreuses
adresses IP.

## Détection des scans par iptables

Les règles doivent être placées à la fin de la chaîne `INPUT`, après les ports
autorisés et juste avant `COMMIT`. Elles ne journalisent donc que les nouvelles
tentatives qui auraient autrement atteint la politique `DROP`.

### IPv4

Ajouter avant `COMMIT` dans `/etc/iptables/rules.v4` :

```iptables
# Journaliser les scans TCP rapides vers les ports fermés.
-A INPUT -p tcp --syn -m hashlimit --hashlimit-above 15/minute --hashlimit-burst 20 --hashlimit-mode srcip --hashlimit-name portscan4 -m limit --limit 10/second --limit-burst 20 -j LOG --log-prefix "IPT_PORTSCAN " --log-level 6

# Journaliser les scans UDP rapides vers les ports fermés.
-A INPUT -p udp -m hashlimit --hashlimit-above 30/minute --hashlimit-burst 30 --hashlimit-mode srcip --hashlimit-name udpscan4 -m limit --limit 10/second --limit-burst 20 -j LOG --log-prefix "IPT_UDPSCAN " --log-level 6
```

### IPv6

Ajouter avant `COMMIT` dans `/etc/iptables/rules.v6` :

```iptables
# Journaliser les scans TCP rapides vers les ports fermés.
-A INPUT -p tcp --syn -m hashlimit --hashlimit-above 15/minute --hashlimit-burst 20 --hashlimit-mode srcip --hashlimit-name portscan6 -m limit --limit 10/second --limit-burst 20 -j LOG --log-prefix "IPT_PORTSCAN " --log-level 6

# Journaliser les scans UDP rapides vers les ports fermés.
-A INPUT -p udp -m hashlimit --hashlimit-above 30/minute --hashlimit-burst 30 --hashlimit-mode srcip --hashlimit-name udpscan6 -m limit --limit 10/second --limit-burst 20 -j LOG --log-prefix "IPT_UDPSCAN " --log-level 6
```

Le module `hashlimit` calcule le seuil par adresse source. Le second module
`limit` plafonne globalement les écritures dans le journal afin qu'un attaquant
ne puisse pas le remplir facilement.

Les règles `LOG` ne bloquent pas elles-mêmes le paquet. La politique `DROP` de
la chaîne `INPUT` s'applique ensuite.

## Appliquer les règles

Tester la syntaxe :

```bash
sudo iptables-restore --test /etc/iptables/rules.v4
sudo ip6tables-restore --test /etc/iptables/rules.v6
```

Appliquer avec retour arrière automatique :

```bash
sudo iptables-apply -t 30 /etc/iptables/rules.v4
sudo ip6tables-apply -t 30 /etc/iptables/rules.v6
```

Si Docker est déjà démarré, recréer ensuite ses chaînes :

```bash
sudo systemctl restart docker
docker ps
```

Contrôler les événements :

```bash
sudo journalctl -k -g 'IPT_PORTSCAN|IPT_UDPSCAN'
```

## Filtre Fail2ban pour les scans

Créer :

```bash
sudo nano /etc/fail2ban/filter.d/iptables-portscan.conf
```

Contenu :

```ini
[Definition]
failregex = ^.*IPT_(?:PORT|UDP)SCAN .*SRC=<HOST>\s.*$
ignoreregex =
journalmatch = _TRANSPORT=kernel
```

Créer la jail :

```bash
sudo nano /etc/fail2ban/jail.d/iptables-portscan.local
```

Contenu :

```ini
[iptables-portscan]
enabled = true
filter = iptables-portscan
backend = systemd
ignoreip = 127.0.0.1/8 ::1 TON_IP_FIXE TON_IPV6_FIXE
maxretry = 3
findtime = 2m
bantime = 24h
banaction = iptables-allports
```

Avec le backend `systemd`, ne pas définir `logpath`. Fail2ban lit directement
les événements du noyau dans le journal systemd.

Vérifier et redémarrer :

```bash
sudo fail2ban-client -t
sudo systemctl restart fail2ban
sudo fail2ban-client status iptables-portscan
```

Afficher les bannissements :

```bash
sudo fail2ban-client get iptables-portscan banip
sudo journalctl -u fail2ban --since "1 hour ago"
```

Débannir une adresse :

```bash
sudo fail2ban-client set iptables-portscan unbanip ADRESSE_IP
```

## Limitation globale dans Nginx

Nginx limite les requêtes avec un mécanisme de type « seau percé ». Les zones
doivent être définies dans le contexte `http`, avant leur utilisation dans les
blocs `server` ou `location`.

Créer :

```bash
nano /opt/selfhosted/gateway/nginx/conf.d/02-rate-limit.conf
```

Contenu initial en mode observation :

```nginx
# Requêtes HTTP ordinaires.
limit_req_zone $binary_remote_addr zone=per_ip_general:20m rate=10r/s;

# WebDAV génère davantage de requêtes qu'une navigation ordinaire.
limit_req_zone $binary_remote_addr zone=per_ip_dav:20m rate=30r/s;

# Modèle réservé aux pages sensibles après identification de leur URL exacte.
limit_req_zone $binary_remote_addr zone=per_ip_sensitive:10m rate=5r/m;

# Nombre de requêtes concurrentes traitées par adresse IP.
limit_conn_zone $binary_remote_addr zone=per_ip_conn:20m;

limit_req_status 429;
limit_conn_status 429;
limit_req_log_level notice;
limit_conn_log_level notice;

# Observer pendant 24 à 48 heures avant de réellement rejeter.
limit_req_dry_run on;
limit_conn_dry_run on;
```

Le fichier `nginx.conf` du projet `gateway` inclut
`/etc/nginx/conf.d/*.conf` dans le contexte `http`. Vérifier :

```bash
docker compose \
  -f /opt/selfhosted/gateway/docker-compose.yml \
  exec nginx nginx -T | grep -F 'conf.d/*.conf'
```

## Appliquer un profil à un service

Pour Grafana, Linkwarden, FreshRSS, Tiny Tiny RSS, Kill the Newsletter et
l'hébergement web, ajouter dans le bloc `server` :

```nginx
limit_conn per_ip_conn 30;
```

Puis ajouter au début de `location /` :

```nginx
limit_req zone=per_ip_general burst=40 nodelay;
```

Pour Davis/WebDAV, utiliser des seuils plus élevés :

```nginx
limit_conn per_ip_conn 60;

location / {
    limit_req zone=per_ip_dav burst=120 nodelay;

    # Conserver ici les directives proxy_pass et proxy_set_header existantes.
}
```

Pour une page de connexion dont l'URL exacte a été vérifiée :

```nginx
location = /URL_CONNEXION {
    limit_req zone=per_ip_sensitive burst=5 nodelay;

    # Conserver ici les directives proxy_pass et proxy_set_header nécessaires.
}
```

Ne pas créer ce dernier bloc avec une URL supposée : un mauvais découpage des
blocs `location` peut modifier le routage de l'application.

## Passage du mode observation au blocage

Tester puis recharger :

```bash
docker compose \
  -f /opt/selfhosted/gateway/docker-compose.yml \
  exec nginx nginx -t
docker compose \
  -f /opt/selfhosted/gateway/docker-compose.yml \
  exec nginx nginx -s reload
```

Observer pendant 24 à 48 heures :

```bash
sudo grep -E 'limiting requests|limiting connections' \
  /opt/selfhosted/gateway/logs/nginx/error.log
```

Si les clients légitimes ne dépassent pas les seuils, modifier
`/opt/selfhosted/gateway/nginx/conf.d/02-rate-limit.conf` :

```nginx
limit_req_dry_run off;
limit_conn_dry_run off;
```

Puis appliquer :

```bash
docker compose \
  -f /opt/selfhosted/gateway/docker-compose.yml \
  exec nginx nginx -t
docker compose \
  -f /opt/selfhosted/gateway/docker-compose.yml \
  exec nginx nginx -s reload
```

Les requêtes refusées reçoivent alors le statut HTTP `429`.

## Bannir les abus HTTP avec Fail2ban

La limitation Nginx suffit souvent. Une jail supplémentaire peut bannir une
adresse qui continue à dépasser les limites.

Créer :

```bash
sudo nano /etc/fail2ban/filter.d/nginx-rate-limit.conf
```

Contenu :

```ini
[Definition]
failregex = ^.*limiting (?:requests|connections).*client: <HOST>,.*$
ignoreregex =
```

Créer :

```bash
sudo nano /etc/fail2ban/jail.d/nginx-rate-limit.local
```

Contenu :

```ini
[nginx-rate-limit]
enabled = true
filter = nginx-rate-limit
backend = auto
logpath = /opt/selfhosted/gateway/logs/nginx/error.log
ignoreip = 127.0.0.1/8 ::1 TON_IP_FIXE TON_IPV6_FIXE
maxretry = 20
findtime = 2m
bantime = 1h
banaction = iptables-allports
```

Tester le filtre sur les événements existants :

```bash
sudo fail2ban-regex \
  /opt/selfhosted/gateway/logs/nginx/error.log \
  /etc/fail2ban/filter.d/nginx-rate-limit.conf
```

Zéro correspondance est normal tant que Nginx n'a pas journalisé de
dépassement.

Activer :

```bash
sudo fail2ban-client -t
sudo systemctl restart fail2ban
sudo fail2ban-client status nginx-rate-limit
```

## Cas d'un proxy ou CDN placé devant Nginx

Cette configuration suppose que Nginx reçoit directement les connexions
Internet. Si Cloudflare, un CDN ou un autre proxy est ajouté, `$remote_addr`
contiendra son adresse.

Il faut alors configurer `set_real_ip_from` et `real_ip_header` avec les plages
officielles du fournisseur avant d'utiliser le rate limiting ou Fail2ban.
Sinon, le proxy partagé risque d'être limité ou banni à la place du client.

## Limites et réglages

- Un changement de port SSH n'empêche pas sa découverte.
- Les scans lents sous les seuils ne sont pas détectés.
- Un scan distribué peut rester sous le seuil pour chaque adresse IP.
- Une adresse partagée par plusieurs utilisateurs, comme une entreprise ou un
  opérateur mobile, nécessite des seuils moins stricts.
- HTTP/2 et HTTP/3 comptent chaque requête concurrente dans `limit_conn`.
- WebDAV, la synchronisation et les API nécessitent souvent des valeurs plus
  élevées que les pages web classiques.
- Ne jamais bannir automatiquement une adresse d'administration connue sans
  l'ajouter à `ignoreip` dans Fail2ban.

## Références

- [Fail2ban : configuration des jails](https://github.com/fail2ban/fail2ban/blob/master/config/jail.conf)
- [Nginx : limitation des requêtes](https://nginx.org/en/docs/http/ngx_http_limit_req_module.html)
- [Nginx : limitation des connexions](https://nginx.org/en/docs/http/ngx_http_limit_conn_module.html)
- [Debian : extensions iptables](https://manpages.debian.org/trixie/iptables/iptables-extensions.8.en.html)
