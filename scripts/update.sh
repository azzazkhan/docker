#!/bin/bash

export DEBIAN_FRONTEND=noninteractive
set -eu

# Pull latest version of all images
docker compose -f docker-compose.yml pull

echo "✅ Pulled latest images for all services"

# Start all services
docker compose up -d

echo "✅ Started all services"

# Only auto-restart non-essential containers!
docker compose -f docker-compose.yml restart mailpit &
docker compose -f docker-compose.yml restart phpmyadmin &
wait

echo "✅ Restarted MailPit and PhpMyAdmin services"
