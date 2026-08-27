#!/bin/bash

# Costruisce e pubblica l'immagine dell'app SENTINEL Fornitori nel registro
# indicato da $IMAGE_REPOBASE (impostato dal core NS8 durante build/CI, oppure
# esportabile a mano per test locali, es:
#   export IMAGE_REPOBASE=ghcr.io/<tuo-org>
#   ./build-images.sh
#
# Le immagini di terze parti (Postgres, MinIO, ClamAV) NON vengono ricostruite:
# sono dichiarate nel file .images (org.nethserver.images) e scaricate in
# automatico dall'azione core create-module. Qui si costruisce solo l'immagine
# applicativa specifica di SENTINEL, a partire dal Dockerfile del repo
# originale dell'app (Next.js / vinext).

set -euo pipefail

IMAGE_REPOBASE="${IMAGE_REPOBASE:?Imposta IMAGE_REPOBASE, es. ghcr.io/<tuo-org>}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# Percorso del sorgente dell'app SENTINEL (il repository Next.js del collega,
# quello con Dockerfile, package.json, ecc. - NON il Dockerfile di backup
# incluso in questo scaffold, che è un'immagine diversa).
APP_SRC_DIR="${APP_SRC_DIR:-./app-src}"

echo "==> Build immagine applicazione (sentinel-fornitori)"
docker build -t "${IMAGE_REPOBASE}/sentinel-fornitori:${IMAGE_TAG}" "${APP_SRC_DIR}"
docker push "${IMAGE_REPOBASE}/sentinel-fornitori:${IMAGE_TAG}"

echo "==> Fatto. Immagine pubblicata: ${IMAGE_REPOBASE}/sentinel-fornitori:${IMAGE_TAG}"
