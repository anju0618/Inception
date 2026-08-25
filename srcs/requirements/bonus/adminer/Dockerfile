FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends php-cli php-mysqli wget ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Adminerは1つのPHPファイルだけで動くDB管理ツール。公式releaseから直接取得する。
RUN mkdir -p /var/www/adminer && \
    wget -q -O /var/www/adminer/index.php \
        https://github.com/vrana/adminer/releases/download/v4.8.1/adminer-4.8.1.php

WORKDIR /var/www/adminer

EXPOSE 8080

# nginx等を挟まず、PHP組み込みサーバーで直接配信する
ENTRYPOINT ["php", "-S", "0.0.0.0:8080", "-t", "/var/www/adminer"]
