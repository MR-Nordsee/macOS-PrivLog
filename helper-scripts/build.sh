#!/bin/bash
# Install docker Desktop and buildx first (tested this on macOS only)
VERSION="v0.3.2"
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
VCS_REF=$(git rev-parse --short HEAD)

docker-buildx create --use

docker-buildx build --build-arg VERSION=${VERSION} \
                    --build-arg BUILD_DATE=${BUILD_DATE} \
                    --build-arg VCS_REF=${VCS_REF} \
                    --platform linux/amd64,linux/arm64 \
                    --provenance=false --sbom=false \
                    -t ghcr.io/mr-nordsee/macos-privlog:latest \
                    -t ghcr.io/mr-nordsee/macos-privlog:${VERSION} \
                    --push \
                    --file ../Dockerfile \
                    ../

#docker save macOS-PrivLog/webhook:${VERSION}-amd64 -o privileges-server_${VERSION}_amd64.tar
#docker save macOS-PrivLog/webhook:${VERSION}-arm64 -o privileges-server_${VERSION}_arm64.tar
