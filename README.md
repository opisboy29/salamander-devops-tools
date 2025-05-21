# DevOps Database Backup & Migration Toolkit

A comprehensive collection of tools for database backup, migration, and transfer operations across various database systems.

## 🛠️ Tools Included

This repository contains the following tools:

### 📦 PostgreSQL Backup Tool

Located in `postgres-backup/`, this tool provides automated PostgreSQL database backup with validation, cloud storage, and notification features.

**Key Features:**
- Automatic backup of Sequelize and Prisma databases
- Multiple backup formats (SQL and binary dumps)
- Backup validation through test restoration
- Discord notifications for backup status
- Google Drive integration for cloud storage

**[Go to PostgreSQL Backup Tool →](./postgres-backup/)**

### 🔄 PostgreSQL Migration Tool

Located in `postgres-migration/`, this tool automates the migration of PostgreSQL databases between servers using SSH and Docker.

**Key Features:**
- Full database export and import between servers
- Support for schema-only or data-only migrations
- SSH key-based authentication
- Automatic cleanup of temporary files

**[Go to PostgreSQL Migration Tool →](./postgres-migration/)**

### 💾 MongoDB Backup Tool

Located in `mongodb-backup/`, this tool provides automated MongoDB database backup with validation and cloud storage integration.

**Key Features:**
- Backup of all collections in a MongoDB database
- Validation through test restoration
- Document count comparison for data verification
- Cloud storage integration via rclone
- Comprehensive error handling

**[Go to MongoDB Backup Tool →](./mongodb-backup/)**

### 📤 MinIO Bucket Migration Tool

Located in `minio-migration/`, this tool enables transfer of MinIO buckets between servers.

**Key Features:**
- Transfer buckets between production and staging MinIO servers
- SSH and Docker-based operation
- Automatic cleanup of temporary files
- Support for filtering specific buckets

**[Go to MinIO Migration Tool →](./minio-migration/)**

## 🚀 Getting Started

Each tool has its own dedicated directory with:
- Detailed README with instructions
- Bash script implementing the functionality
- Configuration example (.env.example)

To use any of the tools:

1. Navigate to the tool's directory
2. Copy the `.env.example` file to `.env` and configure it
3. Make the script executable with `chmod +x <script-name>.sh`
4. Run the script with `./<script-name>.sh`

## 📋 Requirements

Each tool has specific requirements, but generally you'll need:

- Bash 4.0+
- Docker
- SSH access (for migration tools)
- rclone (for cloud storage integration)
- Database-specific clients (PostgreSQL, MongoDB, MinIO)

See individual tool READMEs for detailed requirements.

## 🔒 Security Considerations

- Scripts use environment variables to store sensitive information
- SSH key-based authentication is recommended
- Temporary files are automatically cleaned up
- Backups can be encrypted (see tool-specific documentation)

## 📝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is open source and available under the [MIT License](LICENSE). 