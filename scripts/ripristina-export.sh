#!/usr/bin/env bash
# Ripristina dati e stato di Lizmap dall'export consegnato da Faunalia nella cartella del repository.
#
# Uso (sulla VM, dalla radice del repository):
#   scripts/ripristina-export.sh ~/archivi-faunalia/unica-lizmap_export_20261027.tar.gz
#
# Cosa fa:
#   - estrae l'archivio come root con --numeric-owner, per conservare uid e gid numerici
#     (i container girano come 1000:1000);
#   - sposta nel repository solo dati e stato: lizmap/{instances,var,www,lizmap-modules,
#     qgis-authdb,qgis-plugins} e filebrowser_quantum/filebrowser.sqlite;
#   - lascia invariati i file versionati (docker-compose.yml, lizmap/etc, config.yaml).
# Si ferma se i dati sono già presenti: non sovrascrive mai.
set -euo pipefail

ARCHIVIO=${1:?"uso: $0 /percorso/unica-lizmap_export_AAAAMMGG.tar.gz"}
ARCHIVIO=$(realpath "$ARCHIVIO")
REPO=$(cd "$(dirname "$0")/.." && pwd)
DATI=(instances var www lizmap-modules qgis-authdb qgis-plugins)

cd "$REPO"
for d in "${DATI[@]}"; do
  if [ -e "lizmap/$d" ]; then
    echo "lizmap/$d esiste già: interrompo per non sovrascrivere dati." >&2
    exit 1
  fi
done
if [ -e filebrowser_quantum/filebrowser.sqlite ]; then
  echo "filebrowser_quantum/filebrowser.sqlite esiste già: interrompo." >&2
  exit 1
fi

TMP=$(mktemp -d "$REPO/.ripristino.XXXXXX")
trap 'sudo rm -rf "$TMP"' EXIT

echo "Estrazione di $(basename "$ARCHIVIO")..."
sudo tar --numeric-owner -xzpf "$ARCHIVIO" -C "$TMP"
SRC="$TMP/unica-lizmap_export"

for d in "${DATI[@]}"; do
  sudo mv "$SRC/lizmap/$d" "lizmap/$d"
done
sudo mv "$SRC/filebrowser_quantum/filebrowser.sqlite" filebrowser_quantum/filebrowser.sqlite

echo "Proprietari (atteso 1000:1000):"
sudo stat -c '  %u:%g %n' lizmap/instances lizmap/var/lizmap-db/jauth.db lizmap/var/lizmap-config filebrowser_quantum/filebrowser.sqlite
echo "Ripristino completato. Prossimo passo: docker compose up -d && scripts/smoke-test.sh"
