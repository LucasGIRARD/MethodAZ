# Rapport global d’état serveur

Créer un script unique :

```Bash
sudo nano /usr/local/sbin/server-health-report.sh
```

Contenu :

```Bash
#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="/var/log/server-checks"
REPORT="$REPORT_DIR/health-report.txt"

mkdir -p "$REPORT_DIR"

{
  echo "===== SERVER HEALTH REPORT ====="
  date -Is
  echo

  echo "===== Host ====="
  hostnamectl || true
  echo

  echo "===== Uptime ====="
  uptime
  echo

  echo "===== Disk ====="
  df -h
  echo

  echo "===== Memory ====="
  free -h
  echo

  echo "===== Kernel ====="
  uname -a
  if [ -f /var/run/reboot-required ]; then
    echo "Reboot required: YES"
    cat /var/run/reboot-required.pkgs 2>/dev/null || true
  else
    echo "Reboot required: NO"
  fi
  echo

  echo "===== APT updates ====="
  apt list --upgradable 2>/dev/null || true
  echo

  echo "===== Nginx ====="  
  nginx -t || true  
  systemctl status nginx --no-pager || true  
  echo  
  
  echo "===== Apache containers ====="  
  docker ps --filter "name=apache" --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'  
  echo  
  
  echo "===== Certbot ====="  
  certbot certificates || true  
  echo

  echo "===== UFW ====="
  ufw status verbose || true
  echo

  echo "===== Fail2ban ====="
  fail2ban-client status || true
  fail2ban-client status sshd || true
  echo

  echo "===== Docker containers ====="
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
  echo

  echo "===== Docker disk usage ====="
  docker system df
  echo

  #echo "===== Caddy logs tail ====="
  #docker logs caddy --tail=80 2>&1 || true
  echo

  echo "===== Docker image update report ====="  
  if [ -f /var/log/server-checks/docker-image-updates.txt ]; then  
    cat /var/log/server-checks/docker-image-updates.txt  
  else  
    echo "Pas encore généré"  
  fi  
  echo  
  
echo "===== Nginx recent errors ====="  
tail -n 100 /var/log/nginx/error.log 2>/dev/null || true  
echo

  echo "===== Cockpit ====="
  systemctl status cockpit.socket --no-pager || true

} > "$REPORT"

cat "$REPORT"
```

Permissions :

```Bash
sudo chmod +x /usr/local/sbin/server-health-report.sh
```

Test :

```Bash
sudo /usr/local/sbin/server-health-report.sh
```

Lecture :

```Bash
less /var/log/server-checks/health-report.txt
```