#!/bin/bash
#
# Costruisce e pubblica DUE immagini distinte, seguendo il meccanismo reale
# usato dal template ns8-kickstart (build-images.sh originale, basato su
# buildah, non su un Containerfile "normale" - vedi
# https://github.com/NethServer/ns8-kickstart/blob/main/build-images.sh):
#
# 1. l'immagine APPLICATIVA (Next.js/vinext) - quella che gira davvero,
#    buildata dal Dockerfile del repo sorgente dell'app (APP_SRC_DIR);
# 2. l'immagine "MODULO" - un'immagine scratch (vuota, mai eseguita) che
#    contiene solo imageroot/ e i label org.nethserver.*. È QUESTA seconda
#    immagine che si passa ad `add-module`, non la prima.
#
# Uso:
#   export IMAGE_REPOBASE=ghcr.io/<tuo-org>
#   export APP_SRC_DIR=/percorso/al/repo/app-sentinel
#   ./build-images.sh

set -euo pipefail

IMAGE_REPOBASE="${IMAGE_REPOBASE:?Imposta IMAGE_REPOBASE, es. ghcr.io/<tuo-org>}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
APP_SRC_DIR="${APP_SRC_DIR:-./app-src}"

# Nome dell'immagine applicativa: DEVE restare distinto dal nome del modulo
# ("sentinel-fornitori", riservato all'immagine scratch sotto) altrimenti i
# due tag si sovrascrivono a vicenda nello stesso registro.
APP_IMAGE_NAME="sentinel-fornitori-app"
MODULE_IMAGE_NAME="sentinel-fornitori"

APP_IMAGE_URL="${IMAGE_REPOBASE}/${APP_IMAGE_NAME}:${IMAGE_TAG}"
MODULE_IMAGE_URL="${IMAGE_REPOBASE}/${MODULE_IMAGE_NAME}:${IMAGE_TAG}"

echo "==> 1/2: build immagine applicativa (${APP_IMAGE_URL})"
podman build -t "${APP_IMAGE_URL}" "${APP_SRC_DIR}"
podman push "${APP_IMAGE_URL}"

echo "==> 2/2: build immagine modulo (scratch, veicolo per imageroot/ + ui/) con buildah"

# Immagini di terze parti dichiarate in imageroot/.images, più la nostra
# immagine applicativa appena pubblicata: finiscono tutte nello stesso label
# org.nethserver.images e vengono scaricate automaticamente dall'azione core
# create-module al momento dell'installazione.
THIRD_PARTY_IMAGES=$(grep -v '^#' imageroot/.images | grep -v '^[[:space:]]*$' | tr '\n' ' ')
ALL_IMAGES="${THIRD_PARTY_IMAGES}${APP_IMAGE_URL}"

# add-module esegue SEMPRE l'azione core extract-ui, che pretende un
# percorso /ui nell'immagine modulo (fallisce con "tar: ui: Not found in
# archive" se manca) - non è opzionale, va buildato anche senza una UI
# personalizzata. Riusiamo un container nodebuilder per velocizzare build
# ripetute, esattamente come fa lo script originale del kickstart.
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
buildah push "${MODULE_IMAGE_URL}"

echo "==> Fatto."
echo "Immagine applicativa (usata dalle unit systemd):    ${APP_IMAGE_URL}"
echo "Immagine modulo (da passare ad add-module):          ${MODULE_IMAGE_URL}"
