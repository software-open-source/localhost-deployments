# Memos

Memos is a self-hosted note-taking application for capturing and organizing
notes in a personal timeline. This Compose deployment runs one Memos container
with SQLite storage.

## Files and persistence

```text
memos/
├── docker-compose.yaml
├── .env.example
├── .env             # Local configuration; ignored by Git
└── data/            # SQLite database and local assets; ignored by Git
```

The `./data` directory is mounted to the container's `MEMOS_DATA` path
(`/var/opt/memos` by default). Back up this directory to preserve the database
and uploaded assets.

## Configuration

The Compose file reads all application and port settings from `.env`:

| Variable | Purpose | Default |
| --- | --- | --- |
| `MEMOS_HOST_PORT` | Host port published for the web interface | `5230` |
| `MEMOS_PORT` | HTTP listen port inside the container | `5230` |
| `MEMOS_DATA` | Memos data directory inside the container | `/var/opt/memos` |
| `MEMOS_DRIVER` | Database backend | `sqlite` |
| `MEMOS_INSTANCE_URL` | Canonical URL used by Memos | `http://localhost:5230` |

To restore a missing local `.env`:

```bash
cp .env.example .env
```

If changing `MEMOS_HOST_PORT`, update `MEMOS_INSTANCE_URL` to the URL used to
open Memos. The default URL is intended for local access. If exposing the
service through a reverse proxy or public hostname, set the canonical
`https://` URL and review the instance access policy in Memos settings.

SQLite is stored as `memos_prod.db` beneath `MEMOS_DATA`. This standalone
deployment does not start or depend on an external database.

## Start

Run these commands from the repository root:

```bash
docker compose --env-file dockers/memos/.env \
  -f dockers/memos/docker-compose.yaml up -d
```

Open <http://localhost:5230> and create the initial account.

Check status and logs:

```bash
docker compose --env-file dockers/memos/.env \
  -f dockers/memos/docker-compose.yaml ps
docker compose --env-file dockers/memos/.env \
  -f dockers/memos/docker-compose.yaml logs -f
```

## Stop and update

Stop the container without removing its bind-mounted data:

```bash
docker compose --env-file dockers/memos/.env \
  -f dockers/memos/docker-compose.yaml down
```

To update, pull the configured image and recreate the container:

```bash
docker compose --env-file dockers/memos/.env \
  -f dockers/memos/docker-compose.yaml pull
docker compose --env-file dockers/memos/.env \
  -f dockers/memos/docker-compose.yaml up -d
```

Avoid `down -v` when preserving data. The image tag is `stable`; keep a backup
of `./data` before upgrading.

## References

- [Memos Docker deployment guide](https://usememos.com/docs/deploy/docker)
- [Memos environment variable reference](https://usememos.com/docs/configuration/environment-variables)
