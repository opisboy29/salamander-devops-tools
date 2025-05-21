#!/bin/bash

# Load environment variables from .env file if exists
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# Check if required environment variables are set
: "${SRC_POSTGRES_CONTAINER:?Need to set SRC_POSTGRES_CONTAINER}"
: "${SRC_POSTGRES_USER:?Need to set SRC_POSTGRES_USER}"
: "${SRC_POSTGRES_DB:?Need to set SRC_POSTGRES_DB}"
: "${SRC_SERVER_IP:?Need to set SRC_SERVER_IP}"
: "${SRC_SERVER_USERNAME:?Need to set SRC_SERVER_USERNAME}"
: "${DST_POSTGRES_CONTAINER:?Need to set DST_POSTGRES_CONTAINER}"
: "${DST_POSTGRES_USER:?Need to set DST_POSTGRES_USER}"
: "${DST_POSTGRES_DB:?Need to set DST_POSTGRES_DB}"
: "${DST_SERVER_IP:?Need to set DST_SERVER_IP}"
: "${DST_SERVER_USERNAME:?Need to set DST_SERVER_USERNAME}"
: "${SRC_POSTGRES_PASSWORD:?Need to set SRC_POSTGRES_PASSWORD}"

# Set date for temporary file naming
DATE=$(date +"%Y%m%d%H%M")

# Temporary dump file
TEMP_DUMP_FILE="/tmp/${SRC_POSTGRES_DB}_$DATE.dump"

# Function to validate SSH connection
validate_ssh_connection() {
  local server_ip=$1
  local server_username=$2

  echo "Validating SSH connection to $server_username@$server_ip..."
  ssh -o BatchMode=yes "$server_username@$server_ip" exit
  if [ $? -ne 0 ]; then
    echo "Error: Unable to connect to $server_username@$server_ip using SSH key."
    exit 1
  fi
  echo "SSH connection validated."
}

# Step 1: Validate SSH connections
validate_ssh_connection "$SRC_SERVER_IP" "$SRC_SERVER_USERNAME"
validate_ssh_connection "$DST_SERVER_IP" "$DST_SERVER_USERNAME"

# Step 2: Export database from the source using SSH batch
echo "Exporting database ($SRC_POSTGRES_DB) from source server ($SRC_SERVER_IP)..."
ssh "$SRC_SERVER_USERNAME@$SRC_SERVER_IP" "docker exec $SRC_POSTGRES_CONTAINER bash -c 'export PGPASSWORD=$SRC_POSTGRES_PASSWORD && pg_dump -U $SRC_POSTGRES_USER -h 127.0.0.1 -F c -b -v -f /tmp/${SRC_POSTGRES_DB}.dump $SRC_POSTGRES_DB'"

# Copy the dump file from container to the server source
ssh "$SRC_SERVER_USERNAME@$SRC_SERVER_IP" "docker cp $SRC_POSTGRES_CONTAINER:/tmp/${SRC_POSTGRES_DB}.dump /tmp/${SRC_POSTGRES_DB}.dump"

# Transfer the dump file from the server source to the host
scp "$SRC_SERVER_USERNAME@$SRC_SERVER_IP:/tmp/${SRC_POSTGRES_DB}.dump" "$TEMP_DUMP_FILE"

if [ ! -f "$TEMP_DUMP_FILE" ]; then
    echo "Error: Failed to retrieve dump file from source server!"
    ssh "$SRC_SERVER_USERNAME@$SRC_SERVER_IP" "rm -f /tmp/${SRC_POSTGRES_DB}.dump"  # Cleanup on source server
    exit 1
fi

# Step 3: Transfer dump file to the destination server using scp
echo "Transferring dump file to destination server ($DST_SERVER_IP)..."
scp "$TEMP_DUMP_FILE" "$DST_SERVER_USERNAME@$DST_SERVER_IP:$TEMP_DUMP_FILE"

# Step 4: Configure and import database to the destination using SSH batch
echo "Importing database ($DST_POSTGRES_DB) to destination server ($DST_SERVER_IP)..."
ssh "$DST_SERVER_USERNAME@$DST_SERVER_IP" <<EOF
  docker cp $TEMP_DUMP_FILE $DST_POSTGRES_CONTAINER:/tmp/${SRC_POSTGRES_DB}.dump
  docker exec $DST_POSTGRES_CONTAINER psql -U $DST_POSTGRES_USER -c "DROP DATABASE IF EXISTS $DST_POSTGRES_DB;"
  docker exec $DST_POSTGRES_CONTAINER psql -U $DST_POSTGRES_USER -c "CREATE DATABASE $DST_POSTGRES_DB;"
  docker exec $DST_POSTGRES_CONTAINER pg_restore -U $DST_POSTGRES_USER -d $DST_POSTGRES_DB -v /tmp/${SRC_POSTGRES_DB}.dump
EOF

if [ $? -ne 0 ]; then
    echo "Error: Failed to import database to destination server!"
    ssh "$SRC_SERVER_USERNAME@$SRC_SERVER_IP" "rm -f /tmp/${SRC_POSTGRES_DB}.dump"  # Cleanup on source server
    exit 1
fi

# Cleanup temporary files
echo "Cleaning up temporary files..."
ssh "$SRC_SERVER_USERNAME@$SRC_SERVER_IP" "rm -f /tmp/${SRC_POSTGRES_DB}.dump"  # Cleanup on source server
ssh "$DST_SERVER_USERNAME@$DST_SERVER_IP" "docker exec $DST_POSTGRES_CONTAINER rm -f /tmp/${SRC_POSTGRES_DB}.dump"  # Cleanup on destination container
rm -f "$TEMP_DUMP_FILE"  # Cleanup on host

echo "Database migration completed successfully from $SRC_POSTGRES_DB@$SRC_SERVER_IP to $DST_POSTGRES_DB@$DST_SERVER_IP." 