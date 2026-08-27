# SENTINEL Fornitori → modulo nativo NethServer 8

Guida e scaffold per trasformare il pacchetto Docker Compose "SENTINEL
Fornitori" (portale + PostgreSQL + MinIO + ClamAV + Caddy + backup) in un
modulo NS8 installabile e configurabile dalla GUI cluster-admin
(`add-module`, voce di menu, pagina di configurazione).

Il file `DOCKER-INSTALL.md` del progetto originale segnalava già questo
passaggio come "fase successiva": questo scaffold è il punto di partenza per
farlo, non un modulo pronto per la produzione. Vedi la sezione "Cosa manca
ancora / da verificare" in fondo.

## 1. Perché non basta "docker compose up" su NS8

NethServer 8 non usa Docker Compose. Ogni modulo è un pacchetto distribuito
come immagine container (Podman, rootless per default), con:

- **unit systemd utente** che avviano/fermano i container (al posto dei
  `services:` di Compose);
- un **agente** che espone "azioni" (install, configure-module,
  get-configuration, update, backup, restore, remove) invocabili da CLI o
  dalla cluster-admin;
- **Traefik** come reverse proxy HTTPS condiviso da tutto il cluster (al
  posto del Caddy dedicato incluso nel pacchetto Docker);
- un **file `ui/public/metadata.json`** che fa comparire il modulo con nome,
  icona e descrizione nel Software Center / cluster-admin.

Il vostro stack ha 5 servizi (app, postgres, minio, clamav, backup): la
soluzione più semplice è impacchettarli **tutti in un unico modulo NS8**
("sentinel-fornitori"), con più container gestiti dalle stesse unit
systemd del modulo — esattamente come fanno altri moduli NS8 con più
container (es. quelli che affiancano un Redis o un database al servizio
principale). Non è necessario spezzarli in moduli NS8 separati.

## 2. Struttura di questo scaffold

```
ns8-sentinel-fornitori/
├── build-images.sh                     # build + push immagine app su ghcr.io
├── imageroot/
│   ├── .images                         # immagini di terze parti da scaricare
│   ├── systemd/user/
│   │   ├── sentinel-app.service
│   │   ├── sentinel-postgres.service
│   │   ├── sentinel-minio.service
│   │   ├── sentinel-clamav.service
│   │   ├── sentinel-backup.service
│   │   └── sentinel-backup.timer
│   ├── actions/
│   │   ├── configure-module/10configure
│   │   └── get-configuration/10get
│   ├── update-module.d/10migrate
│   └── ui/public/metadata.json
└── docs/mappatura-compose-ns8.md
```

Manca ancora tutto ciò che il template ufficiale `ns8-kickstart` genera in
automatico (azioni base ereditate, test Robot Framework, workflow CI,
Containerfile del modulo, label `org.nethserver.*`). Il passo 3 spiega come
partire dal template ufficiale e innestarci questi file.

## 3. Procedura passo-passo (da eseguire voi, sul vostro ambiente)

### 3.1 Preparare il repository del modulo

1. Andate su <https://github.com/NethServer/ns8-kickstart>, "Use this
   template" → create un repo chiamato `ns8-sentinel-fornitori` (deve
   iniziare per `ns8-` e non finire con un numero).
2. Clonatelo in locale e copiateci sopra i file di questo scaffold
   (`imageroot/`, `build-images.sh`), **unendoli** con quanto già presente
   nel template (non sovrascrivete le azioni base del kickstart).
3. Nel Containerfile/label del modulo principale (generato dal kickstart),
   aggiungete il label `org.nethserver.images` con il contenuto del file
   `imageroot/.images` di questo scaffold (immagini Postgres/MinIO/mc/ClamAV):
   verranno scaricate in automatico dall'azione core `create-module` e
   trasformate in variabili d'ambiente (`POSTGRES_IMAGE`, `MINIO_IMAGE`, ...)
   usate dalle unit systemd incluse qui.
4. Aggiungete anche il label `org.nethserver.tcp-ports-demand=4` (una porta
   per app, postgres, minio, clamav — vedi `configure-module/10configure`,
   che chiama `agent.allocate_ports(4, "tcp")`).

### 3.2 Portare dentro il codice dell'app

- Il Dockerfile dell'applicazione Next.js/vinext (quello che compila il
  portale, non quello di backup incluso in questo progetto) va copiato/
  referenziato come sorgente per `build-images.sh` (variabile `APP_SRC_DIR`).
- Le migrazioni (`docker/migrate.mjs`) restano nell'immagine app: vengono
  invocate da `imageroot/update-module.d/10migrate` e vanno richiamate anche
  in `configure-module` al primo avvio (da aggiungere: qui è stato lasciato
  solo l'avvio dei servizi, la prima migrazione va eseguita esplicitamente
  la prima volta, con lo stesso comando usato in `10migrate`).

### 3.3 Sostituire Caddy con Traefik + Let's Encrypt di NS8

Questa è la parte più delicata e **non è ancora implementata** in questo
scaffold (vedi TODO in `configure-module/10configure`). In sintesi, sui
moduli web NS8:

