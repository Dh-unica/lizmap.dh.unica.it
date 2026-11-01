# lizmap.dh.unica.it: istruzioni per Claude Code

Configurazione di produzione e strumenti di manutenzione di lizmap.dh.unica.it, il WebGIS Lizmap del Centro DH UNICA (primo progetto: PARC WebGis).

**All'inizio di ogni sessione leggi [PROSSIMI-PASSI.md](PROSSIMI-PASSI.md)**: contiene lo stato attuale e cosa manca. A fine lavoro aggiornalo.

## Contesto

- Produzione su **dhgeo** `90.147.144.148`, utente `dhgeo` (uid 1000, lo stesso dei container). SSH: `ssh -o IdentitiesOnly=yes -i ~/.ssh/id_rsa dhgeo@90.147.144.148`. La password per sudo non sta nel repository.
- Stack in `/home/dhgeo/lizmap.dh.unica.it` (clone di questo repository più le cartelle dati non versionate), Docker Compose v2.
- Sulla stessa VM gira Mergin Maps (`/home/dhgeo/mergin.dh.unica.it`, repository `Dh-unica/mergin.dh.unica.it`).
- Pubblicazione tramite il reverse proxy di dhwp (`proxy.dh.unica`, branch `master`: **un push su master va in produzione via cron entro un minuto**).
- Migrazione da Faunalia: [docs/MIGRAZIONE.md](docs/MIGRAZIONE.md). Archivi originali in `/home/dhgeo/archivi-faunalia/`.

## Regole

- **Nessuna modifica alla produzione senza un ok esplicito.** Le letture vanno bene.
- Prima di cambiare immagini o configurazione: `scripts/backup.sh`, poi `scripts/smoke-test.sh` dopo la modifica.
- Comandi vietati: `docker compose down -v`, `docker system prune`, `docker volume prune`, `rm` su `lizmap/instances` o `lizmap/var`, estrazioni di archivi con `tar` senza `--numeric-owner`.
- I file in `lizmap/var/lizmap-config/` li scrive l'interfaccia di amministrazione di Lizmap: non si versionano e non si sovrascrivono a mano senza backup.
- I progetti QGIS devono restare compatibili con QGIS Server 3.44: non aggiornare `qgis-map-server` di versione minore senza sentire chi cura i progetti.
- Le porte 8084 e 8087 si aprono verso l'esterno solo con le regole `DOCKER-USER` attive (docs/MIGRAZIONE.md, fase F): Docker scavalca `ufw`.
- Git: mai commit su `main`. Un branch per attività (`feat/`, `fix/`, `docs/`, `chore/`, `refactor/`), commit in italiano, poi PR, merge e cancellazione del branch. `main` è protetto su GitHub: si arriva solo da PR con il check «regole» verde. Tag `prod-<data>` per ogni rilascio in produzione. Hook locale: `git config core.hooksPath .githooks`.
- Mai segreti né dati nel repo: `.env`, database SQLite, progetti e dump restano fuori (vedi `.gitignore`).
- Su dhgeo il repository si aggiorna solo con `git pull` (deploy key in sola lettura): lì non si fanno commit.
