# Installation automatisée

## Périmètre

L'installateur Bash prépare :

- Debian et les paquets de base ;
- le compte administrateur par clé ;
- le compte SFTP chrooté ;
- SSH avec conservation temporaire du port 22 ;
- `iptables`, la persistance et Fail2ban ;
- Docker et son endpoint Prometheus local ;
- une instance PostgreSQL partagée ;
- les projets Compose applicatifs sélectionnés ;
- la supervision Grafana et Prometheus, avec cAdvisor et les journaux
  facultatifs.

Il ne redémarre pas automatiquement le VPS, n'obtient pas de certificat TLS et
ne démarre pas les applications par défaut.

## Préparer le poste client

Créer les clés :

```bash
ssh-keygen -t ed25519 -a 100 -f "$HOME/.ssh/vps-admin"
ssh-keygen -t ed25519 -a 100 -f "$HOME/.ssh/vps-sftp"
```

Copier uniquement les clés publiques sur le serveur, puis ouvrir une session
root temporaire :

```bash
scp "$HOME/.ssh/vps-admin.pub" "$HOME/.ssh/vps-sftp.pub" root@IP_DU_SERVEUR:/root/
ssh root@IP_DU_SERVEUR
```

`scp` transfère les deux fichiers `.pub` depuis le poste client vers le
répertoire `/root/` du VPS. Les clés privées sans extension `.pub` ne doivent
jamais être copiées sur le serveur. La connexion `ssh root@IP_DU_SERVEUR` sert
ensuite à continuer l'installation depuis le VPS ; les fichiers publics seront
placés plus bas dans `install/keys/admin.pub` et `install/keys/sftp.pub`.

## Télécharger le bundle sur le VPS

Le dépôt complet MethodAZ ne doit pas être cloné. Télécharger le petit script
de récupération publié avec la dernière release, le lire, puis choisir la
version du bundle `VPS` à installer :

```bash
curl -fL \
  "https://github.com/LucasGIRARD/MethodAZ/releases/latest/download/fetch-vps.sh" \
  -o /root/fetch-vps.sh

less /root/fetch-vps.sh
chmod 700 /root/fetch-vps.sh
/root/fetch-vps.sh --select-version /root/vps-setup
cd /root/vps-setup

install -m 0644 /root/vps-admin.pub install/keys/admin.pub
install -m 0644 /root/vps-sftp.pub install/keys/sftp.pub
cat install/source-version.txt
```

Le mode `--select-version` affiche les releases disponibles et télécharge le
tag choisi. Pour installer directement la dernière release publiée, utiliser
`/root/fetch-vps.sh --latest /root/vps-setup`.

La procédure détaillée pour Windows, Linux et macOS se trouve dans
[Téléchargement depuis GitHub](telechargement-github.md).

## Configuration publique

Créer `install/config/vps.env` à partir du modèle de configuration publique :

