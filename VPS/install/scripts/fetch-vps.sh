#!/bin/sh
set -eu

REPOSITORY=${METHODAZ_REPOSITORY:-LucasGIRARD/MethodAZ}
MODE=ref
REF=main
DESTINATION=./methodaz-vps

usage() {
  cat <<EOF
Usage:
  fetch-vps.sh --version VERSION [DESTINATION]
  fetch-vps.sh --select-version [DESTINATION]
  fetch-vps.sh --latest [DESTINATION]
  fetch-vps.sh --ref REF [DESTINATION]
  fetch-vps.sh REF [DESTINATION]

Options:
  --version VERSION   Télécharge le tag de release indiqué, par exemple v1.2.0.
  --select-version    Liste les releases GitHub et demande quelle version installer.
  --latest            Télécharge la dernière release GitHub publiée.
  --ref REF           Télécharge une branche ou un commit. Réservé aux tests.
EOF
}

if [ "$#" -gt 0 ]; then
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --version)
      [ "$#" -ge 2 ] || {
        echo "Version manquante." >&2
        exit 2
      }
      MODE=version
      REF=$2
      shift 2
      ;;
    --select-version)
      MODE=select
      shift
      ;;
    --latest)
      MODE=latest
      shift
      ;;
    --ref)
      [ "$#" -ge 2 ] || {
        echo "Référence manquante." >&2
        exit 2
      }
      MODE=ref
      REF=$2
      shift 2
      ;;
    --*)
      echo "Option inconnue : $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      MODE=ref
      REF=$1
      shift
      ;;
  esac
fi

if [ "$#" -gt 0 ]; then
  DESTINATION=$1
  shift
fi
[ "$#" -eq 0 ] || {
  echo "Arguments en trop : $*" >&2
  exit 2
}

case "$REPOSITORY" in
  *[!A-Za-z0-9._/-]*|*/*/*|/*|*/|'')
    echo "Dépôt GitHub invalide : $REPOSITORY" >&2
    exit 2
    ;;
esac

validate_ref() {
  case "$1" in
    *[!A-Za-z0-9._-]*|'')
      echo "Référence GitHub invalide : $1" >&2
      exit 2
      ;;
  esac
}

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

release_tags() {
  curl --fail --location --silent --show-error \
    --retry 3 --connect-timeout 15 \
    "https://api.github.com/repos/$REPOSITORY/releases?per_page=20" \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

latest_version() {
  curl --fail --location --silent --show-error \
    --retry 3 --connect-timeout 15 \
    "https://api.github.com/repos/$REPOSITORY/releases/latest" \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | sed -n '1p'
}

select_version() {
  tags=$(release_tags)
  [ -n "$tags" ] || {
    echo "Aucune release GitHub trouvée pour $REPOSITORY." >&2
    exit 1
  }

  echo "Versions disponibles :" >&2
  i=0
  for tag in $tags; do
    i=$((i + 1))
    echo "  $i) $tag" >&2
  done

  printf "Version à installer [1] : " >&2
  read answer
  [ -n "$answer" ] || answer=1

  i=0
  for tag in $tags; do
    i=$((i + 1))
    if [ "$i" = "$answer" ]; then
      printf '%s\n' "$tag"
      return 0
    fi
  done

  echo "Sélection invalide : $answer" >&2
  exit 2
}

case "$MODE" in
  latest)
    REF=$(latest_version)
    [ -n "$REF" ] || {
      echo "Impossible de déterminer la dernière release." >&2
      exit 1
    }
    MODE=version
    ;;
  select)
    REF=$(select_version)
    MODE=version
    ;;
esac
validate_ref "$REF"

destination_parent=$(dirname -- "$DESTINATION")
mkdir -p "$destination_parent"

temporary=$(mktemp -d)
cleanup() {
  rm -rf -- "$temporary"
}
trap cleanup EXIT HUP INT TERM

archive="$temporary/methodaz.tar.gz"
case "$MODE:$REF" in
  version:*)
    default_url="https://github.com/$REPOSITORY/archive/refs/tags/$REF.tar.gz"
    source_type=release
    ;;
  ref:*)
    case "$REF" in
      *[!0-9A-Fa-f]*) is_commit=false ;;
      *) [ "${#REF}" -eq 40 ] && is_commit=true || is_commit=false ;;
    esac

    if [ "$is_commit" = true ]; then
      default_url="https://github.com/$REPOSITORY/archive/$REF.tar.gz"
      source_type=commit
    else
      default_url="https://github.com/$REPOSITORY/archive/refs/heads/$REF.tar.gz"
      source_type=branch
    fi
    ;;
  *)
    echo "Mode interne invalide : $MODE" >&2
    exit 2
    ;;
esac
url=${METHODAZ_ARCHIVE_URL:-$default_url}

echo "Téléchargement de $REPOSITORY ($source_type $REF)"
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
source_type=$source_type
ref=$REF
downloaded_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

mv "$bundle" "$DESTINATION"
echo "Bundle VPS téléchargé dans : $DESTINATION"
echo "Source enregistrée dans : $DESTINATION/install/source-version.txt"
