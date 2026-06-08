
Connexion root initiale :

```Bash
ssh root@IP_DU_SERVEUR
```

Mise à jour :

```Bash
apt update
apt full-upgrade -y
apt install -y sudo curl wget nano vim git unzip htop ca-certificates gnupg lsb-release apt-transport-https ufw fail2ban python3-systemd
reboot
```

Reconnecter après redémarrage :

```Bash
ssh root@IP_DU_SERVEUR
```

Swap config :

```Bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```


---

## 3. Créer un utilisateur administrateur

```Bash
adduser lucas
usermod -aG sudo lucas
```

Copier la clé SSH du root vers le nouvel utilisateur, si elle existe :

```Bash
rsync --archive --chown=lucas:lucas ~/.ssh /home/lucas
```

Tester dans un nouveau terminal :

```Bash
ssh lucas@IP_DU_SERVEUR
sudo whoami
```

Le retour doit être :

```
root
```

Ne pas fermer la session root tant que la connexion avec `lucas` n’est pas confirmée.

---

## 4. Durcir SSH et changer le port

Créer une sauvegarde :

```Bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
```

Éditer :

```Bash
sudo nano /etc/ssh/sshd_config
```

Mettre ou modifier :

```Bash
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
```

Vérifier la configuration :

```Bash
sudo sshd -t
```

Redémarrer SSH :

```Bash
sudo systemctl restart ssh
```

Tester immédiatement dans un nouveau terminal :

```Bash
ssh -p 2222 lucas@IP_DU_SERVEUR
```

---

## 5. Firewall UFW

Ouvrir uniquement SSH, HTTP et HTTPS :

```Bash
sudo ufw default deny incoming
sudo ufw default allow outgoing

sudo ufw allow 2222/tcp comment "SSH custom"
sudo ufw allow 80/tcp comment "HTTP"
sudo ufw allow 443/tcp comment "HTTPS"

sudo ufw enable
sudo ufw status verbose
```

Point important avec Docker : Docker peut publier des ports qui contournent certaines règles UFW si les ports sont exposés directement. La documentation Docker recommande de tenir compte de l’interaction Docker/firewall et d’utiliser notamment la chaîne `DOCKER-USER` pour filtrer proprement.

Dans cette procédure, les applications Docker ne seront pas exposées directement au public ; seul le reverse proxy publiera `80` et `443`.

---

## 6. Fail2ban pour SSH

Créer une configuration locale :

```Bash
sudo nano /etc/fail2ban/jail.local
```

Contenu :

```INI
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
backend = systemd
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = 2222
filter = sshd
logpath = %(sshd_log)s
backend = systemd
```

Activer :

```Bash
sudo systemctl enable --now fail2ban
sudo fail2ban-client status
sudo fail2ban-client status sshd
```

Test de logs :

```Bash
sudo journalctl -u ssh --no-pager -n 50
```

# Plan for BackUp

our ton cas Docker, le plus simple est de tout mettre dans un dossier propre, par exemple :

```Bash
/opt/docker/
  karakeep/
  kill-the-newsletter/
  sabredav/
  caddy/
```

Avec des `docker-compose.yml` et volumes persistants. Comme ça, si tu upgrades de S+ à M+, tu gardes tes conteneurs, volumes, configs et données.

Avant upgrade :

```Bash
cd /opt/docker
sudo tar -czf ~/backup-docker-$(date +%F).tar.gz .
docker ps
docker compose ls
```

Après upgrade :

```Bash
free -h
df -h
docker ps
```