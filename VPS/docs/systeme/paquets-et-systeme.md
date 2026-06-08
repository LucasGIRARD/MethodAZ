# Paquets et système Debian

## Mise à jour initiale

```bash
apt update
apt full-upgrade -y
apt install -y \
  ca-certificates curl fail2ban git iptables iptables-persistent jq \
  logrotate nano needrestart openssh-server openssl rsync sudo \
  unattended-upgrades
```

L'installateur exécute ces commandes avec `DEBIAN_FRONTEND=noninteractive`.
Un redémarrage éventuellement demandé par Debian reste volontairement manuel.

## Swap

Pour un petit VPS, le profil proposé crée un fichier de swap de 2 Gio :

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

Le réglage se contrôle dans `install/config/vps.env` :

```bash
ENABLE_SWAP=true
SWAP_SIZE=2G
```

## Paquets retenus

| Paquet | Rôle | Décision |
| --- | --- | --- |
| `sudo` | Administration non-root | Conserver |
| `curl`, `ca-certificates` | Dépôts HTTPS et contrôles HTTP | Conserver |
| `openssh-server` | SSH et SFTP | Conserver |
| `iptables`, `iptables-persistent` | Pare-feu et persistance | Conserver |
| `fail2ban` | Bannissement SSH et scans | Conserver |
| `logrotate` | Rotation des fichiers de journaux | Conserver |
| `unattended-upgrades` | Correctifs Debian de sécurité | Conserver |
| `needrestart` | Détection des redémarrages nécessaires | Conserver |
| `git`, `rsync`, `jq`, `openssl` | Déploiement et scripts | Conserver |
| `nano` | Éditeur utilisé dans la documentation | Conserver |
| `apache2-utils` | Création ponctuelle d'un `htpasswd` | Installer seulement si nécessaire |
| `msmtp`, `bsd-mailx` | Notifications par courriel | Optionnels |
| `vim`, `wget`, `unzip`, `htop` | Redondants ou confort | Ne pas installer par défaut |
| `apt-transport-https` | Ancien paquet de transition | Inutile |

## Audit avant suppression

```bash
apt-mark showmanual | sort
sudo apt purge --simulate \
  apt-transport-https lsb-release vim unzip htop gnupg apt-listchanges
sudo apt autoremove --simulate
```

Ne confirmer aucune suppression si APT propose de retirer SSH, Docker,
Fail2ban, le noyau ou un paquet imposé par l'hébergeur.
