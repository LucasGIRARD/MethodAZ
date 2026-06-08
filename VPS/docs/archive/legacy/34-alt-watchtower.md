Au lieu de Watchtower, utiliser un script qui :

```
1. Liste les images utilisées par les conteneurs
2. Pull les dernières versions sans redémarrer
3. Compare l’image locale utilisée avec la nouvelle image disponible
4. Génère un rapport
5. Ne modifie pas les conteneurs en production
```

Créer :

```Bash
sudo nano /usr/local/sbin/check-docker-image-updates.sh
```

Contenu :

```Bash
#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="/var/log/server-checks"
REPORT="$REPORT_DIR/docker-image-updates.txt"

mkdir -p "$REPORT_DIR"

{
  echo "===== Docker image update check ====="
  date -Is
  echo

  docker ps --format '{{.Image}}' | sort -u | while read -r IMAGE; do
    echo "### $IMAGE"

    BEFORE_ID="$(docker image inspect "$IMAGE" --format '{{.Id}}' 2>/dev/null || true)"

    echo "Image locale avant pull : $BEFORE_ID"

    docker pull "$IMAGE" >/tmp/docker-pull-check.log 2>&1 || {
      echo "Erreur pendant docker pull:"
      cat /tmp/docker-pull-check.log
      echo
      continue
    }

    AFTER_ID="$(docker image inspect "$IMAGE" --format '{{.Id}}' 2>/dev/null || true)"

    echo "Image locale après pull : $AFTER_ID"

    if [ "$BEFORE_ID" != "$AFTER_ID" ]; then
      echo "UPDATE DISPONIBLE / IMAGE TÉLÉCHARGÉE"
      echo "Action requise : redémarrer le service concerné après sauvegarde."
    else
      echo "OK : image déjà à jour"
    fi

    echo
  done

  echo "===== Conteneurs actifs ====="
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'

} > "$REPORT"

cat "$REPORT"
```

Permissions :

```Bash
sudo chmod +x /usr/local/sbin/check-docker-image-updates.sh
```

Test :

```Bash
sudo /usr/local/sbin/check-docker-image-updates.sh
```

Lire le rapport :

```Bash
less /var/log/server-checks/docker-image-updates.txt
```

Important : ce script télécharge les nouvelles images, mais ne recrée pas les conteneurs. La mise à jour effective reste manuelle :

```Bash
cd /opt/selfhosted/linkwarden
docker compose up -d
```