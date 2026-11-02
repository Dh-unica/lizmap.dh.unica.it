#!/usr/bin/env bash
# Firewall di dhgeo per le porte che Docker pubblica sull'IP della VM: 8084 Lizmap, 8086 Mergin,
# 8087 Filebrowser. Passano solo le connessioni dal reverse proxy dhwp, le altre si scartano.
#
# Uso (sulla VM, dalla radice del repository):
#   sudo scripts/firewall-dhgeo.sh installa   # copia script e unità systemd, abilita, applica
#   sudo firewall-dhgeo applica               # (ri)carica le regole, idempotente
#   sudo firewall-dhgeo stato                 # codice 0 solo se il filtro è attivo davvero
#   sudo firewall-dhgeo rimuovi               # toglie le regole: le porte restano aperte a tutti
#
# Docker scavalca ufw, quindi il filtro sta nella catena DOCKER-USER, che Docker attraversa prima
# delle sue. Docker riscrive la destinazione (DNAT) prima di quella catena: indirizzo e porta si
# confrontano con quelli originali tramite conntrack. L'unità systemd gira prima di docker.service
# e Docker ne dipende: al boot i container non pubblicano mai le porte senza filtro. Docker trova
# la catena pronta, non la svuota e accoda il suo RETURN.
set -euo pipefail

# Configurazione versionata: per cambiarla si modifica qui e si rilancia «installa».
PROXY_IP=90.147.144.144   # dhwp
VM_IP=90.147.144.148      # dhgeo
PORTE=8084:8087
CATENA=DOCKER-USER
ETICHETTA=firewall-dhgeo
LOCK=${FW_LOCK:-/run/lock/firewall-dhgeo.lock}   # FW_LOCK serve solo alle prove

ipt() { iptables -w "$@"; }

filtro=(-p tcp -m conntrack --ctorigdst "$VM_IP" --ctorigdstport "$PORTE" --ctdir ORIGINAL
  -m comment --comment "$ETICHETTA")
ammesso=(-s "$PROXY_IP" "${filtro[@]}" -j RETURN)
scartato=("${filtro[@]}" -j DROP)

# applica e rimuovi leggono le posizioni e poi cancellano per numero: non devono sovrapporsi.
blocca() {
  exec 9>"$LOCK"
  flock -w 60 9 || {
    echo "Un'altra operazione su $CATENA è in corso da più di 60 secondi." >&2
    exit 1
  }
}

# Posizioni delle regole con l'etichetta, in ordine crescente (1 = in cima alla catena).
nostre() {
  ipt -S "$CATENA" | grep '^-A ' | grep -n -- "$ETICHETTA" | cut -d: -f1 || true
}

# Le due regole attese, identiche alla configurazione, in posizione 1 e 2, e nessun'altra con
# l'etichetta. È il controllo di applica, che al boot gira prima che Docker crei il salto.
regole_ok() {
  local prima
  prima=$(ipt -S "$CATENA" | grep '^-A ' | sed -n 1p || true)
  [ "$(nostre | tr '\n' ' ')" = "1 2 " ] &&
    [[ $prima == *"-j RETURN"* ]] &&
    ipt -C "$CATENA" "${ammesso[@]}" 2>/dev/null &&
    ipt -C "$CATENA" "${scartato[@]}" 2>/dev/null
}

applica() {
  blocca
  ipt -n -L "$CATENA" >/dev/null 2>&1 || ipt -N "$CATENA"
  # Prima le nuove in cima, poi via le vecchie: le porte non restano mai scoperte.
  ipt -I "$CATENA" 1 "${ammesso[@]}"
  ipt -I "$CATENA" 2 "${scartato[@]}"
  for n in $(nostre | tail -n +3 | sort -rn); do
    ipt -D "$CATENA" "$n"
  done
  ipt -S "$CATENA"
  regole_ok || {
    echo "Regole $ETICHETTA non corrette dopo applica: controllare $CATENA." >&2
    return 1
  }
}

rimuovi() {
  blocca
  for n in $(nostre | sort -rn); do
    ipt -D "$CATENA" "$n"
  done
  echo "Regole $ETICHETTA rimosse: le porte $PORTE sono raggiungibili da chiunque." >&2
}

# Il filtro è attivo solo se le regole sono giuste e FORWARD passa per primo da DOCKER-USER.
stato() {
  ipt -S "$CATENA" || return 1
  if ! regole_ok; then
    echo "Regole $ETICHETTA assenti, diverse dalla configurazione o non in cima a $CATENA: lanciare 'applica'." >&2
    return 1
  fi
  local primo
  primo=$(ipt -S FORWARD | grep '^-A ' | sed -n 1p || true)
  if [ "$primo" != "-A FORWARD -j $CATENA" ]; then
    echo "FORWARD non passa per primo da $CATENA (Docker è avviato?): il filtro non è attivo." >&2
    return 1
  fi
}

installa() {
  local radice
  radice=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
  install -m 0755 "$radice/scripts/firewall-dhgeo.sh" /usr/local/sbin/firewall-dhgeo
  install -m 0644 "$radice/systemd/firewall-dhgeo.service" /etc/systemd/system/firewall-dhgeo.service
  systemctl daemon-reload
  systemctl enable firewall-dhgeo.service
  # start e non restart: Docker dipende dall'unità e un restart fermerebbe anche i container.
  # Se l'unità è già attiva (reinstallazione) start non fa nulla: le regole si applicano qui.
  systemctl start firewall-dhgeo.service
  applica
  stato
}

case "${1:-}" in
  applica | rimuovi | stato | installa) ;;
  *)
    echo "Uso: $0 installa|applica|stato|rimuovi" >&2
    exit 2
    ;;
esac
if [ "$(id -u)" -ne 0 ]; then
  echo "Serve root: sudo $0 $1" >&2
  exit 1
fi
"$1"
