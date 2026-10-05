#!/bin/bash
# Host to Remote MinIO Container Migration Script
# Migrates data from host folder on Server A to MinIO bucket in container on Server B

# Load environment variables from .env file if exists
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# Default values
SOURCE_FOLDER=${SOURCE_FOLDER:-"/tmp/data"}
BUCKET_NAME=${BUCKET_NAME:-"migrated-data"}
REMOTE_SERVER=${REMOTE_SERVER:-""}
REMOTE_USER=${REMOTE_USER:-""}
CONTAINER_ID=${CONTAINER_ID:-"minio"}
MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY:-"minioadmin"}
MINIO_SECRET_KEY=${MINIO_SECRET_KEY:-"minioadmin"}
MINIO_HOST=${MINIO_HOST:-"localhost"}
MINIO_PORT=${MINIO_PORT:-"9000"}

# Function to display usage
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo "Options:"
  echo "  -s, --source PATH      Source folder path (default: /tmp/data)"
  echo "  -b, --bucket NAME      Bucket name (default: migrated-data)"
  echo "  -r, --remote HOST      Remote server hostname/IP"
  echo "  -u, --user USER        SSH username for remote server"
  echo "  -c, --container ID     MinIO container ID on remote server (default: minio)"
  echo "  -h, --host HOST        MinIO host on remote server (default: localhost)"
  echo "  -p, --port PORT        MinIO port on remote server (default: 9000)"
  echo "  -a, --access KEY       MinIO access key (default: minioadmin)"
  echo "  -k, --secret KEY       MinIO secret key (default: minioadmin)"
  echo "  --help                 Show this help message"
  echo ""
  echo "Environment variables:"
  echo "  SOURCE_FOLDER, BUCKET_NAME, REMOTE_SERVER, REMOTE_USER, CONTAINER_ID"
  echo "  MINIO_HOST, MINIO_PORT, MINIO_ACCESS_KEY, MINIO_SECRET_KEY"
  echo ""
  echo "Examples:"
  echo "  $0 -s /path/to/data -b my-bucket -r 192.168.1.100 -u admin -c minio-prod"
  echo "  SOURCE_FOLDER=/data BUCKET_NAME=uploads REMOTE_SERVER=prod.example.com $0"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -s|--source)
      SOURCE_FOLDER="$2"
      shift 2
      ;;
    -b|--bucket)
      BUCKET_NAME="$2"
      shift 2
      ;;
    -r|--remote)
      REMOTE_SERVER="$2"
      shift 2
      ;;
    -u|--user)
      REMOTE_USER="$2"
      shift 2
      ;;
    -c|--container)
      CONTAINER_ID="$2"
      shift 2
      ;;
    -h|--host)
      MINIO_HOST="$2"
      shift 2
      ;;
    -p|--port)
      MINIO_PORT="$2"
      shift 2
      ;;
    -a|--access)
      MINIO_ACCESS_KEY="$2"
      shift 2
      ;;
    -k|--secret)
      MINIO_SECRET_KEY="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

# Validate required parameters
if [ ! -d "$SOURCE_FOLDER" ]; then
  echo "ERROR: Source folder '$SOURCE_FOLDER' does not exist or is not a directory."
  exit 1
fi

if [ -z "$REMOTE_SERVER" ]; then
  echo "ERROR: Remote server is required. Use -r or set REMOTE_SERVER environment variable."
  exit 1
fi

if [ -z "$REMOTE_USER" ]; then
  echo "ERROR: Remote user is required. Use -u or set REMOTE_USER environment variable."
  exit 1
fi

if [ -z "$BUCKET_NAME" ]; then
  echo "ERROR: Bucket name is required."
  exit 1
fi

echo "=== HOST TO REMOTE MINIO MIGRATION ==="
echo "Source folder: $SOURCE_FOLDER"
echo "Target bucket: $BUCKET_NAME"
echo "Remote server: $REMOTE_USER@$REMOTE_SERVER"
echo "MinIO container: $CONTAINER_ID"
echo "MinIO endpoint: $MINIO_HOST:$MINIO_PORT"
echo "Process started at: $(date)"
echo ""

# Function for cleanup
cleanup() {
  echo ""
  echo "Cleaning up temporary files..."
  if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
    echo "Local temporary directory removed."
  fi
  
  # Clean up remote temporary files
  if [ -n "$REMOTE_SERVER" ] && [ -n "$REMOTE_USER" ]; then
    echo "Cleaning up remote temporary files..."
    ssh "$REMOTE_USER@$REMOTE_SERVER" "rm -rf /tmp/minio-migration-*" 2>/dev/null || true
  fi
}

