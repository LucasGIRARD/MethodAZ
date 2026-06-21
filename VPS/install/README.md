# Installation

Le bundle peut être téléchargé sans cloner le dépôt MethodAZ. Voir
`docs/02-telechargement-github.md` ou les scripts :

```text
install/scripts/fetch-vps.sh
install/scripts/fetch-vps.ps1
```

## Fichiers locaux

```text
config/vps.env       Configuration réelle, exclue de Git
config/secrets.env   Secrets réels, exclus de Git et mode 0600
keys/admin.pub       Clé publique SSH, exclue de Git
keys/sftp.pub        Clé publique SFTP, exclue de Git
```

## Préparation

Créer `install/config/vps.env` depuis le modèle :

- [vps.env.example, dernière release](https://github.com/LucasGIRARD/MethodAZ/releases/latest/download/vps.env.example)
- [vps.env.example, branche main](https://raw.githubusercontent.com/LucasGIRARD/MethodAZ/main/VPS/install/config/vps.env.example)

Puis générer les secrets :

```bash
sh install/scripts/generate-secrets.sh
chmod 0600 install/config/secrets.env
```

Valider avant toute modification du serveur :

```bash
sh install/scripts/validate-bundle.sh --scripts-only
pwsh install/scripts/validate-repository.ps1
```

Le premier script vérifie les projets Compose et les scripts POSIX. Le second
contrôle PowerShell, les liens Markdown, les fichiers sensibles suivis par Git
et les références d'images mutables.

## Test local

Les scripts créent automatiquement, s'ils sont absents :

```text
install/local/vps.env
install/local/secrets.env
install/local/work/
```

Les valeurs initiales proviennent des fichiers `.env.example` suivis dans Git.
Les fichiers générés restent sur l'hôte et ne sont pas écrasés.

Sous Windows :

```powershell
.\install\scripts\local-compose.ps1 validate
.\install\scripts\local-compose.ps1 up linkwarden
```

Sous Linux ou macOS :

```bash
sh install/scripts/local-compose.sh validate
sh install/scripts/local-compose.sh up linkwarden
```

Voir `docs/03-test-local-docker.md`.

## Installation

```bash
sudo sh install/scripts/vps-install.sh --phase all
```

Le projet `databases` est démarré avant les applications et ne publie aucun
port SQL.

Le bundle est ensuite conservé sous `/opt/vps-install` et accessible avec :

```bash
sudo vps-install --help
```

Voir `docs/04-installation-automatisee.md` pour l'ordre complet et les tests SSH
avant fermeture du port 22 temporaire.

La maintenance est installée sous forme de timers systemd :

```bash
systemctl list-timers 'vps-*' 'apt-*'
sudo systemctl start vps-nightly-maintenance.service
```
