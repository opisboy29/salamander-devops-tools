#!/bin/bash

# Make sure script is executable
if [ ! -x "$0" ]; then
    chmod +x "$0"
fi

set -e  # Exit on error

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/.env"

# Verify environment variables are loaded
if [ -z "$DB_PASSWORD" ]; then
    echo "❌ Error: Environment variables not loaded"
    exit 1
fi

DATE=$(date +"%Y%m%d%H%M")
BACKUP_DIR="$SCRIPT_DIR/backups"
LOG_DIR="$SCRIPT_DIR/logs"
TEMP_DIR="$SCRIPT_DIR/temp"

# Create necessary directories if they don't exist
mkdir -p "$BACKUP_DIR" "$LOG_DIR" "$TEMP_DIR"

# Add timestamp to logs
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Add log file
exec 1> >(tee -a "${LOG_DIR}/postgres_backup_${DATE}.log") 2>&1

# Cleanup function for test database and temporary files
cleanup_test_db() {
    local DB_NAME=$1
    local FILE_PREFIX=$2
    
    echo "🧹 Cleaning up test database and files for: $DB_NAME"
    docker exec $RESTORE_CONTAINER dropdb -U $DB_USER --if-exists $DB_NAME
    docker exec $RESTORE_CONTAINER rm -f /tmp/${FILE_PREFIX}.dump /tmp/${FILE_PREFIX}.sql
}

# Function to send simple notification
send_simple_notification() {
    local message="$1"
    local webhook_url="$DISCORD_WEBHOOK_URL"
    
    # Escape quotes in message
    message=$(echo "$message" | sed 's/"/\\"/g')
    
    # Send simple notification
    curl -s -H "Content-Type: application/json" \
         -d "{\"content\": \"$message\"}" \
         "$webhook_url" || true
}

# Function to handle errors
handle_error() {
    local error_message="$1"
    echo "❌ Error: $error_message"
    
    # Send error notification
    curl -s -H "Content-Type: application/json" \
         -d "{\"content\":\"❌ Backup failed: $error_message\"}" \
         "$DISCORD_WEBHOOK_URL" || true
    
    cleanup "error"
    exit 1
}

