# Apache Kafka

This directory deploys a single-node Apache Kafka broker using Docker Compose.
Kafka runs in KRaft mode, with the same node acting as both broker and
controller, so ZooKeeper is not required.

## Features

- Kafka broker for local development and lightweight workloads.
- KRaft-based metadata management without ZooKeeper.
- Persistent topic and metadata storage in a host directory.
- Configurable Kafka image, listener addresses, and published port.
- Docker health check for the Kafka listener.

> This is a single-node configuration. Replication factors are set to `1`, so
> it does not provide high availability or fault tolerance.

## Directory structure

```text
kafka/
├── README.md
├── .env.example
├── .env                 # Local configuration; create from .env.example
├── docker-compose.yaml
└── data/                # Kafka data; created when the container starts
```

Kafka stores its persistent data in `./data`, mounted to
`/var/lib/kafka/data` in the container. Keep this directory when recreating or
upgrading the container.

## Requirements

- Docker Engine.
- Docker Compose plugin (`docker compose`).
- An available host port, `9092` by default.

## Configure and deploy

Run these commands from the repository root.

### 1. Create the environment file

```bash
cp dockers/kafka/.env.example dockers/kafka/.env
```

Review `dockers/kafka/.env` before starting Kafka. Important settings:

| Variable | Purpose | Default |
| --- | --- | --- |
| `KAFKA_IMAGE` | Kafka container image | `apache/kafka-native:latest` |
| `KAFKA_PORT` | Host port mapped to Kafka port `9092` | `9092` |
| `KAFKA_NODE_ID` | KRaft node ID | `1` |
| `KAFKA_PROCESS_ROLES` | Roles assigned to this node | `broker,controller` |
| `KAFKA_LISTENERS` | Interfaces and ports Kafka listens on | `PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093` |
| `KAFKA_ADVERTISED_LISTENERS` | Broker address returned to clients | `PLAINTEXT://localhost:9092` |
| `KAFKA_CONTROLLER_QUORUM_VOTERS` | KRaft controller quorum members | `1@localhost:9093` |
| `CLUSTER_ID` | Persistent identity for the Kafka cluster | See `.env.example` |

Set `KAFKA_ADVERTISED_LISTENERS` to an address reachable by your Kafka clients.
For clients running on the same host, `PLAINTEXT://localhost:9092` is suitable.
For clients on another machine, use a hostname or IP address reachable from
that machine. If clients run in other containers, use a hostname resolvable on
their shared Docker network rather than `localhost`.

The controller listener on port `9093` is used internally by KRaft and is not
published to the host by this Compose file.

### 2. Start Kafka

```bash
docker compose -f dockers/kafka/docker-compose.yaml up -d
```

Check that the container is running and healthy:

```bash
docker compose -f dockers/kafka/docker-compose.yaml ps
docker compose -f dockers/kafka/docker-compose.yaml logs -f
```

Kafka is available to local clients at `localhost:9092` when using the default
advertised listener.

## Operations

Stop Kafka without deleting its data:

```bash
docker compose -f dockers/kafka/docker-compose.yaml down
```

Start it again:

```bash
docker compose -f dockers/kafka/docker-compose.yaml up -d
```

To apply environment changes, recreate the container:

```bash
docker compose -f dockers/kafka/docker-compose.yaml up -d --force-recreate
```

The `data/` directory is preserved by `docker compose down`. Back it up before
making changes to the cluster configuration or Kafka image.

## Security

The example configuration uses the `PLAINTEXT` listener and does not enable
authentication or transport encryption. Use it only on trusted networks.
Configure Kafka security and restrict network access before exposing the broker
to untrusted clients.
