# Prossimi passi

Stato al 1/11/2026.

## Fatto

- [x] Analisi dell'export Faunalia del 27/10/2026 e correzioni al compose (docs/MIGRAZIONE.md)
- [x] Scelta della VM: dhgeo, insieme a Mergin Maps
- [x] Archivi copiati su dhgeo in `~/archivi-faunalia/`, checksum verificate

## Da fare

- [ ] Aggiornare Docker su dhgeo a 24.0.2 con il plugin compose v2
- [ ] Clonare il repository su dhgeo con una deploy key in sola lettura
- [ ] Ripristino dall'export e `scripts/smoke-test.sh`
- [ ] Verifica via tunnel SSH: login, mappa PARC WebGis, Filebrowser
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
