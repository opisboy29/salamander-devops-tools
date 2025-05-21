#!/bin/bash

# Load environment variables from .env file
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

# Debug information
echo "DEBUG: Source Container ID = ${SOURCE_CONTAINER_ID}"      
echo "DEBUG: Restore Container ID = ${RESTORE_CONTAINER_ID}"    
echo "DEBUG: Backup Directory = ${MONGO_BACKUP_DIR}"

# Test source container access
echo "Testing source container access..."
docker exec ${SOURCE_CONTAINER_ID} mongosh --eval 'db.version()' || {
    echo "Error: Cannot access source container"
    exit 1
}

# Start restore container automatically
echo "Starting restore container..."
docker start ${RESTORE_CONTAINER_ID} || {
    echo "Error: Failed to start restore container"
    exit 1
}

# Wait for restore container to be ready
echo "Waiting for restore container to be ready..."
for i in {1..30}; do
    if docker exec ${RESTORE_CONTAINER_ID} mongosh --eval 'db.version()' &>/dev/null; then
        echo "✅ Restore container is ready"
        break
    fi
    echo "Waiting... ($i/30)"
    sleep 1
    if [ $i -eq 30 ]; then
        echo "Error: Restore container failed to become ready"
        exit 1
    fi
done

# Verify restore container is accessible
docker exec ${RESTORE_CONTAINER_ID} mongosh --eval 'db.version()' || {
    echo "Error: Cannot access restore container"
    exit 1
}

# Set the date and time for the backup file name
DATE=$(date +"%Y%m%d%H%M")

# Directory for storing the MongoDB backup
BACKUP_DIR="${MONGO_BACKUP_DIR}/test_${DATE}"

# Create backup directory
mkdir -p ${BACKUP_DIR}

# Function to perform backup
perform_backup() {
    echo "Starting MongoDB backup using mongodump..."

    # Get list of collections
    collections=$(docker exec ${SOURCE_CONTAINER_ID} mongosh --quiet --eval "
        const uri = 'mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${MONGO_HOST}:${MONGO_PORT}/?authSource=${MONGO_AUTH_DB}';
        const client = new Mongo(uri);
        const db = client.getDB('${MONGO_DB_NAME}');
        print(db.getCollectionNames().join(','));
        client.close();
    ")

    if [ -z "$collections" ]; then
        echo "Error: No collections found in database"
        return 1
    fi

    # Convert comma-separated string to array
    IFS=',' read -ra COLLS <<< "$collections"

    # Backup each collection
    for collection in "${COLLS[@]}"; do
        echo "Backing up collection: ${collection}"

        # Perform backup
        docker exec ${SOURCE_CONTAINER_ID} mongodump \
            --host=${MONGO_HOST} \
            --port=${MONGO_PORT} \
            --username=${MONGO_USERNAME} \
            --password=${MONGO_PASSWORD} \
            --authenticationDatabase=${MONGO_AUTH_DB} \
            --db=${MONGO_DB_NAME} \
            --collection=${collection} \
            --out=/backup/${DATE} || {
                echo "Error: Failed to backup collection ${collection}"
                return 1
            }

        # Copy files from container to host
        docker cp ${SOURCE_CONTAINER_ID}:/backup/${DATE}/${MONGO_DB_NAME}/${collection}.bson ${BACKUP_DIR}/ || return 1
        docker cp ${SOURCE_CONTAINER_ID}:/backup/${DATE}/${MONGO_DB_NAME}/${collection}.metadata.json ${BACKUP_DIR}/ || return 1

        # Clean up container backup directory
        docker exec ${SOURCE_CONTAINER_ID} rm -rf /backup/${DATE}
    done

    echo "✅ Backup completed successfully"
    return 0
}

# Function to manage restore container
manage_restore_container() {
    local action=$1
    
    case $action in
        "start")
            echo "Starting restore container..."
            docker start ${RESTORE_CONTAINER_ID} || {
                echo "Error: Failed to start restore container"
                return 1
            }
            
            # Wait for MongoDB to be ready
            for i in {1..30}; do
                if docker exec ${RESTORE_CONTAINER_ID} mongosh --eval 'db.runCommand({ping: 1})' &>/dev/null; then
                    echo "✅ Restore container is ready"
                    return 0
                fi
                echo "Waiting for MongoDB to be ready... ($i/30)"
                sleep 1
            done
            echo "Error: Restore container failed to become ready"
            return 1
            ;;
            
        "stop")
            echo "Cleaning up restore database..."
            # Drop all data before stopping
            docker exec ${RESTORE_CONTAINER_ID} mongosh --eval "
                db.getSiblingDB('${MONGO_RESTORE_DB_NAME}').dropDatabase()
            " || echo "Warning: Failed to drop database"
            
            echo "Stopping restore container..."
            docker stop ${RESTORE_CONTAINER_ID} || {
                echo "Error: Failed to stop restore container"
                return 1
            }
            echo "✅ Restore container stopped"
            ;;
            
        *)
            echo "Error: Invalid action for manage_restore_container"
            return 1
            ;;
    esac
}

