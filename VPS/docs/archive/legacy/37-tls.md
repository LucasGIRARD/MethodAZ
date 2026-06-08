# Vérification des certificats TLS
Caddy renouvelle automatiquement les certificats, mais ce script vérifie les dates d’expiration côté client.

Créer :

```Bash
sudo nano /usr/local/sbin/check-certificates.sh
```

Contenu :

```Bash
#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="/var/log/server-checks"
REPORT="$REPORT_DIR/certificates.txt"

DOMAINS=(
  "links.example.fr"
  "dav.example.fr"
  "newsletter.example.fr"
  "freshrss.example.fr"
  "ttrss.example.fr"
  "web.example.fr"
)

mkdir -p "$REPORT_DIR"

{
  echo "===== Certificate check ====="
  date -Is
  echo

  for DOMAIN in "${DOMAINS[@]}"; do
    echo "### $DOMAIN"

    EXPIRY_RAW="$(
      echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN:443" 2>/dev/null \
      | openssl x509 -noout -enddate 2>/dev/null \
      | cut -d= -f2 || true
    )"

    if [ -z "$EXPIRY_RAW" ]; then
      echo "Erreur: certificat non récupérable"
      echo
      continue
    fi

    EXPIRY_EPOCH="$(date -d "$EXPIRY_RAW" +%s)"
    NOW_EPOCH="$(date +%s)"
    DAYS_LEFT="$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))"

    echo "Expiration : $EXPIRY_RAW"
    echo "Jours restants : $DAYS_LEFT"

    if [ "$DAYS_LEFT" -lt 15 ]; then
      echo "ALERTE: certificat proche expiration"
    else
      echo "OK"
    fi

    echo
  done
} > "$REPORT"

cat "$REPORT"
```

Remplacer les domaines :

```Bash
sudo nano /usr/local/sbin/check-certificates.sh
```

Permissions :

```Bash
sudo chmod +x /usr/local/sbin/check-certificates.sh
```

Test :

```Bash
sudo /usr/local/sbin/check-certificates.sh
```