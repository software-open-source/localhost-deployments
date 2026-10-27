#!/usr/bin/env bash

set -Eeuo pipefail

NETWORK="${GATEWAY_NETWORK:-nginx_gateway}"
DOMAIN="${GATEWAY_DOMAIN:-localhost}"
API_URL="${NPM_API_URL:-http://app:8181/api}"
MANAGED_MARKER="# managed-by-nginx-proxy-manager-docker-sync"
declare -A ACTIVE_DOMAINS=()
declare -A USED_DOMAINS=()
declare -A PORT_OVERRIDES=()

log() {
    printf '[docker-sync] %s\n' "$*"
}

warn() {
    printf '[docker-sync] Warning: %s\n' "$*" >&2
}

for command in docker curl jq; do
    command -v "$command" >/dev/null 2>&1 || {
        warn "Required command not found: $command"
        exit 1
    }
done

[[ "$NETWORK" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || {
    warn "Invalid Docker network name: $NETWORK"
    exit 1
}
[[ "$DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] &&
    [[ "$DOMAIN" != *..* && "$DOMAIN" != *.-* && "$DOMAIN" != *-.* ]] || {
    warn "Invalid gateway domain: $DOMAIN"
    exit 1
}
[[ -n "${NPM_EMAIL:-}" && -n "${NPM_PASSWORD:-}" ]] || {
    warn "Set NPM_EMAIL and NPM_PASSWORD in the local .env file."
    exit 1
}

if [[ -n "${GATEWAY_HTTP_PORTS:-}" ]]; then
    IFS=',' read -r -a port_overrides <<<"$GATEWAY_HTTP_PORTS"
    for entry in "${port_overrides[@]}"; do
        [[ "$entry" == *=* ]] || {
            warn "Invalid GATEWAY_HTTP_PORTS entry: $entry (expected container=port)."
            exit 1
        }
        override_name="${entry%%=*}"
        override_port="${entry#*=}"
        [[ "$override_name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ &&
            "$override_port" =~ ^[0-9]+$ ]] || {
            warn "Invalid GATEWAY_HTTP_PORTS entry: $entry"
            exit 1
        }
        override_port_number=$((10#$override_port))
        (( override_port_number >= 1 && override_port_number <= 65535 )) || {
            warn "Port in GATEWAY_HTTP_PORTS must be between 1 and 65535: $entry"
            exit 1
        }
        PORT_OVERRIDES["$override_name"]="$override_port_number"
    done
fi

if ! docker network inspect "$NETWORK" >/dev/null 2>&1; then
    warn "Docker network $NETWORK does not exist."
    exit 1
fi

token_response="$(curl --fail-with-body --silent --show-error \
    --connect-timeout 5 --max-time 15 \
    -H 'Content-Type: application/json' \
    --data "$(jq -n --arg identity "$NPM_EMAIL" --arg secret "$NPM_PASSWORD" \
        '{identity: $identity, secret: $secret}')" \
    "$API_URL/tokens")" || {
    warn "Could not authenticate to NPM API at $API_URL. Check the NPM credentials."
    exit 1
}
token="$(jq -er '.token' <<<"$token_response")" || {
    warn "NPM API did not return an access token."
    exit 1
}

api_request() {
    local method="$1"
    local path="$2"
    local payload="${3:-}"
    local args=(
        --fail-with-body --silent --show-error
        --connect-timeout 5 --max-time 30
        -X "$method"
        -H "Authorization: Bearer $token"
        -H 'Content-Type: application/json'
    )
    if [[ -n "$payload" ]]; then
        args+=(--data "$payload")
    fi
    curl "${args[@]}" "$API_URL$path"
}

existing_hosts="$(api_request GET /nginx/proxy-hosts)" || {
    warn "Could not list NPM Proxy Hosts."
    exit 1
}
jq -e 'type == "array"' >/dev/null <<<"$existing_hosts" || {
    warn "NPM API returned an unexpected Proxy Host list."
    exit 1
}

certificate_id="${NPM_CERTIFICATE_ID:-0}"
if [[ ! "$certificate_id" =~ ^[0-9]+$ ]]; then
    warn "NPM_CERTIFICATE_ID must be a numeric certificate ID."
    exit 1
fi
certificate_id=$((10#$certificate_id))
(( certificate_id <= 2147483647 )) || {
    warn "NPM_CERTIFICATE_ID is out of range."
    exit 1
}

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

while IFS= read -r container_id; do
    [[ -n "$container_id" ]] || continue

    inspect="$(docker inspect "$container_id")" || {
        warn "Could not inspect container $container_id."
        continue
    }
    container_name="$(jq -r '.[0].Name | ltrimstr("/")' <<<"$inspect")"

    if [[ "$container_name" == "nginx-proxy-manager" ||
        "$container_name" == "nginx-proxy-manager-docker-sync" ]]; then
        continue
    fi

    network_mode="$(jq -r '.[0].HostConfig.NetworkMode' <<<"$inspect")"
    if [[ "$network_mode" == "host" ]]; then
        warn "$container_name uses host networking and cannot join $NETWORK."
        continue
    fi

    if ! jq -e --arg network "$NETWORK" '.[0].NetworkSettings.Networks | has($network)' \
        >/dev/null <<<"$inspect"; then
        if docker network connect "$NETWORK" "$container_id"; then
            log "Connected $container_name to $NETWORK."
            inspect="$(docker inspect "$container_id")" || {
                warn "Could not inspect $container_name after connecting it."
                continue
            }
        else
            warn "Could not connect $container_name to $NETWORK."
            continue
        fi
    fi

    labels="$(jq -r '.[0].Config.Labels // {}' <<<"$inspect")"
    if [[ "$(jq -r '."gateway.enable" // ""' <<<"$labels")" == "false" ]]; then
        log "HTTP route disabled for $container_name by gateway.enable=false."
        continue
    fi

    slug="$(printf '%s' "$container_name" |
        tr '[:upper:]' '[:lower:]' |
        sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//')"
    [[ -n "$slug" ]] || continue
    if [[ -n "${USED_DOMAINS[$slug]:-}" ]]; then
        slug="${slug}-${container_id:0:8}"
    fi
    USED_DOMAINS["$slug"]=1
    route_domain="$slug.$DOMAIN"

    port="$(jq -r '."gateway.http.port" // ""' <<<"$labels")"
    if [[ -z "$port" ]]; then
        port="${PORT_OVERRIDES[$container_name]:-}"
    fi

    scheme="$(jq -r '."gateway.http.scheme" // "http"' <<<"$labels")"
    if [[ -z "$port" ]]; then
        while IFS= read -r exposed_port; do
            [[ "$exposed_port" == */tcp ]] || continue
            candidate_port="${exposed_port%/tcp}"
            [[ "$candidate_port" =~ ^[0-9]+$ ]] || continue
            if ! is_non_http_port "$candidate_port"; then
                port="$candidate_port"
                break
            fi
        done < <(jq -r '.[0].Config.ExposedPorts // {} | keys[]?' <<<"$inspect")
    fi

    if [[ -z "$port" ]]; then
        continue
    fi
    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        warn "Invalid HTTP port for $container_name: $port"
        continue
    fi
    port=$((10#$port))
    if (( port < 1 || port > 65535 )); then
        warn "Invalid HTTP port for $container_name: $port"
        continue
    fi
    if [[ "$scheme" == "http" && ( "$port" == "443" || "$port" == "8443" ) ]]; then
        scheme="https"
    fi
    if [[ "$scheme" != "http" && "$scheme" != "https" ]]; then
        warn "Invalid upstream scheme for $container_name: $scheme"
        continue
    fi

    ACTIVE_DOMAINS["$route_domain"]=1
    payload="$(jq -n \
        --arg domain "$route_domain" \
        --arg scheme "$scheme" \
        --arg container "$container_name" \
        --argjson port "$port" \
        --arg marker "$MANAGED_MARKER" \
        --argjson certificate_id "$certificate_id" \
        '{
            domain_names: [$domain],
            forward_scheme: $scheme,
            forward_host: $container,
            forward_port: $port,
            access_list_id: 0,
            certificate_id: $certificate_id,
            ssl_forced: ($certificate_id > 0),
            caching_enabled: false,
            block_exploits: false,
            allow_websocket_upgrade: true,
            http2_support: ($certificate_id > 0),
            advanced_config: $marker,
            locations: []
        }')"

    matching_host="$(jq -c --arg domain "$route_domain" \
        '[.[] | select(any(.domain_names[]?; . == $domain))] | .[0] // empty' \
        <<<"$existing_hosts")"
    if [[ -n "$matching_host" ]]; then
        host_id="$(jq -r '.id' <<<"$matching_host")"
        if [[ "$(jq -r '.advanced_config // ""' <<<"$matching_host")" != "$MANAGED_MARKER" ]]; then
            warn "$route_domain already exists as a manually managed NPM Proxy Host; leaving it unchanged."
            continue
        fi
        response="$(api_request PUT "/nginx/proxy-hosts/$host_id" "$payload")" || {
            warn "Could not update Proxy Host $route_domain."
            continue
        }
        if (( certificate_id > 0 )); then
            public_scheme="https"
        else
            public_scheme="http"
        fi
        log "Updated $public_scheme://$route_domain -> $scheme://$container_name:$port (host ID $host_id)."
    else
        response="$(api_request POST /nginx/proxy-hosts "$payload")" || {
            warn "Could not create Proxy Host $route_domain."
            continue
        }
        host_id="$(jq -r '.id // "unknown"' <<<"$response")"
        if (( certificate_id > 0 )); then
            public_scheme="https"
        else
            public_scheme="http"
        fi
        log "Created $public_scheme://$route_domain -> $scheme://$container_name:$port (host ID $host_id)."
    fi
done < <(docker ps -q)

stale_hosts="$(jq -c --arg marker "$MANAGED_MARKER" \
    '[.[] | select((.advanced_config // "") == $marker)]' <<<"$existing_hosts")"
while IFS= read -r host; do
    [[ -n "$host" ]] || continue
    host_id="$(jq -r '.id' <<<"$host")"
    host_domains="$(jq -r '.domain_names | join(", ")' <<<"$host")"
    still_active=false
    while IFS= read -r domain; do
        if [[ -n "${ACTIVE_DOMAINS[$domain]:-}" ]]; then
            still_active=true
            break
        fi
    done < <(jq -r '.domain_names[]?' <<<"$host")
    if [[ "$still_active" != true ]]; then
        if api_request DELETE "/nginx/proxy-hosts/$host_id" >/dev/null; then
            log "Removed stale managed Proxy Host: $host_domains."
        else
            warn "Could not remove stale Proxy Host: $host_domains."
        fi
    fi
done < <(jq -c '.[]' <<<"$stale_hosts")
