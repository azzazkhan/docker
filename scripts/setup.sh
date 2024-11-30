#!/bin/bash

export DEBIAN_FRONTEND=noninteractive
set -eu

# Copy environment variables file if not already present
if [[ ! -f .env ]]; then
    echo "Creating environment configuration file for base containers"

    cp .env.example .env
    sed -i "s/MYSQL_ROOT_PASSWORD=.*/MYSQL_ROOT_PASSWORD=$(pwgen -cnsBv 20 1)/" .env
fi

# Create access log for Traefik as Docker mount point
if [[ ! -f volumes/traefik/access.log ]]; then
    echo "Creating access log file for Traefik reverse proxy"

    touch volumes/traefik/access.log
fi
