FROM debian:bookworm-slim

# 証明書のCN/server_nameに使うドメイン名(docker-compose.ymlのargsから渡される)
ARG DOMAIN_NAME=amakino.42.fr

RUN apt-get update && \
    apt-get install -y --no-install-recommends nginx openssl && \
    rm -rf /var/lib/apt/lists/*

# 自己署名のTLS証明書をビルド時に生成する(-x509 = CAに頼らず自分で署名済み証明書を作る)
RUN mkdir -p /etc/nginx/ssl && \
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/inception.key \
        -out /etc/nginx/ssl/inception.crt \
        -subj "/C=JP/ST=Tokyo/L=Tokyo/O=42Tokyo/OU=Inception/CN=${DOMAIN_NAME}"

COPY conf/nginx.conf /etc/nginx/sites-available/wordpress.conf

# server_nameのプレースホルダを実際のドメイン名に置き換え、デフォルトvhostの代わりに有効化
RUN sed -i "s/DOMAIN_NAME_PLACEHOLDER/${DOMAIN_NAME}/" /etc/nginx/sites-available/wordpress.conf && \
    rm -f /etc/nginx/sites-enabled/default && \
    ln -s /etc/nginx/sites-available/wordpress.conf /etc/nginx/sites-enabled/wordpress.conf

EXPOSE 443

# フォアグラウンドで起動(exec形式、PID1としてシグナルを正しく受け取る)
ENTRYPOINT ["nginx", "-g", "daemon off;"]
