#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
NETWORK="${GATEWAY_NETWORK:-nginx_gateway}"
DOMAIN="${GATEWAY_DOMAIN:-localhost}"
NGINX_CONTAINER="nginx-container"
GENERATED_DIR="$SCRIPT_DIR/conf/generated"
TLS_DIR="$SCRIPT_DIR/tls"
ROUTES_FILE="$GENERATED_DIR/routes.conf"
TEMP_ROUTES_FILE=""
FAILED_CONTAINERS=()
HOST_NETWORK_CONTAINERS=()
declare -A PORT_OVERRIDES=()

cleanup() {
    if [[ -n "$TEMP_ROUTES_FILE" && -f "$TEMP_ROUTES_FILE" ]]; then
        rm -f -- "$TEMP_ROUTES_FILE"
    fi
}
trap cleanup EXIT

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

for command in docker openssl; do
    command -v "$command" >/dev/null 2>&1 || fail "Required command not found: $command"
done

docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 is required."
docker info >/dev/null 2>&1 || fail "Cannot connect to the Docker daemon."

[[ "$NETWORK" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || fail "Invalid Docker network name: $NETWORK"
[[ "$DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || fail "Invalid gateway domain: $DOMAIN"
[[ "$DOMAIN" != *..* && "$DOMAIN" != *.-* && "$DOMAIN" != *-.* ]] || fail "Invalid gateway domain: $DOMAIN"

if [[ -n "${GATEWAY_HTTP_PORTS:-}" ]]; then
    IFS=',' read -r -a port_overrides <<<"$GATEWAY_HTTP_PORTS"
    for entry in "${port_overrides[@]}"; do
        [[ "$entry" == *=* ]] || fail "Invalid GATEWAY_HTTP_PORTS entry: $entry (expected container=port)."
        override_name="${entry%%=*}"
        override_port="${entry#*=}"
        [[ "$override_name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] ||
            fail "Invalid container name in GATEWAY_HTTP_PORTS: $override_name"
        [[ "$override_port" =~ ^[0-9]+$ ]] || fail "Invalid port in GATEWAY_HTTP_PORTS: $entry"
        override_port_number=$((10#$override_port))
        (( override_port_number >= 1 && override_port_number <= 65535 )) ||
            fail "Port in GATEWAY_HTTP_PORTS must be between 1 and 65535: $entry"
        PORT_OVERRIDES["$override_name"]="$override_port_number"
    done
fi

mkdir -p -- "$GENERATED_DIR" "$TLS_DIR"

if ! docker network inspect "$NETWORK" >/dev/null 2>&1; then
    printf 'Creating Docker network %s...\n' "$NETWORK"
    docker network create "$NETWORK" >/dev/null || fail "Could not create Docker network $NETWORK."
fi

certificate_matches_domain=false
if [[ -s "$TLS_DIR/fullchain.pem" && -s "$TLS_DIR/privkey.pem" ]] &&
    openssl x509 -in "$TLS_DIR/fullchain.pem" -noout -ext subjectAltName 2>/dev/null |
        grep -Fq "DNS:$DOMAIN" &&
    openssl x509 -in "$TLS_DIR/fullchain.pem" -noout -ext subjectAltName 2>/dev/null |
        grep -Fq "DNS:*.$DOMAIN"; then
    certificate_matches_domain=true
fi

if [[ "$certificate_matches_domain" != true ]]; then
    printf 'Generating a self-signed certificate for %s and *.%s...\n' "$DOMAIN" "$DOMAIN"
    umask 077
    openssl req -x509 -nodes -newkey rsa:3072 -sha256 -days 365 \
        -keyout "$TLS_DIR/privkey.pem" \
        -out "$TLS_DIR/fullchain.pem" \
        -subj "/CN=$DOMAIN" \
        -addext "subjectAltName=DNS:$DOMAIN,DNS:*.$DOMAIN" \
        || fail "Could not generate the self-signed TLS certificate."
fi

TEMP_ROUTES_FILE="$(mktemp "$GENERATED_DIR/routes.conf.XXXXXX")"
cat >"$TEMP_ROUTES_FILE" <<'EOF'
resolver 127.0.0.11 valid=30s ipv6=off;
EOF

declare -A USED_HOSTNAMES=()

is_non_http_port() {
    case "$1" in
        21|22|25|53|110|111|123|135|137|138|139|143|161|389|445|465|\
        514|587|631|636|993|995|1433|1521|2049|2181|2375|2376|3306|\
        3389|4369|5432|5433|5672|6379|7000|7001|7199|9042|9092|9300|\
        11211|27017|27018|28017|50000)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

for container_id in $(docker ps -q); do
    container_name="$(docker inspect --format '{{.Name}}' "$container_id")"
    container_name="${container_name#/}"

    if [[ "$container_name" == "$NGINX_CONTAINER" ]]; then
        continue
    fi

    name_slug="$(printf '%s' "$container_name" |
        tr '[:upper:]' '[:lower:]' |
        sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//')"
    [[ -n "$name_slug" ]] || name_slug="service"
    if [[ -n "${USED_HOSTNAMES[$name_slug]:-}" ]]; then
        name_slug="${name_slug}-${container_id:0:8}"
    fi
    USED_HOSTNAMES["$name_slug"]=1

    network_mode="$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$container_id")"
    if [[ "$network_mode" == "host" ]]; then
        HOST_NETWORK_CONTAINERS+=("$container_name")
        printf 'Warning: %s uses host networking and cannot join %s; no route will be created.\n' \
            "$container_name" "$NETWORK" >&2
        continue
    fi

    connected_networks="$(docker inspect --format \
        '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}} {{end}}' "$container_id")"
    if [[ " $connected_networks " != *" $NETWORK "* ]]; then
        if ! docker network connect --alias "$name_slug" "$NETWORK" "$container_id"; then
            printf 'Error: could not connect %s to %s.\n' "$container_name" "$NETWORK" >&2
            FAILED_CONTAINERS+=("$container_name")
            continue
        fi
        printf 'Connected %s to %s.\n' "$container_name" "$NETWORK"
    fi

    enabled="$(docker inspect --format '{{index .Config.Labels "gateway.enable"}}' "$container_id")"
    if [[ "$enabled" == "false" ]]; then
        printf 'Connected %s; HTTP routing disabled by gateway.enable=false.\n' "$container_name"
        continue
    fi

    port="$(docker inspect --format '{{index .Config.Labels "gateway.http.port"}}' "$container_id")"
    if [[ "$port" == "<no value>" || -z "$port" ]]; then
        port="${PORT_OVERRIDES[$container_name]:-}"
    fi

    scheme="$(docker inspect --format '{{index .Config.Labels "gateway.http.scheme"}}' "$container_id")"
    if [[ "$scheme" == "<no value>" || -z "$scheme" ]]; then
        scheme="http"
        scheme_from_label=false
    else
        scheme_from_label=true
    fi

    if [[ -z "$port" ]]; then
        exposed_ports="$(docker inspect --format \
            '{{range $port, $_ := .Config.ExposedPorts}}{{$port}} {{end}}' "$container_id")"
        for exposed_port in $exposed_ports; do
            [[ "$exposed_port" == */tcp ]] || continue
            candidate_port="${exposed_port%/tcp}"
            [[ "$candidate_port" =~ ^[0-9]+$ ]] || continue
            if ! is_non_http_port "$candidate_port"; then
                port="$candidate_port"
                break
            fi
        done
    fi

    if [[ -z "$port" ]]; then
        printf 'Connected %s; no HTTP port was identified, so no route was created.\n' "$container_name"
        continue
    fi
    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        printf 'Error: invalid gateway.http.port label on %s: %s\n' "$container_name" "$port" >&2
        FAILED_CONTAINERS+=("$container_name")
        continue
    fi
    numeric_port=$((10#$port))
    if (( numeric_port < 1 || numeric_port > 65535 )); then
        printf 'Error: invalid gateway.http.port label on %s: %s\n' "$container_name" "$port" >&2
        FAILED_CONTAINERS+=("$container_name")
        continue
    fi
    port="$numeric_port"
    if [[ "$scheme_from_label" != true && ( "$port" == "443" || "$port" == "8443" ) ]]; then
        scheme="https"
    fi
    if [[ "$scheme" != "http" && "$scheme" != "https" ]]; then
        printf 'Error: gateway.http.scheme on %s must be http or https.\n' "$container_name" >&2
        FAILED_CONTAINERS+=("$container_name")
        continue
    fi

    route_host="$name_slug.$DOMAIN"
    cat >>"$TEMP_ROUTES_FILE" <<EOF

server {
    listen 443 ssl;
    server_name $route_host;

    ssl_certificate /etc/nginx/tls/fullchain.pem;
    ssl_certificate_key /etc/nginx/tls/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        set \$gateway_upstream "$scheme://$container_name:$port";
        proxy_pass \$gateway_upstream;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_read_timeout 300s;
    }
}
EOF

    printf 'Route configured: https://%s -> %s:%s (%s)\n' \
        "$route_host" "$container_name" "$port" "$scheme"
done

mv -- "$TEMP_ROUTES_FILE" "$ROUTES_FILE"
TEMP_ROUTES_FILE=""

printf 'Starting the Nginx gateway...\n'
GATEWAY_NETWORK="$NETWORK" docker compose --project-directory "$SCRIPT_DIR" -f "$SCRIPT_DIR/docker-compose.yaml" up -d \
    || fail "Could not start the Nginx gateway."

GATEWAY_NETWORK="$NETWORK" docker compose --project-directory "$SCRIPT_DIR" -f "$SCRIPT_DIR/docker-compose.yaml" exec -T nginx nginx -t \
    || fail "Nginx configuration validation failed."
GATEWAY_NETWORK="$NETWORK" docker compose --project-directory "$SCRIPT_DIR" -f "$SCRIPT_DIR/docker-compose.yaml" exec -T nginx nginx -s reload \
    || fail "Could not reload Nginx with the generated routes."

if ((${#HOST_NETWORK_CONTAINERS[@]})); then
    printf '\nHost-network containers were not attached or routed: %s\n' \
        "$(IFS=', '; printf '%s' "${HOST_NETWORK_CONTAINERS[*]}")" >&2
fi

if ((${#FAILED_CONTAINERS[@]})); then
    printf '\nGateway setup completed with connection/configuration errors for: %s\n' \
        "$(IFS=', '; printf '%s' "${FAILED_CONTAINERS[*]}")" >&2
    exit 1
fi

printf '\nGateway is ready: https://<container-name>.%s (self-signed certificate)\n' "$DOMAIN"
