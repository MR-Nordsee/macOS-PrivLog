# syntax=docker/dockerfile:1

# Comments are provided throughout this file to help you get started.
# If you need more help, visit the Dockerfile reference guide at
# https://docs.docker.com/go/dockerfile-reference/

# use builder so curl does not end up in the container
FROM alpine:latest AS builder
ARG TARGETARCH

# Install dependency
RUN apk update && apk add curl

# Download supercronic for jobs
RUN if [ ${TARGETARCH} = "amd64" ]; then \
    curl -fsSLO "https://github.com/aptible/supercronic/releases/download/v0.2.34/supercronic-linux-amd64" \
    && echo "e8631edc1775000d119b70fd40339a7238eece14 supercronic-linux-amd64" | sha1sum -c - \
    && chmod +x "supercronic-linux-amd64" \
    && mv "supercronic-linux-amd64" "supercronic" \
    ; fi

RUN if [ ${TARGETARCH} = "arm64" ]; then \
    curl -fsSLO "https://github.com/aptible/supercronic/releases/download/v0.2.34/supercronic-linux-arm64" \
    && echo "4ab6343b52bf9da592e8b4bb7ae6eb5a8e21b71e supercronic-linux-arm64" | sha1sum -c - \
    && chmod +x "supercronic-linux-arm64" \
    && mv "supercronic-linux-arm64" "supercronic" \
    ; fi

FROM python:3.12-alpine AS base
ARG VERSION
ARG VCS_REF
ARG BUILD_DATE

# Set OCI-compliant labels (https://github.com/opencontainers/image-spec/blob/main/annotations.md)
LABEL org.opencontainers.image.title="macOS-Privileges-Webhook-Server" \
      org.opencontainers.image.description="FastAPI backend for macos-enterpise-privileges webhooks" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.authors="MR-Nordsee" \
      org.opencontainers.image.source="https://github.com/MR-Nordsee/macOS-PrivLog" \
      org.opencontainers.image.licenses="MIT, BSD-3-Clause, Apache-2.0, PSF-2.0"

# Prevents Python from writing pyc files.
ENV PYTHONDONTWRITEBYTECODE=1

# Keeps Python from buffering stdout and stderr to avoid situations where
# the application crashes without emitting any logs due to buffering.
ENV PYTHONUNBUFFERED=1

# Create a non-privileged user that the app will run under.
# See https://docs.docker.com/go/dockerfile-user-best-practices/
ARG PUID=1000
ARG PGID=1000
RUN addgroup -g ${PGID} appgroup
RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/nonexistent" \
    --shell "/sbin/nologin" \
    --no-create-home \
    --uid ${PUID} \
    --ingroup appgroup \
    appuser

# Download dependencies as a separate step to take advantage of Docker's caching.
# Leverage a cache mount to /root/.cache/pip to speed up subsequent builds.
# Leverage a bind mount to requirements.txt to avoid having to copy them into
# into this layer.
RUN --mount=type=cache,target=/root/.cache/pip \
    --mount=type=bind,source=requirements.txt,target=requirements.txt \
    python -m pip install -r requirements.txt

# Create the directory and change ownership
RUN mkdir -p /app/Logs && mkdir -p /app/backup && mkdir -p /app/Data

COPY Licences/* /app/licences/

COPY cronjobs /app
COPY api_server.py /app
COPY db-backup.sh /app
COPY db-cleanup.sh /app
COPY init.sh /app
RUN chown -R ${PUID}:${PGID} /app

RUN chmod -R 755 /app/Logs /app/backup /app/Data
RUN chmod 555 /app/api_server.py /app/init.sh /app/db-backup.sh

# Install supervisor & bash
RUN apk update && apk add --no-cache supervisor
RUN apk add --no-cache --upgrade bash

# Get supercronic from build image to base image
COPY --from=builder supercronic /usr/local/bin/supercronic

# Replace default supervisor config
COPY supervisord.conf /etc/supervisor/supervisord.conf

# Copy the source code into the container.
WORKDIR /app

# Expose the port & volume for the application
EXPOSE 8080
VOLUME ["/app/Data", "/app/Logs", "/app/backup"]

# Run the application.
ENTRYPOINT ["/bin/bash", "/app/init.sh"]