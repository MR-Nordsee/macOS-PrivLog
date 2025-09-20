#!/bin/bash
# Install docker Desktop and buildx first (tested this on macOS only)
VERSION="v1.0.0"
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
VCS_REF=$(git rev-parse --short HEAD)

docker-buildx create --use

docker-buildx build --build-arg VERSION=${VERSION} \
                    --build-arg BUILD_DATE=${BUILD_DATE} \
                    --build-arg VCS_REF=${VCS_REF} \
                    --platform linux/amd64,linux/arm64 \
                    --provenance=false --sbom=false \
                    -t privileges-server:local-arm64 \
                    -t privileges-server:${VERSION}-local-arm64 \
                    --load \
                    --file ../Dockerfile \
                    ../

docker-buildx build --build-arg VERSION=${VERSION} \
                    --build-arg BUILD_DATE=${BUILD_DATE} \
                    --build-arg VCS_REF=${VCS_REF} \
                    --platform linux/amd64 \
                    --provenance=false --sbom=false \
                    -t privileges-server:local-amd64 \
                    -t privileges-server:${VERSION}-amd64 \
                    --load \
                    --file ../Dockerfile \
                    ../

docker save privileges-server:local-arm64 -o privileges-server_${VERSION}_arm64.tar
docker save privileges-server:local-amd64 -o privileges-server_${VERSION}_amd64.tar
