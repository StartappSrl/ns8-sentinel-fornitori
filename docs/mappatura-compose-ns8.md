# Mappatura compose.yml → modulo NS8

| Servizio Compose | Nel modulo NS8 | Note |
|---|---|---|
| `app` | `sentinel-app.service` | pubblicato solo su `127.0.0.1:${TCP_PORT}`, esposto da Traefik (da implementare, §3.3 del README) invece che da `proxy`/Caddy |
| `postgres` | `sentinel-postgres.service` | immagine scaricata via `org.nethserver.images`; volume Podman `sentinel-postgres-data` al posto del volume Compose `postgres-data` |
| `minio` | `sentinel-minio.service` | volume `sentinel-minio-data`; healthcheck Compose → gestito da `ExecStartPost=wait`/`ensure-minio-bucket` nella unit |
| `minio-init` | script `runagent ensure-minio-bucket` (da scrivere) | eseguito come `ExecStartPost` di `sentinel-minio.service` invece che come container Compose separato |
| `clamav` | `sentinel-clamav.service` | volume `sentinel-clamav-data` |
| `proxy` (Caddy) | **rimosso** | sostituito dal Traefik condiviso del cluster NS8 + modulo `letsencrypt` per i certificati |
| `backup` (Dockerfile dedicato + `backup.sh`) | `sentinel-backup.timer` + `sentinel-backup.service` (`runagent run-backup`, da scrivere) | oppure, se possibile, il meccanismo di backup/restore generico di NS8 a livello di modulo (da verificare, vedi README §4) |
| `docker/install.sh` | `configure-module` (azione del modulo) | genera segreti e persiste variabili invece di scrivere un file `.env` |
| `docker/update.sh` / `rollback.sh` | `update-module` (azione core) + `imageroot/update-module.d/10migrate` | rollback gestito dalla CLI NS8 (`update-module --force <image-precedente>`), non da uno script custom |
| `.env` / `.env.docker.example` | variabili persistite dall'agente (`agent.set_env`) in `%S/state/environment` | non più un file `.env` manuale per installazione |
| `INSTALLATION_ID`, `CUSTOMER_NAME`, ecc. | stessi nomi, passati come parametri di `configure-module` invece che argomenti posizionali di `install.sh` | |
