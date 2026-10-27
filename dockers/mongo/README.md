# MongoDB

This directory deploys MongoDB as a single Docker Compose service. The
container publishes MongoDB on host port `27017` and persists database files
in the local `data/` directory.

## Files

```text
mongo/
├── docker-compose.yaml
├── .env                 # Local credentials; ignored by Git
└── data/                # MongoDB files; ignored by Git
```

## Configuration

Set the following variables in `.env`:

| Variable | Purpose |
| --- | --- |
| `MONGO_INITDB_ROOT_USERNAME` | Root administrator username |
| `MONGO_INITDB_ROOT_PASSWORD` | Root administrator password |

The Compose file currently uses the `mongo:latest` image, maps host port
`27017` to container port `27017`, and mounts `./data` at `/data/db`.

MongoDB applies the root username and password when initializing an empty data
directory. If `./data` already contains a database, changing these environment
variables does not update the existing MongoDB user's credentials.

## Start

Run from the repository root:

```bash
docker compose --env-file dockers/mongo/.env \
  -f dockers/mongo/docker-compose.yaml up -d
```

Check container status and logs:

```bash
docker compose --env-file dockers/mongo/.env \
  -f dockers/mongo/docker-compose.yaml ps
docker compose --env-file dockers/mongo/.env \
  -f dockers/mongo/docker-compose.yaml logs -f
```

## Connect

MongoDB is available from the host at `localhost:27017`. Authenticate the root
user against the `admin` authentication database:

```text
mongodb://<username>:<password>@localhost:27017/?authSource=admin
```

Replace the placeholders with the values configured in `.env`. Keep
credentials private and avoid placing them in shell history or shared logs.

## Stop and data

Stop the service without deleting its database files:

```bash
docker compose --env-file dockers/mongo/.env \
  -f dockers/mongo/docker-compose.yaml down
```

Database files are stored under `dockers/mongo/data/` and are ignored by Git.
Back up this directory regularly. Do not delete it or use a command that
removes volumes when you need to keep the database.
