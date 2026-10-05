# Host to Remote MinIO Container Migration Tool

A tool to migrate data from host folders on Server A to MinIO buckets in containers on Server B.

## Features

- Migrate data from local host folders to remote MinIO buckets
- Cross-server data transfer using SSH and rsync/scp
- Automatic bucket creation on remote MinIO
- Progress monitoring and verification
- Support for various MinIO configurations
- Command-line options and environment variables
- Error handling and cleanup

## Prerequisites

- SSH access to remote server
- Docker with MinIO container running on remote server
- MinIO client (mc) will be installed automatically
- Sufficient disk space for data transfer
- Network connectivity between servers

## Installation

1. Make the script executable:
   ```bash
   chmod +x host-to-minio-remote.sh
   ```

2. Set up SSH key-based authentication:
   ```bash
   # Generate SSH key if you don't have one
   ssh-keygen -t rsa -b 4096
   
   # Copy your key to the remote server
   ssh-copy-id username@remote-server
   ```

3. Create a `.env` file (optional):
   ```bash
   cp .env.example .env
   ```

## Usage

### Basic Usage

```bash
# Migrate data from /path/to/data to bucket 'uploads' on remote server
./host-to-minio-remote.sh -s /path/to/data -b uploads -r 192.168.1.100 -u admin -c minio-container

# Using environment variables
SOURCE_FOLDER=/data BUCKET_NAME=uploads REMOTE_SERVER=prod.example.com REMOTE_USER=admin ./host-to-minio-remote.sh
```

### Command Line Options

```bash
-s, --source PATH      Source folder path (default: /tmp/data)
-b, --bucket NAME      Bucket name (default: migrated-data)
-r, --remote HOST      Remote server hostname/IP
-u, --user USER        SSH username for remote server
-c, --container ID     MinIO container ID on remote server (default: minio)
-h, --host HOST        MinIO host on remote server (default: localhost)
-p, --port PORT        MinIO port on remote server (default: 9000)
-a, --access KEY       MinIO access key (default: minioadmin)
-k, --secret KEY       MinIO secret key (default: minioadmin)
--help                 Show help message
```

### Environment Variables

```bash
SOURCE_FOLDER          Source folder path
BUCKET_NAME            Target bucket name
REMOTE_SERVER          Remote server hostname/IP
REMOTE_USER            SSH username for remote server
CONTAINER_ID           MinIO container ID on remote server
MINIO_HOST             MinIO server host on remote server
MINIO_PORT             MinIO server port on remote server
MINIO_ACCESS_KEY       MinIO access key
MINIO_SECRET_KEY       MinIO secret key
```

## Examples

### Example 1: Basic Remote Migration

```bash
./host-to-minio-remote.sh \
  -s /var/www/uploads \
  -b user-uploads \
  -r 192.168.1.100 \
  -u admin \
  -c minio-prod
```

### Example 2: Using Environment Variables

```bash
export SOURCE_FOLDER="/data/documents"
export BUCKET_NAME="documents"
export REMOTE_SERVER="prod.example.com"
export REMOTE_USER="admin"
export CONTAINER_ID="minio-staging"

./host-to-minio-remote.sh
```

### Example 3: Custom MinIO Configuration

```bash
./host-to-minio-remote.sh \
  -s /backup/files \
  -b backup-2024 \
  -r minio.example.com \
  -u backup-user \
  -c minio-backup \
  -h minio.example.com \
  -p 9000 \
  -a myaccesskey \
  -k mysecretkey
```

## Process Flow

1. **SSH Connection**: Test connection to remote server
2. **Validation**: Check source folder and remote MinIO container
3. **Preparation**: Count files and prepare data
4. **Data Transfer**: Transfer data from local to remote server
5. **Configuration**: Set up MinIO client in remote container
6. **Bucket Management**: Create target bucket if needed
7. **Upload**: Transfer data from remote server to MinIO bucket
8. **Verification**: Verify upload and count objects
9. **Cleanup**: Remove temporary files

## Performance Optimization

### Using rsync (Recommended)

The script automatically uses `rsync` if available for efficient transfer:

```bash
# Install rsync if not available
# Ubuntu/Debian
sudo apt-get install rsync

# CentOS/RHEL
sudo yum install rsync

# macOS
brew install rsync
```

### Network Optimization

```bash
# Use compression for slow connections
rsync -avz --compress-level=6 /source/ user@server:/dest/

# Limit bandwidth usage
rsync -avz --bwlimit=1000 /source/ user@server:/dest/
```

## Troubleshooting

### Common Issues

1. **SSH Connection Issues**:
   ```bash
   # Test SSH connection
   ssh -v user@remote-server
   
   # Check SSH key
   ssh-add -l
   ```

2. **Permission Denied**:
   ```bash
   # Check folder permissions
   ls -la /path/to/source
   chmod -R 755 /path/to/source
   ```

3. **Remote Container Not Running**:
   ```bash
   # Check remote container
   ssh user@remote-server "docker ps | grep minio"
   ```

4. **Insufficient Space**:
   ```bash
   # Check local space
   df -h
   
   # Check remote space
   ssh user@remote-server "df -h"
   ```

### Debug Mode

Add `set -x` at the beginning of the script to enable debug output:

```bash
#!/bin/bash
set -x
# ... rest of script
```

## Security Considerations

- Use SSH key authentication instead of passwords
- Limit SSH user permissions on remote server
- Use strong MinIO access keys and secrets
- Consider using VPN for sensitive data
- Verify data integrity after upload

## Integration

### Cron Job

```bash
# Daily backup at 2 AM
0 2 * * * /path/to/host-to-minio-remote.sh -s /data/uploads -b daily-backup -r prod.example.com -u admin
```

### Docker Compose

```yaml
services:
  migration:
    image: alpine:latest
    volumes:
      - .:/migration
      - /path/to/data:/data:ro
    command: /migration/host-to-minio-remote.sh -s /data -b my-bucket -r minio.example.com -u admin
    depends_on:
      - minio
```

## License

This tool is provided as-is for data migration purposes.
