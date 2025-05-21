# MongoDB Backup Tool

A comprehensive backup solution for MongoDB databases with restoration validation.

## Features

- Automatic backup of all collections in a MongoDB database
- Validation through test restoration to ensure backup integrity
- Document count comparison with tolerance for data verification
- Automatic upload to cloud storage
- Cleanup of temporary files
- Error handling and detailed logging

## Technology Stack Requirements

- **Bash**: Script runs on Bash shell 4.0+
- **Docker**: Running MongoDB containers
- **MongoDB Tools**: mongodump, mongorestore, mongosh utilities
- **rclone**: For cloud storage integration (see [Rclone Configuration](#rclone-configuration))
- **coreutils**: For basic file operations (df, du, etc.)
- **SSH**: For remote server operations (optional)
- **jq**: For JSON parsing and manipulation

## Prerequisites

- Docker containers running MongoDB databases
- rclone configured for cloud storage access
- Sufficient disk space for temporary backup files (at least 2GB recommended)
- MongoDB command-line tools (mongodump, mongorestore, mongosh)

## Setup

1. Copy `.env.example` to `.env`
2. Configure the environment variables in `.env` to match your MongoDB setup
3. Make the script executable: `chmod +x mongo-backup.sh`
4. Configure rclone for your preferred cloud storage (see [Rclone Configuration](#rclone-configuration))
5. Create necessary directories: `mkdir -p backups logs temp`

## Configuration

The following environment variables need to be configured:

### MongoDB Configuration
- `SOURCE_CONTAINER_ID`: The container ID of the source MongoDB
- `RESTORE_CONTAINER_ID`: The container ID for test restoration
- `MONGO_DB_NAME`: The database name to backup
- `MONGO_RESTORE_DB_NAME`: The database name for test restoration

### MongoDB Connection
- `MONGO_HOST`: MongoDB host address
- `MONGO_PORT`: MongoDB port
- `MONGO_USERNAME`: MongoDB username
- `MONGO_PASSWORD`: MongoDB password
- `MONGO_AUTH_DB`: Authentication database name

### Backup Configuration
- `BACKUP_BASE_DIR`: Base directory for backups
- `MONGO_BACKUP_DIR`: Directory for MongoDB backups
- `CLOUD_REMOTE_PATH`: rclone path for cloud storage (e.g., `gdrive:/backup/mongodb/`)

## Rclone Configuration

This backup script uses [rclone](https://rclone.org/) to upload backups to cloud storage. Here's how to set it up:

1. **Install rclone**:
   ```bash
   # Linux
   curl https://rclone.org/install.sh | sudo bash

   # macOS
   brew install rclone

   # Windows - Use the installer from https://rclone.org/downloads/
   ```

2. **Configure rclone with your cloud storage provider**:
   ```bash
   rclone config
   ```

3. **Follow the interactive setup**. For example, to configure Google Drive:
   - Choose `n` for a new remote
   - Enter a name for the remote (e.g., `gdrive`)
   - Select `Google Drive` from the list of providers
   - Set up OAuth authentication as prompted
   - Set the scope as needed (usually `drive` for full access)
   - Follow remaining prompts to complete setup

4. **Update the `.env` file with your rclone remote path**:
   ```
   CLOUD_REMOTE_PATH="gdrive:/backup/mongodb/"
   ```
   Replace `gdrive` with the name you chose for your remote, and set the desired path.

5. **Test your rclone configuration**:
   ```bash
   rclone lsd gdrive:/
   ```

For more information about rclone setup for specific cloud providers, refer to the [rclone documentation](https://rclone.org/docs/).

## Usage

```bash
./mongo-backup.sh
```

The script performs the following steps:
1. Connects to the source MongoDB container
2. Exports all collections to backup files
3. Tests the backup by restoring to a test container
4. Verifies data integrity by comparing document counts
5. Creates a compressed archive of the backup
6. Uploads the backup to cloud storage
7. Cleans up all temporary files

## Verification Process

The backup includes a verification stage where:
- Each collection is restored to a test database
- Document counts are compared between source and restored collections
- A 1% tolerance is allowed to account for potential changes during backup
- Multiple retries are performed if verification fails initially

## Scheduling with Cron

You can schedule the backup script to run automatically using cron:

```bash
# Edit crontab
crontab -e

# Add a line to run the backup daily at 3 AM
0 3 * * * /path/to/mongodb-backup/mongo-backup.sh
```

Make sure the script has all necessary permissions and environment variables are correctly set.

## Error Handling

The script includes comprehensive error handling:
- Container connectivity checks
- Backup and restore operation validation
- Automatic cleanup on script failure via trap handlers

## Troubleshooting

### Common Issues

1. **MongoDB connection issues**:
   - Verify container IDs are correct
   - Check MongoDB credentials
   - Ensure MongoDB is running and accessible

2. **rclone authentication issues**:
   - Verify your rclone configuration with `rclone config show`
   - Ensure API access is enabled for your cloud provider
   - Re-authenticate if tokens have expired

3. **Space issues**:
   - Ensure sufficient space in temp directory
   - Check if old backups are being properly cleaned up

4. **Validation failures**:
   - Check if MongoDB is under heavy load during backup
   - Increase tolerance percentage for document count verification
   - Examine logs for specific collection issues

## Supported Cloud Storage Providers

Rclone supports many cloud storage providers, including:
- Google Drive
- Dropbox
- Amazon S3
- Microsoft OneDrive
- Backblaze B2
- SFTP
- And many more

Configure your preferred provider with `rclone config` and update the `CLOUD_REMOTE_PATH` variable accordingly. 