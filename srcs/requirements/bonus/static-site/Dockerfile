FROM debian:bookworm-slim

# PHPを使わない、という要件を満たすためPython3だけを入れる
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3 && \
    rm -rf /var/lib/apt/lists/*

COPY site/ /var/www/static-site/

WORKDIR /var/www/static-site

EXPOSE 8081

# Python標準ライブラリの簡易HTTPサーバーで静的ファイルを配信するだけ
ENTRYPOINT ["python3", "-m", "http.server", "8081"]
