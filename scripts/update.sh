#!/bin/bash

# Pull latest version of all images
docker compose -f docker-compose.yml pull

# Start all services
docker compose up -d

# Only auto-restart non-essential containers!
docker compose -f docker-compose.yml restart mailpit &
docker compose -f docker-compose.yml restart phpmyadmin &
wait
