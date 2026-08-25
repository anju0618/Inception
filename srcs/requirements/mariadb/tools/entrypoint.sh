#!/bin/bash
set -e

DB_ROOT_PASSWORD=$(cat "$MYSQL_ROOT_PASSWORD_FILE")
DB_PASSWORD=$(cat "$MYSQL_PASSWORD_FILE")

if [ ! -d /var/lib/mysql/mysql ]; then
    echo "Initializing MariaDB data directory..."
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql \
        --auth-root-authentication-method=normal > /dev/null

    chown -R mysql:mysql /var/lib/mysql /run/mysqld

    mariadbd --user=mysql --skip-networking --socket=/run/mysqld/mysqld.sock &
    pid="$!"

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

        CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
        CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
        GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
        ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
        FLUSH PRIVILEGES;
EOSQL

    mysqladmin --socket=/run/mysqld/mysqld.sock -u root -p"${DB_ROOT_PASSWORD}" shutdown
    wait "$pid" 2>/dev/null || true
    echo "MariaDB initialization complete."
else
    chown -R mysql:mysql /var/lib/mysql /run/mysqld
fi

exec mariadbd --user=mysql
