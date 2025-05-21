# PostgreSQL Database Migration Tool

This tool automates the migration of a PostgreSQL database from a source server to a destination server.

## Features

- SSH and Docker-based migration
- Full database export and import
- Automatic cleanup of temporary files
- Error handling and validation
- Support for schema-only or data-only migrations
- Optional custom SQL execution post-migration

## Technology Stack Requirements

- **Bash**: Script runs on Bash shell 4.0+
- **Docker**: Running on both source and destination servers
- **PostgreSQL Client**: pg_dump, psql utilities
- **SSH**: For remote server access and file transfer
- **scp/rsync**: For efficient file transfer
- **coreutils**: For basic file operations
- **gzip**: For compression/decompression (optional)

## Prerequisites

- SSH access to both source and destination servers
- Docker running on both servers with PostgreSQL containers
- SSH key-based authentication configured
- PostgreSQL client tools installed
- Sufficient disk space for temporary database dumps
- Network connectivity between servers

## Installation

### PostgreSQL Client Tools

If PostgreSQL client tools are not already installed:

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install postgresql-client

# CentOS/RHEL
sudo yum install postgresql

# macOS
brew install postgresql

# Windows - Download from https://www.postgresql.org/download/windows/
```

## Setup

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/postgres-migration.git
   cd postgres-migration
   ```

2. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```

3. Fill in the variables in `.env` with your server and database details:
   ```
   # Source Database
   SRC_POSTGRES_CONTAINER=source_container_id
   SRC_POSTGRES_USER=postgres_user
   SRC_POSTGRES_PASSWORD=postgres_password
   SRC_POSTGRES_DB=database_name
   SRC_SERVER_IP=source_server_ip
   SRC_SERVER_USERNAME=ssh_username

   # Destination Database
   DST_POSTGRES_CONTAINER=destination_container_id
   DST_POSTGRES_USER=postgres_user
   DST_POSTGRES_PASSWORD=postgres_password
   DST_POSTGRES_DB=database_name
   DST_SERVER_IP=destination_server_ip
   DST_SERVER_USERNAME=ssh_username
   ```

4. Make the script executable:
   ```bash
   chmod +x postgres-e2e.sh
   ```

5. Set up SSH key-based authentication (if not already configured):
   ```bash
   # Generate SSH key if you don't have one
   ssh-keygen -t rsa -b 4096

   # Copy your key to the source server
   ssh-copy-id your_ssh_username@source_server_ip

   # Copy your key to the destination server
   ssh-copy-id your_ssh_username@destination_server_ip
   ```

## Usage

```bash
./postgres-e2e.sh [options]
```

Options:
- `--schema-only`: Migrate only the database schema (no data)
- `--data-only`: Migrate only the data (no schema)
- `--post-sql=file.sql`: Execute custom SQL after migration

The script will automatically:

1. Validate SSH connections to both servers
2. Export the database from the source server
3. Transfer the dump file to the local machine
4. Transfer the dump file to the destination server
5. Import the database to the destination server
6. Execute any post-migration SQL if specified
7. Clean up temporary files

## Environment Variables

### Source Database
- `SRC_POSTGRES_CONTAINER`: Container ID of the source PostgreSQL
- `SRC_POSTGRES_USER`: PostgreSQL username for the source database
- `SRC_POSTGRES_PASSWORD`: PostgreSQL password for the source database
- `SRC_POSTGRES_DB`: Name of the source database
- `SRC_SERVER_IP`: IP address of the source server
- `SRC_SERVER_USERNAME`: SSH username for the source server

### Destination Database
- `DST_POSTGRES_CONTAINER`: Container ID of the destination PostgreSQL
- `DST_POSTGRES_USER`: PostgreSQL username for the destination database
- `DST_POSTGRES_PASSWORD`: PostgreSQL password for the destination database
- `DST_POSTGRES_DB`: Name of the destination database
- `DST_SERVER_IP`: IP address of the destination server
- `DST_SERVER_USERNAME`: SSH username for the destination server

### Additional Configuration
- `TEMP_DIR`: Local temporary directory (default: `/tmp/postgres-migration`)
- `DUMP_FORMAT`: Format for pg_dump (default: `c` for custom)
- `COMPRESSION`: Use compression for transfer (true/false, default: true)
- `TRANSFER_METHOD`: Method for file transfer (scp/rsync, default: scp)

## Scheduling with Cron

You can schedule the migration to run automatically using cron:

```bash
# Edit crontab
crontab -e

# Add a line to run the migration weekly on Saturday at 2 AM
0 2 * * 6 /path/to/postgres-migration/postgres-e2e.sh
```

## Error Handling

The script includes error handling for:
- SSH connection failures
- Docker container validation
- Database dump and restore errors
- File transfer problems
- Permission issues

## Troubleshooting

### Common Issues

1. **SSH Connection Issues**:
   - Verify SSH key is properly configured
   - Check network connectivity between servers
   - Ensure firewall rules allow SSH connections

2. **PostgreSQL Access Issues**:
   - Verify container IDs are correct
   - Check PostgreSQL credentials
   - Ensure containers are running and accessible

3. **Space Issues**:
   - Check for sufficient disk space on source, local, and destination servers
   - Use compression for large databases
   - Clean up old dump files

4. **Permission Problems**:
   - Ensure user has necessary permissions on all servers
   - Check file permissions for temporary directories
   - Verify Docker access permissions

5. **Transfer Failures**:
   - Consider using rsync instead of scp for large databases
   - Check network stability between servers
   - Try reducing dump size by migrating in parts

## Security Considerations

- Use SSH key authentication instead of passwords
- Consider using dedicated user accounts with limited permissions
- Encrypt sensitive information in .env files
- Remove temporary database dumps immediately after transfer
- Use secure, unique passwords for database access 