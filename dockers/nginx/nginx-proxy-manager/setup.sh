#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
NETWORK="${GATEWAY_NETWORK:-nginx_gateway}"
LEGACY_COMPOSE="$SCRIPT_DIR/../nginx/docker-compose.yaml"

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

command -v docker >/dev/null 2>&1 || fail "Docker is required."
docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 is required."
compose_version="$(docker compose version --short | sed -E 's/^v//; s/[-+].*$//')"
[[ "$compose_version" =~ ^[0-9]+\.[0-9]+ ]] || fail "Could not determine Docker Compose version."
compose_major="${compose_version%%.*}"
compose_minor="${compose_version#*.}"
compose_minor="${compose_minor%%.*}"
if (( compose_major < 2 || (compose_major == 2 && compose_minor < 30) )); then
    fail "Docker Compose v2.30 or newer is required for raw credentials in the watcher env file."
fi
docker info >/dev/null 2>&1 || fail "Cannot connect to the Docker daemon."
[[ "$NETWORK" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || fail "Invalid Docker network name: $NETWORK"

if ! docker network inspect "$NETWORK" >/dev/null 2>&1; then
    printf 'Creating Docker network %s...\n' "$NETWORK"
    docker network create "$NETWORK" >/dev/null || fail "Could not create Docker network $NETWORK."
fi

if docker inspect nginx-container >/dev/null 2>&1; then
    legacy_image="$(docker inspect --format '{{.Config.Image}}' nginx-container)"
    legacy_service="$(docker inspect --format '{{index .Config.Labels "com.docker.compose.service"}}' nginx-container)"
    legacy_project="$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' nginx-container)"

    if [[ "$legacy_image" == nginx* && "$legacy_service" == nginx && -f "$LEGACY_COMPOSE" ]]; then
        printf 'Stopping the legacy Nginx gateway to release ports 80 and 443...\n'
        docker compose --project-directory "$(dirname "$LEGACY_COMPOSE")" \
            -f "$LEGACY_COMPOSE" down \
            || fail "Could not stop the legacy Nginx Compose project."
        printf 'Legacy Nginx gateway stopped (Compose project: %s).\n' "$legacy_project"
    else
        fail "Container nginx-container exists but does not look like the expected legacy gateway; stop it manually before switching."
    fi
fi

while IFS= read -r container_id; do
    [[ -n "$container_id" ]] || continue
    container_name="$(docker inspect --format '{{.Name}}' "$container_id")"
    container_name="${container_name#/}"

    [[ "$container_name" == "nginx-proxy-manager" ]] && continue

    network_mode="$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$container_id")"
    if [[ "$network_mode" == "host" ]]; then
        printf 'Warning: %s uses host networking and cannot join %s.\n' "$container_name" "$NETWORK" >&2
        continue
    fi

    connected_networks="$(docker inspect --format \
        '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}} {{end}}' "$container_id")"
    if [[ " $connected_networks " != *" $NETWORK "* ]]; then
        if docker network connect "$NETWORK" "$container_id"; then
            printf 'Connected %s to %s.\n' "$container_name" "$NETWORK"
        else
            printf 'Error: could not connect %s to %s.\n' "$container_name" "$NETWORK" >&2
            exit 1
        fi
    fi
done < <(docker ps -q)

mkdir -p "$SCRIPT_DIR/config"

if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
    cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
    chmod 600 "$SCRIPT_DIR/.env"
    printf 'Created %s; set NPM_EMAIL and NPM_PASSWORD after completing NPM first-time setup.\n' \
        "$SCRIPT_DIR/.env"
fi

GATEWAY_NETWORK="$NETWORK" docker compose \
    --project-directory "$SCRIPT_DIR" \
    -f "$SCRIPT_DIR/docker-compose.yaml" \
    pull app || fail "Could not pull jlesage/nginx-proxy-manager."

GATEWAY_NETWORK="$NETWORK" docker compose \
    --project-directory "$SCRIPT_DIR" \
    -f "$SCRIPT_DIR/docker-compose.yaml" \
    up -d app || fail "Could not start Nginx Proxy Manager."

if ! awk -F= '
    $1 == "NPM_EMAIL" && length(substr($0, index($0, "=") + 1)) > 0 { email = 1 }
    $1 == "NPM_PASSWORD" && length(substr($0, index($0, "=") + 1)) > 0 { password = 1 }
    END { exit !(email && password) }
' "$SCRIPT_DIR/.env"; then
    printf '\nNginx Proxy Manager is running, but automatic Docker sync is not enabled yet.\n'
    printf 'Complete first-time login at http://localhost:8100, then set NPM_EMAIL and NPM_PASSWORD in %s/.env.\n' \
        "$SCRIPT_DIR"
    printf 'Run this setup script again to start automatic synchronization.\n'
    exit 0
fi

GATEWAY_NETWORK="$NETWORK" docker compose \
    --project-directory "$SCRIPT_DIR" \
    -f "$SCRIPT_DIR/docker-compose.yaml" \
    --profile auto-sync up -d --build || fail "Could not start the NPM Docker sync watcher."

printf '\nNginx Proxy Manager is starting.\n'
printf 'Admin UI: http://localhost:8100\n'
printf 'Docker containers are synchronized to NPM Proxy Hosts on %s.\n' "$NETWORK"
