# PostgreSQL

This directory contains a single PostgreSQL server deployed with Docker
Compose. It publishes PostgreSQL on host port `5432` and stores the database
cluster in a persistent local directory.

## Features

- PostgreSQL database server using the official `postgres` image.
- Persistent database files in `./data`.
- Configurable initial database user and password.
- UTC timezone configured for the container.
- A dedicated Docker bridge network for the service.

## Directory structure

```text
postgres/
├── README.md
├── .env.example       # Environment variable template
├── .env               # Local credentials; create from .env.example
├── docker-compose.yaml
├── postgresql.conf    # Configuration reference; not mounted by this Compose file
├── setup_data.sh     # Data directory setup script; see warning below
└── data/              # Persistent PostgreSQL database files
```

The Compose file bind-mounts `./data` to `/var/lib/postgresql` in the
container. Keep this directory to preserve databases across container
recreation and upgrades. Do not delete it unless you intend to remove the
database cluster.

## Requirements

- Docker Engine.
- Docker Compose plugin (`docker compose`).
- An available host port `5432`, or update the port mapping in
  `docker-compose.yaml`.

## Configure and deploy

Run these commands from this directory:

```bash
cd dockers/postgres
cp .env.example .env
```

Edit `.env` and set a strong password:

| Variable | Purpose | Example value |
| --- | --- | --- |
| `POSTGRES_USER` | Initial PostgreSQL superuser name | `postgres` |
| `POSTGRES_PASSWORD` | Password for the initial superuser | Set a strong, unique password |

Start PostgreSQL:

```bash
docker compose up -d
```

Check service status and startup logs:

```bash
docker compose ps
docker compose logs -f postgres
```

The server listens on port `5432`. Connect from the host with:

```bash
psql -h localhost -p 5432 -U postgres
```

Replace `postgres` with the value of `POSTGRES_USER` if you changed it. Other
containers can connect using the host's reachable address and port `5432`.

## Operations

Stop the container while preserving database files:

```bash
docker compose down
```

Start it again:

```bash
docker compose up -d
```

The `POSTGRES_USER` and `POSTGRES_PASSWORD` variables initialize a new,
empty data directory. Changing them in `.env` does not change users or
passwords in an already initialized database; update existing database roles
using PostgreSQL tools instead.

## Configuration and data safety

The supplied `postgresql.conf` is not mounted by `docker-compose.yaml`, so its
settings are not applied to the running container. To use it, first configure
an explicit read-only mount and a PostgreSQL `config_file` startup argument,
then validate the configuration before restarting the service.

Do not run `setup_data.sh` unless you have reviewed it and intentionally want
to remove the existing `data/` directory: the script stops Compose and
recursively deletes `./data` before recreating it.

The Compose file publishes port `5432` on the host and uses plaintext database
connections. Restrict network access with the host firewall and do not expose
the service to untrusted networks without configuring appropriate PostgreSQL
authentication and transport security.

Do not commit `.env` files containing real credentials. Keep `.env.example`
as a template and use a unique password outside local development.
