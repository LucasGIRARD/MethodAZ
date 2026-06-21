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
uniquement à amorcer l'installation depuis le VPS ; l'installateur crée ensuite
le compte administrateur sudoer et bloque les nouvelles connexions SSH root.
Les fichiers publics seront placés plus bas dans `install/keys/admin.pub` et
`install/keys/sftp.pub`.

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

Dans `install/config/vps.env`, conserver les chemins stables du modèle :

```bash
ADMIN_SSH_KEY_FILE=install/keys/admin.pub
SFTP_SSH_KEY_FILE=install/keys/sftp.pub
```

Ne pas utiliser de chemin relatif du type `../../vps-sftp.pub` : après la
première installation, le bundle est recopié dans `/opt/vps-install` et ce
chemin ne pointe plus vers le même fichier.

Le mode `--select-version` affiche les releases disponibles et télécharge le
tag choisi. Pour installer directement la dernière release publiée, utiliser
`/root/fetch-vps.sh --latest /root/vps-setup`.

La procédure détaillée pour Windows, Linux et macOS se trouve dans
[Téléchargement depuis GitHub](02-telechargement-github.md).

## Configuration publique

Créer `install/config/vps.env` à partir du modèle de configuration publique :

- [vps.env.example, dernière release](https://github.com/LucasGIRARD/MethodAZ/releases/latest/download/vps.env.example)
- [vps.env.example, branche main](https://raw.githubusercontent.com/LucasGIRARD/MethodAZ/main/VPS/install/config/vps.env.example)

Le même modèle est présent dans le bundle téléchargé sous
`install/config/vps.env.example`.

Deux méthodes sont possibles :

- créer ou modifier `install/config/vps.env` directement sur le VPS ;
- préparer `vps.env` sur le poste client, puis le déposer par SFTP ou SCP dans
  `/root/vps-setup/install/config/vps.env`.

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
WEB_DOMAIN=example.fr
WEB_SUBDOMAINS=www
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

Le fichier peut aussi être préparé sur le poste client puis déposé par SFTP ou
SCP dans `/root/vps-setup/install/config/secrets.env`. Dans ce cas, vérifier
ensuite sur le VPS :

```bash
sudo chown root:root install/config/secrets.env
sudo chmod 0600 install/config/secrets.env
```

Si `LINKWARDEN_BOOTSTRAP_USER` est renseigné, conserver aussi
`LINKWARDEN_BOOTSTRAP_PASSWORD` dans ce fichier. Ce mot de passe sert à créer
le premier compte Linkwarden quand les inscriptions publiques sont fermées.

Afficher uniquement le mot de passe administrateur initial si nécessaire :

```bash
sudo sed -n 's/^ADMIN_INITIAL_PASSWORD=//p' install/config/secrets.env
```

Après validation de `sudo`, cette valeur en clair peut être supprimée du
fichier ; `ADMIN_PASSWORD_HASH` doit être conservé pour les réapplications.
Si `ADMIN_PASSWORD_HASH` est modifié à la main avec un hash `openssl passwd -6`,
le placer entre quotes simples, par exemple `ADMIN_PASSWORD_HASH='$6$...'`.

## Valider le bundle

```bash
sh install/scripts/validate-bundle.sh --scripts-only
```

Cette commande vérifie la syntaxe des scripts sans dépendre de Docker, qui
n'est pas encore installé à ce stade. La validation Compose complète peut être
rejouée après la phase Docker avec `sh install/scripts/validate-bundle.sh`.

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
ssh -i ~/.ssh/vps-admin -p 22 root@IP_DU_SERVEUR
ssh -i ~/.ssh/vps-admin -p PORT_REEL lucas@IP_DU_SERVEUR
sftp -i ~/.ssh/vps-sftp -P PORT_REEL depot@IP_DU_SERVEUR
```

Ne pas poursuivre si l'une des connexions échoue. La première connexion root
sert uniquement de filet de sécurité pendant le bootstrap ; elle est fermée
après `--finalize-ssh`.

Si `lucas` retourne `Authentication rejected`, vérifier depuis la session root
ouverte :

```bash
sudo ls -l /root/.ssh/authorized_keys /home/lucas/.ssh/authorized_keys
sudo ssh-keygen -lf /root/.ssh/authorized_keys
sudo ssh-keygen -lf /home/lucas/.ssh/authorized_keys
sudo sh install/scripts/vps-install.sh --phase base
sudo sh install/scripts/vps-install.sh --phase ssh
```

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

Suivre ensuite sa fiche dans [Services Docker](08-services-docker.md).

## Vérification post-installation

Contrôler d'abord les accès système :

```bash
sudo ss -ltnp | grep sshd
sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication)'
sudo fail2ban-client status sshd
```

Depuis le poste client, vérifier les deux accès attendus :

```bash
ssh -i ~/.ssh/vps-admin -p PORT_REEL ADMIN_USER@IP_DU_SERVEUR
sftp -i ~/.ssh/vps-sftp -P PORT_REEL depot@IP_DU_SERVEUR
```

Contrôler Docker, PostgreSQL et les réseaux isolés :

```bash
sudo docker ps
sudo docker network ls | grep vps-db
sudo vps-compose databases ps
sudo vps-compose databases exec -T postgres pg_isready -U postgres
```

Contrôler les stacks applicatifs déclarés dans `SERVICES` :

```bash
for service in linkwarden davis freshrss ttrss web; do
  sudo vps-compose "$service" config --quiet
  sudo vps-compose "$service" ps
done
```

Contrôler le reverse proxy et les certificats :

```bash
sudo vps-gateway test
sudo vps-gateway status
sudo vps-gateway logs
```

Depuis le poste client, tester les URL publiques configurées :

```bash
curl -I https://linkwarden.example.fr
curl -I https://www.example.fr
```

Remplacer les domaines d'exemple par les domaines réels. Si un service n'est
pas dans `SERVICES`, ignorer sa commande `vps-compose`.

## Déployer un nouveau site web

Le service `web` sert le domaine racine depuis :

```text
/opt/selfhosted/web/html
```

Chaque entrée de `WEB_SUBDOMAINS` ajoute un sous-domaine et un dossier dédié.
Par exemple :

```env
WEB_DOMAIN=example.fr
WEB_SUBDOMAINS=www,blog
```

donne :

```text
https://example.fr       -> /opt/selfhosted/web/html
https://www.example.fr   -> /opt/selfhosted/web/html/www
https://blog.example.fr  -> /opt/selfhosted/web/html/blog
```

Pour ajouter un nouveau sous-domaine :

```bash
sudo nano /opt/vps-install/config/vps.env
# ajouter le label dans WEB_SUBDOMAINS, par exemple : WEB_SUBDOMAINS=www,blog,docs

sudo vps-install --phase services
sudo vps-compose web up -d --build

sudo vps-install --phase gateway
sudo vps-gateway issue-certificate
sudo vps-gateway enable-tls
```

La phase `services` crée automatiquement les dossiers déclarés dans
`WEB_SUBDOMAINS`. Il reste ensuite à déposer les fichiers du site dans le
dossier correspondant, par exemple :

```bash
sudo rsync -a /chemin/local/docs-site/ /opt/selfhosted/web/html/docs/
sudo chown -R root:root /opt/selfhosted/web/html/docs
sudo find /opt/selfhosted/web/html/docs -type d -exec chmod 0755 {} \;
sudo find /opt/selfhosted/web/html/docs -type f -exec chmod 0644 {} \;
```

Valider ensuite depuis le VPS et depuis le poste client :

```bash
sudo vps-compose web ps
curl -I http://127.0.0.1:3006
curl -I https://docs.example.fr
```

Pour un site déposé par SFTP, envoyer les fichiers avec le compte `depot` dans
`/upload`, puis les déplacer depuis la session SSH admin vers
`/opt/selfhosted/web/html/NOM_DU_SITE`.

## Reprise après erreur

Corriger la configuration ou le secret concerné dans `/opt/vps-install`, puis
relancer seulement la phase nécessaire :

```bash
sudo nano /opt/vps-install/config/vps.env
sudo nano /opt/vps-install/config/secrets.env
sudo vps-install --phase NOM_DE_PHASE
```

Ne pas lancer la finalisation SSH comme mécanisme de reprise.
