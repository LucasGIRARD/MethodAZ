# Téléchargement depuis GitHub

## Objectif

Le dépôt public est :

```text
https://github.com/LucasGIRARD/MethodAZ
```

Il n'est pas nécessaire de cloner ou d'initialiser tout le dépôt MethodAZ.
Les scripts de téléchargement utilisent une archive GitHub temporaire et ne
conservent que le contenu du dossier `VPS`, sans historique Git ni dossier
`.git`.

La version téléchargée est enregistrée dans :

```text
install/source-version.txt
```

## Choix de la version

Pour tester la version publiée, utiliser la sélection de release. Pour tester
un état de développement non publié, la branche `main` reste disponible avec
`--ref main`.

Pour la production, utiliser une release publiée. Le script de téléchargement
peut afficher les versions disponibles et télécharger le tag choisi :

```bash
./fetch-vps.sh --select-version ./methodaz-vps
```

Une branche peut évoluer. Une release versionnée rend le téléchargement et une
future réinstallation reproductibles. L'ancien mode par commit reste disponible
pour les tests ciblés avec `--ref IDENTIFIANT_COMPLET_DU_COMMIT`.

Chaque release doit publier `fetch-vps.sh`, `fetch-vps.ps1`,
`vps.env.example` et `secrets.env.example` comme assets. Les deux scripts
servent uniquement à récupérer le bundle `VPS` correspondant à la version
choisie ; les deux fichiers `.env.example` servent de modèles lisibles avant
installation.

Le workflow GitHub Actions `Assets release VPS` attache ces fichiers lors de la
publication d'une release. Pour compléter une release déjà publiée, le lancer
manuellement avec `workflow_dispatch` et renseigner le tag concerné.

## Windows PowerShell

Télécharger le script sans l'exécuter directement :

```powershell
$url = "https://github.com/LucasGIRARD/MethodAZ/releases/latest/download/fetch-vps.ps1"

Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile .\fetch-vps.ps1
Get-Content .\fetch-vps.ps1
```

Après lecture du script :

```powershell
powershell -ExecutionPolicy Bypass -File .\fetch-vps.ps1 `
  -SelectVersion `
  -Destination .\methodaz-vps

Set-Location .\methodaz-vps
.\install\scripts\local-compose.ps1 validate
```

Le dossier de destination doit être absent. Cette règle évite d'écraser une
configuration ou des données de test existantes.

Pour installer directement la dernière release publiée, remplacer
`-SelectVersion` par `-Latest`.

## Linux ou macOS

Pour un test local :

```bash
curl -fL \
  "https://github.com/LucasGIRARD/MethodAZ/releases/latest/download/fetch-vps.sh" \
  -o fetch-vps.sh

less fetch-vps.sh
chmod 700 fetch-vps.sh
./fetch-vps.sh --select-version ./methodaz-vps
cd ./methodaz-vps
sh install/scripts/local-compose.sh validate
```

## VPS de production

Utiliser une release publiée et ne transférer depuis le poste client que les deux
clés publiques, puis ouvrir une session root temporaire :

```bash
scp "$HOME/.ssh/vps-admin.pub" "$HOME/.ssh/vps-sftp.pub" root@IP_DU_SERVEUR:/root/
ssh root@IP_DU_SERVEUR
```

`scp` copie les deux fichiers `.pub` dans `/root/` sur le VPS. Les clés privées
correspondantes restent sur le poste client. La session SSH ouverte juste après
sert à exécuter les commandes suivantes directement sur le serveur.

Sur le VPS :

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

Il faut ensuite créer les fichiers locaux de configuration et lancer la
procédure décrite dans
[Installation automatisée](installation-automatisee.md).

## Mise à jour du bundle

Ne pas télécharger une nouvelle version par-dessus le dossier existant.
Utiliser un nouveau répertoire, comparer les changements, puis lancer la phase
nécessaire avec les fichiers de configuration conservés.

Les données persistantes restent sous `/opt/selfhosted` et les secrets
canoniques sous `/opt/vps-install/config`.

## Sécurité

- Ne jamais exécuter directement une commande de type `curl | sh`.
- Lire le téléchargeur avant son exécution.
- Utiliser une release versionnée en production.
- Conserver `install/source-version.txt` avec le compte rendu d'installation.
- Vérifier que l'URL utilise bien le compte `LucasGIRARD` et le dépôt
  `MethodAZ`.

GitHub documente les archives de branche, de tag et de commit dans
[Téléchargement des archives de code source](https://docs.github.com/en/repositories/working-with-files/using-files/downloading-source-code-archives).
