#!/bin/bash
#
# Costruisce e pubblica l'immagine "MODULO": un'immagine scratch (vuota,
# mai eseguita) che contiene solo imageroot/ + ui/dist e i label
# org.nethserver.*, seguendo il meccanismo reale usato dal template
# ns8-kickstart (build-images.sh originale, basato su buildah, non su un
# Containerfile "normale" - vedi
# https://github.com/NethServer/ns8-kickstart/blob/main/build-images.sh).
# È QUESTA l'immagine che si passa ad `add-module`/`update-module`.
#
# L'immagine APPLICATIVA (Next.js) NON viene più costruita/pubblicata da
# questo script (vedi guida §3.17/3.18): è pubblicata da una pipeline
# esterna a questo progetto (repository GitHub
# startappate/sentinel-fornitori-nis2, privato), con una cadenza di
# rilascio indipendente da quella del modulo NS8. Il modulo la risolve da
# solo: alla primissima configurazione di un'istanza,
# configure-module/10configure interroga ghcr.io per l'ultimo tag semver
# pubblicato; gli aggiornamenti successivi passano dai pulsanti "Verifica
# aggiornamento"/"Aggiorna ora" (azioni check-update/update-now), non più
# da qui. Per questo l'immagine app NON è (più) elencata nel label
# org.nethserver.images: se lo fosse, NS8 deriverebbe il nome della
# variabile d'ambiente dall'ultimo segmento del suo path reale, un nome
# che non controlliamo (vedi commento in configure-module/10configure).
#
# VERSIONING di QUESTA immagine (modulo, non app - vedi anche guida
# §3.15): il tag di pubblicazione di default è il contenuto del file
# VERSION alla radice del repo, non "latest". "podman run
# <immagine>:latest" non riscarica un'immagine gia' presente in cache
# locale con lo stesso tag, anche se sul registro il contenuto e'
# cambiato (causa reale, vista piu' volte in collaudo, di container/moduli
# bloccati su una build vecchia nonostante push ripetuti) - un tag
# versionato e immutabile elimina l'ambiguita' alla radice: ogni release
# ha un nome diverso, niente più bisogno di indovinare se la cache locale
# di un nodo o di un utente di sistema e' aggiornata o no.
#
# Per rilasciare una nuova versione DEL MODULO: aggiornate il file
# VERSION, fate commit, poi lanciate questo script senza altro. "latest"
# viene comunque pubblicato in aggiunta, come comodo alias per i test
# rapidi, MA add-module/update-module in produzione vanno sempre puntati
# al tag versionato esplicito, mai a "latest" (che può cambiare sotto i
# piedi di un cliente senza che ve ne accorgiate).
#
# Uso:
#   export IMAGE_REPOBASE=ghcr.io/<tuo-org>
#   ./build-images.sh
#   # oppure, per forzare un tag diverso dal contenuto di VERSION:
#   IMAGE_TAG=1.2.3-rc1 ./build-images.sh

set -euo pipefail

IMAGE_REPOBASE="${IMAGE_REPOBASE:?Imposta IMAGE_REPOBASE, es. ghcr.io/<tuo-org>}"
if [ -z "${IMAGE_TAG:-}" ]; then
    if [ ! -f VERSION ]; then
        echo "Errore: file VERSION mancante e IMAGE_TAG non impostato. Crea VERSION (es. 'echo 1.0.0 > VERSION') o esporta IMAGE_TAG esplicitamente." >&2
        exit 1
    fi
    IMAGE_TAG="$(tr -d '[:space:]' < VERSION)"
fi

MODULE_IMAGE_NAME="sentinel-fornitori"
MODULE_IMAGE_URL="${IMAGE_REPOBASE}/${MODULE_IMAGE_NAME}:${IMAGE_TAG}"
MODULE_IMAGE_URL_LATEST="${IMAGE_REPOBASE}/${MODULE_IMAGE_NAME}:latest"

echo "==> Versione modulo: ${IMAGE_TAG}"
echo "==> build immagine modulo (scratch, veicolo per imageroot/ + ui/) con buildah"

ALL_IMAGES=$(grep -v '^#' imageroot/.images | grep -v '^[[:space:]]*$' | tr '\n' ' ')

if ! buildah containers --format "{{.ContainerName}}" | grep -q nodebuilder-sentinel; then
    echo "Pulling NodeJS runtime per la build della UI..."
    buildah from --name nodebuilder-sentinel -v "${PWD}:/usr/src:Z" docker.io/library/node:24-slim
fi
echo "Build file statici UI con node..."
buildah run \
    --workingdir=/usr/src/ui \
    --env="NODE_OPTIONS=--openssl-legacy-provider" \
    nodebuilder-sentinel \
    sh -c "corepack enable && yarn install && yarn build"

container=$(buildah from scratch)
buildah add "${container}" imageroot /imageroot
buildah add "${container}" ui/dist /ui
buildah config \
    --entrypoint=/ \
    --label="org.nethserver.authorizations=traefik@node:routeadm" \
    --label="org.nethserver.tcp-ports-demand=4" \
    --label="org.nethserver.rootfull=0" \
    --label="org.nethserver.images=${ALL_IMAGES}" \
    "${container}"
buildah commit "${container}" "${MODULE_IMAGE_URL}"
buildah tag "${MODULE_IMAGE_URL}" "${MODULE_IMAGE_URL_LATEST}"
buildah push "${MODULE_IMAGE_URL}"
buildah push "${MODULE_IMAGE_URL_LATEST}"

echo "==> Fatto."
echo "Immagine modulo (da passare ad add-module/update-module):"
echo "  versionata (usare SEMPRE questa in produzione): ${MODULE_IMAGE_URL}"
echo "  alias latest (solo comodo per test manuali):    ${MODULE_IMAGE_URL_LATEST}"
echo
echo "Nota: l'immagine applicativa non viene toccata da questo script."
echo "La risolve da sola configure-module (prima installazione) o"
echo "update-now (aggiornamenti), interrogando ghcr.io/startappate/sentinel-fornitori-nis2."
