# PostgreSQL Backup Tool

A comprehensive solution for backing up multiple PostgreSQL databases with validation and cloud storage integration.

## Features

- Automatic backup of Sequelize and Prisma databases
- Multiple backup formats (SQL dump and binary dump)
- Backup validation through test restoration
- Table structure and data integrity verification
- Discord notifications for backup status
- Google Drive integration for cloud storage
- Automatic cleanup of old backups

## Technology Stack Requirements

- **Bash**: Script runs on Bash shell 4.0+
- **Docker**: Running PostgreSQL containers
- **PostgreSQL**: 12.0+ with pg_dump, createdb, dropdb utilities
- **rclone**: For cloud storage integration (see [rclone setup](#rclone-setup))
- **curl**: For sending Discord notifications
- **coreutils**: For basic file operations (df, du, etc.)
- **SSH**: For remote server operations (optional)

## Prerequisites

- Docker containers running PostgreSQL databases
- rclone configured for Google Drive access
- Discord webhook URL (optional but recommended for monitoring)
- Sufficient disk space for temporary backup files (at least 5GB recommended)
- PostgreSQL command-line tools (psql, pg_dump, pg_restore)

## Setup

1. Copy `.env.example` to `.env`
2. Configure the environment variables in `.env` to match your PostgreSQL setup
3. Make sure the script is executable: `chmod +x postgres-backup.sh`
4. Configure rclone for Google Drive access (see [rclone setup](#rclone-setup))
5. Create necessary directories: `mkdir -p backups logs temp`

## rclone Setup

rclone is used to transfer backup files to Google Drive. Follow these steps to set it up:

1. **Install rclone**:
   ```bash
   # Linux
   curl https://rclone.org/install.sh | sudo bash

   # macOS
   brew install rclone

   # Windows - Use the installer from https://rclone.org/downloads/
   ```

2. **Configure rclone for Google Drive**:
   ```bash
   rclone config
   ```

3. **Follow the interactive configuration**:
   - Select `n` for new remote
   - Enter a name for your remote (e.g., `gdrive`)
   - Select Google Drive from the list
   - Follow the authentication process in your browser
   - Select appropriate access level
   - For team drives, answer additional questions as needed

4. **Test your configuration**:
   ```bash
   rclone lsd gdrive:
   ```

5. **Update your .env file** with the proper rclone paths:
   ```
   GDRIVE_SEQUELIZE_DUMP=gdrive:backup/production/postgres/sequelize/dump
   GDRIVE_SEQUELIZE_SQL=gdrive:backup/production/postgres/sequelize/sql
   GDRIVE_PRISMA_DUMP=gdrive:backup/production/postgres/prisma/dump
   GDRIVE_PRISMA_SQL=gdrive:backup/production/postgres/prisma/sql
   ```

## Discord Webhook Setup

To enable Discord notifications:

1. Create a Discord webhook in your server settings
2. Copy the webhook URL to your `.env` file
3. Test the webhook with a simple command:
   ```bash
   curl -H "Content-Type: application/json" -d '{"content":"Test notification from backup script"}' "YOUR_WEBHOOK_URL"
   ```

## Configuration

The following environment variables need to be configured:

### Database Connection
- `DB_USER`: PostgreSQL username
- `DB_PASSWORD`: PostgreSQL password
- `DB_HOST`: PostgreSQL host address

### Container Names
- `SEQUELIZE_CONTAINER`: Container ID/name for Sequelize database
- `PRISMA_CONTAINER`: Container ID/name for Prisma database
- `RESTORE_CONTAINER`: Container ID/name for test restoration

### Database Names
- `SEQUELIZE_DB`: Name of the Sequelize database
- `PRISMA_DB`: Name of the Prisma database

### Google Drive Paths (rclone)
- `GDRIVE_SEQUELIZE_DUMP`: rclone path for Sequelize dump backups
- `GDRIVE_SEQUELIZE_SQL`: rclone path for Sequelize SQL backups
- `GDRIVE_PRISMA_DUMP`: rclone path for Prisma dump backups
- `GDRIVE_PRISMA_SQL`: rclone path for Prisma SQL backups

### Discord Webhook
- `DISCORD_WEBHOOK_URL`: URL for Discord notifications

### Optional Settings
- `BACKUP_RETENTION_DAYS`: Number of days to keep backup files (default: 30)
- `REQUIRED_DISK_SPACE`: Minimum required disk space in MB (default: 5120)

## Usage

```bash
./postgres-backup.sh
```

## Backup Process

The script performs the following steps:
1. Creates backup directory structure
2. Performs database backups in both SQL and binary dump formats
3. Validates backups by restoring to a test container
4. Verifies table structure and record counts
5. Uploads backups to Google Drive
6. Sends status notifications to Discord
7. Cleans up temporary files and old backups

## Directory Structure

The script creates and manages the following directories:
- `backups/`: Stores local backup files
- `logs/`: Contains log files with detailed information
- `temp/`: Used for temporary files during backup process

## Discord Notifications

The script sends notifications to Discord at each major step:
- Backup process start
- Backup file creation
- Validation status
- Upload status
- Completion with summary of file sizes and duration

## Scheduling with Cron

You can schedule the backup script to run automatically using cron:

```bash
# Edit crontab
crontab -e

# Add a line to run the backup daily at 2 AM
0 2 * * * /path/to/postgres-backup/postgres-backup.sh
```

Make sure the script has all necessary permissions and environment variables are correctly set.

## Troubleshooting

### Common Issues

1. **rclone authentication issues**:
   - Verify your rclone configuration with `rclone config show`
   - Ensure Google Drive API access is enabled
   - Re-authenticate if tokens have expired

2. **Docker container access**:
   - Ensure the user running the script has permissions to access Docker
   - Verify container names/IDs are correct
   - Check that PostgreSQL is running in the containers

3. **Space issues**:
   - Ensure sufficient space in temp directory
   - Check if old backups are being properly cleaned up

4. **Discord webhook errors**:
   - Verify webhook URL is valid and not revoked
   - Check network connectivity to Discord API

## Notes on Script Implementation

This repository includes the `.env.example` file but does not include the complete script implementation to maintain security. The full script is available in the organization's private repository and should include:

1. Comprehensive error handling
2. Database connection and validation functions
3. Backup creation and testing
4. Discord notification functions
5. Google Drive upload functions
6. Cleanup and retention policy management

Contact your system administrator for access to the complete script. 