Recommandation : ne pas exposer Cockpit via un sous-domaine public au début. Garde-le sur `:9090`, protégé par UFW, ou utilise un VPN type WireGuard/Tailscale plus tard.

Hypothèses à remplacer :

```Bash
DOMAIN="example.fr"
SSH_PORT="2222"
ADMIN_USER="lucas"
EMAIL_ADMIN="contact@example.fr"
TZ="Europe/Paris"
```

Sous-domaines proposés :

```
links.example.fr       Linkwarden
dav.example.fr         Davis / CalDAV / CardDAV / WebDAV
newsletter.example.fr  Kill the Newsletter
freshrss.example.fr    FreshRSS
ttrss.example.fr       Tiny Tiny RSS
.example.fr         Hébergement PHP/MySQL/HTML
```

# 1. Préparation DNS

IPv4
```
A     example.fr              IP_DU_SERVEUR
A     links.example.fr        IP_DU_SERVEUR
A     dav.example.fr          IP_DU_SERVEUR
A     newsletter.example.fr   IP_DU_SERVEUR
A     freshrss.example.fr     IP_DU_SERVEUR
A     ttrss.example.fr        IP_DU_SERVEUR
A     web.example.fr          IP_DU_SERVEUR
```

IPv6 (Optionnel)
```
AAAA  example.fr              IPV6_DU_SERVEUR
AAAA  *.example.fr            IPV6_DU_SERVEUR
```

Attendre la propagation DNS avant de lancer HTTPS.



Webadmin système : Cockpit  
Mises à jour Docker : Watchtower en mode notification / vérification, pas auto-update aveugle  
Scan CVE : Trivy  
Certificats : Caddy gère le renouvellement, mais on ajoute un script de contrôle  
Noyau / paquets Debian : unattended-upgrades + rapport périodique

# Résultat final attendu

Tu auras :

```
Cockpit             https://IP_DU_SERVEUR:9090
Rapport santé       /var/log/server-checks/health-report.txt
Rapport noyau       /var/log/server-checks/kernel-check.txt
Rapport certificats /var/log/server-checks/certificates.txt
Rapports CVE        /var/log/server-checks/trivy/
Vérif images Docker docker logs watchtower
```

Pour une configuration prudente :

```
[ ] Cockpit ouvert seulement à ton IP ou via VPN
[ ] Watchtower en monitor-only
[ ] Trivy lancé chaque semaine
[ ] Reboot noyau fait manuellement après vérification
[ ] Certificats contrôlés même si Caddy renouvelle automatiquement
[ ] Aucun auto-update aveugle des bases de données
```


# Ports attendus

Avec cette version, `ss -tulpn` doit surtout montrer :

```
22 ou 2222/tcp       SSH
80/tcp               Nginx
443/tcp              Nginx
9090/tcp             Cockpit, idéalement limité par UFW
127.0.0.1:3001       Linkwarden
127.0.0.1:3002       Davis
127.0.0.1:3003       FreshRSS
127.0.0.1:3004       tt-rss
127.0.0.1:3005       Kill the Newsletter
127.0.0.1:3006       Apache/PHP
```

Vérification :

```Bash
sudo ss -tulpn
sudo ufw status verbose
```

---

# Résumé de la correction

```
[REMPLACÉ] Caddy
[AJOUTÉ]   Nginx hôte Debian comme reverse proxy HTTPS
[AJOUTÉ]   Certbot + plugin Nginx
[AJOUTÉ]   Apache/PHP en conteneur pour hébergement web
[RETIRÉ]   Watchtower
[AJOUTÉ]   Script check-docker-image-updates.sh
[CONSERVÉ] Trivy pour CVE
[CONSERVÉ] Cockpit pour panneau webadmin
[CONSERVÉ] Fail2ban, UFW, rapports, vérification noyau
```