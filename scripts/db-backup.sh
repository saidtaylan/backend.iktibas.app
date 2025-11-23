#!/bin/bash
#
# Complete PostgreSQL Database Backup Script for Self-Hosted Supabase
# Backs up all roles, schemas, and data using pg_dumpall.
# Reads password and username from the .env file.
#

# --- SETTINGS: ADJUST THESE FIELDS ACCORDING TO YOUR SETUP ---

# 1. FULL PATH to your Supabase project (where docker-compose.yml is)
#    DO NOT USE $(pwd) as it will run in cron. Write the full path.
#    EXAMPLE: PROJECT_DIR="/opt/iktibas/backend.iktibas.app"
PROJECT_DIR="/opt/iktibas/backend.iktibas.app"

# 2. Directory where backups will be stored
#    Ensure this directory exists and you have write permissions.
BACKUP_DIR="/opt/db-backups"

# 3. How many days of backups to keep? (E.g.: 60 = delete backups older than 60 days)
RETENTION_DAYS=60

# 4. Name of your database service in Docker Compose (usually 'db')
DB_SERVICE_NAME="db"

# 5. Name of your superuser (NOTE: This should be the same as POSTGRES_USER in your .env file)
DB_SUPERUSER="supabase_admin"

# --- SCRIPT SETTINGS END ---

# Full path to the .env file
ENV_FILE="$PROJECT_DIR/.env"

# For error checking
set -o pipefail

# --- CHECK AND READ THE .env FILE ---

if [ ! -f "$ENV_FILE" ]; then
    echo "$(date): ERROR: .env file not found: $ENV_FILE"
    exit 1
fi

# Read POSTGRES_PASSWORD from the .env file
# (tr -d '\r' added to clean up Windows line endings (\r))
DB_PASSWORD=$(grep -E '^POSTGRES_PASSWORD=' "$ENV_FILE" | cut -d '=' -f2- | tr -d '\r')

if [ -z "$DB_PASSWORD" ]; then
    echo "$(date): ERROR: POSTGRES_PASSWORD not found in .env file."
    exit 1
fi

# --- BACKUP PROCESS ---

# Ensure the backup directory exists
mkdir -p $BACKUP_DIR

# File name (E.g.: supabase_backup_2025-11-03_2115.sql.gz)
FILENAME="supabase_backup_$(date +%Y-%m-%d_%H%M).sql.gz"
BACKUP_FILE_PATH="$BACKUP_DIR/$FILENAME"

echo "$(date): Backup starting: $FILENAME"

# Execute docker compose exec command with PGPASSWORD and PGUSER variables
# -T flag prevents terminal allocation so it can run inside cron
# PGPASSWORD and PGUSER are read by the pg_dumpall command INSIDE the container
docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T \
  -e PGPASSWORD="$DB_PASSWORD" \
  -e PGUSER="$DB_SUPERUSER" \
  $DB_SERVICE_NAME \
  pg_dumpall | gzip > $BACKUP_FILE_PATH

# Check command success status
if [ $? -eq 0 ]; then
  echo "$(date): Success: Backup completed and saved to: $BACKUP_FILE_PATH"
else
  echo "$(date): ERROR: An issue occurred during backup."
  rm -f $BACKUP_FILE_PATH # Delete the empty file if it failed
  exit 1
fi

# --- CLEANUP PROCESS ---

echo "$(date): Cleaning up old backups (Retention: $RETENTION_DAYS days)..."
find $BACKUP_DIR -name "supabase_backup_*.sql.gz" -mtime +$RETENTION_DAYS -exec rm {} \;

echo "$(date): Cleanup complete."
echo "---"

exit 0