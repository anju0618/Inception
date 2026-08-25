#!/bin/bash
set -e

# .envのBACKUP_INTERVAL_HOURSを元にcronの実行間隔を組み立てて登録する
echo "0 */${BACKUP_INTERVAL_HOURS} * * * root /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1" > /etc/cron.d/backup-cron
chmod 0644 /etc/cron.d/backup-cron
crontab /etc/cron.d/backup-cron
touch /var/log/backup.log

# 起動直後にも1回バックアップを取っておく(cronの初回発火まで待たなくて良いように)
/usr/local/bin/backup.sh || true

# cronをフォアグラウンドで起動(execでPID1を明け渡す)
exec cron -f
