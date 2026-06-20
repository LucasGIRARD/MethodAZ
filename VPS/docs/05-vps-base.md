# Base VPS Debian

## Objectif

Préparer Debian 13 avec un accès administrateur par clé, un compte SFTP
isolé, `iptables`, Fail2ban et les paquets strictement nécessaires. Ce document
est le récapitulatif de la brique système.

## Découpage

| Brique | Résultat | Documentation |
| --- | --- | --- |
| Paquets et swap | Debian à jour, outils de base, swap facultatif | [Paquets et système](systeme/paquets-et-systeme.md) |
| SSH | Administrateur sans connexion root ni mot de passe SSH | [Accès SSH et SFTP](systeme/acces-ssh-sftp.md) |
| SFTP | Compte sans shell, chrooté dans son répertoire | [Accès SSH et SFTP](systeme/acces-ssh-sftp.md) |
| Pare-feu | Entrées limitées à SSH, HTTP et HTTPS | [Pare-feu et Fail2ban](systeme/pare-feu-fail2ban.md) |
| Fail2ban | Protection SSH et scans rapides | [Pare-feu et Fail2ban](systeme/pare-feu-fail2ban.md) |

## Installation recommandée

L'installation automatisée applique ces briques dans l'ordre et conserve
temporairement le port SSH 22 pendant la validation :

```bash
sudo sh install/scripts/vps-install.sh --phase all
```

La procédure complète est décrite dans
[Installation automatisée](04-installation-automatisee.md).

## État attendu

```text
SSH administrateur   clé publique, port privé **000
SFTP                 clé publique, même port SSH, compte sans shell
HTTP                  80/tcp
HTTPS                 443/tcp
Entrées restantes     bloquées par défaut
Docker                installé depuis le dépôt officiel
```

`**000` est uniquement le masque public de la documentation. Le vrai port est
stocké dans le fichier local `install/config/vps.env`, exclu de Git.

## Vérification

```bash
whoami
sudo sshd -t
sudo iptables -L INPUT -n -v --line-numbers
sudo ip6tables -L INPUT -n -v --line-numbers
sudo fail2ban-client status
sudo ss -tulpn
```

Ne jamais fermer la session root initiale avant d'avoir ouvert une seconde
session avec le compte administrateur sur le nouveau port.
