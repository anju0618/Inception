#!/bin/bash
set -e

DB_PASSWORD=$(cat "$MYSQL_PASSWORD_FILE")
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DUMP_FILE="/backups/${MYSQL_DATABASE}_${TIMESTAMP}.sql.gz"

# WordPressのDBを丸ごとダンプし、圧縮して名前付きボリュームに保存する
mysqldump -h mariadb -u"${MYSQL_USER}" -p"${DB_PASSWORD}" "${MYSQL_DATABASE}" | gzip > "${DUMP_FILE}"
echo "$(date -Iseconds) backup created: ${DUMP_FILE}"

# 保持期間(日数)を超えた古いバックアップを削除する
find /backups -name "*.sql.gz" -mtime +"${BACKUP_RETENTION_DAYS}" -delete
