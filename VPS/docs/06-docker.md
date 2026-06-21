# Docker

## Objectif

Installer Docker depuis le dépôt officiel et préparer l'arborescence applicative
unique sous `/opt/selfhosted`.

## Supprimer les paquets conflictuels

```bash
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  sudo apt remove -y "$pkg" || true
done
```

## Installer Docker

```bash
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings

sudo curl -fsSL https://download.docker.com/linux/debian/gpg \
  -o /etc/apt/keyrings/docker.asc

sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

## Journaux et métriques Docker

Avant de créer les conteneurs, envoyer leurs sorties standard dans
`journald`. Cette stratégie permet à Grafana Alloy de lire les journaux sans
monter directement le socket Docker. La rotation est assurée par les limites
globales de journald décrites dans
[Journalisation, rotation et rétention](16-journalisation-rotation.md).

Activer également l'endpoint Prometheus du démon Docker sur l'adresse locale.
Il ne doit jamais écouter sur une adresse publique.

Créer ou fusionner avec précaution `/etc/docker/daemon.json` :

```json
{
  "log-driver": "journald",
  "log-opts": {
    "tag": "{{.Name}}",
    "labels": "com.docker.compose.project,com.docker.compose.service"
  },
  "metrics-addr": "127.0.0.1:9323",
  "experimental": true
}
```

Si le fichier existe déjà, ne pas écraser ses autres options. Vérifier puis
redémarrer Docker :

```bash
sudo dockerd --validate --config-file=/etc/docker/daemon.json
sudo systemctl restart docker
docker info --format '{{.LoggingDriver}}'
```

Le résultat attendu est :

```text
journald
```

Vérifier aussi l'endpoint local :

```bash
curl -fsS http://127.0.0.1:9323/metrics >/dev/null
sudo ss -ltnp | grep ':9323'
```

La nouvelle configuration de journalisation s'applique uniquement aux
conteneurs créés après le changement. Les conteneurs existants doivent être
recréés service par service.

## Activer Docker

```bash
sudo systemctl enable --now docker
sudo docker run hello-world
```

Autoriser l'utilisateur administrateur à utiliser Docker :

```bash
sudo usermod -aG docker lucas
```

Se déconnecter puis se reconnecter, puis vérifier :

```bash
docker compose version
docker ps
```

## Arborescence applicative

```bash
sudo mkdir -p /opt/selfhosted/{databases,linkwarden,davis,kill-newsletter,freshrss,ttrss,web,backups}
sudo chown -R lucas:lucas /opt/selfhosted
cd /opt/selfhosted
```

Règles retenues :

- Un dossier par service.
- Un fichier `docker-compose.yml` par service.
- Les volumes persistants dans le dossier du service.
- Aucun fichier Compose dans `/var/lib/docker`.

Exemple :

```text
/opt/selfhosted/
  databases/
    docker-compose.yml
    postgres/
  linkwarden/
    docker-compose.yml
    data/
  davis/
    docker-compose.yml
    data/
  backups/
```

## Convention réseau

Les services accessibles depuis Internet publient un port local :

```yaml
ports:
  - "127.0.0.1:3001:3000"
```

Chaque application rejoint uniquement son réseau SQL interne :

```yaml
networks:
  database:
    external: true
    name: vps-db-linkwarden
```

Le projet `databases` crée ces réseaux avec `internal: true`. Aucun port
PostgreSQL n'est publié.

## Vérification

```bash
docker ps
docker network ls
sudo ss -tulpn
```

Vérifier le pilote de chaque conteneur :

```bash
docker inspect --format '{{.Name}} {{.HostConfig.LogConfig.Type}} {{json .HostConfig.LogConfig.Config}}' $(docker ps -q)
```

La politique complète est décrite dans
[Journalisation, rotation et rétention](16-journalisation-rotation.md).

## Verrouillage des images

Un tag, même numéroté, peut être remplacé dans un registre. Avant de démarrer
un projet en production, résoudre toutes ses images en digests :

```bash
sudo vps-image-lock linkwarden
sudo vps-compose linkwarden up -d
```

Le fichier `docker-compose.lock.yml` créé dans le projet est chargé
automatiquement par `vps-compose`, `vps-gateway` et `vps-monitoring`.

Si `vps-image-lock` échoue avec `install: ... are the same file`, le helper
installé dans `/usr/local/sbin/vps-image-lock` est trop ancien. Rejouer la phase
concernée avec un bundle à jour ; les phases applicatives réinstallent les
helpers avant de les utiliser.

La procédure complète et l'audit des CVE sont décrits dans
[Sécurité des images Docker](17-securite-images-docker.md).
