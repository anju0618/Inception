#!/bin/bash
set -e

DB_PASSWORD=$(cat "$WORDPRESS_DB_PASSWORD_FILE")
WP_ADMIN_PASSWORD=$(cat "$WP_ADMIN_PASSWORD_FILE")
WP_USER_PASSWORD=$(cat "$WP_USER_PASSWORD_FILE")

echo "Waiting for MariaDB at ${WORDPRESS_DB_HOST}..."
until mysqladmin ping -h"${WORDPRESS_DB_HOST}" -u"${WORDPRESS_DB_USER}" -p"${DB_PASSWORD}" --silent 2>/dev/null; do
    sleep 2
done
echo "MariaDB is up."

if [ ! -f /var/www/html/wp-load.php ]; then
    echo "Downloading WordPress core..."
    wp core download --allow-root --path=/var/www/html

    wp config create --allow-root --path=/var/www/html \
        --dbname="${WORDPRESS_DB_NAME}" \
        --dbuser="${WORDPRESS_DB_USER}" \
        --dbpass="${DB_PASSWORD}" \
        --dbhost="${WORDPRESS_DB_HOST}"

    wp core install --allow-root --path=/var/www/html \
        --url="https://${DOMAIN_NAME}" \
        --title="${WORDPRESS_TITLE}" \
        --admin_user="${WORDPRESS_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WORDPRESS_ADMIN_EMAIL}" \
        --skip-email

    wp user create "${WORDPRESS_USER}" "${WORDPRESS_USER_EMAIL}" \
        --allow-root --path=/var/www/html \
        --role=author \
        --user_pass="${WP_USER_PASSWORD}"

    wp plugin install redis-cache --allow-root --path=/var/www/html --activate || true
    wp config set WP_REDIS_HOST "${REDIS_HOST}" --allow-root --path=/var/www/html
    wp redis enable --allow-root --path=/var/www/html || true

    echo "WordPress installation complete."
else
    echo "WordPress already installed, skipping setup."
fi

chown -R www-data:www-data /var/www/html

exec php-fpm8.2 -F
