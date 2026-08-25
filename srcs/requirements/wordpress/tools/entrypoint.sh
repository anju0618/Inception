#!/bin/bash
set -e

# secretsはファイルとしてマウントされているので、中身を読んで変数に入れる
DB_PASSWORD=$(cat "$WORDPRESS_DB_PASSWORD_FILE")
WP_ADMIN_PASSWORD=$(cat "$WP_ADMIN_PASSWORD_FILE")
WP_USER_PASSWORD=$(cat "$WP_USER_PASSWORD_FILE")

# MariaDBコンテナの起動を待つ(compose起動順は保証されても、中身の準備完了までは保証されないため)
echo "Waiting for MariaDB at ${WORDPRESS_DB_HOST}..."
until mysqladmin ping -h"${WORDPRESS_DB_HOST}" -u"${WORDPRESS_DB_USER}" -p"${DB_PASSWORD}" --silent 2>/dev/null; do
    sleep 2
done
echo "MariaDB is up."

# wp-load.phpが無ければ「まだ未インストール」= 初回起動として非対話セットアップを行う
if [ ! -f /var/www/html/wp-load.php ]; then
    echo "Downloading WordPress core..."
    wp core download --allow-root --path=/var/www/html

    # DB接続情報を書き込んだwp-config.phpを生成
    wp config create --allow-root --path=/var/www/html \
        --dbname="${WORDPRESS_DB_NAME}" \
        --dbuser="${WORDPRESS_DB_USER}" \
        --dbpass="${DB_PASSWORD}" \
        --dbhost="${WORDPRESS_DB_HOST}"

    # 管理者ユーザーを作成しつつWordPress本体をインストール
    wp core install --allow-root --path=/var/www/html \
        --url="https://${DOMAIN_NAME}" \
        --title="${WORDPRESS_TITLE}" \
        --admin_user="${WORDPRESS_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WORDPRESS_ADMIN_EMAIL}" \
        --skip-email

    # 2人目(一般ユーザー、role=author)を追加
    wp user create "${WORDPRESS_USER}" "${WORDPRESS_USER_EMAIL}" \
        --allow-root --path=/var/www/html \
        --role=author \
        --user_pass="${WP_USER_PASSWORD}"

    # Redisをオブジェクトキャッシュとして有効化(ボーナス)
    wp plugin install redis-cache --allow-root --path=/var/www/html --activate || true
    wp config set WP_REDIS_HOST "${REDIS_HOST}" --allow-root --path=/var/www/html
    wp redis enable --allow-root --path=/var/www/html || true

    echo "WordPress installation complete."
else
    # 2回目以降の起動(名前付きボリュームに既にインストール済み)はここに来る
    echo "WordPress already installed, skipping setup."
fi

chown -R www-data:www-data /var/www/html

# フォアグラウンドでphp-fpmを起動(execでPID1を明け渡す。daemon化しない)
exec php-fpm8.2 -F
