#!/bin/sh
set -eu

REPOSITORY=${METHODAZ_REPOSITORY:-LucasGIRARD/MethodAZ}
REF=${1:-main}
DESTINATION=${2:-./methodaz-vps}

case "$REPOSITORY" in
  *[!A-Za-z0-9._/-]*|*/*/*|/*|*/|'')
    echo "Dépôt GitHub invalide : $REPOSITORY" >&2
    exit 2
    ;;
esac

case "$REF" in
  *[!A-Za-z0-9._-]*|'')
    echo "Référence GitHub invalide : $REF" >&2
    exit 2
    ;;
esac

[ ! -e "$DESTINATION" ] || {
  echo "La destination existe déjà : $DESTINATION" >&2
  exit 1
}

command -v curl >/dev/null 2>&1 || {
  echo "curl est requis." >&2
  exit 1
}
command -v tar >/dev/null 2>&1 || {
  echo "tar est requis." >&2
  exit 1
}

destination_parent=$(dirname -- "$DESTINATION")
mkdir -p "$destination_parent"

temporary=$(mktemp -d)
cleanup() {
  rm -rf -- "$temporary"
}
trap cleanup EXIT HUP INT TERM

archive="$temporary/methodaz.tar.gz"
case "$REF" in
  *[!0-9A-Fa-f]*) is_commit=false ;;
  *) [ "${#REF}" -eq 40 ] && is_commit=true || is_commit=false ;;
esac

if [ "$is_commit" = true ]; then
  default_url="https://github.com/$REPOSITORY/archive/$REF.tar.gz"
else
  default_url="https://github.com/$REPOSITORY/archive/refs/heads/$REF.tar.gz"
fi
url=${METHODAZ_ARCHIVE_URL:-$default_url}

echo "Téléchargement de $REPOSITORY à la référence $REF"
if ! curl --fail --location --silent --show-error \
  --retry 3 --connect-timeout 15 \
  --output "$archive" "$url"; then
  echo "Téléchargement impossible. Vérifier que le dépôt est public et que la référence existe." >&2
  exit 1
fi

readme_entry=$(
  tar -tzf "$archive" \
    | awk '/\/VPS\/README[.]md$/ { print; exit }'
)
[ -n "$readme_entry" ] || {
  echo "Le dossier VPS est absent de l'archive." >&2
  exit 1
}
prefix=${readme_entry%/VPS/README.md}

bundle="$temporary/bundle"
mkdir "$bundle"
tar -xzf "$archive" \
  --directory "$bundle" \
  --strip-components=2 \
  "$prefix/VPS"

cat > "$bundle/install/source-version.txt" <<EOF
repository=$REPOSITORY
ref=$REF
downloaded_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

mv "$bundle" "$DESTINATION"
echo "Bundle VPS téléchargé dans : $DESTINATION"
echo "Source enregistrée dans : $DESTINATION/install/source-version.txt"
