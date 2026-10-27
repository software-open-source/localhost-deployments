# Beszel

Beszel is a lightweight server monitoring platform. It consists of a central
Hub for the web interface and one or more Agents that collect metrics from
monitored hosts.

This directory contains separate Docker Compose deployments for the Hub and
the NVIDIA-enabled Agent.

## Features

- Monitor host CPU, memory, disk, and network usage.
- Monitor NVIDIA GPU metrics with the NVIDIA Agent image.
- Inspect Docker containers and view their logs from the Hub.
- Keep Hub data and Agent identity data in persistent local directories.
- Connect Agents to the Hub over WebSocket.

## Directory structure

```text
beszel/
├── README.md
├── beszel-hub/
│   ├── .env.example
│   ├── docker-compose.yaml
│   └── data/                 # Created when the Hub starts
└── beszel-agent/
    ├── .env.example
    ├── docker-compose.yaml
    └── data/
        └── beszel_agent_data/ # Created when the Agent starts
```

The Hub database and configuration are stored in `beszel-hub/data/`. The
Agent's persistent fingerprint is stored in
`beszel-agent/data/beszel_agent_data/`.

## Requirements

- Docker Engine and the Docker Compose plugin.
- A Linux host for the supplied Agent configuration (`network_mode: host`).
- For NVIDIA GPU monitoring, an NVIDIA GPU and the NVIDIA Container Toolkit
  configured for Docker.

The Agent reports CPU, memory, disk, and network metrics by default. The
provided Compose file uses the NVIDIA-specific Agent image and configures
`nvidia-smi` as the GPU collector.

## Configure and deploy

Run the following commands from the repository root.

### 1. Configure the Hub

```bash
cp dockers/beszel/beszel-hub/.env.example dockers/beszel/beszel-hub/.env
```

Edit `dockers/beszel/beszel-hub/.env` if needed:

| Variable | Purpose | Default |
| --- | --- | --- |
| `APP_URL` | Hub URL used in links and notifications | `http://localhost:8090` |
| `HUB_PORT` | Host port published for the Hub | `8090` |
| `CONTAINER_DETAILS` | Enables container details and log viewing | `true` |
| `HUB_DATA_DIR` | Host directory for persistent Hub data | `./data/beszel_data` |

Start the Hub:

```bash
docker compose \
  -f dockers/beszel/beszel-hub/docker-compose.yaml \
  up -d
```

Open the Hub at <http://localhost:8090>. Add a system in the Hub and use the
Agent configuration it provides to obtain the system's `TOKEN` and public
`KEY`.

### 2. Configure the Agent

Copy the example and edit the credentials using the values supplied by the
Hub:

```bash
cp dockers/beszel/beszel-agent/.env.example dockers/beszel/beszel-agent/.env
```

| Variable | Purpose | Default |
| --- | --- | --- |
| `LISTEN` | Port used by the Agent's SSH listener | `45876` |
| `HUB_URL` | URL of the Hub, reachable from the Agent host | `http://localhost:8090` |
| `BESZEL_TOKEN` | Agent registration token from the Hub | Set this value |
| `BESZEL_KEY` | Public key from the Hub | Set this value |
| `GPU_COLLECTOR` | GPU metric collector | `nvidia-smi` |
| `AGENT_DATA_DIR` | Host directory for Agent identity data | `./data/beszel_agent_data` |
| `DOCKER_SOCKET` | Docker daemon socket on the Agent host | `/var/run/docker.sock` |

`HUB_URL` must be reachable from the machine running the Agent. If the Hub is
on another host, replace `localhost` with that host's address or DNS name.

Start the Agent:

```bash
docker compose \
  -f dockers/beszel/beszel-agent/docker-compose.yaml \
  up -d
```

The Agent uses host networking, so its configured Hub URL must resolve from the
host. Its data directory is mounted persistently so its fingerprint survives
container recreation.

## Viewing Docker container logs

The Agent mounts `DOCKER_SOCKET` as `/var/run/docker.sock` inside the
container. The Hub has `CONTAINER_DETAILS=true` by default. In the Hub, open a
system, select a container, and use its details/logs view.

Access to the Docker socket grants powerful access to the Docker daemon.
Protect the Agent host and its Hub credentials accordingly. The `:ro` mount
does not make Docker API operations read-only.

## Operations

View service status:

```bash
docker compose -f dockers/beszel/beszel-hub/docker-compose.yaml ps
docker compose -f dockers/beszel/beszel-agent/docker-compose.yaml ps
```

View logs:

```bash
docker compose -f dockers/beszel/beszel-hub/docker-compose.yaml logs -f
docker compose -f dockers/beszel/beszel-agent/docker-compose.yaml logs -f
```

After changing an environment file, recreate the affected service to apply the
new settings:

```bash
docker compose -f dockers/beszel/beszel-agent/docker-compose.yaml up -d
```

Do not commit `.env` files containing real credentials. Keep the `.env.example`
files as templates with placeholders.