# Set trap for cleanup
trap cleanup EXIT

# Create temporary directory
TEMP_DIR=$(mktemp -d)
echo "Using temporary directory: $TEMP_DIR"

echo "=== STEP 1: TEST SSH CONNECTION ==="
# Test SSH connection
echo "Testing SSH connection to $REMOTE_USER@$REMOTE_SERVER..."
if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE_USER@$REMOTE_SERVER" "echo 'SSH connection successful'" >/dev/null 2>&1; then
  echo "ERROR: Cannot connect to remote server via SSH."
  echo "Please ensure:"
  echo "  1. SSH key is configured for passwordless access"
  echo "  2. Remote server is accessible"
  echo "  3. User has proper permissions"
  exit 1
fi

echo "SSH connection successful."

echo "=== STEP 2: VALIDATE REMOTE MINIO CONTAINER ==="
# Check if MinIO container is running on remote server
echo "Checking MinIO container on remote server..."
if ! ssh "$REMOTE_USER@$REMOTE_SERVER" "docker ps | grep -q '$CONTAINER_ID'"; then
  echo "ERROR: MinIO container '$CONTAINER_ID' is not running on remote server."
  exit 1
fi

echo "MinIO container '$CONTAINER_ID' is running on remote server."

# Check if MinIO is accessible
echo "Testing MinIO connectivity on remote server..."
if ! ssh "$REMOTE_USER@$REMOTE_SERVER" "docker exec '$CONTAINER_ID' sh -c 'wget --spider -q http://localhost:9000/minio/health/live'" 2>/dev/null; then
  echo "WARNING: MinIO health check failed on remote server, but continuing..."
fi

echo "=== STEP 3: PREPARE DATA ==="
# Count files in source folder
FILE_COUNT=$(find "$SOURCE_FOLDER" -type f | wc -l)
echo "Found $FILE_COUNT files in source folder."

if [ "$FILE_COUNT" -eq 0 ]; then
  echo "WARNING: Source folder is empty. Creating placeholder file..."
  mkdir -p "$TEMP_DIR/placeholder"
  echo "This is a placeholder file" > "$TEMP_DIR/placeholder/placeholder.txt"
  SOURCE_FOLDER="$TEMP_DIR/placeholder"
  FILE_COUNT=1
fi

echo "=== STEP 4: TRANSFER DATA TO REMOTE SERVER ==="
# Create remote temporary directory
REMOTE_TEMP_DIR="/tmp/minio-migration-$(date +%s)"
echo "Creating remote temporary directory: $REMOTE_TEMP_DIR"
ssh "$REMOTE_USER@$REMOTE_SERVER" "mkdir -p '$REMOTE_TEMP_DIR'"

# Transfer data to remote server
echo "Transferring data to remote server..."
TRANSFER_START=$(date +%s)

# Use rsync if available, otherwise use scp
if command -v rsync >/dev/null 2>&1; then
  echo "Using rsync for efficient transfer..."
  if ! rsync -avz --progress "$SOURCE_FOLDER/" "$REMOTE_USER@$REMOTE_SERVER:$REMOTE_TEMP_DIR/"; then
    echo "ERROR: Failed to transfer data to remote server."
    exit 1
  fi
else
  echo "Using scp for transfer..."
  if ! scp -r "$SOURCE_FOLDER" "$REMOTE_USER@$REMOTE_SERVER:$REMOTE_TEMP_DIR/"; then
    echo "ERROR: Failed to transfer data to remote server."
    exit 1
  fi
fi

TRANSFER_END=$(date +%s)
TRANSFER_DURATION=$((TRANSFER_END - TRANSFER_START))
echo "Data transferred successfully in ${TRANSFER_DURATION} seconds."

echo "=== STEP 5: CONFIGURE REMOTE MINIO CLIENT ==="
# Install MinIO client in remote container if not present
echo "Setting up MinIO client in remote container..."
ssh "$REMOTE_USER@$REMOTE_SERVER" "
  docker exec '$CONTAINER_ID' sh -c '
    if ! command -v mc >/dev/null 2>&1; then
      echo \"Installing MinIO client...\"
      wget -q https://dl.min.io/client/mc/release/linux-amd64/mc -O /tmp/mc
      chmod +x /tmp/mc
      mv /tmp/mc /usr/local/bin/mc
    fi
  '
"

