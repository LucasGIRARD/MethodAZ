# Scan CVE Docker avec Trivy

Trivy est adapté ici car il scanne directement les images Docker locales et peut produire des sorties table, JSON ou SARIF.

Créer un dossier :

```Bash
sudo mkdir -p /var/log/server-checks/trivy
sudo chown -R lucas:lucas /var/log/server-checks
```

Installer Trivy via conteneur Docker, sans installation système :

```Bash
docker pull aquasec/trivy:latest
```

Créer le script :

```Bash
sudo nano /usr/local/sbin/scan-docker-cves.sh
```

Contenu :

```Bash
#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="/var/log/server-checks/trivy"
DATE="$(date +%F_%H-%M-%S)"
TXT_REPORT="$REPORT_DIR/cve-report-$DATE.txt"
JSON_REPORT="$REPORT_DIR/cve-report-$DATE.json"

mkdir -p "$REPORT_DIR"

#IMAGES="$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -v '<none>' | sort -u)"
IMAGES="$(docker ps --format '{{.Image}}' | sort -u)"

echo "===== Docker CVE scan =====" | tee "$TXT_REPORT"
echo "Date: $(date -Is)" | tee -a "$TXT_REPORT"
echo | tee -a "$TXT_REPORT"

echo "[" > "$JSON_REPORT"
FIRST=1

for IMAGE in $IMAGES; do
  echo "### Image: $IMAGE" | tee -a "$TXT_REPORT"

  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v trivy-cache:/root/.cache/ \
    aquasec/trivy:latest image \
    --severity HIGH,CRITICAL \
    --ignore-unfixed \
    --format table \
    "$IMAGE" | tee -a "$TXT_REPORT" || true

  TMP_JSON="$(mktemp)"

  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v trivy-cache:/root/.cache/ \
    aquasec/trivy:latest image \
    --severity HIGH,CRITICAL \
    --ignore-unfixed \
    --format json \
    "$IMAGE" > "$TMP_JSON" || true

  if [ "$FIRST" -eq 0 ]; then
    echo "," >> "$JSON_REPORT"
  fi

  jq --arg image "$IMAGE" '. + {"ScannedImage": $image}' "$TMP_JSON" >> "$JSON_REPORT" || cat "$TMP_JSON" >> "$JSON_REPORT"

  FIRST=0
  rm -f "$TMP_JSON"

  echo | tee -a "$TXT_REPORT"
done

echo "]" >> "$JSON_REPORT"

echo "Rapport texte : $TXT_REPORT"
echo "Rapport JSON  : $JSON_REPORT"

find "$REPORT_DIR" -type f -name "cve-report-*.txt" -mtime +30 -delete
find "$REPORT_DIR" -type f -name "cve-report-*.json" -mtime +30 -delete
```

Installer `jq` :

```Bash
sudo apt install -y jq
```

Permissions :

```Bash
sudo chmod +x /usr/local/sbin/scan-docker-cves.sh
```

Test :

```Bash
sudo /usr/local/sbin/scan-docker-cves.sh
```

Lire le dernier rapport :

```Bash
ls -lh /var/log/server-checks/trivy/
tail -n 100 /var/log/server-checks/trivy/cve-report-*.txt
```