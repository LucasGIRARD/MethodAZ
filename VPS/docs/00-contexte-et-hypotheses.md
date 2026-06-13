# Contexte et hypothèses

## Objectif

Mettre en place un VPS Debian 13 « Trixie » propre pour héberger plusieurs
services Docker derrière Nginx, avec HTTPS, pare-feu `iptables`, sauvegardes,
rapports de contrôle et maintenance automatique bornée.

## Architecture cible

```text
Internet
  |
  | 80/tcp, 443/tcp
  v
Conteneur Nginx avec le réseau de l'hôte
  |
  +-- 127.0.0.1:3000 --> Conteneur Grafana
  |                          |
  |                          +--> Prometheus, Node Exporter et cAdvisor facultatif
  |                          +--> Loki et Alloy, facultatifs
  |
  +-- 127.0.0.1:3001..3006 --> Conteneurs Docker dans /opt/selfhosted
                              |
                              +--> PostgreSQL partagé
                                   via un réseau interne propre
```

Les conteneurs applicatifs ne doivent pas exposer de ports publics. Lorsqu'un
service doit être accessible par Nginx, il publie seulement un port local :

```yaml
ports:
  - "127.0.0.1:3001:3000"
```

## DNS à préparer

IPv4 :

```text
A     example.fr              IP_DU_SERVEUR
A     links.example.fr        IP_DU_SERVEUR
A     dav.example.fr          IP_DU_SERVEUR
A     newsletter.example.fr   IP_DU_SERVEUR
A     freshrss.example.fr     IP_DU_SERVEUR
A     ttrss.example.fr        IP_DU_SERVEUR
A     web.example.fr          IP_DU_SERVEUR
A     monitoring.example.fr   IP_DU_SERVEUR
```

IPv6, si disponible :

```text
AAAA  example.fr              IPV6_DU_SERVEUR
AAAA  *.example.fr            IPV6_DU_SERVEUR
```

Attendre la propagation DNS avant de lancer Certbot.

## Ports attendus

Après l'installation, `ss -tulpn` doit principalement afficher :

```text
**000/tcp             SSH, valeur réelle volontairement masquée
**000/tcp             SFTP, même transport SSH
80/tcp                Nginx
443/tcp               Nginx
127.0.0.1:3000        Grafana en conteneur
127.0.0.1:8080        cAdvisor facultatif en conteneur
127.0.0.1:9090        Prometheus en conteneur
127.0.0.1:9100        Node Exporter en conteneur
127.0.0.1:9323        Métriques du démon Docker
127.0.0.1:3100        Loki, si les journaux sont activés
127.0.0.1:3001        Linkwarden
127.0.0.1:3002        Davis
127.0.0.1:3003        FreshRSS
127.0.0.1:3004        Tiny Tiny RSS
127.0.0.1:3005        Kill the Newsletter
127.0.0.1:3006        Apache/PHP
```

Vérification :

```bash
sudo ss -tulpn
sudo iptables -L INPUT -n -v --line-numbers
sudo ip6tables -L INPUT -n -v --line-numbers
docker ps
```

La stratégie complète d'exposition est décrite dans
[l'annexe des ports](08-annexe-ports.md).

## Liste de contrôle

- [ ] Grafana accessible uniquement via Nginx et avec le rôle `Viewer`.
- [ ] Le projet Compose de supervision n'expose que des écoutes sur
  `127.0.0.1`.
- [ ] Les règles IPv4 et IPv6 sont persistantes après redémarrage.
- [ ] Aucun conteneur applicatif publié sur `0.0.0.0`.
- [ ] Nginx est le seul frontal HTTP/HTTPS public.
- [ ] Certbot renouvelle les certificats.
- [ ] Docker Scout scanne les images Docker chaque semaine.
- [ ] Les mises à jour Docker sont appliquées service par service après sauvegarde.
- [ ] Aucune mise à jour automatique aveugle des bases de données.
