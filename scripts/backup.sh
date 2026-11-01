#!/usr/bin/env bash
# Backup di dati e stato di Lizmap: progetti, configurazione, utenti e Filebrowser.
#
# Uso (sulla VM, dalla radice del repository, anche da cron):
#   scripts/backup.sh [cartella_di_destinazione]     # predefinita: ./backup
# Conserva gli ultimi $GIORNI giorni. La copia fuori dalla VM è un passo separato.
# Richiede il client sqlite3 sull'host (apt install sqlite3).
set -euo pipefail

cd "$(dirname "$0")/.."
command -v sqlite3 >/dev/null || { echo "manca sqlite3: sudo apt install sqlite3" >&2; exit 1; }
DEST=${1:-backup}
GIORNI=${GIORNI:-14}
STAMP=$(date +%F_%H%M)
mkdir -p "$DEST"

# I database SQLite si copiano con .backup, che dà un file coerente anche a servizi accesi.
# Le copie finiscono nell'archivio sotto sqlite/, con lo stesso percorso relativo dell'originale.
TMP=$(mktemp -d)
trap 'sudo rm -rf "$TMP"' EXIT
DBS=(lizmap/var/lizmap-db/jauth.db lizmap/var/lizmap-db/logs.db filebrowser_quantum/filebrowser.sqlite)
for db in "${DBS[@]}"; do
  mkdir -p "$TMP/sqlite/$(dirname "$db")"
  sudo sqlite3 "$db" ".backup '$TMP/sqlite/$db'"
done

sudo tar --numeric-owner -czpf "$DEST/lizmap_$STAMP.tar.gz" \
  --exclude='lizmap/var/lizmap-log/*' \
  lizmap/instances lizmap/var lizmap/etc filebrowser_quantum docker-compose.yml \
  -C "$TMP" sqlite

sudo find "$DEST" -name 'lizmap_*.tar.gz' -mtime +"$GIORNI" -delete
ls -lh "$DEST/lizmap_$STAMP.tar.gz"
