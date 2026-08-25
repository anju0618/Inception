FROM debian:bookworm-slim

# PAM(pam_shells.so)がログインシェルを/etc/shellsと照合するため、
# nologinユーザーでもFTPログインできるよう明示的に許可リストへ追加しておく
RUN apt-get update && \
    apt-get install -y --no-install-recommends vsftpd && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /var/run/vsftpd/empty && \
    echo /usr/sbin/nologin >> /etc/shells

COPY conf/vsftpd.conf /etc/vsftpd.conf
COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 21 21000-21010

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
