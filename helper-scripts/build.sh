#!/bin/bash
# Install docker Desktop and buildx first (tested this on macOS only)
VERSION="v0.3.0"
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
VCS_REF=$(git rev-parse --short HEAD)

docker-buildx create --use

docker-buildx build --build-arg VERSION=${VERSION} \
                    --build-arg BUILD_DATE=${BUILD_DATE} \
                    --build-arg VCS_REF=${VCS_REF} \
                    --platform linux/amd64 \
                    -t macOS-PrivLog/webhook:${VERSION}-amd64 \
                    --load ../

docker-buildx build --build-arg VERSION=${VERSION} \
                    --build-arg BUILD_DATE=${BUILD_DATE} \
                    --build-arg VCS_REF=${VCS_REF} \
                    --platform linux/arm64 \
                    -t macOS-PrivLog/webhook:${VERSION}-arm64 \
                    --load ../

docker save macOS-PrivLog/webhook:${VERSION}-amd64 -o privileges-server_${VERSION}_amd64.tar
docker save macOS-PrivLog/webhook:${VERSION}-arm64 -o privileges-server_${VERSION}_arm64.tar
