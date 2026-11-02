# Migrazione di Lizmap dal server Faunalia a dhgeo

Fino a ottobre 2026 Faunalia ospitava Lizmap su `webparc.it` e Filebrowser su `webparc.it/files/`. Il 27/10/2026 ha consegnato l'export `unica-lizmap_export_20261027.tar.gz` (348 MB). Il nuovo indirizzo è `lizmap.dh.unica.it`, su dhgeo dietro il reverse proxy del Centro.

Il piano complessivo, che comprende Mergin Maps, la scelta della VM, il DNS e il proxy, sta nella cartella di lavoro `mergin-lizmap/PIANO-MIGRAZIONE.md`. Qui c'è la parte che riguarda Lizmap.

## Contenuto dell'export

| Percorso | Contenuto | Destinazione |
|---|---|---|
| `docker-compose.yml` | 5 servizi: lizmap, map, redis, web, filebrowser | versionato, con le correzioni sotto |
| `lizmap/etc/` | drop-in di Lizmap, `nginx.conf`, opzioni di QGIS | versionato, invariato |
| `lizmap/instances/` | `PARC webGIS/` (PARC_WEB.qgs, 24 GeoPackage, circa 360 MB) e `PARC_RC01/` (circa 205 MB) | dati, non versionati |
| `lizmap/var/` | configurazione scritta dall'interfaccia (`lizmapConfig.ini.php`), utenti (`jauth.db`, 4 utenti), log | stato, non versionato |
| `lizmap/www/` | asset di Lizmap 3.9.11 | generato, non versionato |
| `lizmap/qgis-plugins/` | `lizmap_server`, `wfsOutputExtension` | non versionato |
| `filebrowser_quantum/` | `config.yaml` e `filebrowser.sqlite` | config versionata, database no |

I progetti sono salvati con QGIS 3.44.7 e 3.44.8 e usano solo GeoPackage con percorsi relativi. Nessun PostGIS.

## Problemi trovati e correzioni

1. **Redis non raggiungibile.** Lizmap cerca la cache su `lizmap-redis`, ma il servizio si chiamava `redis` (container `unica-lizmap-redis`). Corretto con un alias di rete nel compose.
2. **Versioni mobili.** `3liz/lizmap-web-client:3.9` scaricherebbe oggi una 3.9.x successiva alla 3.9.11 installata. Bloccata a `3.9.11`; `nginx:alpine` bloccato a `nginx:1.27-alpine`.
3. **Porte.** Nel compose originale le porte erano commentate. Ora sono configurabili da `.env`: si parte da `127.0.0.1` e si passa all'IP della VM solo con il firewall attivo.
4. **Proprietari dei file.** L'archivio registra il proprietario `debian` (uid 1000). Si estrae con `--numeric-owner`: su dhgeo l'uid 1000 è l'utente `dhgeo`, lo stesso con cui girano i container.
5. **URL esterno di Filebrowser.** Da `https://webparc.it/files` a `https://lizmap.dh.unica.it/files`.
6. **PHP vulnerabile.** L'immagine 3.9.11 contiene PHP 8.3.29, esposto a PHP2Shell (CVE-2026-109618 e 109619, corretto dalla 8.3.36). Dopo il ripristino identico e il primo smoke test, il 1/11/2026 Lizmap è passato alla 3.9.12 (PHP 8.3.36) prima di essere pubblicato.

## Procedura

### Preparazione di dhgeo (una volta, comune a Mergin)

Docker 18.09 e docker-compose 1.23 non leggono i compose senza `version:`. Dal repository Docker già configurato:

```bash
sudo apt-get update
sudo apt-get install docker-ce=5:24.0.2-1~ubuntu.18.04~bionic docker-ce-cli=5:24.0.2-1~ubuntu.18.04~bionic \
  containerd.io docker-compose-plugin docker-buildx-plugin sqlite3
docker version --format '{{.Server.Version}}'   # 24.0.2
docker compose version
```

### Ripristino

```bash
cd ~ && git clone git@github.com-lizmap:Dh-unica/lizmap.dh.unica.it.git   # deploy key in sola lettura
cd ~/lizmap.dh.unica.it
cp .env.example .env
scripts/ripristina-export.sh ~/archivi-faunalia/unica-lizmap_export_20261027.tar.gz
docker compose pull
docker compose up -d
scripts/smoke-test.sh
```

