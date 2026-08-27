# Mappatura compose.yml → modulo NS8

| Servizio Compose | Nel modulo NS8 | Note |
|---|---|---|
| `app` | `sentinel-app.service` | pubblicato solo su `127.0.0.1:${TCP_PORT}`; route pubblica registrata da `configure-module` con `agent.set_route()` invece che da `proxy`/Caddy |
| `postgres` | `sentinel-postgres.service` | immagine scaricata via `org.nethserver.images`; volume Podman `sentinel-postgres-data` al posto del volume Compose `postgres-data`; readiness via `ExecStartPost` con `pg_isready` |
| `minio` | `sentinel-minio.service` | volume `sentinel-minio-data`; readiness + creazione bucket in `ExecStartPost` (chiamate dirette a `mc` via podman, stesso client del vecchio `minio-init`) |
| `minio-init` | inglobato nell'`ExecStartPost` di `sentinel-minio.service` | non più un container/servizio separato |
| `clamav` | `sentinel-clamav.service` | volume `sentinel-clamav-data` |
| `proxy` (Caddy) | **rimosso** | sostituito dal Traefik condiviso del cluster NS8, instradato via `agent.set_route()`; certificati gestiti da Let's Encrypt lato NS8 |
| `backup` (Dockerfile dedicato + `backup.sh`) | **rimosso** | sostituito dal backup nativo NS8 (Restic) sui percorsi dichiarati in `imageroot/etc/state-include.conf` |
| `docker/install.sh` | `configure-module` (azione del modulo) | genera segreti e persiste variabili invece di scrivere un file `.env` |
| `docker/update.sh` / `rollback.sh` | `update-module` (azione core) + `imageroot/update-module.d/10migrate` | rollback gestito dalla CLI NS8 (`update-module --force <image-precedente>`), non da uno script custom |
| `.env` / `.env.docker.example` | variabili persistite dall'agente (`agent.set_env`) in `%S/state/environment` | non più un file `.env` manuale per installazione |
| `INSTALLATION_ID`, `CUSTOMER_NAME`, ecc. | stessi nomi, passati come parametri di `configure-module` invece che argomenti posizionali di `install.sh` | |
