#!/bin/bash

# Terminal colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🚀 Starting OpenTodo setup...${NC}"

# 1. Create the data directory if it does not exist
DATA_DIR="./opentodo-data"
if [ ! -d "$DATA_DIR" ]; then
    echo -e "${YELLOW}📁 Creating directory $DATA_DIR...${NC}"
    mkdir -p "$DATA_DIR"
fi

# 2. Set directory ownership to UID 65532 (the default OpenTodo container user)
echo -e "${YELLOW}🔑 Granting the container (UID 65532) write access to the data directory...${NC}"
sudo chown -R 65532:65532 "$DATA_DIR"

# 3. Create docker-compose.yml if it does not exist
COMPOSE_FILE="docker-compose.yml"
if [ ! -f "$COMPOSE_FILE" ]; then
    echo -e "${YELLOW}⚙️ Creating $COMPOSE_FILE...${NC}"
    cat << 'EOF' > "$COMPOSE_FILE"
services:
  opentodo:
    image: ghcr.io/pixari/opentodo:latest
    container_name: opentodo
    restart: unless-stopped
    ports:
      - "9004:8080"
    volumes:
      - ./opentodo-data:/data
    healthcheck:
      test: ["CMD", "/opentodo", "healthcheck"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF
    echo -e "${GREEN}✅ Successfully created $COMPOSE_FILE.${NC}"
else
    echo -e "${GREEN}✅ $COMPOSE_FILE already exists; skipping creation.${NC}"
fi

# 4. Start the container
echo -e "${YELLOW}🐳 Starting OpenTodo...${NC}"
docker compose up -d

# 5. Check the container status
echo -e "\n${YELLOW}📊 Container status:${NC}"
docker compose ps

echo -e "\n${GREEN}🎉 Done! OpenTodo is ready.${NC}"
echo -e "🌐 Open: ${GREEN}http://localhost:9004${NC}"
echo -e "💡 To view logs, run: ${YELLOW}docker compose logs -f${NC}"