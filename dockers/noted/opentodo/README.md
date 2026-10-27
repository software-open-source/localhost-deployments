# OpenTodo

OpenTodo is a self-hosted to-do application for planning daily work, organizing
projects, setting reminders, and sharing lists with family or a team. It works
on desktop and mobile devices and supports offline use.

This directory deploys OpenTodo as a single Docker Compose service. Application
data is stored in a local directory, so it persists when the container is
recreated.

## Features

- Manage tasks and plan your day.
- Organize tasks into projects and lists.
- Set reminders and share lists.
- Use the app on desktop and mobile, including offline.
- Self-host your data without a separate database service.

See the [OpenTodo website](https://noted.lol/opentodo) and
[upstream project](https://github.com/pixari/opentodo) for more information.

## Directory structure

```text
opentodo/
├── README.md
├── docker-compose.yaml
├── start.sh
└── data/                # Persistent application data; created on startup
```

The Compose file mounts `./data` on the host to `/data` in the container.
Back up this directory to preserve application data.

## Requirements

- Docker Engine.
- Docker Compose plugin (`docker compose`).
- Host port `9004` available.

## Deploy with Docker Compose

From the repository root, start OpenTodo:

```bash
docker compose -f dockers/noted/opentodo/docker-compose.yaml up -d
```

Check the service status and logs:

```bash
docker compose -f dockers/noted/opentodo/docker-compose.yaml ps
docker compose -f dockers/noted/opentodo/docker-compose.yaml logs -f opentodo
```

Open <http://localhost:9004>. The first visit creates your account.

The current Compose configuration uses the `ghcr.io/pixari/opentodo:latest`
image, maps host port `9004` to container port `8080`, mounts `./data` at
`/data`, and includes a health check.

## Operations

Stop the service without removing its data:

```bash
docker compose -f dockers/noted/opentodo/docker-compose.yaml down
```

Start it again:

```bash
docker compose -f dockers/noted/opentodo/docker-compose.yaml up -d
```

Follow application logs:

```bash
docker compose -f dockers/noted/opentodo/docker-compose.yaml logs -f
```

Do not delete the `data/` directory unless you intend to remove the persisted
application data.

## Note about `start.sh`

The provided `start.sh` is a legacy setup helper. It uses a different data
directory (`opentodo-data`) and can generate a separate `docker-compose.yml`,
while the tracked Compose file uses `data/` and is named
`docker-compose.yaml`. Use the Compose commands above to deploy the
configuration documented here.
