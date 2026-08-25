FROM debian:bookworm-slim

# php-fpm本体と、WordPressが必要とする拡張、wp-cli実行に要るcurl/mysqlクライアント
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        php-fpm php-mysqli php-gd php-curl php-mbstring php-xml php-zip php-redis \
        curl ca-certificates default-mysql-client less \
    && rm -rf /var/lib/apt/lists/*

# wp-cli(WordPress公式の管理CLI)を1ファイルのpharとして取得
RUN curl -o /usr/local/bin/wp -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && \
    chmod +x /usr/local/bin/wp

COPY conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf
COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /var/www/html

EXPOSE 9000

# 実際のインストール処理はentrypoint.sh側でやる(ボリュームが空の状態で初回起動するため)
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
