#!/usr/bin/env bash
# Controlli rapidi dello stack Lizmap, da lanciare sulla VM dalla radice del repository.
# Solo letture: non modifica nulla. Esce con codice 1 se un controllo fallisce.
set -uo pipefail

cd "$(dirname "$0")/.."
# shellcheck disable=SC1091
[ -f .env ] && set -a && . ./.env && set +a
WEB=${LIZMAP_WEB_PORT:-127.0.0.1:8084}
FILES=${FILEBROWSER_PORT:-127.0.0.1:8087}
PROGETTO="PARC webGIS/PARC_WEB.qgs"
esito=0

ok()   { echo "  OK    $*"; }
ko()   { echo "  ERRORE $*"; esito=1; }

echo "Container:"
for c in unica-lizmap unica-lizmap-map unica-lizmap-redis unica-lizmap-web unica-filebrowser; do
  stato=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo assente)
  [ "$stato" = running ] && ok "$c" || ko "$c: $stato"
done

echo "Rete interna:"
docker compose exec -T lizmap getent hosts lizmap-redis >/dev/null \
  && ok "lizmap-redis risolto dal container lizmap" || ko "lizmap-redis non risolto"

echo "QGIS Server:"
caps=$(docker compose exec -T lizmap php -r '
  $u = "http://map:8080/ows/?MAP=" . rawurlencode($argv[1]) . "&SERVICE=WMS&REQUEST=GetCapabilities";
  echo @file_get_contents($u);' "$PROGETTO" 2>/dev/null)
if echo "$caps" | grep -q "<WMS_Capabilities"; then
  ok "GetCapabilities di $PROGETTO ($(echo "$caps" | grep -c '<Layer') layer)"
else
  ko "GetCapabilities di $PROGETTO non valido"
fi

echo "HTTP:"
codice=$(curl -s -o /dev/null -w '%{http_code}' "http://$WEB/")
case "$codice" in 200|302) ok "Lizmap http://$WEB/ -> $codice" ;; *) ko "Lizmap http://$WEB/ -> $codice" ;; esac
codice=$(curl -s -o /dev/null -w '%{http_code}' "http://$FILES/files/")
case "$codice" in 200|302) ok "Filebrowser http://$FILES/files/ -> $codice" ;; *) ko "Filebrowser http://$FILES/files/ -> $codice" ;; esac

echo "Errori recenti nei log (ultimi 15 minuti):"
n=$(docker compose logs --since 15m lizmap map 2>&1 | grep -ciE 'error|fatal|exception' || true)
[ "$n" -eq 0 ] && ok "nessuno" || ko "$n righe: docker compose logs --since 15m lizmap map"

exit $esito
