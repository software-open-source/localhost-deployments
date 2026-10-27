# ZooNavigator

ZooNavigator is a web UI for browsing and managing ZooKeeper. It runs in its
own Docker Compose project and connects to the separately managed ZooKeeper
service through `host.docker.internal:2181`. The container uses host
networking because this Docker host does not allow bridge containers to reach
host-published ports through its bridge gateway. ZooNavigator still connects
to the published ZooKeeper host port; it does not depend on the ZooKeeper
container name or share its Docker bridge network.

## Configuration

The local `.env` controls the image, web server port, and ZooKeeper connection
preset. The image is `elkozmon/zoonavigator:latest`. On Linux, Compose maps
`host.docker.internal` to the Docker host gateway. Because ZooNavigator uses
host networking, `ZOONAVIGATOR_PORT` is the port it listens on directly on
the host.

To recreate a missing `.env`:

```bash
cp .env.example .env
```

## Start

From the repository root:

```bash
docker compose --env-file dockers/zoo-navigator/.env \
  -f dockers/zoo-navigator/docker-compose.yaml up -d
```

Open <http://localhost:9000> (or the configured `ZOONAVIGATOR_PORT`).
ZooNavigator is configured to connect automatically to the preset
DolphinScheduler ZooKeeper connection.

Check logs or stop the UI without affecting ZooKeeper:

```bash
docker compose --env-file dockers/zoo-navigator/.env \
  -f dockers/zoo-navigator/docker-compose.yaml logs -f
docker compose --env-file dockers/zoo-navigator/.env \
  -f dockers/zoo-navigator/docker-compose.yaml down
```
