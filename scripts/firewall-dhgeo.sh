#!/usr/bin/env bash
# Firewall di dhgeo per le porte che Docker pubblica sull'IP della VM: 8084 Lizmap, 8086 Mergin,
# 8087 Filebrowser. Passano solo le connessioni dal reverse proxy dhwp, le altre si scartano.
#
# Uso (sulla VM, dalla radice del repository):
#   sudo scripts/firewall-dhgeo.sh installa   # copia script e unità systemd, abilita, applica
#   sudo scripts/firewall-dhgeo.sh applica    # (ri)carica le regole, idempotente
#   sudo scripts/firewall-dhgeo.sh stato      # mostra DOCKER-USER; codice 1 se le regole mancano
#   sudo scripts/firewall-dhgeo.sh rimuovi    # toglie le regole: le porte restano aperte a tutti
#
# Docker scavalca ufw, quindi il filtro sta nella catena DOCKER-USER, che Docker attraversa prima
# delle sue. Docker riscrive la destinazione (DNAT) prima di quella catena: indirizzo e porta si
# confrontano con quelli originali tramite conntrack. L'unità systemd gira prima di docker.service,
# così al boot i container non pubblicano mai le porte senza filtro; Docker trova la catena pronta,
# non la svuota e accoda il suo RETURN.
set -euo pipefail

PROXY_IP=${PROXY_IP:-90.147.144.144}   # dhwp
VM_IP=${VM_IP:-90.147.144.148}         # dhgeo
PORTE=${PORTE:-8084:8087}
CATENA=DOCKER-USER
ETICHETTA=firewall-dhgeo

ipt() { iptables -w "$@"; }

filtro=(-p tcp -m conntrack --ctorigdst "$VM_IP" --ctorigdstport "$PORTE" --ctdir ORIGINAL
  -m comment --comment "$ETICHETTA")

# Posizioni delle regole con l'etichetta, in ordine crescente (1 = in cima alla catena).
nostre() {
  ipt -S "$CATENA" | grep '^-A ' | grep -n -- "$ETICHETTA" | cut -d: -f1 || true
}

applica() {
  ipt -n -L "$CATENA" >/dev/null 2>&1 || ipt -N "$CATENA"
  # Prima le nuove in cima, poi via le vecchie: le porte non restano mai scoperte.
  ipt -I "$CATENA" 1 -s "$PROXY_IP" "${filtro[@]}" -j RETURN
  ipt -I "$CATENA" 2 "${filtro[@]}" -j DROP
  for n in $(nostre | tail -n +3 | sort -rn); do
    ipt -D "$CATENA" "$n"
  done
  stato
}

rimuovi() {
  for n in $(nostre | sort -rn); do
    ipt -D "$CATENA" "$n"
  done
  echo "Regole $ETICHETTA rimosse: le porte $PORTE sono raggiungibili da chiunque." >&2
}

stato() {
  ipt -S "$CATENA"
  local prima seconda
  prima=$(ipt -S "$CATENA" | grep '^-A ' | sed -n 1p)
  seconda=$(ipt -S "$CATENA" | grep '^-A ' | sed -n 2p)
  if [ "$(nostre | tr '\n' ' ')" != "1 2 " ] ||
    ! grep -q -- '-j RETURN' <<<"$prima" || ! grep -q -- '-j DROP' <<<"$seconda"; then
    echo "Regole $ETICHETTA assenti o non in cima a $CATENA: lanciare 'applica'." >&2
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
  systemctl restart firewall-dhgeo.service
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
