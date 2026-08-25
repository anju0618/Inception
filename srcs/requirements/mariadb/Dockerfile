FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends mariadb-server && \
    rm -rf /var/lib/apt/lists/*

# The Debian package's postinst already runs mysql_install_db, baking a
# default (unconfigured) datadir into the image layer. Since our named
# volume is empty on first run, Docker would otherwise auto-copy that
# baked-in content into the volume, making the entrypoint's "already
# initialized?" check skip our own init logic. Wipe it so the volume
# starts genuinely empty.
RUN rm -rf /var/lib/mysql/*

COPY conf/50-server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf
COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh && \
    mkdir -p /run/mysqld && chown mysql:mysql /run/mysqld

EXPOSE 3306

# 初期化(初回のみ)をentrypoint.shで行い、最後にmariadbdをフォアグラウンド起動する
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
