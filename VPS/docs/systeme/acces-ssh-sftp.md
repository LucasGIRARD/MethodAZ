# Accès SSH et SFTP

## Modèle retenu

Deux comptes séparés sont utilisés :

| Compte | Usage | Shell | Accès |
| --- | --- | --- | --- |
| `lucas` | Administration | `/bin/bash` | SSH par clé et `sudo` |
| `depot` | Transfert de fichiers | Aucun | SFTP interne, chrooté |

SFTP utilise le protocole SSH. Il écoute donc sur le même port privé `**000`
et ne nécessite aucun port FTP supplémentaire.

Configuration publique associée :

```env
ENABLE_SFTP=true
SFTP_USER=depot
SFTP_SSH_KEY_FILE=install/keys/sftp.pub
SFTP_CHROOT_DIR=/opt/selfhosted/web
SFTP_START_DIRECTORY=/html
SFTP_UMASK=0022
```

## Générer les clés sur le poste client

Créer une clé distincte pour chaque usage :

```bash
ssh-keygen -t ed25519 -a 100 -f "$HOME/.ssh/vps-admin"
ssh-keygen -t ed25519 -a 100 -f "$HOME/.ssh/vps-sftp"
```

Copier uniquement les fichiers publics dans le répertoire d'installation :

```text
install/keys/admin.pub
install/keys/sftp.pub
```

Les clés privées restent sur le poste client.

## Configuration SSH appliquée

L'installateur crée `/etc/ssh/sshd_config.d/20-vps-hardening.conf`.
Pendant le bootstrap, root reste autorisé uniquement par clé :

```text
Port **000
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys /etc/ssh/authorized_keys/%u
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
```

Pendant le premier passage, un second fichier conserve temporairement le port
22. La clé `admin.pub` est installée à la fois pour `lucas` et pour `root` :

```text
/home/lucas/.ssh/authorized_keys
/root/.ssh/authorized_keys
```

Root ne peut pas se connecter par mot de passe. Il reste accessible par clé
uniquement le temps de valider le compte administrateur et le port privé.
Après `vps-install --finalize-ssh`, l'installateur applique
`PermitRootLogin no`.

## Isolation SFTP

Le compte SFTP appartient au groupe `sftp-only` et reçoit :

```text
ChrootDirectory /opt/selfhosted/web
ForceCommand internal-sftp -d /html -u 0022
AllowAgentForwarding no
AllowTcpForwarding no
PermitTunnel no
X11Forwarding no
```

Le répertoire de chroot appartient obligatoirement à root. Le dossier web
accessible en SFTP appartient au compte `depot` :

```text
/opt/selfhosted/web        root:root, 0755
/opt/selfhosted/web/html   depot:sftp-only, 0755
```

Dans la session SFTP, `depot` arrive dans `/html`. Ce chemin correspond sur le
système hôte à `/opt/selfhosted/web/html`.

La clé SFTP est stockée hors du chroot dans
`/etc/ssh/authorized_keys/depot`, avec le propriétaire `root:root` et le mode
`0644`. Le contenu est une clé publique ; OpenSSH doit pouvoir lire ce fichier
pendant l'authentification de `depot`.

Le compte `depot` n'a pas de mot de passe connu. L'installateur lui attribue
un hash aléatoire non stocké plutôt qu'un compte verrouillé (`!` ou `*`), car
OpenSSH peut refuser les clés publiques d'un compte verrouillé avant même
d'arriver à la phase SFTP.

## Connexion depuis le client

Configuration conseillée dans `~/.ssh/config` :

```sshconfig
Host mon-vps
    HostName IP_DU_SERVEUR
    User lucas
    Port **000
    IdentityFile ~/.ssh/vps-admin
    IdentitiesOnly yes

Host mon-vps-sftp
    HostName IP_DU_SERVEUR
    User depot
    Port **000
    IdentityFile ~/.ssh/vps-sftp
    IdentitiesOnly yes
```

Connexions :

```bash
ssh mon-vps
sftp mon-vps-sftp
```

Dans SFTP, le répertoire accessible en écriture est `/html`, qui correspond à
`/opt/selfhosted/web/html` sur le VPS.

## Modifier l'emplacement SFTP après installation

Éditer la configuration canonique :

```bash
sudo nano /opt/vps-install/config/vps.env
```

Valeurs attendues pour exposer le contenu web :

```env
SFTP_CHROOT_DIR=/opt/selfhosted/web
SFTP_START_DIRECTORY=/html
SFTP_UMASK=0022
```

Réappliquer ensuite SSH et le service web :

```bash
sudo vps-install --phase ssh
sudo vps-install --phase services
```

La première commande met à jour `sshd` et les droits du dossier `/html`. La
seconde réapplique les droits si la phase web recrée des dossiers.

## Retirer le port 22

Conserver la session root initiale et tester dans un second terminal :

```bash
ssh -i ~/.ssh/vps-admin -p 22 root@IP_DU_SERVEUR
ssh -i ~/.ssh/vps-admin -p **000 lucas@IP_DU_SERVEUR
sftp -i ~/.ssh/vps-sftp -P **000 depot@IP_DU_SERVEUR
```

Après réussite des deux tests :

```bash
sudo vps-install --finalize-ssh
```

Cette commande demande une confirmation, supprime l'écoute temporaire sur 22,
valide `sshd`, recharge SSH et régénère le pare-feu.

## Vérification

```bash
sudo sshd -t
sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication)'
sudo ss -ltnp | grep sshd
sudo systemctl is-active ssh.socket || true
sudo ls -l /root/.ssh/authorized_keys /home/lucas/.ssh/authorized_keys
sudo ls -l /etc/ssh/authorized_keys/depot
sudo namei -l /etc/ssh/authorized_keys/depot
sudo passwd -S depot
```

Si les logs SSH indiquent :

```text
Could not open user 'depot' authorized keys '/etc/ssh/authorized_keys/depot': Permission denied
```

OpenSSH ne peut pas traverser un dossier parent ou lire le fichier de clé
publique. Corriger :

```bash
sudo chown root:root /etc/ssh /etc/ssh/authorized_keys
sudo chmod 0755 /etc/ssh /etc/ssh/authorized_keys
sudo chown root:root /etc/ssh/authorized_keys/depot
sudo chmod 0644 /etc/ssh/authorized_keys/depot
sudo sshd -t
sudo systemctl restart ssh
```

Si `22` apparaît encore avant la finalisation, c'est normal :
`KEEP_SSH_PORT_22=true` conserve ce port temporairement. Le port privé doit
toutefois apparaître aussi dans `sshd -T` et `ss -ltnp`. Si le port privé
écoute localement mais reste inaccessible depuis le poste client, vérifier le
pare-feu du fournisseur VPS en plus des règles `iptables`.

## Références

- [Debian : sshd_config](https://manpages.debian.org/trixie/openssh-server/sshd_config.5.en.html)
- [Debian : serveur OpenSSH](https://manpages.debian.org/trixie/openssh-server/sshd.8.en.html)