Verifica dal proprio PC con un tunnel: `ssh -L 8084:127.0.0.1:8084 -L 8087:127.0.0.1:8087 dhgeo@90.147.144.148`, poi `http://localhost:8084` (login, pagina «Informazioni server» dell'amministrazione, mappa PARC WebGis) e `http://localhost:8087/files/`.

### Pubblicazione

1. **DNS**: `lizmap.dh.unica.it` è un CNAME di `dh.unica.it` (90.147.144.144), attivo dal 2/11/2026. Non c'è un wildcard DNS: ogni nome si chiede con un ticket a [helpdesk.unica.it](https://helpdesk.unica.it/servicePortal).
2. **Proxy**: virtual host `lizmap_dhunica.conf` in `proxy.dh.unica`, con il certificato wildcard `*.dh.unica.it`: `/` verso `90.147.144.148:8084`, `/files/` verso `90.147.144.148:8087`.
3. **Firewall e porte** (fase F): `sudo scripts/firewall-dhgeo.sh installa`, poi in `.env` `LIZMAP_WEB_PORT=90.147.144.148:8084` e `FILEBROWSER_PORT=90.147.144.148:8087` e `docker compose up -d`.

### Fase F: firewall

dhwp (90.147.144.144) e dhgeo stanno nella stessa sottorete, 90.147.144.128/26, e si parlano direttamente senza passare dal firewall perimetrale dell'ateneo. Verso Internet è aperta solo la 443 di dhwp, quindi non serve un ticket al settore reti: basta il firewall di dhgeo.

Docker scavalca `ufw`, attivo su dhgeo: il filtro sta nella catena `DOCKER-USER`. Docker riscrive la destinazione (DNAT) prima di quella catena, quindi indirizzo e porta si confrontano con quelli originali tramite `conntrack`. Le regole sono due, marcate con il commento `firewall-dhgeo`, e coprono 8084–8087, quindi anche la 8086 di Mergin:

```text
-A DOCKER-USER -s 90.147.144.144/32 -p tcp -m conntrack --ctorigdst 90.147.144.148 --ctorigdstport 8084:8087 --ctdir ORIGINAL -m comment --comment firewall-dhgeo -j RETURN
-A DOCKER-USER -p tcp -m conntrack --ctorigdst 90.147.144.148 --ctorigdstport 8084:8087 --ctdir ORIGINAL -m comment --comment firewall-dhgeo -j DROP
```

Non c'è una regola per la VPN: l'amministrazione passa dal tunnel SSH.

Le regole le carica [`scripts/firewall-dhgeo.sh`](../scripts/firewall-dhgeo.sh), in modo idempotente e con un lock. Indirizzi e porte sono costanti nello script: per cambiarli si modifica il repository e si rilancia `installa`. L'unità [`systemd/firewall-dhgeo.service`](../systemd/firewall-dhgeo.service) lo lancia prima di `docker.service`, e Docker ne dipende (`RequiredBy`): se le regole non si caricano Docker non parte, così le porte non vengono mai pubblicate senza filtro. Docker trova la catena pronta e accoda il suo `RETURN`. Non si usa `iptables-persistent`, che salverebbe e ripristinerebbe anche le catene gestite da Docker.

```bash
cd ~/lizmap.dh.unica.it && git pull
sudo scripts/firewall-dhgeo.sh installa   # /usr/local/sbin/firewall-dhgeo e unità systemd, abilitata e avviata
sudo firewall-dhgeo stato                 # codice 0: regole identiche alla configurazione, in cima, e FORWARD passa da DOCKER-USER
```

L'unità non va fermata né riavviata con `systemctl`, perché fermerebbe anche Docker. Per ricaricare le regole si usa `sudo firewall-dhgeo applica`, per toglierle `sudo firewall-dhgeo rimuovi`.

Solo dopo si aprono le porte: in `.env` `LIZMAP_WEB_PORT=90.147.144.148:8084` e `FILEBROWSER_PORT=90.147.144.148:8087`, nello stack Mergin `MERGIN_PORT=90.147.144.148:8086`, poi `docker compose up -d` nei due stack. Verifiche:

- da dhwp `curl -sI http://90.147.144.148:8084/` e `curl -s http://90.147.144.148:8086/ping` rispondono;
- da qualsiasi altra macchina, VPN compresa, le stesse richieste vanno in timeout.

Lo script si prova senza toccare il firewall vero, in un namespace di rete isolato: `tests/firewall-dhgeo.test.sh`. Gira anche in CI a ogni PR che lo modifica.

## Verifiche di accettazione

- [ ] senza login il repository `parcwebgis` non si vede; dopo il login si apre PARC WebGis
- [ ] layer, popup, ricerca, stampa ed export funzionano; le basemap si caricano
- [ ] nessun contenuto misto http/https nella console del browser
- [ ] Filebrowser: login, upload e download in `PARC_RC01`; il file caricato appartiene a 1000:1000
- [ ] `scripts/smoke-test.sh` tutto OK e nessun errore nei log
- [ ] `scripts/backup.sh` produce un archivio e il restore di prova funziona

## Rollback

Gli archivi originali restano in `/home/dhgeo/archivi-faunalia/` con le checksum (`SHA256SUMS`). Per ripartire: `docker compose down`, spostare `lizmap/{instances,var,www,lizmap-modules,qgis-authdb,qgis-plugins}` e `filebrowser_quantum/filebrowser.sqlite` in una cartella `*.failed-<data>` e rilanciare `scripts/ripristina-export.sh`.
