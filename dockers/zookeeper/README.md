# ZooKeeper

This directory contains one Docker Compose service for Apache ZooKeeper. It is
deployed independently from DolphinScheduler and any other Compose project.
The container publishes ZooKeeper's client port from the Docker host and
stores its persistent data under `./data/`.

DolphinScheduler services connect to ZooKeeper through the Docker host at
`host.docker.internal:2181`; they do not connect to this container by its
container name or through a shared Compose network.

## Files

```text
zookeeper/
├── docker-compose.yaml
├── .env.example
├── .env                 # Local settings; ignored by Git
└── data/                # Persistent ZooKeeper data; ignored by Git
```

## Configuration

The local `.env` defines every variable consumed by the Compose file:

- `ZOOKEEPER_IMAGE`: ZooKeeper container image and version.
- `ZOOKEEPER_PORT`: host port published for ZooKeeper's client connection
  port (`2181` inside the container).
- `ZOOKEEPER_ALLOW_ANONYMOUS_LOGIN`: allows DolphinScheduler to connect
  without ZooKeeper credentials.
- `ZOOKEEPER_4LW_COMMANDS_WHITELIST`: four-letter commands allowed by the
  image, including the commands used for health checks.
- `TZ`: container timezone.

To recreate a missing `.env`, copy the template:

```bash
cp .env.example .env
```

This deployment enables anonymous ZooKeeper access for DolphinScheduler.
The published port is reachable through the Docker host; restrict access to it
with the host firewall to trusted systems.

## Start and manage

Run these commands from the repository root:

```bash
docker compose --env-file dockers/zookeeper/.env \
  -f dockers/zookeeper/docker-compose.yaml up -d
```

Check its state and logs:

```bash
docker compose --env-file dockers/zookeeper/.env \
  -f dockers/zookeeper/docker-compose.yaml ps
docker compose --env-file dockers/zookeeper/.env \
  -f dockers/zookeeper/docker-compose.yaml logs -f
```

Stop ZooKeeper without deleting its data:

```bash
docker compose --env-file dockers/zookeeper/.env \
  -f dockers/zookeeper/docker-compose.yaml down
```

The service listens on host port `ZOOKEEPER_PORT` (default `2181`). Its
persistent data is stored in `dockers/zookeeper/data/zookeeper/`; back up that
directory before making changes to the deployment. Do not use `down -v` when
you intend to preserve the service data.
