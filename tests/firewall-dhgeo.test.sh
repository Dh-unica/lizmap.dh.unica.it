#!/usr/bin/env bash
# Prove di scripts/firewall-dhgeo.sh in un namespace di rete isolato: il firewall della macchina
# non viene toccato.
#
# Uso: tests/firewall-dhgeo.test.sh
# Serve unshare con i namespace utente (sul PC); dove sono bloccati, per esempio sui runner di
# GitHub, si lancia con sudo.
set -euo pipefail

cd "$(dirname "$0")/.."
if [ "${FW_NAMESPACE:-}" != 1 ]; then
  if [ "$(id -u)" -eq 0 ]; then
    exec env FW_NAMESPACE=1 unshare -n "$0"
  fi
  exec env FW_NAMESPACE=1 unshare -rn "$0"
fi

FW=scripts/firewall-dhgeo.sh
fallite=0

regole() { iptables -w -S DOCKER-USER 2>/dev/null | grep '^-A ' || true; }
regola() { regole | sed -n "${1}p"; }
nostre() { regole | grep -c 'firewall-dhgeo' || true; }
azzera() {
  iptables -w -F DOCKER-USER 2>/dev/null || true
  iptables -w -X DOCKER-USER 2>/dev/null || true
}
verifica() {
  local descrizione=$1; shift
  if "$@" >/dev/null; then
    echo "ok - $descrizione"
  else
    echo "FALLITA - $descrizione" >&2
    regole | sed 's/^/    /' >&2
    fallite=$((fallite + 1))
  fi
}
contiene() { grep -q -e "$2" <<<"$1"; }

# 1. Catena assente, come al primo boot prima di Docker: la crea e mette le due regole.
azzera
bash "$FW" applica >/dev/null
verifica "crea DOCKER-USER se manca" iptables -w -S DOCKER-USER
verifica "regola 1: RETURN dal proxy" contiene "$(regola 1)" '-s 90.147.144.144/32 .*-j RETURN'
verifica "regola 2: DROP per tutti gli altri" contiene "$(regola 2)" '-j DROP'
verifica "filtra sulla destinazione originale (prima del DNAT)" \
  contiene "$(regola 2)" '--ctorigdst 90.147.144.148\(/32\)\? --ctorigdstport 8084:8087 --ctdir ORIGINAL'
verifica "stato esce con 0" bash -c "bash $FW stato >/dev/null"

# 2. Catena di Docker con il suo RETURN finale: le nostre vanno in cima, il resto resta.
azzera
iptables -w -N DOCKER-USER
iptables -w -A DOCKER-USER -j RETURN
bash "$FW" applica >/dev/null
verifica "le nostre in cima" contiene "$(regola 2)" 'firewall-dhgeo'
verifica "il RETURN di Docker resta in fondo" test "$(regola 3)" = "-A DOCKER-USER -j RETURN"

# 3. Idempotenza: rilanciata non duplica.
bash "$FW" applica >/dev/null
bash "$FW" applica >/dev/null
verifica "dopo tre applica restano due regole nostre" test "$(nostre)" = 2
verifica "tre regole in tutto" test "$(regole | wc -l)" = 3

# 4. Cambio del proxy: le regole vecchie spariscono.
PROXY_IP=192.0.2.10 bash "$FW" applica >/dev/null
verifica "il nuovo proxy è ammesso" contiene "$(regola 1)" '-s 192.0.2.10/32'
verifica "il vecchio proxy non c'è più" test "$(regole | grep -c '90.147.144.144' || true)" = 0
verifica "ancora due regole nostre" test "$(nostre)" = 2

# 5. Regole fuori posto: stato se ne accorge, applica le rimette in cima.
bash "$FW" applica >/dev/null
iptables -w -I DOCKER-USER 1 -j RETURN
verifica "stato fallisce se le regole non sono in cima" bash -c "! bash $FW stato >/dev/null 2>&1"
bash "$FW" applica >/dev/null
verifica "applica le rimette in cima" contiene "$(regola 1)" 'firewall-dhgeo'
verifica "senza duplicati" test "$(nostre)" = 2

# 6. Rimozione: via le nostre, il resto resta.
bash "$FW" rimuovi >/dev/null 2>&1
verifica "rimuovi toglie le regole nostre" test "$(nostre)" = 0
verifica "rimuovi lascia le altre" test "$(regole | wc -l)" = 2
verifica "stato fallisce senza regole" bash -c "! bash $FW stato >/dev/null 2>&1"

# 7. Comando sconosciuto.
verifica "comando sconosciuto: codice 2" bash -c "bash $FW boh >/dev/null 2>&1; test \$? -eq 2"

if [ "$fallite" -gt 0 ]; then
  echo "$fallite prove fallite" >&2
  exit 1
fi
echo "tutte le prove passate"
