#!/bin/bash
set -e

echo "0 */${BACKUP_INTERVAL_HOURS} * * * root /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1" > /etc/cron.d/backup-cron
chmod 0644 /etc/cron.d/backup-cron
crontab /etc/cron.d/backup-cron
touch /var/log/backup.log

/usr/local/bin/backup.sh || true

exec cron -f
