# Test local avec Docker Compose

## Objectif

Tester les projets Docker applicatifs sans modifier Debian, SSH, le pare-feu
ou `/opt/selfhosted`. Le test local utilise uniquement Docker Compose.

Les fichiers de travail et les données sont créés sous :

```text
install/local/work
```

Ce répertoire et le fichier `install/local/secrets.env` sont exclus de Git.

## Télécharger les fichiers

Il n'est pas nécessaire de cloner MethodAZ. Télécharger uniquement le bundle
`VPS` avec les scripts PowerShell ou Bash documentés dans
[Téléchargement depuis GitHub](telechargement-github.md), puis exécuter les
commandes suivantes depuis la racine du bundle.

## Périmètre

| Projet | Validation Compose | Exécution locale |
| --- | --- | --- |
| MariaDB et PostgreSQL partagées | Oui | Oui, sans port publié |
| Linkwarden | Oui | Oui, port `3001` |
| Davis | Oui | Oui, port `3002` |
| FreshRSS | Oui | Oui, port `3003` |
| Tiny Tiny RSS | Oui | Oui, port `3004` |
| Kill the Newsletter | Oui | Après clonage du code source |
| Apache/PHP | Oui | Oui, port `3006` |
| Gateway Nginx/Certbot | Oui | Non recommandé |
| Monitoring complet | Oui | Non recommandé |

Le gateway et la supervision utilisent `network_mode: host`, les ports
`80/443` et des montages Linux comme `/sys`, `/var/run` et `/var/lib/docker`.
Leur exécution complète doit être testée dans une VM Debian 13 ou sur le VPS.

## Prérequis

- Docker Desktop sous Windows ou macOS, ou Docker Engine sous Linux.
- Docker Compose v2.
- Ports locaux `3001` à `3006` disponibles pour les services testés.

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

Pour l'assistant FreshRSS :

```text
Hôte       mariadb
Base       freshrss
Utilisateur freshrss
Mot de passe local_freshrss_db
```

Pour Davis :

```text
Utilisateur admin
Mot de passe local_davis_admin
```

## Kill the Newsletter

Préparer le code dans le répertoire de travail :

```bash
git clone https://github.com/3nprob/kill-the-newsletter.com.git \
  install/local/work/kill-newsletter/app
```

Puis lancer uniquement ce service :

```bash
sh install/scripts/local-compose.sh up kill-newsletter
```

## Contrôles

```bash
curl -fsSI http://localhost:3001
curl -fsSI http://localhost:3002
curl -fsSI http://localhost:3003
curl -fsSI http://localhost:3004
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

Le nettoyage demande de saisir exactement `OUI`.
