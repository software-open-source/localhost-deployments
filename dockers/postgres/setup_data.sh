#!/usr/bin/env bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get current user information
CURRENT_USER=$(whoami)
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

DATA_DIR="./data"

echo -e "${YELLOW}=== Setup PostgreSQL Data Directory ===${NC}"
echo -e "User: ${GREEN}${CURRENT_USER}${NC} (UID: ${CURRENT_UID}, GID: ${CURRENT_GID})"
echo -e "Directory: ${GREEN}${DATA_DIR}${NC}"
echo ""

# 1. Stop running containers
echo -e "${YELLOW}[1/5] Stopping containers with 'docker compose down'...${NC}"
docker compose down
if [ $? -ne 0 ]; then
  echo -e "${RED}✗ Failed to stop containers${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Containers stopped${NC}"
echo ""

# 2. Remove old data directory if it exists
if [ -d "$DATA_DIR" ]; then
  echo -e "${YELLOW}[2/5] Removing old data directory...${NC}"
  sudo rm -rf "$DATA_DIR"
  echo -e "${GREEN}✓ Old data directory removed${NC}"
else
  echo -e "${BLUE}[2/5] No existing data directory found, skipping removal${NC}"
fi
echo ""

# 3. Create new data directory with 777 permissions for Docker
echo -e "${YELLOW}[3/5] Creating new data directory with 777 permissions...${NC}"
mkdir -p "$DATA_DIR"
chmod 777 "$DATA_DIR"
echo -e "${GREEN}✓ Data directory created${NC}"
echo ""

# 4. Start containers to let PostgreSQL initialize data
echo -e "${YELLOW}[4/5] Starting containers with 'docker compose up -d'...${NC}"
docker compose up -d
if [ $? -ne 0 ]; then
  echo -e "${RED}✗ Failed to start containers${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Containers started${NC}"
echo ""

# 5. Wait for PostgreSQL to finish initialization
echo -e "${YELLOW}[5/5] Waiting for PostgreSQL to initialize (10 seconds)...${NC}"
sleep 10

# Check if container is running
if docker compose ps | grep -q "Up"; then
  echo -e "${GREEN}✓ PostgreSQL container is running${NC}"
else
  echo -e "${RED}✗ PostgreSQL container is not running. Check logs with 'docker compose logs'${NC}"
  exit 1
fi
echo ""

# Check results
echo -e "${GREEN}=== Completed! ===${NC}"
echo "Directory details:"
ls -ld "$DATA_DIR"
echo ""
echo "Files in data directory:"
ls -la "$DATA_DIR"
echo ""

# Test if it is writable
if [ -w "$DATA_DIR" ]; then
  echo -e "${GREEN}✓ Directory is writable${NC}"
else
  echo -e "${RED} Directory is NOT writable${NC}"
  exit 1
fi

echo ""
echo -e "${GREEN}Setup complete! PostgreSQL is running with data in ${DATA_DIR}${NC}"
