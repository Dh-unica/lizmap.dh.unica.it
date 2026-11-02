# Prossimi passi

Stato al 2/11/2026. **In servizio su https://lizmap.dh.unica.it** dal 2/11/2026, 14:47 UTC, dietro il proxy di dhwp; porte 8084 e 8087 sull'IP di dhgeo, filtrate dal firewall.

## Fatto

- [x] Analisi dell'export Faunalia del 27/10/2026 e correzioni al compose (docs/MIGRAZIONE.md)
- [x] Scelta della VM: dhgeo, insieme a Mergin Maps
- [x] Archivi copiati su dhgeo in `~/archivi-faunalia/`, checksum verificate
- [x] Docker su dhgeo aggiornato da 18.09 a 24.0.2 con il plugin compose 2.18.1; limite predefinito ai log in `/etc/docker/daemon.json`
- [x] Repository clonato su dhgeo con deploy key in sola lettura (`~/.ssh/deploy_lizmap`, alias `github.com-lizmap`)
- [x] Ripristino dall'export e avvio: `scripts/smoke-test.sh` tutto OK (GetCapabilities di PARC_WEB con 22 layer)
- [x] Accesso riservato verificato: da anonimo il WMS di `parcwebgis` dà eccezione e la mappa rimanda al login
- [x] Backup provato: `scripts/backup.sh` (341 MB, SQLite coerenti, 4 utenti)
- [x] Lizmap 3.9.11 → 3.9.12 per PHP2Shell (PHP 8.3.29 → 8.3.36)
- [x] DNS: `lizmap.dh.unica.it` è un CNAME di `dh.unica.it` (90.147.144.144), attivo dal 2/11/2026
- [x] Credenziali amministrative di Lizmap e Filebrowser ricevute da Faunalia il 2/11/2026 (fuori dal repository)
- [x] Firewall: `scripts/firewall-dhgeo.sh` e `systemd/firewall-dhgeo.service`, prove passate anche su dhgeo (iptables 1.6.1, in un namespace); Docker dipende dall'unità
- [x] Firewall installato su dhgeo (unità attiva e abilitata) e porte sull'IP della VM; `.env` precedenti in `~/env-backup/`. Da dhwp le porte rispondono (200, `/ping` online), dalla VPN vanno in timeout; smoke test tutto OK
- [x] PR #25 di `proxy.dh.unica` unita (f9238e0), deploy automatico e `nginx -t` OK. Da Internet: HTTPS valido (`*.dh.unica.it`, scade l'11/02/2027), redirect da HTTP, home e `/files/` a 200, nessun URL `http://` assoluto nella home

## Da fare

- [ ] Login con un account amministratore su https://lizmap.dh.unica.it: pagina «Informazioni server», mappa PARC WebGis senza contenuti misti, Filebrowser con upload di prova; poi reset delle password
- [ ] Verifiche di accettazione con Antonio M. Corda
- [ ] Backup giornaliero in cron e copia fuori dalla VM
- [ ] Avvisare Faunalia che può spegnere il vecchio server (acceso fino a inizio dicembre 2026), dopo le verifiche di accettazione

## Dopo la messa in servizio

- [ ] Redis 5 → 7 (solo cache, rischio minimo)
- [ ] Redirect da `webparc.it` a `lizmap.dh.unica.it`, se il DNS di `webparc.it` è disponibile
