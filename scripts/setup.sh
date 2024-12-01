#!/bin/bash

export DEBIAN_FRONTEND=noninteractive
set -eu

# Create required docker networks (if not already created)
docker network ls | grep -q traefik || docker network create traefik
docker network ls | grep -q docker || docker network create docker

echo "✅ Created required Docker networks"

# Copy environment variables file if not already present
if [[ ! -f .env ]]; then
    cp .env.example .env
    sed -i "s/MYSQL_ROOT_PASSWORD=.*/MYSQL_ROOT_PASSWORD=$(pwgen -cnsBv 20 1)/" .env

    echo "✅ Created default environment configuration file"
fi

# Create access log for Traefik as Docker mount point
if [[ ! -f volumes/traefik/access.log ]]; then
    touch volumes/traefik/access.log

    echo "✅ Created Traefik access log file"
fi
