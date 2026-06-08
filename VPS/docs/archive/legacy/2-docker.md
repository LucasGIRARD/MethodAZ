Supprimer d’éventuels paquets conflictuels :

```Bash
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  sudo apt remove -y "$pkg" || true
done
```

Ajouter le dépôt Docker :

```Bash
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

Activer Docker :

```Bash
sudo systemctl enable --now docker
sudo docker run hello-world
```

Autoriser l’utilisateur à lancer Docker sans `sudo` :

```Bash
sudo usermod -aG docker lucas
```

Se déconnecter/reconnecter, puis vérifier :

```Bash
docker compose version
docker ps
```

## Structure simple

```Bash
mkdir -p ~/docker/apps
cd ~/docker/apps
```

Exemple `docker-compose.yml` minimal avec Nginx :

```Yaml
services:
  web:
    image: nginx:alpine
    container_name: nginx
    ports:
      - "80:80"
    restart: unless-stopped
```

Lancer :

```Bash
docker compose up -d
```

Voir les conteneurs :

```Bash
docker ps
```

Logs :

```Bash
docker logs -f nginx
```

Arrêter :

```Bash
docker compose down
```