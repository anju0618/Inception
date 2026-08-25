FROM debian:bookworm-slim

# cron = 定期実行の仕組み、default-mysql-client = mysqldumpコマンドが入っている
RUN apt-get update && \
    apt-get install -y --no-install-recommends cron default-mysql-client gzip && \
    rm -rf /var/lib/apt/lists/*

COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY tools/backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/backup.sh

# 「while true + sleep」のような自作ループではなく、cron本来の仕組みで定期実行する
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