- [vps.env.example, dernière release](https://github.com/LucasGIRARD/MethodAZ/releases/latest/download/vps.env.example)
- [vps.env.example, branche main](https://raw.githubusercontent.com/LucasGIRARD/MethodAZ/main/VPS/install/config/vps.env.example)

Le même modèle est présent dans le bundle téléchargé sous
`install/config/vps.env.example`.

Renseigner au minimum :

```bash
ADMIN_USER=lucas
SSH_PORT=PORT_REEL
BASE_DOMAIN=example.fr
ADMIN_EMAIL=contact@example.fr
SERVICES=linkwarden,davis,freshrss,ttrss,web
LINKWARDEN_DISABLE_REGISTRATION=true
LINKWARDEN_BOOTSTRAP_USER=lucas
LINKWARDEN_BOOTSTRAP_NAME=Lucas
```

Le vrai port SSH reste uniquement dans ce fichier exclu de Git. Dans la
documentation publique, il continue d'être représenté par `**000`.

Après une première installation, ce fichier est conservé dans
`/opt/vps-install/config/vps.env`. Pour revenir dessus, modifier cette copie
puis relancer uniquement la phase concernée, comme décrit dans
[Reprise après erreur](#reprise-apres-erreur).

## Secrets

Générer un fichier distinct :

```bash
sh install/scripts/generate-secrets.sh
sudo chown root:root install/config/secrets.env
sudo chmod 0600 install/config/secrets.env
```

Le fichier contient les mots de passe applicatifs, les secrets de session et
le hash du mot de passe système initial. Il est exclu de Git.

Le modèle de référence est consultable ici, mais ne doit pas être utilisé tel
quel en production :

- [secrets.env.example, dernière release](https://github.com/LucasGIRARD/MethodAZ/releases/latest/download/secrets.env.example)
- [secrets.env.example, branche main](https://raw.githubusercontent.com/LucasGIRARD/MethodAZ/main/VPS/install/config/secrets.env.example)

Si `LINKWARDEN_BOOTSTRAP_USER` est renseigné, conserver aussi
`LINKWARDEN_BOOTSTRAP_PASSWORD` dans ce fichier. Ce mot de passe sert à créer
le premier compte Linkwarden quand les inscriptions publiques sont fermées.

Afficher uniquement le mot de passe administrateur initial si nécessaire :

```bash
sudo sed -n 's/^ADMIN_INITIAL_PASSWORD=//p' install/config/secrets.env
```

Après validation de `sudo`, cette valeur en clair peut être supprimée du
fichier ; `ADMIN_PASSWORD_HASH` doit être conservé pour les réapplications.

## Valider le bundle

```bash
sh install/scripts/validate-bundle.sh
```

Cette commande vérifie la syntaxe des scripts et de tous les projets Compose
sans démarrer de conteneur.

## Lancer l'installation

```bash
sudo sh install/scripts/vps-install.sh --phase all
```

Le script copie ensuite son bundle dans `/opt/vps-install` et installe la
commande :

```bash
sudo vps-install --help
```

À partir de ce moment, le fichier de secrets canonique est :

```text
/opt/vps-install/config/secrets.env
```

Après réussite complète et sauvegarde chiffrée, supprimer la copie
d'amorçage restée sous `/root/vps-setup/install/config/secrets.env`. Conserver
`/opt/vps-install/source-version.txt` pour identifier la version installée.

## Phases disponibles

| Phase | Commande | Effet |
| --- | --- | --- |
| Base | `sudo vps-install --phase base` | Paquets, utilisateur, clé, swap |
| SSH | `sudo vps-install --phase ssh` | SSH renforcé et compte SFTP |
| Pare-feu | `sudo vps-install --phase firewall` | iptables et Fail2ban |
| Docker | `sudo vps-install --phase docker` | Dépôt officiel et démon |
| Bases | `sudo vps-install --phase databases` | PostgreSQL et réseaux isolés |
| Services | `sudo vps-install --phase services` | Copie des projets sélectionnés |
| Gateway | `sudo vps-install --phase gateway` | Nginx HTTP et préparation Certbot |
| Supervision | `sudo vps-install --phase monitoring` | Dashboard et collecteurs |
| Ensemble | `sudo vps-install --phase all` | Toutes les phases dans l'ordre |

Les phases sont conçues pour être rejouées. Les données applicatives sous
`/opt/selfhosted` ne sont pas supprimées par la copie des modèles.

La phase Docker installe également la sauvegarde et le timer de maintenance
nocturne. La phase Base borne les timers APT entre `04:15` et `05:00`.
`RESOURCE_PROFILE` applique les limites mémoire `VPS_2G` ou `VPS_4G`.
`ENABLE_REMOTE_BACKUP=true` ajoute Restic et rclone. Koofr via rclone est le
backend recommandé ; les identifiants restent dans `/etc/vps-backup`, jamais
dans le dépôt.

## Tester SSH et SFTP

Depuis un second terminal client :

```bash
ssh -i ~/.ssh/vps-admin -p PORT_REEL lucas@IP_DU_SERVEUR
sftp -i ~/.ssh/vps-sftp -P PORT_REEL depot@IP_DU_SERVEUR
```

Ne pas poursuivre si l'une des connexions échoue.

## Fermer le port 22 temporaire

Après validation :

```bash
sudo vps-install --finalize-ssh
```

Puis vérifier :

```bash
sudo ss -ltnp | grep sshd
sudo iptables -L INPUT -n -v --line-numbers
```

## Démarrer les applications

Valider chaque application séparément :

```bash
sudo vps-compose databases ps
sudo vps-image-lock linkwarden
sudo vps-compose linkwarden config --quiet
sudo vps-compose linkwarden up -d
```

Suivre ensuite sa fiche dans [Services Docker](03-services-docker.md).

## Reprise après erreur

Corriger la configuration ou le secret concerné dans `/opt/vps-install`, puis
relancer seulement la phase nécessaire :

```bash
sudo nano /opt/vps-install/config/vps.env
sudo nano /opt/vps-install/config/secrets.env
sudo vps-install --phase NOM_DE_PHASE
```

Ne pas lancer la finalisation SSH comme mécanisme de reprise.
