# Test local avec Docker Compose

## Objectif

Tester les projets Docker applicatifs sans modifier Debian, SSH, le pare-feu
ou `/opt/selfhosted`. Le test local utilise uniquement Docker Compose.

Les fichiers de travail et les données sont créés sous :

```text
install/local/work
```

Sous Docker Desktop, PostgreSQL utilise le volume Docker nommé
`vps-local-databases_postgres_data`. L'override
`install/local/databases.override.yml` évite de monter le répertoire de données
sur NTFS, dont les permissions ne satisfont pas les contrôles PostgreSQL.

Tiny Tiny RSS utilise également le volume nommé
`vps-local-ttrss_ttrss_app` avec l'override
`install/local/ttrss.override.yml`. Son script de démarrage exécute `chown`,
`rsync` et Git dans `/var/www/html`; un bind mount NTFS peut le faire
redémarrer avant le lancement de PHP-FPM.

Kill the Newsletter utilise de la même manière un volume Docker nommé pour
`/app/data` avec `install/local/kill-newsletter.override.yml`. Le déploiement
Debian conserve son répertoire hôte sous `/opt/selfhosted`.

Au premier lancement, les scripts créent automatiquement sur l'hôte :

```text
install/local/vps.env       configuration locale
install/local/secrets.env   secrets de test
install/local/work/         fichiers Compose et données persistantes
```

Les deux fichiers `.env` sont copiés depuis :

```text
install/local/vps.env.example
install/local/secrets.env.example
```

Ils ne sont jamais écrasés lors des exécutions suivantes et sont exclus de
Git. Il est donc possible de modifier les ports, versions ou valeurs locales
dans `install/local/vps.env` avant un démarrage.

## Télécharger les fichiers

Il n'est pas nécessaire de cloner MethodAZ. Télécharger uniquement le bundle
`VPS` avec les scripts PowerShell ou Bash documentés dans
[Téléchargement depuis GitHub](telechargement-github.md), puis exécuter les
commandes suivantes depuis la racine du bundle.

## Télécharger les fichiers

Il n'est pas nécessaire de cloner MethodAZ. Télécharger uniquement le bundle
`VPS` avec les scripts PowerShell ou Bash documentés dans
[Téléchargement depuis GitHub](telechargement-github.md), puis exécuter les
commandes suivantes depuis la racine du bundle.

## Périmètre

| Projet | Validation Compose | Exécution locale |
| --- | --- | --- |
| PostgreSQL partagé | Oui | Oui, sans port publié |
| Linkwarden | Oui | Oui, port `3001` |
| Davis | Oui | Oui, port `3002` |
| FreshRSS | Oui | Oui, port `3003` |
| Tiny Tiny RSS | Oui | Oui, port `3004` |
| Kill the Newsletter | Oui | Oui, port `3005`, source clonée automatiquement |
| Apache/PHP | Oui | Oui, port `3006` |
| Gateway Nginx/Certbot | Oui | Non recommandé |
| Grafana, Prometheus, Node Exporter | Oui | Oui |
| cAdvisor | Oui | Facultatif |
| Loki et Alloy | Oui | Facultatif |

Le gateway de production utilise `network_mode: host` et les ports `80/443` ;
il reste à tester dans une VM Debian 13 ou sur le VPS. La supervision locale
utilise une composition dédiée compatible avec le réseau bridge de Docker
Desktop.

Grafana provisionne localement un dashboard distinct nommé
`Test local - Docker Desktop`. Le dashboard Debian de production n'est pas
chargé dans cet environnement.

## Prérequis

- Docker Desktop sous Windows ou macOS, ou Docker Engine sous Linux.
- Docker Compose v2.
- Ports locaux `3000` à `3006` et `9090` disponibles selon les services
  testés.

Vérification :

```bash
docker version
docker compose version
```

## Windows PowerShell

Initialiser le répertoire de travail :

```powershell
.\install\scripts\local-compose.ps1 init
```

Cette commande écrit les fichiers `.env` locaux s'ils sont absents. Les
actions `validate`, `pull` et `up` effectuent aussi cette initialisation
automatiquement. L'action `init` ne nécessite pas que Docker soit déjà
démarré.

Valider tous les fichiers Compose sans démarrer de conteneur :

```powershell
.\install\scripts\local-compose.ps1 validate
```

Tester un seul service :

```powershell
.\install\scripts\local-compose.ps1 pull linkwarden
.\install\scripts\local-compose.ps1 up linkwarden
.\install\scripts\local-compose.ps1 ps linkwarden
.\install\scripts\local-compose.ps1 logs linkwarden
```

Le script démarre automatiquement le projet `databases` avant l'application.

Arrêter le service :

```powershell
.\install\scripts\local-compose.ps1 down linkwarden
```

## Linux ou macOS

Les mêmes actions sont disponibles avec le script POSIX :

```bash
sh install/scripts/local-compose.sh init
sh install/scripts/local-compose.sh validate
sh install/scripts/local-compose.sh pull linkwarden
sh install/scripts/local-compose.sh up linkwarden
sh install/scripts/local-compose.sh ps linkwarden
sh install/scripts/local-compose.sh logs linkwarden
sh install/scripts/local-compose.sh down linkwarden
```