# Main cleanup function
cleanup() {
    local reason=$1
    echo -e "\n🧹 Performing cleanup..."
    
    # Cleanup temp files in local temp directory
    rm -f $TEMP_DIR/*.dump $TEMP_DIR/*.sql
    
    # Cleanup temp files in containers
    if [ "$(docker ps -q -f name=$SEQUELIZE_CONTAINER)" ]; then
        echo "🧹 Cleaning up Sequelize container temp files..."
        docker exec $SEQUELIZE_CONTAINER rm -f /tmp/sequelize.dump /tmp/sequelize.sql
    fi
    
    if [ "$(docker ps -q -f name=$PRISMA_CONTAINER)" ]; then
        echo "🧹 Cleaning up Prisma container temp files..."
        docker exec $PRISMA_CONTAINER rm -f /tmp/prisma.dump /tmp/prisma.sql
    fi
    
    if [ "$(docker ps -q -f name=$RESTORE_CONTAINER)" ]; then
        echo "🧹 Cleaning up test databases..."
        # Drop test databases
        docker exec $RESTORE_CONTAINER dropdb -U $DB_USER --if-exists -f test_sequelize_dump
        docker exec $RESTORE_CONTAINER dropdb -U $DB_USER --if-exists -f test_sequelize_sql
        docker exec $RESTORE_CONTAINER dropdb -U $DB_USER --if-exists -f test_prisma_dump
        docker exec $RESTORE_CONTAINER dropdb -U $DB_USER --if-exists -f test_prisma_sql
        
        # Cleanup restore container temp files
        echo "🧹 Cleaning up restore container temp files..."
        docker exec $RESTORE_CONTAINER rm -f /tmp/sequelize.dump /tmp/sequelize.sql /tmp/prisma.dump /tmp/prisma.sql
        
        echo "🛑 Stopping restore container..."
        docker stop $RESTORE_CONTAINER
    fi

    # Cleanup old log files (older than 30 days)
    echo "🧹 Cleaning up old log files..."
    find $LOG_DIR -name "*.log" -mtime +30 -delete

    # Cleanup old backup files (older than 30 days)
    echo "🧹 Cleaning up old backup files..."
    find $BACKUP_DIR -name "*.dump" -mtime +30 -delete
    find $BACKUP_DIR -name "*.sql" -mtime +30 -delete

    # Cleanup system temp files
    echo "🧹 Cleaning up system temp files..."
    rm -f /tmp/sequelize*.{dump,sql} /tmp/prisma*.{dump,sql}

    if [ "$interrupt" = "interrupted" ]; then
        # Hardcoded simple notification
        curl -s -H "Content-Type: application/json" \
             -d '{"content":"🧹 Cleanup completed"}' \
             "$DISCORD_WEBHOOK_URL" || true
    fi

    # Only send notification if cleanup was triggered by error
    if [ "$reason" = "error" ]; then
        notify_discord "ERROR" "❌ Backup failed"
    fi

    # Don't exit if this is a normal cleanup after success
    if [ "$reason" = "error" ]; then
        exit 1
    fi
}

# Handle interrupts and termination
handle_interrupt() {
    echo -e "\n⚠️ Received interrupt signal..."
    
    # Hardcoded simple notification
    curl -s -H "Content-Type: application/json" \
         -d '{"content":"⚠️ Backup process was interrupted"}' \
         "$DISCORD_WEBHOOK_URL" || true
    
    cleanup "interrupted"
}

# Register cleanup handlers
trap handle_interrupt SIGINT SIGTERM
trap cleanup EXIT

# Define notify_discord function first
notify_discord() {
    local status=$1
    local message=$2
    
    if [ -z "$DISCORD_WEBHOOK_URL" ]; then
        echo "⚠️ Discord webhook URL not configured"
        return 1
    fi
    
    # Format emoji based on status
    local emoji="✅"
    if [ "$status" = "ERROR" ]; then
        emoji="❌"
    elif [ "$status" = "WARNING" ]; then
        emoji="⚠️"
    fi
    
    local json_payload="{\"content\": \"${emoji} ${message}\"}"
    
    curl -s -H "Content-Type: application/json" \
         -d "$json_payload" \
         "$DISCORD_WEBHOOK_URL"
}

# Function to get database URL for a container
get_db_url() {
    local container=$1
    local db_name=$2
    local CONTAINER_PASSWORD=$(docker exec $container env | grep POSTGRES_PASSWORD | cut -d= -f2)
    local DB_PASSWORD_ENCODED=$(echo "$CONTAINER_PASSWORD" | sed 's/@/%40/g' | sed 's/\$/%24/g')
    echo "postgresql://$DB_USER:$DB_PASSWORD_ENCODED@127.0.0.1:5432${db_name:+/$db_name}"
}

# Check required environment variables
check_env_vars() {
    local missing_vars=()
    
    # Database names
    [ -z "$SEQUELIZE_DB" ] && missing_vars+=("SEQUELIZE_DB")
    [ -z "$PRISMA_DB" ] && missing_vars+=("PRISMA_DB")
    
    # Database user
    [ -z "$DB_USER" ] && missing_vars+=("DB_USER")
    [ -z "$DB_PASSWORD" ] && missing_vars+=("DB_PASSWORD")
    
    # Container names
    [ -z "$RESTORE_CONTAINER" ] && missing_vars+=("RESTORE_CONTAINER")
    [ -z "$SEQUELIZE_CONTAINER" ] && missing_vars+=("SEQUELIZE_CONTAINER")
    [ -z "$PRISMA_CONTAINER" ] && missing_vars+=("PRISMA_CONTAINER")
    
    # Google Drive paths
    [ -z "$GDRIVE_SEQUELIZE_DUMP" ] && missing_vars+=("GDRIVE_SEQUELIZE_DUMP")
    [ -z "$GDRIVE_SEQUELIZE_SQL" ] && missing_vars+=("GDRIVE_SEQUELIZE_SQL")
    [ -z "$GDRIVE_PRISMA_DUMP" ] && missing_vars+=("GDRIVE_PRISMA_DUMP")
    [ -z "$GDRIVE_PRISMA_SQL" ] && missing_vars+=("GDRIVE_PRISMA_SQL")
    
    # Discord webhook
    [ -z "$DISCORD_WEBHOOK_URL" ] && missing_vars+=("DISCORD_WEBHOOK_URL")
    
    # If any variables are missing
    if [ ${#missing_vars[@]} -ne 0 ]; then
        echo "❌ Error: Missing required environment variables:"
        printf '%s\n' "${missing_vars[@]}"
        
        notify_discord "ERROR" "❌ Backup initialization failed\n\nℹ️ Missing environment variables:\n• ${missing_vars[*]// /\n• }"
        cleanup "error"
        exit 1
    fi
    
    # Debug: print variables
    echo "Debug info:"
    echo "DB_USER: $DB_USER"
    echo "DB_PASSWORD: ${DB_PASSWORD:0:3}...${DB_PASSWORD: -3}"
    echo "SEQUELIZE_CONTAINER: $SEQUELIZE_CONTAINER"
    echo "SEQUELIZE_DB: $SEQUELIZE_DB"
    
    # Test connection using container password
    echo "Testing connection using container password..."
    local DB_URL=$(get_db_url $SEQUELIZE_CONTAINER)
    DATABASES=$(docker exec $SEQUELIZE_CONTAINER psql "$DB_URL" -c '\l')
    echo "$DATABASES"
    
    # Check if database exists
    if ! echo "$DATABASES" | grep -qw $SEQUELIZE_DB; then
        echo "❌ Database validation failed: Sequelize database '$SEQUELIZE_DB' does not exist"
        cleanup "error"
        exit 1
    fi
    
    echo "✅ Database validation successful"
}

# Call check at the start of the script
check_env_vars

# Function to log and notify
log_and_notify() {
    local status=$1
    local message=$2
    local notify=${3:-true}  # Default to true
    
    # Local logging
    echo "$message"
    
    # Discord notification if enabled
    if [ "$notify" = true ]; then
        notify_discord "$status" "$message"
    fi
}

# Start time and initial notification
START_TIME=$(date +%s)
log_and_notify "INFO" "🚀 Starting database backup process..."

# Step 1: Create backups
log_and_notify "INFO" "📦 Creating Sequelize database backup..." true

# Create Sequelize backups
DB_URL=$(get_db_url $SEQUELIZE_CONTAINER $SEQUELIZE_DB)
docker exec $SEQUELIZE_CONTAINER pg_dump "$DB_URL" -F c -b -v -f /tmp/sequelize.dump || {
    notify_discord "ERROR" "❌ Backup creation failed\n\nℹ️ Failed to create Sequelize dump backup"
    cleanup "error"
    exit 1
}
log_and_notify "INFO" "✅ Sequelize dump backup created successfully" true

docker exec $SEQUELIZE_CONTAINER pg_dump "$DB_URL" -F p -b -v -f /tmp/sequelize.sql || {
    notify_discord "ERROR" "❌ Backup creation failed\n\nℹ️ Failed to create Sequelize SQL backup"
    cleanup "error"
    exit 1
}
log_and_notify "INFO" "✅ Sequelize SQL backup created successfully" true

# Create Prisma backups
log_and_notify "INFO" "📦 Creating Prisma database backup..." true
DB_URL=$(get_db_url $PRISMA_CONTAINER $PRISMA_DB)
docker exec $PRISMA_CONTAINER pg_dump "$DB_URL" -F c -b -v -f /tmp/prisma.dump || {
    notify_discord "ERROR" "❌ Backup creation failed\n\nℹ️ Failed to create Prisma dump backup"
    cleanup "error"
    exit 1
}
log_and_notify "INFO" "✅ Prisma dump backup created successfully" true

docker exec $PRISMA_CONTAINER pg_dump "$DB_URL" -F p -b -v -f /tmp/prisma.sql || {
    notify_discord "ERROR" "❌ Backup creation failed\n\nℹ️ Failed to create Prisma SQL backup"
    cleanup "error"
    exit 1
}
log_and_notify "INFO" "✅ Prisma SQL backup created successfully" true

# Copy backups to local temp
log_and_notify "INFO" "📋 Copying backups to temporary location..." true
docker cp $SEQUELIZE_CONTAINER:/tmp/sequelize.dump $TEMP_DIR/sequelize_${DATE}.dump || {
    notify_discord "ERROR" "❌ Backup copy failed\n\nℹ️ Failed to copy Sequelize dump backup\n• Source: $SEQUELIZE_CONTAINER:/tmp/sequelize.dump\n• Destination: $TEMP_DIR/sequelize_${DATE}.dump"
    cleanup "error"
    exit 1
}

docker cp $SEQUELIZE_CONTAINER:/tmp/sequelize.sql $TEMP_DIR/sequelize_${DATE}.sql || {
    notify_discord "ERROR" "❌ Backup copy failed\n\nℹ️ Failed to copy Sequelize SQL backup\n• Source: $SEQUELIZE_CONTAINER:/tmp/sequelize.sql\n• Destination: $TEMP_DIR/sequelize_${DATE}.sql"
    cleanup "error"
    exit 1
}

docker cp $PRISMA_CONTAINER:/tmp/prisma.dump $TEMP_DIR/prisma_${DATE}.dump || {
    notify_discord "ERROR" "❌ Backup copy failed\n\nℹ️ Failed to copy Prisma dump backup\n• Source: $PRISMA_CONTAINER:/tmp/prisma.dump\n• Destination: $TEMP_DIR/prisma_${DATE}.dump"
    cleanup "error"
    exit 1
}

docker cp $PRISMA_CONTAINER:/tmp/prisma.sql $TEMP_DIR/prisma_${DATE}.sql || {
    notify_discord "ERROR" "❌ Backup copy failed\n\nℹ️ Failed to copy Prisma SQL backup\n• Source: $PRISMA_CONTAINER:/tmp/prisma.sql\n• Destination: $TEMP_DIR/prisma_${DATE}.sql"
    cleanup "error"
    exit 1
}
log_and_notify "INFO" "✅ All backups copied successfully" true

# Test Sequelize backups
log_and_notify "INFO" "📋 Testing Sequelize backups..." true
docker cp $TEMP_DIR/sequelize_${DATE}.dump $RESTORE_CONTAINER:/tmp/sequelize.dump || {
    notify_discord "ERROR" "❌ Backup validation failed\n\nℹ️ Failed to copy backup to restore container"
    cleanup "error"
    exit 1
}

# Test Prisma backups
log_and_notify "INFO" "📋 Testing Prisma backups..." true
docker cp $TEMP_DIR/prisma_${DATE}.dump $RESTORE_CONTAINER:/tmp/prisma.dump || {
    notify_discord "ERROR" "❌ Backup validation failed\n\nℹ️ Failed to copy backup to restore container"
    cleanup "error"
    exit 1
}

# Test restore
log_and_notify "INFO" "🔍 Starting backup validation process..." true

# Check if restore container is running
if [ ! "$(docker ps -q -f name=$RESTORE_CONTAINER)" ]; then
    echo "🚀 Starting restore container..."
    docker start $RESTORE_CONTAINER || {
        notify_discord "ERROR" "❌ Container startup failed\n\nℹ️ Failed to start restore container: $RESTORE_CONTAINER"
        cleanup "error"
        exit 1
    }
    
    # Wait for PostgreSQL to be ready
    for i in {1..30}; do
        if docker exec $RESTORE_CONTAINER pg_isready -U $DB_USER &>/dev/null; then
            echo "✅ Restore container is ready"
            break
        fi
        echo "⏳ Waiting for container... ($i/30)"
        sleep 1
        if [ $i -eq 30 ]; then
            notify_discord "ERROR" "❌ Container startup timeout\n\nℹ️ Restore container failed to initialize within 30 seconds"
            cleanup "error"
            exit 1
        fi
    done
fi

# Function to validate database content and structure
validate_db_content() {
    local SOURCE_CONTAINER=$1
    local SOURCE_DB=$2
    local TEST_DB=$3
    local DB_TYPE=$4

    if ! docker exec $RESTORE_CONTAINER pg_isready -U $DB_USER &>/dev/null; then
        notify_discord "ERROR" "❌ Restore container is not ready\n\nℹ️ Database connection failed"
        return 1
    fi

    log_and_notify "INFO" "🔍 Validating ${DB_TYPE} database:\n• Checking table structure\n• Comparing record counts\n• Validating data integrity" true

    # Get URLs for source and test databases
    local SOURCE_URL=$(get_db_url $SOURCE_CONTAINER $SOURCE_DB)
    local TEST_URL=$(get_db_url $RESTORE_CONTAINER $TEST_DB)

    # Compare number of tables
    echo "📊 Checking table count..."
    local SOURCE_TABLES=$(docker exec $SOURCE_CONTAINER psql "$SOURCE_URL" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';")
    local TEST_TABLES=$(docker exec $RESTORE_CONTAINER psql "$TEST_URL" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';")
    
    if [ "$SOURCE_TABLES" != "$TEST_TABLES" ]; then
        notify_discord "ERROR" "❌ Table count mismatch for ${DB_TYPE}!\n\nℹ️ Source: ${SOURCE_TABLES}\nTest: ${TEST_TABLES}"
        return 1
    fi

    # Get list of tables
    local TABLES=$(docker exec $SOURCE_CONTAINER psql "$SOURCE_URL" -t -c "SELECT tablename FROM pg_tables WHERE schemaname = 'public';")
    
    for TABLE in $TABLES; do
        log_and_notify "INFO" "📋 Validating table: ${TABLE}" false
        
        # Compare table structure
        echo "  🔍 Checking table structure..."
        local SOURCE_STRUCTURE=$(docker exec $SOURCE_CONTAINER psql "$SOURCE_URL" -t -c "
            SELECT column_name, data_type, character_maximum_length, is_nullable, column_default
            FROM information_schema.columns 
            WHERE table_schema = 'public' AND table_name = '${TABLE}'
            ORDER BY ordinal_position;
        ")
        local TEST_STRUCTURE=$(docker exec $RESTORE_CONTAINER psql "$TEST_URL" -t -c "
            SELECT column_name, data_type, character_maximum_length, is_nullable, column_default
            FROM information_schema.columns 
            WHERE table_schema = 'public' AND table_name = '${TABLE}'
            ORDER BY ordinal_position;
        ")
        
        if [ "$SOURCE_STRUCTURE" != "$TEST_STRUCTURE" ]; then
            log_and_notify "ERROR" "❌ Table structure mismatch for ${TABLE}!" true
            return 1
        fi

        # Compare record count
        echo "  🔍 Checking record count..."
        local SOURCE_COUNT=$(docker exec $SOURCE_CONTAINER psql "$SOURCE_URL" -t -c "SELECT COUNT(*) FROM \"${TABLE}\";" 2>/dev/null || echo "0")
        local TEST_COUNT=$(docker exec $RESTORE_CONTAINER psql "$TEST_URL" -t -c "SELECT COUNT(*) FROM \"${TABLE}\";" 2>/dev/null || echo "0")
        
        # Remove whitespace
        SOURCE_COUNT=$(echo $SOURCE_COUNT | tr -d '[:space:]')
        TEST_COUNT=$(echo $TEST_COUNT | tr -d '[:space:]')
        
        if [ "$SOURCE_COUNT" -gt 0 ]; then
            local DIFF=$((SOURCE_COUNT - TEST_COUNT))
            if [ "$DIFF" -lt 0 ]; then
                DIFF=$((DIFF * -1))
            fi
            local DIFF_PERCENT=$(( (DIFF * 100) / SOURCE_COUNT ))
            
            if [ "$DIFF_PERCENT" -gt 1 ]; then
                log_and_notify "ERROR" "❌ Record count mismatch in ${TABLE}!\nSource: ${SOURCE_COUNT}, Test: ${TEST_COUNT}, Difference: ${DIFF_PERCENT}%" true
                return 1
            fi
        fi

        log_and_notify "INFO" "✅ Table ${TABLE} validated successfully" false
    done

    log_and_notify "INFO" "✅ ${DB_TYPE} database validation successful" true
    return 0
}

# Function to validate backup
validate_backup() {
    local SOURCE_CONTAINER=$1
    local SOURCE_DB=$2
    local TEST_DB=$3
    local BACKUP_TYPE=$4
    local PERCENT_TOLERANCE=1  # Toleransi 1%
    
    echo "🔍 Validating $BACKUP_TYPE backup..."
    
    # Compare table count
    local SOURCE_URL=$(get_db_url $SOURCE_CONTAINER $SOURCE_DB)
    local TEST_URL=$(get_db_url $RESTORE_CONTAINER $TEST_DB)
    
    echo "📊 Comparing table counts..."
    local SOURCE_COUNT=$(docker exec $SOURCE_CONTAINER psql "$SOURCE_URL" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';")
    local TEST_COUNT=$(docker exec $RESTORE_CONTAINER psql "$TEST_URL" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';")
    
    SOURCE_COUNT=$(echo $SOURCE_COUNT | tr -d '[:space:]')
    TEST_COUNT=$(echo $TEST_COUNT | tr -d '[:space:]')
    
    if [ "$SOURCE_COUNT" != "$TEST_COUNT" ]; then
        log_and_notify "ERROR" "❌ Table count mismatch in $BACKUP_TYPE backup!\nSource: $SOURCE_COUNT, Test: $TEST_COUNT" true
        return 1
    fi
    
    # Compare row counts for each table
    echo "📊 Comparing row counts for each table..."
    local TABLES=$(docker exec $SOURCE_CONTAINER psql "$SOURCE_URL" -t -c "SELECT tablename FROM pg_tables WHERE schemaname = 'public';")
    
    for TABLE in $TABLES; do
        echo "  Checking table: $TABLE"
        local SOURCE_ROWS=$(docker exec $SOURCE_CONTAINER psql "$SOURCE_URL" -t -c "SELECT COUNT(*) FROM \"$TABLE\";")
        local TEST_ROWS=$(docker exec $RESTORE_CONTAINER psql "$TEST_URL" -t -c "SELECT COUNT(*) FROM \"$TABLE\";")
        
        SOURCE_ROWS=$(echo $SOURCE_ROWS | tr -d '[:space:]')
        TEST_ROWS=$(echo $TEST_ROWS | tr -d '[:space:]')
        
        if [ "$SOURCE_ROWS" -gt 0 ]; then
            local DIFF=$((SOURCE_ROWS - TEST_ROWS))
            if [ "$DIFF" -lt 0 ]; then
                DIFF=$((DIFF * -1))
            fi
            local DIFF_PERCENT=$(( (DIFF * 100) / SOURCE_ROWS ))
            
            if [ "$DIFF_PERCENT" -gt "$PERCENT_TOLERANCE" ]; then
                log_and_notify "ERROR" "❌ Row count mismatch in table $TABLE!\nSource: $SOURCE_ROWS, Test: $TEST_ROWS (diff: $DIFF rows, ${DIFF_PERCENT}%)" true
                return 1
            elif [ "$DIFF" -gt 0 ]; then
                echo "  ⚠️ Minor difference in row count for $TABLE (diff: $DIFF rows, ${DIFF_PERCENT}%, within tolerance)"
            fi
        fi
    done
    
    echo "✅ $BACKUP_TYPE backup validation successful"
    return 0
}

# Function to restore and test backup
test_backup() {
    local CONTAINER=$1
    local DB_NAME=$2
    local BACKUP_FILE=$3
    local TYPE=$4
    
    echo "🧹 Preparing test environment for $TYPE..."
    local DB_URL=$(get_db_url $RESTORE_CONTAINER)
    
    # Drop existing database if exists
    docker exec $RESTORE_CONTAINER dropdb -U $DB_USER --if-exists $DB_NAME
    
    # Create new database
    docker exec $RESTORE_CONTAINER createdb -U $DB_USER $DB_NAME || {
        notify_discord "ERROR" "❌ Database creation failed\n\nℹ️ Failed to create test database: $DB_NAME"
        return 1
    }
    
    # Restore with options to ignore ownership issues
    docker exec $RESTORE_CONTAINER pg_restore \
        --no-owner \
        --no-privileges \
        --role=$DB_USER \
        -d "$(get_db_url $RESTORE_CONTAINER $DB_NAME)" \
        $BACKUP_FILE || {
        echo "⚠️ Warning: Some non-fatal errors occurred during restore"
    }
    
    return 0
}

# After backup creation and testing
test_backup $SEQUELIZE_CONTAINER "test_sequelize_dump" "/tmp/sequelize.dump" "Sequelize" && \
validate_backup $SEQUELIZE_CONTAINER $SEQUELIZE_DB "test_sequelize_dump" "Sequelize" || {
    notify_discord "ERROR" "❌ Backup validation failed for Sequelize"
    cleanup "error"
    exit 1
}

test_backup $PRISMA_CONTAINER "test_prisma_dump" "/tmp/prisma.dump" "Prisma" && \
validate_backup $PRISMA_CONTAINER $PRISMA_DB "test_prisma_dump" "Prisma" || {
    notify_discord "ERROR" "❌ Backup validation failed for Prisma"
    cleanup "error"
    exit 1
}

# Step 3: Stop restore container
echo "🛑 Stopping restore container..."
docker stop $RESTORE_CONTAINER || {
    notify_discord "ERROR" "❌ Container shutdown failed\n\nℹ️ Failed to stop restore container"
    cleanup "error"
    exit 1
}

# Step 4: Upload to Google Drive
log_and_notify "INFO" "☁️ Uploading backups to Google Drive..." true
rclone copy $TEMP_DIR/sequelize_${DATE}.dump $GDRIVE_SEQUELIZE_DUMP/ || {
    notify_discord "ERROR" "❌ Failed to upload Sequelize dump backup\n\nℹ️ Error occurred during upload to Google Drive"
    cleanup "error"
    exit 1
}
log_and_notify "INFO" "✅ Sequelize dump uploaded successfully" true

rclone copy $TEMP_DIR/sequelize_${DATE}.sql $GDRIVE_SEQUELIZE_SQL/ || {
    notify_discord "ERROR" "❌ Failed to upload Sequelize SQL backup\n\nℹ️ Error occurred during upload to Google Drive"
    cleanup "error"
    exit 1
}
log_and_notify "INFO" "✅ Sequelize SQL uploaded successfully" true

rclone copy $TEMP_DIR/prisma_${DATE}.dump $GDRIVE_PRISMA_DUMP/ || {
    notify_discord "ERROR" "❌ Failed to upload Prisma dump backup\n\nℹ️ Error occurred during upload to Google Drive"
    cleanup "error"
    exit 1
}
log_and_notify "INFO" "✅ Prisma dump uploaded successfully" true

rclone copy $TEMP_DIR/prisma_${DATE}.sql $GDRIVE_PRISMA_SQL/ || {
    notify_discord "ERROR" "❌ Failed to upload Prisma SQL backup\n\nℹ️ Error occurred during upload to Google Drive"
    cleanup "error"
    exit 1
}
log_and_notify "INFO" "✅ Prisma SQL uploaded successfully" true

# Function to check disk space
check_disk_space() {
    local REQUIRED_SPACE=${REQUIRED_DISK_SPACE:-5120}  # Default 5GB if not set
    local AVAILABLE_SPACE=$(df -m /tmp | awk 'NR==2 {print $4}')
    
    if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
        log "❌ Error: Insufficient disk space. Required: ${REQUIRED_SPACE}MB, Available: ${AVAILABLE_SPACE}MB"
        return 1
    fi
}

# Function to report backup sizes
report_backup_sizes() {
    log "📊 Backup sizes:"
    log "Sequelize dump: $(du -h $TEMP_DIR/sequelize_${DATE}.dump | cut -f1)"
    log "Sequelize SQL: $(du -h $TEMP_DIR/sequelize_${DATE}.sql | cut -f1)"
    log "Prisma dump: $(du -h $TEMP_DIR/prisma_${DATE}.dump | cut -f1)"
    log "Prisma SQL: $(du -h $TEMP_DIR/prisma_${DATE}.sql | cut -f1)"
}

# Function to cleanup old backups
cleanup_old_backups() {
    local RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-30}  # Use from env or default to 30
    
    log "🧹 Cleaning up old backups (older than ${RETENTION_DAYS} days)..."
    
    # Cleanup local backups and logs
    find $BACKUP_DIR -name "*.dump" -mtime +${RETENTION_DAYS} -delete
    find $BACKUP_DIR -name "*.sql" -mtime +${RETENTION_DAYS} -delete
    find $LOG_DIR -name "*.log" -mtime +${RETENTION_DAYS} -delete
    
    # Cleanup temporary directory
    rm -rf $TEMP_DIR/*
}

# Function to check database health
check_database_health() {
    local CONTAINER=$1
    local DB=$2
    
    log "🏥 Checking database health for ${DB}..."
    
    # Check if database is accepting connections
    if ! docker exec $CONTAINER pg_isready -U $DB_USER; then
        log "❌ Database is not accepting connections"
        return 1
    fi
    
    # Check for active connections
    local ACTIVE_CONNECTIONS=$(docker exec $CONTAINER psql -U $DB_USER -d $DB -t -c "SELECT count(*) FROM pg_stat_activity;")
    log "Active connections: ${ACTIVE_CONNECTIONS}"
    
    # Check database size
    local DB_SIZE=$(docker exec $CONTAINER psql -U $DB_USER -d $DB -t -c "SELECT pg_size_pretty(pg_database_size('${DB}'));")
    log "Database size: ${DB_SIZE}"
}

# After successful backup creation
log_and_notify "INFO" "📦 Backup files created successfully\n• Sequelize DB\n• Prisma DB" true

# After successful validation
log_and_notify "INFO" "✅ Backup validation completed successfully" true

# At the end of successful backup
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
DURATION_FORMAT=$(printf '%02dh:%02dm:%02ds' $((DURATION/3600)) $((DURATION%3600/60)) $((DURATION%60)))

# Send success message
send_success_message "$DURATION_FORMAT"

# Call cleanup without error
cleanup "success"

# Function to send success message
send_success_message() {
    local duration=$1
    
    # Get file sizes
    local seq_dump_size=$(du -h "$TEMP_DIR/sequelize_${DATE}.dump" | cut -f1)
    local seq_sql_size=$(du -h "$TEMP_DIR/sequelize_${DATE}.sql" | cut -f1)
    local prisma_dump_size=$(du -h "$TEMP_DIR/prisma_${DATE}.dump" | cut -f1)
    local prisma_sql_size=$(du -h "$TEMP_DIR/prisma_${DATE}.sql" | cut -f1)
    
    local message="**🔄 Database Backup Report**\n\n"
    message+="**⏱️ Duration:** ${duration}\n\n"
    message+="**📊 Backup Status:**\n"
    message+="```\n"
    message+="✅ Sequelize Database\n"
    message+="   └─ Dump: ${seq_dump_size}\n"
    message+="   └─ SQL:  ${seq_sql_size}\n\n"
    message+="✅ Prisma Database\n"
    message+="   └─ Dump: ${prisma_dump_size}\n"
    message+="   └─ SQL:  ${prisma_sql_size}\n"
    message+="```\n\n"
    message+="**🔍 Validation Status:**\n"
    message+="```\n"
    message+="✓ Backup files created\n"
    message+="✓ Validation completed\n"
    message+="✓ Files uploaded to Drive\n"
    message+="```\n\n"
    message+="**🕒 Completed at:** $(date '+%Y-%m-%d %H:%M:%S')"
    
    if [ -n "$DISCORD_WEBHOOK_URL" ]; then
        curl -H "Content-Type: application/json" \
             -d "{\"content\":\"$message\"}" \
             "$DISCORD_WEBHOOK_URL"
    fi
}