# Function to get document count with container check
get_document_count() {
    local container=$1
    local db_name=$2
    local collection=$3
    local auth_params=$4

    # Check if container is running
    if ! docker ps -q -f "name=${container}" &>/dev/null; then
        echo "Error: Container ${container} is not running"
        return 1
    fi

    local count
    if [ -n "$auth_params" ]; then
        # For source database with auth
        count=$(docker exec ${container} mongosh --quiet ${auth_params} \
            --eval "db.getSiblingDB('${db_name}').${collection}.countDocuments({})")
    else
        # For restore database without auth
        count=$(docker exec ${container} mongosh --quiet \
            --eval "db.getSiblingDB('${db_name}').${collection}.countDocuments({})")
    fi

    # Validate count is a number
    if ! [[ "$count" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid count value: ${count}"
        return 1
    fi

    echo "$count"
}

# Function to check document count with tolerance
check_count_with_tolerance() {
    local source_count=$1
    local restore_count=$2
    local tolerance_percentage=1  # 1% tolerance

    # Validate inputs are numbers
    if ! [[ "$source_count" =~ ^[0-9]+$ ]] || ! [[ "$restore_count" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid count values - Source: ${source_count}, Restore: ${restore_count}"
        return 1
    fi

    # If either count is 0, require exact match
    if [ "$source_count" -eq 0 ] || [ "$restore_count" -eq 0 ]; then
        [ "$source_count" -eq "$restore_count" ]
        return $?
    fi

    # Calculate allowed difference
    local max_difference=$(( source_count * tolerance_percentage / 100 ))
    local actual_difference=$(( source_count - restore_count ))
    
    # Convert to absolute value
    if [ $actual_difference -lt 0 ]; then
        actual_difference=$(( -actual_difference ))
    fi

    # Check if difference is within tolerance
    if [ $actual_difference -le $max_difference ]; then
        echo "✅ Document count within ${tolerance_percentage}% tolerance"
        echo "Source: ${source_count}, Restored: ${restore_count}, Difference: ${actual_difference}"
        return 0
    else
        echo "❌ Document count difference (${actual_difference}) exceeds ${tolerance_percentage}% tolerance"
        echo "Source: ${source_count}, Restored: ${restore_count}"
        return 1
    fi
}

# Function to ensure restore container is running
ensure_restore_container() {
    if ! docker ps -q -f "name=${RESTORE_CONTAINER_ID}" &>/dev/null; then
        echo "Restore container stopped, restarting..."
        docker start ${RESTORE_CONTAINER_ID} || {
            echo "Error: Failed to start restore container"
            return 1
        }
        
        # Wait for MongoDB to be ready
        echo "Waiting for restore container to be ready..."
        for i in {1..30}; do
            if docker exec ${RESTORE_CONTAINER_ID} mongosh --eval 'db.version()' &>/dev/null; then
                echo "✅ Restore container is ready"
                return 0
            fi
            echo "Waiting... ($i/30)"
            sleep 2
        done
        echo "Error: Restore container failed to become ready"
        return 1
    fi
    return 0
}

# Function to test restore
test_restore() {
    echo "Starting restore test..."
    local restore_success=true
    
    # Ensure container is running before dropping database
    ensure_restore_container || {
        echo "Error: Cannot proceed with restore test"
        return 1
    }

    # Drop existing test database
    echo "Dropping existing test database..."
    docker exec ${RESTORE_CONTAINER_ID} mongosh --eval "
        db.getSiblingDB('${MONGO_RESTORE_DB_NAME}').dropDatabase()
    "

    for collection in ${BACKUP_DIR}/*.bson; do
        collection_name=$(basename "$collection" .bson)
        
        # Skip system collections
        if [[ "$collection_name" == "system."* ]]; then
            echo "Skipping system collection: ${collection_name}"
            continue
        fi

        echo "Testing restore for collection: ${collection_name}"

        # Ensure container is running before each collection
        ensure_restore_container || {
            restore_success=false
            break
        }

        # Copy backup files to test container
        docker cp "${collection}" "${RESTORE_CONTAINER_ID}:/tmp/" || {
            echo "Error: Failed to copy bson file for ${collection_name}"
            restore_success=false
            break
        }
        docker cp "${BACKUP_DIR}/${collection_name}.metadata.json" "${RESTORE_CONTAINER_ID}:/tmp/" || {
            echo "Error: Failed to copy metadata file for ${collection_name}"
            restore_success=false
            break
        }

        # Ensure container is still running before restore
        ensure_restore_container || {
            restore_success=false
            break
        }

        # Attempt restore
        docker exec ${RESTORE_CONTAINER_ID} mongorestore \
            --db=${MONGO_RESTORE_DB_NAME} \
            --collection=${collection_name} \
            "/tmp/${collection_name}.bson" || {
                echo "Error: Failed to restore collection ${collection_name}"
                restore_success=false
                break
            }

        # Verify restore with retries
        local max_retries=3
        local retry_count=0
        local verification_success=false

        while [ $retry_count -lt $max_retries ]; do
            # Ensure container is running before verification
            if ensure_restore_container; then
                local source_count restore_count
                
                source_count=$(get_document_count "${SOURCE_CONTAINER_ID}" "${MONGO_DB_NAME}" "${collection_name}" \
                    "--host=${MONGO_HOST} --port=${MONGO_PORT} --username=${MONGO_USERNAME} --password=${MONGO_PASSWORD} --authenticationDatabase=${MONGO_AUTH_DB}")
                
                restore_count=$(get_document_count "${RESTORE_CONTAINER_ID}" "${MONGO_RESTORE_DB_NAME}" "${collection_name}")

                if check_count_with_tolerance "$source_count" "$restore_count"; then
                    verification_success=true
                    break
                fi
            fi

            echo "Retrying count verification for ${collection_name} (attempt $((retry_count + 1)))"
            sleep 5
            retry_count=$((retry_count + 1))
        done

        if ! $verification_success; then
            echo "❌ Error: Document count verification failed after ${max_retries} attempts"
            restore_success=false
            break
        fi

        # Cleanup temporary files
        docker exec ${RESTORE_CONTAINER_ID} rm -f "/tmp/${collection_name}.bson" "/tmp/${collection_name}.metadata.json"
        echo "✅ Restore test passed for collection: ${collection_name}"
    done

    if [ "$restore_success" = true ]; then
        echo "✅ All restore tests completed successfully"
        return 0
    else
        echo "❌ Restore test failed"
        return 1
    fi
}

# Function to upload backup
upload_backup() {
    echo "Creating backup archive..."
    cd ${MONGO_BACKUP_DIR}
    tar -czf test_${DATE}.tar.gz test_${DATE} || {
        echo "Error: Failed to create backup archive"
        return 1
    }

    echo "Uploading backup to cloud storage..."
    rclone copy test_${DATE}.tar.gz ${CLOUD_REMOTE_PATH} || {
        echo "Error: Failed to upload backup to cloud storage"
        return 1
    }
    
    echo "✅ Upload completed successfully"
    return 0
}

# Function to cleanup
cleanup_all() {
    echo "Performing final cleanup..."

    # Make sure restore container is running for cleanup
    if ! docker ps -q -f "name=${RESTORE_CONTAINER_ID}" &>/dev/null; then
        echo "Starting restore container for cleanup..."
        docker start ${RESTORE_CONTAINER_ID}
        sleep 5  # Wait for container to be ready
    fi

    # Clean up restore database
    echo "Cleaning up restore database..."
    docker exec ${RESTORE_CONTAINER_ID} mongosh --eval "
        db.getSiblingDB('${MONGO_RESTORE_DB_NAME}').dropDatabase()
    " || echo "Warning: Failed to drop database"

    # Remove local backup files
    rm -rf ${BACKUP_DIR}
    rm -f ${MONGO_BACKUP_DIR}/test_${DATE}.tar.gz

    # Finally, stop restore container
    echo "Stopping restore container..."
    docker stop ${RESTORE_CONTAINER_ID} || {
        echo "Warning: Failed to stop restore container"
    }
    echo "✅ Final cleanup completed"
}

# Main execution flow with proper error handling
echo "🚀 Starting backup process..."

# Make sure cleanup runs even if script fails
trap cleanup_all EXIT

# Step 1: Perform backup
perform_backup || {
    echo "❌ Backup failed"
    exit 1
}

# Step 2: Test restore (mandatory)
test_restore || {
    echo "❌ Restore test failed - Backup is not reliable!"
    exit 1
}

# Step 3: Upload backup
upload_backup || {
    echo "❌ Upload failed"
    exit 1
}

echo "✅ MongoDB backup process completed successfully on $(date)" 