#!/usr/bin/env bash
# Prove di scripts/firewall-dhgeo.sh in un namespace di rete isolato: il firewall della macchina
# non viene toccato.
#
# Uso: tests/firewall-dhgeo.test.sh
# Serve unshare con i namespace utente (sul PC); dove sono bloccati, per esempio sui runner di
# GitHub, si lancia con sudo.
set -euo pipefail

cd "$(dirname "$0")/.."

# In un namespace di rete nuovo c'è solo lo. Il controllo guarda la rete, non un flag: anche
# lanciate da root su dhgeo, le prove non arrivano mai alla DOCKER-USER vera.
isolato() { [ "$(tail -n +3 /proc/net/dev | cut -d: -f1 | tr -d ' ')" = lo ]; }
if ! isolato; then
  if [ -n "${FW_UNSHARE:-}" ]; then
    echo "unshare non ha isolato la rete: prove interrotte." >&2
    exit 1
  fi
  if [ "$(id -u)" -eq 0 ]; then
    exec env FW_UNSHARE=1 unshare -n "$0"
  fi
  exec env FW_UNSHARE=1 unshare -rn "$0"
fi

FW=scripts/firewall-dhgeo.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export FW_LOCK="$TMP/lock"
fallite=0

regole() { iptables -w -S DOCKER-USER 2>/dev/null | grep '^-A ' || true; }
regola() { regole | sed -n "${1}p"; }
nostre() { regole | grep -c 'firewall-dhgeo' || true; }
azzera() {
  iptables -w -F FORWARD
  iptables -w -F DOCKER-USER 2>/dev/null || true
  iptables -w -X DOCKER-USER 2>/dev/null || true
}
# Quello che fa Docker all'avvio: catena con il RETURN finale e salto in cima a FORWARD.
docker_avviato() {
  iptables -w -n -L DOCKER-USER >/dev/null 2>&1 || iptables -w -N DOCKER-USER
  iptables -w -C DOCKER-USER -j RETURN 2>/dev/null || iptables -w -A DOCKER-USER -j RETURN
  iptables -w -I FORWARD 1 -j DOCKER-USER
}
verifica() {
  local descrizione=$1
  shift
  if "$@" >/dev/null; then
    echo "ok - $descrizione"
  else
    echo "FALLITA - $descrizione" >&2
    regole | sed 's/^/    /' >&2
    fallite=$((fallite + 1))
  fi
}
contiene() { grep -q -e "$2" <<<"$1"; }
fallisce() { ! bash "$@" >/dev/null 2>&1; }

# 1. Boot: l'unità gira prima di Docker. Crea la catena e mette le regole; stato segnala che
#    il traffico non passa ancora dalla catena.
azzera
verifica "applica prima di Docker riesce" bash "$FW" applica
verifica "crea DOCKER-USER se manca" iptables -w -S DOCKER-USER
verifica "regola 1: RETURN dal proxy" contiene "$(regola 1)" '-s 90.147.144.144/32 .*-j RETURN'
verifica "regola 2: DROP per tutti gli altri" contiene "$(regola 2)" '-j DROP'
verifica "filtra sulla destinazione originale (prima del DNAT)" \
  contiene "$(regola 2)" '--ctorigdst 90.147.144.148\(/32\)\? --ctorigdstport 8084:8087 --ctdir ORIGINAL'
verifica "stato fallisce senza il salto da FORWARD" fallisce "$FW" stato

# 2. Docker avviato: le nostre restano in cima, il RETURN di Docker in fondo, stato a 0.
docker_avviato
verifica "stato esce con 0 con Docker avviato" bash "$FW" stato
verifica "il RETURN di Docker resta in fondo" test "$(regola 3)" = "-A DOCKER-USER -j RETURN"

# 3. Idempotenza: rilanciata non duplica.
bash "$FW" applica >/dev/null
bash "$FW" applica >/dev/null
verifica "dopo tre applica restano due regole nostre" test "$(nostre)" = 2
verifica "tre regole in tutto" test "$(regole | wc -l)" = 3

# 4. Regola con l'etichetta ma con un indirizzo diverso: stato se ne accorge, applica la sostituisce.
iptables -w -R DOCKER-USER 2 -p tcp -m conntrack --ctorigdst 192.0.2.1 --ctorigdstport 8084:8087 \
  --ctdir ORIGINAL -m comment --comment firewall-dhgeo -j DROP
verifica "stato fallisce se l'indirizzo non è quello atteso" fallisce "$FW" stato
bash "$FW" applica >/dev/null
verifica "applica la sostituisce" bash "$FW" stato
verifica "l'indirizzo sbagliato non c'è più" test "$(regole | grep -c '192.0.2.1' || true)" = 0

# 5. Regole fuori posto o salto aggirato: stato se ne accorge.
iptables -w -I DOCKER-USER 1 -j RETURN
verifica "stato fallisce se le regole non sono in cima" fallisce "$FW" stato
bash "$FW" applica >/dev/null
verifica "applica le rimette in cima" contiene "$(regola 1)" 'firewall-dhgeo'
verifica "senza duplicati" test "$(nostre)" = 2
iptables -w -D DOCKER-USER -j RETURN   # il RETURN aggiunto sopra, ora sotto le nostre
iptables -w -I FORWARD 1 -j ACCEPT
verifica "stato fallisce se in FORWARD qualcosa viene prima del salto" fallisce "$FW" stato
iptables -w -D FORWARD 1

# 6. Cambio del proxy nello script versionato: le regole vecchie spariscono.
sed 's/^PROXY_IP=90.147.144.144/PROXY_IP=192.0.2.10/' "$FW" >"$TMP/fw-nuovo.sh"
bash "$TMP/fw-nuovo.sh" applica >/dev/null
verifica "il nuovo proxy è ammesso" contiene "$(regola 1)" '-s 192.0.2.10/32'
verifica "il vecchio proxy non c'è più" test "$(regole | grep -c '90.147.144.144' || true)" = 0
verifica "ancora due regole nostre" test "$(nostre)" = 2
bash "$FW" applica >/dev/null

# 7. Lock: applica aspetta che finisca un'altra operazione sulla catena.
flock "$FW_LOCK" sleep 2 &
sleep 0.3
inizio=$(date +%s)
bash "$FW" applica >/dev/null
fine=$(date +%s)
wait
verifica "applica aspetta il lock" test "$((fine - inizio))" -ge 1

# 8. Rimozione: via le nostre, il resto resta.
bash "$FW" rimuovi >/dev/null 2>&1
verifica "rimuovi toglie le regole nostre" test "$(nostre)" = 0
verifica "rimuovi lascia le altre" test "$(regole | wc -l)" = 1
verifica "stato fallisce senza regole" fallisce "$FW" stato

# 9. Comando sconosciuto.
verifica "comando sconosciuto: codice 2" bash -c "bash $FW boh >/dev/null 2>&1; test \$? -eq 2"

if [ "$fallite" -gt 0 ]; then
  echo "$fallite prove fallite" >&2
  exit 1
fi
echo "tutte le prove passate"
