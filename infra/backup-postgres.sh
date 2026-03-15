#!/bin/bash
set -e

PROJECT_DIR="/opt/go-flutter-messenger"
BACKUP_DIR="$PROJECT_DIR/backups"
TIMESTAMP=$(date +%F_%H-%M-%S)
CONTAINER="go-flutter-messenger-postgres"

# Use same DB name/user as docker-compose (.env)
if [ -f "$PROJECT_DIR/.env" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$PROJECT_DIR/.env"
  set +a
fi
DB_NAME="${POSTGRES_DB:-messenger}"
DB_USER="${POSTGRES_USER:-messenger}"

mkdir -p "$BACKUP_DIR"

docker exec "$CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" > "$BACKUP_DIR/postgres_$TIMESTAMP.sql"

# Keep only last 7 days
find "$BACKUP_DIR" -type f -name "postgres_*.sql" -mtime +7 -delete
