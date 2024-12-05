#!/bin/bash

export DEBIAN_FRONTEND=noninteractive
set -eu

UNSECURE=false
COMPOSE_FILE="docker-compose.yml"

while getopts 'u' flag; do
    case "${flag}" in
        u) UNSECURE=true ;;
        *) true
    esac
done

if [ "$UNSECURE" = true ]; then
    COMPOSE_FILE="docker-compose.http.yml"
    echo "Using unsecure compose file"
else
    echo "Using secure compose file"
fi

# Pull latest version of all images
docker compose -f "$COMPOSE_FILE" pull

echo "✅ Pulled latest images for all services"

# Start all services
docker compose -f "$COMPOSE_FILE" up -d

echo "✅ Started all services"

# Only auto-restart non-essential containers!
docker compose -f "$COMPOSE_FILE" restart mailpit &
docker compose -f "$COMPOSE_FILE" restart phpmyadmin &
wait

echo "✅ Restarted MailPit and PhpMyAdmin services"