- il container applicativo si pubblica **solo su loopback**
  (`127.0.0.1:${TCP_PORT}`, come già fatto in `sentinel-app.service`);
- il Traefik del cluster instrada il traffico pubblico verso quella porta
  in base al dominio configurato;
- il certificato TLS per il dominio è gestito dal modulo `letsencrypt` del
  cluster, non da Caddy.

Il modo esatto per registrare la route (evento Redis, azione dedicata,
opzioni di dominio/percorso) va copiato da un modulo NS8 reale con interfaccia
web, ad esempio i repository pubblici `ns8-nextcloud` o `ns8-webtop` su
GitHub — guardate come i loro `configure-module` registrano il dominio e
come i loro `.metadata`/label dichiarano la necessità del proxy. Non
inventate qui la sintassi senza verificarla sul modulo di riferimento e
sulla pagina "Network" del developer manual (<https://nethserver.github.io/ns8-core/modules/network/>).

### 3.4 Personalizzare `metadata.json`

Aprite `imageroot/ui/public/metadata.json` e sostituite `<tuo-org>` con
l'organizzazione GitHub/registro reale, aggiungete un logo in
`imageroot/ui/src/assets/module_default_logo.png` (dimensioni secondo le
convenzioni del kickstart).

### 3.5 Build e pubblicazione delle immagini

```sh
export IMAGE_REPOBASE=ghcr.io/<tuo-org>
export APP_SRC_DIR=/percorso/al/repo/app-sentinel   # il Dockerfile Next.js
./build-images.sh
```

Verificate che l'immagine sia pubblica (o che il server NethServer8 abbia le
credenziali per accedere al registro privato) prima di installarla.

### 3.6 Installazione sul server NethServer8 (da voi, via SSH)

Sul nodo leader del cluster NS8:

```sh
add-module ghcr.io/<tuo-org>/sentinel-fornitori:latest 1
```

Poi, dalla GUI cluster-admin (`https://<server>/cluster-admin`), aprite il
modulo appena installato e completate la configurazione (dominio, email
amministratore, ecc.) — questo richiama l'azione `configure-module` che
avete personalizzato al punto 3.1-3.3. L'applicazione sarà raggiungibile
all'indirizzo configurato una volta collegata a Traefik.

### 3.7 Verifica, backup, aggiornamento

- Verifica: `curl -fsS https://<dominio>/api/health` (lo stesso endpoint già
  usato nel pacchetto Docker originale).
- Backup: la piattaforma NS8 ha un meccanismo di backup/restore a livello di
  modulo basato sui volumi Podman: prima di reinventare uno script come
  `docker/backup.sh`, verificate sul developer manual
  (sezione "Backup and Restore") se potete appoggiarvi al meccanismo comune
  invece di gestirlo con la unit `sentinel-backup.timer` inclusa qui (che è
  un fallback funzionante ma più manuale, modellato sul vecchio
  `docker/backup.sh`).
- Aggiornamento: `update-module <module_id> ghcr.io/<tuo-org>/sentinel-fornitori:<nuova-versione>`
  esegue in automatico gli script in `imageroot/update-module.d/` (qui:
  `10migrate`).

## 4. Cosa manca ancora / da verificare prima della produzione

Questo scaffold è stato scritto a tavolino confrontando la documentazione
ufficiale NS8 (developer manual su nethserver.github.io/ns8-core e il
template ns8-kickstart) con lo stack Docker Compose esistente, **senza un
server NS8 reale su cui testarlo**. Prima di installarlo su un cliente,
verificate/completate almeno:

1. **Registrazione route Traefik + certificato Let's Encrypt** (§3.3): è
   l'unico punto davvero non scritto, copiate la logica da un modulo reale.
2. **Container `minio-init`** (creazione bucket con versioning/object lock):
   nello scaffold è solo accennato come `ExecStartPost=ensure-minio-bucket`
   in `sentinel-minio.service`; lo script `runagent ensure-minio-bucket` va
   scritto (equivalente del servizio `minio-init` del `compose.yml`
   originale, che lancia `mc mb --with-lock` e `mc version enable`).
3. **Primo bootstrap admin**: `docker/bootstrap-admin.mjs` va richiamato la
   prima volta che il modulo viene configurato (in `configure-module`, dopo
   il primo avvio di Postgres), non solo nelle migrazioni successive.
4. **Azioni backup-module / restore-module** esplicite, se decidete di non
   usare il meccanismo generico di NS8: al momento c'è solo un timer che
   richiama `runagent run-backup`, ma lo step `run-backup` stesso (dump
   Postgres + sync bucket MinIO, equivalente di `docker/backup.sh`) va
   scritto.
5. **Test end-to-end** su un cluster NS8 reale (installazione, riavvio nodo,
   backup/restore, update, rimozione) prima di consegnare al cliente.

## 5. Riferimenti utili

- Developer manual NS8: <https://nethserver.github.io/ns8-core/>
- Tutorial nuovo modulo: <https://nethserver.github.io/ns8-core/modules/new_module/>
- Template ufficiale: <https://github.com/NethServer/ns8-kickstart>
- Esempio reale con unit systemd Podman: <https://github.com/NethServer/ns8-dokuwiki>
