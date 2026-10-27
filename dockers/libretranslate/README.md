# LibreTranslate

LibreTranslate is a free and open-source machine translation API. This
deployment runs LibreTranslate in Docker with the CUDA-enabled image and
persistent storage for API keys and translation models.

## Features

- Self-hosted translation API and web interface.
- English-to-Vietnamese and Vietnamese-to-English language pairs enabled.
- API key authentication.
- NVIDIA GPU acceleration through the CUDA image.
- Persistent API key database and translation models.

## Directory structure

```text
libretranslate/
├── README.md
├── docker-compose.yaml
└── data/
    ├── db/       # Persistent API key database
    └── models/   # Downloaded Argos Translate models
```

The `data/` directory is bind-mounted into the container so API keys and
downloaded models persist when the container is recreated.

## Requirements

- Docker Engine and Docker Compose plugin.
- An NVIDIA GPU and NVIDIA Container Toolkit configured for Docker.
- Host port `5000` available.

The Compose file uses `libretranslate/libretranslate:latest-cuda` and reserves
one NVIDIA GPU. For a host without a supported NVIDIA GPU, change the image to
the non-CUDA LibreTranslate image and remove the GPU device reservation.

## Deploy with Docker Compose

From the repository root, start LibreTranslate:

```bash
docker compose -f dockers/libretranslate/docker-compose.yaml up -d
```

Check the service and follow its logs:

```bash
docker compose -f dockers/libretranslate/docker-compose.yaml ps
docker compose -f dockers/libretranslate/docker-compose.yaml logs -f libretranslate
```

The web interface and API are available at <http://localhost:5000>.

## API keys

The service is configured to require API keys. Create a key with `ltmanage`:

```bash
docker exec -it libretranslate ltmanage keys add 5000
```

List the keys:

```bash
docker exec -it libretranslate ltmanage keys
```

Keep generated API keys private. The key database is persisted in
`data/db/api_keys.db`.

## Test the translation API

Replace `YOUR_API_KEY_HERE` with a key created above:

```bash
curl -X POST http://localhost:5000/translate \
  -H "Content-Type: application/json" \
  -H "api_key: YOUR_API_KEY_HERE" \
  -d '{"q": "Hello world", "source": "en", "target": "vi"}'
```

## Configuration

The current Compose file sets these LibreTranslate environment variables:

| Variable | Purpose | Current value |
| --- | --- | --- |
| `ARGOS_LANGUAGE_PAIRS` | Translation directions to install/use | `vi-en,en-vi` |
| `BACKEND` | Translation backend | `argos` |
| `LT_API_KEYS` | Require API keys for API requests | `true` |
| `LT_API_KEYS_DB_PATH` | API key database location in the container | `/app/db/api_keys.db` |
| `LT_REQ_LIMIT` | Request limit setting | `5000` |
| `LT_UPDATE_MODELS` | Allow model updates | `true` |
| `LT_DEBUG` | Enable debug mode | `true` |

Review the LibreTranslate documentation before changing these values. Disable
debug mode when running in a production environment.

## Operations

Stop the service while preserving data:

```bash
docker compose -f dockers/libretranslate/docker-compose.yaml down
```

Restart it:

```bash
docker compose -f dockers/libretranslate/docker-compose.yaml up -d
```

Do not delete `data/` unless you intend to remove the API key database and
downloaded translation models.

## Security

The Compose file publishes port `5000` on the host. Restrict access using a
firewall or reverse proxy if the service should not be publicly reachable.
Keep API keys secret, and avoid exposing the service with debug mode enabled.
