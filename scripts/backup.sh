#!/usr/bin/env bash
# Backup di dati e stato di Lizmap: progetti, configurazione, utenti, plugin QGIS e Filebrowser.
#
# Uso (sulla VM, dalla radice del repository, anche da cron):
#   scripts/backup.sh [cartella_di_destinazione]     # predefinita: ./backup
# Conserva gli ultimi $GIORNI giorni. La copia fuori dalla VM è un passo separato.
# Richiede il client sqlite3 sull'host (apt install sqlite3).
#
# L'archivio contiene gli hash delle password (jauth.db): cartella 700, file 600.
set -euo pipefail

cd "$(dirname "$0")/.."
command -v sqlite3 >/dev/null || { echo "manca sqlite3: sudo apt install sqlite3" >&2; exit 1; }
DEST=${1:-backup}
GIORNI=${GIORNI:-14}
STAMP=$(date +%F_%H%M)
install -d -m 700 "$DEST"
ARCHIVIO="$DEST/lizmap_$STAMP.tar.gz"

# I database SQLite si copiano con .backup, che dà un file coerente anche a servizi accesi.
# Le copie finiscono nell'archivio sotto sqlite/, con lo stesso percorso relativo dell'originale;
# gli originali, che possono cambiare durante la lettura, restano fuori.
TMP=$(mktemp -d)
trap 'sudo rm -rf "$TMP"' EXIT
DBS=(lizmap/var/lizmap-db/jauth.db lizmap/var/lizmap-db/logs.db filebrowser_quantum/filebrowser.sqlite)
for db in "${DBS[@]}"; do
  mkdir -p "$TMP/sqlite/$(dirname "$db")"
  sudo sqlite3 "$db" ".backup '$TMP/sqlite/$db'"
done

# --anchored: le esclusioni valgono solo per i percorsi originali, non per le copie sotto sqlite/.
# Codice 1 di tar = qualche file è cambiato durante la lettura (per esempio un upload in corso):
# l'archivio è comunque utilizzabile, si segnala e si prosegue.
esito=0
sudo sh -c 'umask 077; exec "$@"' sh tar --numeric-owner -czpf "$ARCHIVIO" \
  --anchored \
  --exclude='lizmap/var/lizmap-log/*' \
  --exclude='lizmap/var/lizmap-db/*' \
  --exclude='filebrowser_quantum/filebrowser.sqlite*' \
  lizmap/instances lizmap/var lizmap/etc lizmap/lizmap-modules lizmap/qgis-plugins lizmap/qgis-authdb \
  filebrowser_quantum docker-compose.yml \
  -C "$TMP" sqlite || esito=$?
if [ "$esito" -eq 1 ]; then
  echo "Attenzione: alcuni file sono cambiati durante il backup (vedi sopra)." >&2
elif [ "$esito" -ne 0 ]; then
  echo "Backup fallito (tar, codice $esito)." >&2
  exit "$esito"
fi

sudo find "$DEST" -name 'lizmap_*.tar.gz' -mtime +"$GIORNI" -delete
sudo ls -lh "$ARCHIVIO"