# Configure MinIO client on remote server
echo "Configuring MinIO client on remote server..."
ssh "$REMOTE_USER@$REMOTE_SERVER" "docker exec '$CONTAINER_ID' mc alias set local http://$MINIO_HOST:$MINIO_PORT '$MINIO_ACCESS_KEY' '$MINIO_SECRET_KEY'"

echo "=== STEP 6: CREATE AND VERIFY BUCKET ==="
# Create bucket if it doesn't exist
echo "Creating bucket '$BUCKET_NAME' on remote MinIO..."
ssh "$REMOTE_USER@$REMOTE_SERVER" "docker exec '$CONTAINER_ID' mc mb 'local/$BUCKET_NAME'" || echo "Bucket may already exist, continuing..."

# Verify bucket exists
if ! ssh "$REMOTE_USER@$REMOTE_SERVER" "docker exec '$CONTAINER_ID' mc ls 'local/$BUCKET_NAME'" >/dev/null 2>&1; then
  echo "ERROR: Failed to create or access bucket '$BUCKET_NAME' on remote MinIO."
  exit 1
fi

echo "Bucket '$BUCKET_NAME' is ready on remote MinIO."

echo "=== STEP 7: UPLOAD DATA TO REMOTE BUCKET ==="
# Copy data to remote container temporarily
echo "Copying data to remote container..."
CONTAINER_TEMP_DIR="/tmp/source_data"
ssh "$REMOTE_USER@$REMOTE_SERVER" "docker exec '$CONTAINER_ID' mkdir -p '$CONTAINER_TEMP_DIR'"

# Copy source folder to remote container
if ! ssh "$REMOTE_USER@$REMOTE_SERVER" "docker cp '$REMOTE_TEMP_DIR/$(basename "$SOURCE_FOLDER")' '$CONTAINER_ID:$CONTAINER_TEMP_DIR'"; then
  echo "ERROR: Failed to copy source folder to remote container."
  exit 1
fi

# Upload data using MinIO client on remote server
echo "Uploading data to remote bucket..."
UPLOAD_START=$(date +%s)

if ! ssh "$REMOTE_USER@$REMOTE_SERVER" "docker exec '$CONTAINER_ID' mc cp --recursive '$CONTAINER_TEMP_DIR/$(basename "$SOURCE_FOLDER")/' 'local/$BUCKET_NAME/'"; then
  echo "ERROR: Failed to upload data to remote MinIO bucket."
  exit 1
fi

UPLOAD_END=$(date +%s)
UPLOAD_DURATION=$((UPLOAD_END - UPLOAD_START))

echo "Data uploaded successfully in ${UPLOAD_DURATION} seconds."

echo "=== STEP 8: VERIFY UPLOAD ==="
# List uploaded objects
echo "Verifying uploaded objects..."
ssh "$REMOTE_USER@$REMOTE_SERVER" "docker exec '$CONTAINER_ID' mc ls 'local/$BUCKET_NAME' --recursive" | head -10

# Count uploaded objects
UPLOADED_COUNT=$(ssh "$REMOTE_USER@$REMOTE_SERVER" "docker exec '$CONTAINER_ID' mc ls 'local/$BUCKET_NAME' --recursive" | wc -l)
echo "Total objects uploaded: $UPLOADED_COUNT"

echo "=== STEP 9: CLEANUP ==="
# Clean up remote temporary data
echo "Cleaning up remote temporary files..."
ssh "$REMOTE_USER@$REMOTE_SERVER" "
  rm -rf '$REMOTE_TEMP_DIR'
  docker exec '$CONTAINER_ID' rm -rf '$CONTAINER_TEMP_DIR'
"

echo "=== MIGRATION COMPLETED SUCCESSFULLY! ==="
echo "Source folder: $SOURCE_FOLDER"
echo "Destination bucket: $BUCKET_NAME"
echo "Remote server: $REMOTE_USER@$REMOTE_SERVER"
echo "Objects uploaded: $UPLOADED_COUNT"
echo "MinIO endpoint: $MINIO_HOST:$MINIO_PORT"
echo "Process completed at: $(date)"
echo ""
echo "You can access your data at:"
echo "  Web UI: http://$REMOTE_SERVER:$MINIO_PORT"
echo "  API: http://$REMOTE_SERVER:$MINIO_PORT"
echo ""
echo "Access credentials:"
echo "  Access Key: $MINIO_ACCESS_KEY"
echo "  Secret Key: $MINIO_SECRET_KEY"
