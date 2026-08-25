#!/bin/bash
set -e

DB_ROOT_PASSWORD=$(cat "$MYSQL_ROOT_PASSWORD_FILE")
DB_PASSWORD=$(cat "$MYSQL_PASSWORD_FILE")

# データディレクトリが空 = 初回起動。この分岐は2回目以降スキップされる。
if [ ! -d /var/lib/mysql/mysql ]; then
    echo "Initializing MariaDB data directory..."
    # システムテーブル一式を作成する(mysql_install_db相当)
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql \
        --auth-root-authentication-method=normal > /dev/null

    chown -R mysql:mysql /var/lib/mysql /run/mysqld

    # 外部からアクセスできない一時起動(--skip-networking、ソケットのみ)でDB/ユーザーを準備する
    mariadbd --user=mysql --skip-networking --socket=/run/mysqld/mysqld.sock &
    pid="$!"

    # mariadbdの起動完了を待つ
    until mysqladmin --socket=/run/mysqld/mysqld.sock ping --silent 2>/dev/null; do
        sleep 1
    done

    mysql --socket=/run/mysqld/mysqld.sock -u root <<-EOSQL
        -- mariadb-install-db creates anonymous accounts (empty username) by
        -- default. Their Host value ('localhost' / the container hostname) is
        -- more specific than '%', so they are matched *before* our own
        -- '${MYSQL_USER}'@'%' account for local/socket connections, causing
        -- "Access denied" even with the correct password. Drop them, as
        -- mysql_secure_installation normally would.
        DELETE FROM mysql.user WHERE User = '';

        -- mariadb-install-db also creates 'root'@'127.0.0.1', 'root'@'::1' and
        -- 'root'@'<hostname>' with NO password. Only 'root'@'localhost' gets a
        -- password below, so without this, root is reachable password-less over
        -- TCP (e.g. 'mysql -h <hostname> -u root') -- exactly what a 42 defense
        -- explicitly tests for and instantly fails on. Keep only 'root'@'localhost'.
        DELETE FROM mysql.user WHERE User = 'root' AND Host != 'localhost';

        CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
        CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
        GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
        ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
        FLUSH PRIVILEGES;
EOSQL

    # 一時起動していたmariadbdを止める(この後、通常モードで改めて起動し直す)
    mysqladmin --socket=/run/mysqld/mysqld.sock -u root -p"${DB_ROOT_PASSWORD}" shutdown
    wait "$pid" 2>/dev/null || true
    echo "MariaDB initialization complete."
else
    chown -R mysql:mysql /var/lib/mysql /run/mysqld
fi

# 通常モード(ネットワーク有効)でフォアグラウンド起動。execでPID1を明け渡す。
exec mariadbd --user=mysql
