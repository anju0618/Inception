FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends python3 && \
    rm -rf /var/lib/apt/lists/*

COPY site/ /var/www/static-site/

WORKDIR /var/www/static-site

EXPOSE 8081

ENTRYPOINT ["python3", "-m", "http.server", "8081"]
