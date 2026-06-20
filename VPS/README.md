# VPS auto-hébergé

Documentation d'installation et de maintenance d'un VPS Debian 13 « Trixie »
avec Docker, Nginx, Certbot, rapports de contrôle et services auto-hébergés.

## Parcours recommandé

Lire et appliquer les documents dans cet ordre :

1. [Contexte et hypothèses](docs/00-contexte-et-hypotheses.md)
2. [Téléchargement depuis GitHub](docs/telechargement-github.md)
3. [Test local avec Docker Compose](docs/test-local-docker.md)
4. [Installation automatisée](docs/installation-automatisee.md)
5. [Base VPS Debian](docs/01-vps-base.md)
6. [Docker](docs/02-docker.md)
7. [Bases de données partagées](docs/bases-donnees-partagees.md)
8. [Services Docker](docs/03-services-docker.md)
9. [Nginx et Certbot dans Docker](docs/04-nginx-certbot.md)
10. [Supervision et rapports](docs/05-supervision-rapports.md)
11. [Dashboard d'observabilité](docs/05-dashboard-observabilite.md)
12. [Maintenance et mises à jour](docs/06-maintenance-mises-a-jour.md)
13. [Commandes utiles](docs/07-commandes-utiles.md)
14. [Annexe : référentiel des ports réseau](docs/08-annexe-ports.md)
15. [Protection contre les scans et limitation Nginx](docs/09-protection-scans-rate-limit.md)
16. [Journalisation, rotation et rétention](docs/10-journalisation-rotation.md)
17. [Sécurité des images Docker](docs/securite-images-docker.md)
18. [Dimensionnement du VPS IONOS](docs/dimensionnement-vps-ionos.md)
19. [Restauration complète sur un VPS vierge](docs/procedures/restauration-vps-vierge.md)
20. [Retour arrière après une mise à jour](docs/procedures/retour-arriere-mise-a-jour.md)
21. [Ajouter une application](docs/procedures/ajout-application.md)

## Décisions actives

- Système : dernière Debian stable, actuellement Debian 13.5 « Trixie ».
- Pare-feu : commandes `iptables`/`ip6tables` avec le frontal nftables de Debian.
- Persistance du pare-feu : `iptables-persistent` et `netfilter-persistent`.
- Proxy inverse public : Nginx conteneurisé avec le réseau de l'hôte.
- Certificats TLS : Certbot conteneurisé en mode `webroot`.
- Répertoire applicatif : `/opt/selfhosted`.
- Bases SQL : une instance PostgreSQL officielle partagée par les cinq
  applications SQL, sans port publié.
- Ports applicatifs Docker : publiés seulement sur `127.0.0.1`.
- Port SSH personnalisé : valeur réelle secrète, représentée publiquement par `**000`.
- SFTP : compte séparé, sans shell, chrooté et authentifié par clé sur le port
  SSH.
- Installation : script Bash rejouable par phases, configuration publique et
  secrets séparés.
- Supervision web : Grafana, Prometheus et Node Exporter dans un projet Docker
  Compose lié uniquement à `127.0.0.1`. cAdvisor est facultatif.
- Journaux dans Grafana : Loki et Alloy facultatifs, contrôlés par
  `/etc/default/vps-monitoring`.
- Mises à jour Docker : vérification et mise à jour manuelle, sans mise à jour automatique aveugle.
- Images Docker : tags précis, verrouillage local par digest et audit des CVE
  avec Docker Scout.
- Journaux : rotation et rétention bornées pour journald, Docker, Nginx,
  Fail2ban, Certbot, msmtp et les rapports locaux.
- Maintenance : sauvegarde et contrôles démarrés vers `02:15`, puis mises à
  jour Debian à `04:15` et `04:45`, selon le fuseau `Europe/Paris`.
- Restaurations : test SQL isolé le premier jour du mois.
- Sauvegarde externe : Restic chiffré vers Koofr via rclone, facultatif et
  désactivé par défaut. Un backend S3 reste possible.
- Ressources : limites mémoire `VPS_2G` ou `VPS_4G`.

## Installation rapide

Télécharger d'abord uniquement le bundle `VPS` en suivant
[Téléchargement depuis GitHub](docs/telechargement-github.md).

Créer ensuite `install/config/vps.env` depuis le modèle
[vps.env.example de la dernière release](https://github.com/LucasGIRARD/MethodAZ/releases/latest/download/vps.env.example)
ou, à défaut, depuis la
[branche main](https://raw.githubusercontent.com/LucasGIRARD/MethodAZ/main/VPS/install/config/vps.env.example),
puis lancer :

```bash
sh install/scripts/generate-secrets.sh
sudo sh install/scripts/vps-install.sh --phase all
```

Le premier passage crée le compte administrateur sudoer, bloque SSH pour root
et conserve temporairement le port SSH 22 pour le compte administrateur. Après
validation de SSH et SFTP sur le port réel, la finalisation ferme le port 22 :

```bash
sudo vps-install --finalize-ssh
```

## Validation continue

Le workflow [Validation VPS](../.github/workflows/validate-vps.yml) exécute
Compose, ShellCheck, l'analyse PowerShell, le contrôle des liens Markdown, le
contrôle des versions d'images et Gitleaks à chaque modification de `VPS/`.

La validation locale principale reste :

```bash
sh install/scripts/validate-bundle.sh
pwsh install/scripts/validate-repository.ps1
```

## Variables à remplacer

```bash
DOMAIN="example.fr"
MONITORING_DOMAIN="monitoring.example.fr"
SERVER_IP="IP_DU_SERVEUR"
SSH_PORT="**000"
ADMIN_USER="lucas"
EMAIL_ADMIN="contact@example.fr"
TZ="Europe/Paris"
```

`**000` est volontairement masqué. Cette valeur ne doit pas être exécutée ni
copiée telle quelle : elle doit être remplacée localement par le port SSH réel.

## Sous-domaines prévus

```text
links.example.fr       Linkwarden
dav.example.fr         Davis / CalDAV / CardDAV / WebDAV
newsletter.example.fr  Kill the Newsletter
freshrss.example.fr    FreshRSS
ttrss.example.fr       Tiny Tiny RSS
web.example.fr         Hébergement PHP/PostgreSQL/HTML
```

## Archives

Les anciennes notes et les brouillons sont conservés sous [docs/archive](docs/archive/README.md).
Ils servent d'historique, mais ne font plus partie de la procédure active.
