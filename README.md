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
│   ├── etc/state-include.conf          # cosa include il backup nativo NS8
│   ├── systemd/user/
│   │   ├── sentinel-app.service
│   │   ├── sentinel-postgres.service
│   │   ├── sentinel-minio.service
│   │   └── sentinel-clamav.service
│   ├── actions/
│   │   ├── configure-module/10configure
│   │   └── get-configuration/10get
│   ├── update-module.d/10migrate
│   └── ui/public/metadata.json
└── docs/mappatura-compose-ns8.md
```

Non c'è più una unit/timer di backup dedicata: il backup usa il meccanismo
nativo di NS8 (vedi §3.3bis).

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
- Le migrazioni (`docker/migrate.mjs`) e il bootstrap admin
  (`docker/bootstrap-admin.mjs`) restano nell'immagine app: vengono
  invocati sia da `configure-module/10configure` (primo avvio) sia da
  `imageroot/update-module.d/10migrate` (aggiornamenti). **Verificate il
  nome esatto** della variabile d'ambiente che contiene l'immagine
  principale del modulo (nello scaffold è dato per scontato `APP_IMAGE`,
  ma l'azione core `create-module` potrebbe usare un nome diverso, es.
  `IMAGE_URL` — correggetelo in `10configure` e `10migrate` di conseguenza).

### 3.3 Sostituire Caddy con Traefik + Let's Encrypt di NS8

Il container applicativo si pubblica **solo su loopback**
(`127.0.0.1:${TCP_PORT}`, già impostato in `sentinel-app.service`).
`configure-module/10configure` registra la route pubblica chiamando
`agent.set_route()`, secondo l'API documentata in
<https://nethserver.github.io/ns8-core/modules/certificates/>:

```python
agent.set_route({
    "instance": os.environ["MODULE_ID"],
    "url": f"http://127.0.0.1:{tcp_port}",
    "host": domain,
    "lets_encrypt": True,
    "http2https": True,
})
```

Questo dice a Traefik di instradare `domain` verso l'app e richiede/rinnova
il certificato via Let's Encrypt: non serve più Caddy né gestire i
certificati a mano. Va comunque collaudato su un cluster reale — in
particolare cosa succede se `set_route` fallisce (validazione remota Let's
Encrypt che non va a buon fine: per il comportamento di default, che aborta
il processo, vs `error_passthrough=False` per gestirlo voi, vedi la pagina
sopra).

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
- Backup: **non serve più uno script custom.** Il core NS8 esegue backup
  programmati basati su Restic per l'intero modulo; `imageroot/etc/state-include.conf`
  dice cosa includere (qui: i volumi Postgres e MinIO). Il ripristino è
  `api-cli run cluster/restore-module --data '{"node":1,"repository":"<UUID>","path":"<module/path>","snapshot":""}'`.
  Il volume ClamAV (solo definizioni virus) è escluso di proposito.
- Aggiornamento: `update-module <module_id> ghcr.io/<tuo-org>/sentinel-fornitori:<nuova-versione>`
  esegue in automatico gli script in `imageroot/update-module.d/` (qui:
  `10migrate`).

## 4. Cosa manca ancora / da verificare prima della produzione

Questo scaffold è stato scritto a tavolino confrontando la documentazione
ufficiale NS8 (developer manual su nethserver.github.io/ns8-core e il
template ns8-kickstart) con lo stack Docker Compose esistente, **senza un
server NS8 reale su cui testarlo**. Rispetto alla prima versione, la
registrazione Traefik/Let's Encrypt (`agent.set_route`), la creazione del
bucket MinIO e il backup sono stati risolti con API/meccanismi confermati
dalla documentazione ufficiale (non più TODO generici). Restano da
verificare/completare:

1. **Nome della variabile d'ambiente dell'immagine principale** (`APP_IMAGE`
   nello scaffold): controllate cosa imposta davvero l'azione core
   `create-module` per l'immagine dichiarata nel Containerfile/label del
   modulo, e allineate `configure-module/10configure` e
   `update-module.d/10migrate`.
2. **Comportamento di `agent.set_route` in caso di errore Let's Encrypt**
   (per default aborta il processo di configurazione): decidete se va bene
   così o se preferite gestirlo con `error_passthrough=False`.
3. **Wait-loop di readiness** in `sentinel-postgres.service` e
   `sentinel-minio.service`: gli `ExecStartPost` inclusi sono script bash
   diretti (non azioni NS8), semplici ma da collaudare con carichi/tempi di
   avvio reali (i timeout di 30s potrebbero essere insufficienti in
   ambienti lenti).
4. **Test end-to-end** su un cluster NS8 reale (installazione, riavvio nodo,
   backup/restore, update, rimozione) prima di consegnare al cliente.

## 5. Riferimenti utili

- Developer manual NS8: <https://nethserver.github.io/ns8-core/>
- Tutorial nuovo modulo: <https://nethserver.github.io/ns8-core/modules/new_module/>
- Template ufficiale: <https://github.com/NethServer/ns8-kickstart>
- Esempio reale con unit systemd Podman: <https://github.com/NethServer/ns8-dokuwiki>
