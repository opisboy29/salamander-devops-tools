# MinIO Bucket Migration Tool

A simple tool to transfer buckets from production MinIO to staging MinIO.

## Features

- Transfer buckets between servers using SSH and Docker
- Automatic connection and transfer
- Error handling and validation
- Automatic cleanup of temporary files
- Support for filtering specific buckets
- Progress monitoring during transfer

## Technology Stack Requirements

- **Bash**: Script runs on Bash shell 4.0+
- **Docker**: Running on both source and destination servers
- **MinIO Client (mc)**: For bucket operations
- **SSH**: For remote server access and file transfer
- **rsync**: For efficient file transfer (optional)
- **coreutils**: For basic file operations
- **jq**: For JSON parsing (optional, if using configuration files)

## Prerequisites

- SSH access to staging server
- Docker running on both servers with MinIO containers
- SSH key-based authentication configured
- Sufficient disk space for temporary file storage
- Network connectivity between production and staging servers
- MinIO client (mc) installed on both servers

## Installation

### MinIO Client Installation

If MinIO client is not already installed:

```bash
# Linux
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/

# macOS
brew install minio/stable/mc

# Windows - Download from https://dl.min.io/client/mc/release/windows-amd64/mc.exe
```

## Setup

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/minio-migration.git
   cd minio-migration
   ```

2. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```

3. Fill in the variables in `.env` with your server and MinIO container details:
   ```
   PROD_CONTAINER_ID=your_production_container_id
   STAGING_SERVER=your_staging_server_ip
   STAGING_USER=your_ssh_username
   STAGING_CONTAINER_ID=your_staging_container_id
   ```

4. Make the script executable:
   ```bash
   chmod +x minio-transfer.sh
   ```

5. Set up SSH key-based authentication (if not already configured):
   ```bash
   # Generate SSH key if you don't have one
   ssh-keygen -t rsa -b 4096

   # Copy your key to the staging server
   ssh-copy-id your_ssh_username@your_staging_server_ip
   ```

## Usage

```bash
./minio-transfer.sh [bucket_name]
```

- If `bucket_name` is provided, only that specific bucket will be transferred
- If no bucket name is provided, all buckets will be transferred

The script will automatically:

1. Export data from production MinIO
2. Transfer data to staging server
3. Import data to staging MinIO
4. Clean up temporary files

## Environment Variables

- `PROD_CONTAINER_ID`: Production MinIO container ID
- `STAGING_SERVER`: Staging server IP address
- `STAGING_USER`: SSH username for staging server
- `STAGING_CONTAINER_ID`: Staging MinIO container ID
- `TEMP_DIR`: Local temporary directory for data (default: `/tmp/minio-migration`)
- `REMOTE_TEMP_DIR`: Remote temporary directory (default: `/tmp/minio-migration`)
- `TRANSFER_METHOD`: Transfer method to use (rsync or scp, default: scp)

## Scheduling with Cron

You can schedule the transfer to run automatically using cron:

```bash
# Edit crontab
crontab -e

# Add a line to run the transfer weekly on Sunday at 1 AM
0 1 * * 0 /path/to/minio-migration/minio-transfer.sh
```

## Troubleshooting

### Common Issues

1. **SSH Connection Issues**:
   - Verify SSH key is properly configured
   - Check network connectivity between servers
   - Ensure firewall rules allow SSH connections

2. **Docker Container Access**:
   - Verify container IDs are correct in .env file
   - Ensure Docker daemon is running on both servers
   - Check Docker permissions for current user

3. **MinIO Client Issues**:
   - Verify mc is installed and in PATH
   - Check MinIO server is running in containers
   - Verify access credentials if authentication is required

4. **Transfer Failures**:
   - Check disk space on both servers
   - Examine transfer logs for error messages
   - Try with a single bucket to isolate issues

## Security Considerations

- Use SSH key authentication instead of passwords
- Consider using dedicated user accounts with limited permissions
- Verify data integrity after transfer
- Remove temporary files immediately after transfer completes 