# Accès SSH et SFTP

## Modèle retenu

Deux comptes séparés sont utilisés :

| Compte | Usage | Shell | Accès |
| --- | --- | --- | --- |
| `lucas` | Administration | `/bin/bash` | SSH par clé et `sudo` |
| `depot` | Transfert de fichiers | Aucun | SFTP interne, chrooté |

SFTP utilise le protocole SSH. Il écoute donc sur le même port privé `**000`
et ne nécessite aucun port FTP supplémentaire.

## Générer les clés sur le poste client

Créer une clé distincte pour chaque usage :

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/vps-admin
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/vps-sftp
```

Copier uniquement les fichiers publics dans le répertoire d'installation :

```text
install/keys/admin.pub
install/keys/sftp.pub
```

Les clés privées restent sur le poste client.

## Configuration SSH appliquée

L'installateur crée `/etc/ssh/sshd_config.d/20-vps-hardening.conf` :

```text
Port **000
PermitRootLogin no
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
22. Pendant cette courte phase, root reste récupérable uniquement par clé avec
`PermitRootLogin prohibit-password`. La finalisation passe ensuite
`PermitRootLogin` à `no`.

## Isolation SFTP

Le compte SFTP appartient au groupe `sftp-only` et reçoit :

```text
ChrootDirectory /srv/sftp/%u
ForceCommand internal-sftp -d /upload -u 0027
AllowAgentForwarding no
AllowTcpForwarding no
PermitTunnel no
X11Forwarding no
```

Le répertoire de chroot appartient obligatoirement à root :

```text
/srv/sftp/depot          root:root, 0755
/srv/sftp/depot/upload   depot:sftp-only, 0750
```

La clé SFTP est stockée hors du chroot dans
`/etc/ssh/authorized_keys/depot`.

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

Dans SFTP, le répertoire accessible en écriture est `/upload`.

## Retirer le port 22

Conserver la session root initiale et tester dans un second terminal :

```bash
ssh -p **000 lucas@IP_DU_SERVEUR
sftp -P **000 depot@IP_DU_SERVEUR
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
```

## Références

- [Debian : sshd_config](https://manpages.debian.org/trixie/openssh-server/sshd_config.5.en.html)
- [Debian : serveur OpenSSH](https://manpages.debian.org/trixie/openssh-server/sshd.8.en.html)
