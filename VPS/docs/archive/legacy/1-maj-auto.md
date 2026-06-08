# Mises à jour automatiques Debian + noyau

Installer :

```Bash
sudo apt install -y unattended-upgrades apt-listchanges needrestart
```

Activer :

```Bash
sudo dpkg-reconfigure unattended-upgrades
```

Configurer :

```Bash
sudo nano /etc/apt/apt.conf.d/50unattended-upgrades
```

Vérifier que ces lignes sont actives :

```
Unattended-Upgrade::Origins-Pattern {
        "origin=Debian,codename=${distro_codename},label=Debian-Security";
        "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
        "origin=Debian,codename=${distro_codename}-updates,label=Debian";
};

Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
```

Créer un contrôle de noyau actif :

```Bash
sudo nano /usr/local/sbin/check-kernel-reboot.sh
```

Contenu :

```Bash
#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="/var/log/server-checks"
REPORT="$REPORT_DIR/kernel-check.txt"

mkdir -p "$REPORT_DIR"

{
  echo "===== Kernel check ====="
  date -Is
  echo
  echo "Kernel actif :"
  uname -r
  echo
  echo "Dernier kernel installé :"
  dpkg -l 'linux-image-*' 2>/dev/null | awk '/^ii/ {print $2}' | sort -V | tail -n 5
  echo
  echo "Reboot requis :"
  if [ -f /var/run/reboot-required ]; then
    cat /var/run/reboot-required
    [ -f /var/run/reboot-required.pkgs ] && cat /var/run/reboot-required.pkgs
  else
    echo "Non"
  fi
  echo
  echo "Paquets à mettre à jour :"
  apt list --upgradable 2>/dev/null || true
} > "$REPORT"

cat "$REPORT"
```

Permissions :

```Bash
sudo chmod +x /usr/local/sbin/check-kernel-reboot.sh
```

Test :

```Bash
sudo /usr/local/sbin/check-kernel-reboot.sh
```

---

# Vérification des mises à jour Docker

Je déconseille l’auto-update complet sans validation, surtout pour Linkwarden, Davis, FreshRSS, tt-rss et les bases de données. Meilleure approche :

```
1. Vérifier les nouvelles images
2. Scanner CVE
3. Sauvegarder
4. Mettre à jour service par service
5. Vérifier les logs
```

Installer Watchtower en mode vérification seulement :

```Bash
mkdir -p /opt/selfhosted/watchtower
cd /opt/selfhosted/watchtower
nano docker-compose.yml
```

Contenu :

```YAML
services:
  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    restart: unless-stopped
    command:
      - --monitor-only
      - --schedule
      - "0 0 6 * * *"
      - --cleanup
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - TZ=Europe/Paris
```

Démarrer :

```Bash
docker compose up -ddocker logs -f watchtower
```

Pour une vérification manuelle :

```Bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  containrrr/watchtower:latest \
  --run-once \
  --monitor-only
```