Le script applique le mode `0600` aux deux fichiers `.env` sur l'hôte Linux ou
macOS.

## Tester tous les services

Cette commande peut consommer plusieurs gigaoctets de mémoire :

```powershell
.\install\scripts\local-compose.ps1 up all
```

Équivalent POSIX :

```bash
sh install/scripts/local-compose.sh up all
```

Pour un poste limité, tester les services un par un.

## URLs locales

```text
http://localhost:3001   Linkwarden
http://localhost:3002   Davis
http://localhost:3003   FreshRSS
http://localhost:3004   Tiny Tiny RSS
http://localhost:3005   Kill the Newsletter
http://localhost:3006   Apache/PHP
```

Les URL Linkwarden et Tiny Tiny RSS sont remplacées par des valeurs HTTP
locales. La configuration de production reste en HTTPS.

## Paramètres de développement

Les identifiants locaux sont dans :

```text
install/local/secrets.env
```

Ils sont volontairement simples et ne doivent jamais être copiés sur Debian.
Toutes les valeurs nécessaires sont fournies par défaut pour le test local.

Pour l'assistant FreshRSS :

```text
Type       PostgreSQL
Hôte       postgres
Port       5432
Base       freshrss
Utilisateur freshrss
Mot de passe local_freshrss_db
```

Pour Davis :

```text
Utilisateur admin
Mot de passe local_davis_admin
```

## Supervision locale

Grafana, Prometheus et Node Exporter sont démarrés avec :

```powershell
.\install\scripts\local-compose.ps1 pull monitoring
.\install\scripts\local-compose.ps1 up monitoring
.\install\scripts\local-compose.ps1 ps monitoring
```

Équivalent POSIX :

```bash
sh install/scripts/local-compose.sh pull monitoring
sh install/scripts/local-compose.sh up monitoring
```

Grafana est disponible sur `http://localhost:3000` et Prometheus sur
`http://localhost:9090`.

Le profil local complet active cAdvisor et la collecte des journaux Docker
par défaut. Pour un ancien fichier `install/local/vps.env`, ajouter ou mettre
à jour :

```dotenv
ENABLE_CONTAINER_METRICS=true
ENABLE_LOGS=true
```

Puis rejouer `up monitoring`. Loki, Alloy, Node Exporter et cAdvisor restent
internes au réseau Docker ; Grafana et Prometheus y accèdent directement.
Alloy lit les journaux des conteneurs via le socket Docker local.

Une valeur explicite `false` désactive le composant correspondant. Si les
variables sont absentes, les scripts locaux utilisent `true`.

Le dashboard local affiche l'état des collecteurs, les ressources de la VM
Linux Docker Desktop, les ressources des conteneurs, les métriques du démon
Docker et les journaux. Les indicateurs strictement Debian de production,
comme APT, systemd, Fail2ban, sauvegardes et restauration, n'y figurent pas.

Pour les métriques du démon Docker, ouvrir **Docker Desktop > Settings >
Docker Engine**, ajouter la clé suivante au document JSON existant, puis
appliquer et redémarrer Docker Desktop :

```json
"metrics-addr": "127.0.0.1:9323"
```

Prometheus interroge ensuite `host.docker.internal:9323`. Ne pas publier ce
port sur une autre interface. Node Exporter mesure la VM Linux de Docker
Desktop, pas les compteurs natifs de Windows ou macOS.

Références :

- [Docker : métriques Prometheus du démon](https://docs.docker.com/engine/daemon/prometheus/)
- [Grafana Alloy : collecte des journaux Docker](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.docker/)

## Kill the Newsletter

Le script clone automatiquement le dépôt amont et sélectionne la révision
`KILL_NEWSLETTER_REF` définie dans `install/local/vps.env` :

```powershell
.\install\scripts\local-compose.ps1 pull kill-newsletter
.\install\scripts\local-compose.ps1 up kill-newsletter
```

Il n'est plus nécessaire de préparer `install/local/work/kill-newsletter/app`
manuellement. Le mode local démarre uniquement l'interface HTTP ; la
réception SMTP publique reste hors du périmètre de ce test.

## Contrôles

```bash
curl -fsSI http://localhost:3001
curl -fsSI http://localhost:3002
curl -fsSI http://localhost:3003
curl -fsSI http://localhost:3004
curl -fsSI http://localhost:3005
curl -fsS http://localhost:3006
```

Consulter également :

```bash
docker ps
docker stats --no-stream
```

## Arrêt et nettoyage

Arrêter tous les conteneurs en conservant les données :

```powershell
.\install\scripts\local-compose.ps1 down all
```

Supprimer les conteneurs et toutes les données locales de test :

```powershell
.\install\scripts\local-compose.ps1 clean
```

Le nettoyage demande de saisir exactement `OUI`. Il supprime
`install/local/work/`, mais conserve `install/local/vps.env` et
`install/local/secrets.env` afin de préserver les réglages de l'hôte.
