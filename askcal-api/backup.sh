#!/bin/sh
# Nightly Postgres backup for the Askcal VM.
# Dumps the running db container to a gzipped, timestamped file and keeps the
# last 14. Installed as a root cron job (see deploy notes). Run manually with:
#   sudo /home/nafeess/askcal-api/backup.sh
set -e

APP_DIR="/home/nafeess/askcal-api"
BACKUP_DIR="/home/nafeess/askcal-backups"
KEEP=14

mkdir -p "$BACKUP_DIR"
STAMP=$(date +%Y%m%d-%H%M%S)

cd "$APP_DIR"
docker compose -f docker-compose.prod.yml exec -T db \
  pg_dump -U askcal -d askcal --no-owner --no-privileges \
  | gzip > "$BACKUP_DIR/askcal-$STAMP.sql.gz"

# Retention: delete all but the newest $KEEP dumps.
ls -1t "$BACKUP_DIR"/askcal-*.sql.gz 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -f

echo "backup written: $BACKUP_DIR/askcal-$STAMP.sql.gz"
