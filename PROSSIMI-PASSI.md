# Prossimi passi

Stato al 1/11/2026. Lo stack gira su dhgeo con le porte solo su 127.0.0.1, in attesa di DNS e proxy.

## Fatto

- [x] Analisi dell'export Faunalia del 27/10/2026 e correzioni al compose (docs/MIGRAZIONE.md)
- [x] Scelta della VM: dhgeo, insieme a Mergin Maps
- [x] Archivi copiati su dhgeo in `~/archivi-faunalia/`, checksum verificate
- [x] Docker su dhgeo aggiornato da 18.09 a 24.0.2 con il plugin compose 2.18.1; limite predefinito ai log in `/etc/docker/daemon.json`
- [x] Repository clonato su dhgeo con deploy key in sola lettura (`~/.ssh/deploy_lizmap`, alias `github.com-lizmap`)
- [x] Ripristino dall'export e avvio: `scripts/smoke-test.sh` tutto OK (GetCapabilities di PARC_WEB con 22 layer)
- [x] Accesso riservato verificato: da anonimo il WMS di `parcwebgis` dà eccezione e la mappa rimanda al login

## Da fare

- [ ] Verifica via tunnel SSH con un account amministratore: pagina «Informazioni server», mappa PARC WebGis, Filebrowser (le credenziali sono da chiedere a Faunalia)
- [ ] Ticket DNS per `lizmap.dh.unica.it` → 90.147.144.144
- [ ] Firewall `DOCKER-USER` e porte sull'IP di dhgeo
- [ ] Virtual host nel proxy (PR su `proxy.dh.unica`, da unire solo a DNS attivo)
- [ ] Verifiche di accettazione con Antonio M. Corda
- [ ] Backup giornaliero in cron e copia fuori dalla VM
- [ ] Tag `prod-<data>` sul primo rilascio

## Dopo la messa in servizio

- [ ] Redis 5 → 7 (solo cache, rischio minimo)
- [ ] Ultima Lizmap 3.9.x
- [ ] Redirect da `webparc.it` a `lizmap.dh.unica.it`, se il DNS di `webparc.it` è disponibile
