FROM debian:bookworm-slim

ARG DOMAIN_NAME=amakino.42.fr

RUN apt-get update && \
    apt-get install -y --no-install-recommends nginx openssl && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/nginx/ssl && \
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/inception.key \
        -out /etc/nginx/ssl/inception.crt \
        -subj "/C=JP/ST=Tokyo/L=Tokyo/O=42Tokyo/OU=Inception/CN=${DOMAIN_NAME}"

COPY conf/nginx.conf /etc/nginx/sites-available/wordpress.conf

RUN sed -i "s/DOMAIN_NAME_PLACEHOLDER/${DOMAIN_NAME}/" /etc/nginx/sites-available/wordpress.conf && \
    rm -f /etc/nginx/sites-enabled/default && \
    ln -s /etc/nginx/sites-available/wordpress.conf /etc/nginx/sites-enabled/wordpress.conf

EXPOSE 443

ENTRYPOINT ["nginx", "-g", "daemon off;"]
