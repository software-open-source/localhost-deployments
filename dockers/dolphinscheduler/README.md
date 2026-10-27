# Apache DolphinScheduler Standalone

This deployment runs the Apache DolphinScheduler standalone server as one
Docker container. It is intended for trying out DolphinScheduler and
lightweight standalone use; it is not the distributed multi-container
deployment.

The standalone image includes its own H2 database and does not connect to the
separate PostgreSQL or ZooKeeper deployments in this repository. No other
service is started by this Compose file.

## Files and data

```text
dolphinscheduler/
├── docker-compose.yaml
├── .env.example
├── .env                         # Local settings; ignored by Git
└── data/
    └── dolphinscheduler_data/   # Persistent application data and logs
```

Runtime files are bind-mounted under `./data/`, which is ignored by Git. Back
up this directory if the standalone instance contains data you need to keep.

## Configuration

The Compose file reads its settings from `.env`:

| Variable | Purpose | Current value |
| --- | --- | --- |
| `DOLPHINSCHEDULER_VERSION` | Standalone Docker image tag | `latest` |
| `DS_WEB_PORT` | Host port for the Web UI and API | `12345` |
| `DS_GRPC_PORT` | Host port for gRPC | `25333` |
| `DS_DATA_DIR` | Host directory for persistent files and logs | `./data/dolphinscheduler_data` |

If `.env` is missing, create it from the example:

```bash
cp dockers/dolphinscheduler/.env.example dockers/dolphinscheduler/.env
```

Change the host ports in `.env` if either default port is already in use. The
container listens on ports `12345` and `25333`; the corresponding host ports
are configurable.

## Start

Run from the repository root:

```bash
docker compose --env-file dockers/dolphinscheduler/.env \
  -f dockers/dolphinscheduler/docker-compose.yaml up -d
```

Docker downloads the configured image tag if it is not present locally. Open
the Web UI at <http://localhost:12345/dolphinscheduler/ui> after the
application has finished starting.

Check container status and logs:

```bash
docker compose --env-file dockers/dolphinscheduler/.env \
  -f dockers/dolphinscheduler/docker-compose.yaml ps
docker compose --env-file dockers/dolphinscheduler/.env \
  -f dockers/dolphinscheduler/docker-compose.yaml logs -f
```

## Stop and update

Stop the container without deleting its bind-mounted data:

```bash
docker compose --env-file dockers/dolphinscheduler/.env \
  -f dockers/dolphinscheduler/docker-compose.yaml down
```

To update the image, change `DOLPHINSCHEDULER_VERSION` in `.env`, then pull
and recreate the container:

```bash
docker compose --env-file dockers/dolphinscheduler/.env \
  -f dockers/dolphinscheduler/docker-compose.yaml pull
docker compose --env-file dockers/dolphinscheduler/.env \
  -f dockers/dolphinscheduler/docker-compose.yaml up -d
```

Avoid `down -v` when you want to preserve the deployment data. The `latest`
tag can change over time; for repeatable deployments, set
`DOLPHINSCHEDULER_VERSION` to a specific image version.

## References

- [Apache DolphinScheduler Docker deployment guide](https://dolphinscheduler.apache.org/en-us/docs/3.4.3/guide/start/docker)
- [DolphinScheduler standalone server image](https://hub.docker.com/r/apache/dolphinscheduler-standalone-server)