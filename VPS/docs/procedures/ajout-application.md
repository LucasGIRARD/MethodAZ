# Ajouter une application

## Décision préalable

Vérifier avant intégration :

- image officielle ou publication clairement reliée au dépôt amont ;
- version précise ou digest, jamais un tag mutable ;
- un processus applicatif principal par conteneur ;
- architecture `amd64` disponible pour le VPS ;
- consommation compatible avec `VPS_2G` ou `VPS_4G` ;
- méthode documentée pour sauvegarder et restaurer les données ;
- support éventuel des secrets sous forme de fichiers.

## Créer le projet

Ajouter :

```text
install/services/NOM/docker-compose.yml
docs/services/NOM.md
```

Le projet doit respecter les conventions suivantes :

- port publié uniquement sur `127.0.0.1` ;
- `restart: unless-stopped` ;
- `pids_limit`, `mem_limit` et `no-new-privileges` ;
- healthcheck applicatif sans dépendance ajoutée inutilement à l'image ;
- volume ou bind mount explicite pour chaque donnée persistante ;
- réseau SQL interne propre si une base partagée est utilisée ;
- secret Compose uniquement si l'application sait lire le fichier monté.

## Intégrer l'installation

Modifier :

- `install/scripts/vps-install.sh` pour copier le projet et écrire son `.env` ;
- `install/scripts/vps-compose` et `vps-image-lock` pour reconnaître le nom ;
- les scripts de test local ;
- `install/scripts/vps-backup` si des données sortent des répertoires déjà
  archivés ;
- Nginx et la documentation des ports ;
- le profil mémoire `VPS_2G` et `VPS_4G`.

Si une base partagée est ajoutée, créer un utilisateur, une base et un réseau
distincts dans `install/databases`.

## Valider

```bash
sh install/scripts/validate-bundle.sh
pwsh install/scripts/validate-repository.ps1
sh install/scripts/local-compose.sh validate
sh install/scripts/local-compose.sh up NOM
```

Contrôler ensuite :

```bash
docker inspect --format '{{.State.Health.Status}}' CONTENEUR
docker stats --no-stream
curl -fsSI http://127.0.0.1:PORT
```

Ajouter enfin le service au dashboard ou aux métriques locales si son état ne
peut pas être déduit du healthcheck Docker.
