# Developer Documentation

## Setting up the environment from scratch

### 1. Virtual machine

The whole project must be built and run inside a virtual machine (VirtualBox, UTM, or
any hypervisor of your choice), with Docker and the Docker Compose plugin installed.
See `vm/README.md` (not committed) for the exact steps used to provision the VM used
during development of this repository.

### 2. Configuration files

- `srcs/.env` — non-sensitive configuration: domain name, database/user names,
  WordPress titles/usernames, bonus service ports. Already provided in this
  repository; edit it if you need a different login/domain.
- `secrets/*.txt` — one password per file, referenced as Docker secrets in
  `srcs/docker-compose.yml`. These files are `.gitignore`d and must be created
  locally before the first `make`:

  ```sh
  mkdir -p secrets
  openssl rand -base64 24 | tr -d '=+/' | cut -c1-20 > secrets/db_root_password.txt
  openssl rand -base64 24 | tr -d '=+/' | cut -c1-20 > secrets/db_password.txt
  openssl rand -base64 24 | tr -d '=+/' | cut -c1-20 > secrets/credentials.txt
  openssl rand -base64 24 | tr -d '=+/' | cut -c1-20 > secrets/wp_users_password.txt
  openssl rand -base64 24 | tr -d '=+/' | cut -c1-20 > secrets/ftp_password.txt
  chmod 600 secrets/*.txt
  ```

- `/home/amakino/data/{wordpress,mariadb,backups}` — created automatically by `make`
  (target `prepare`); this is where the named volumes are physically backed on the
  host, per subject requirement.

## Building and launching the project

```sh
make            # make prepare + docker compose up --build -d
make build      # build images only, without starting containers
make ps         # show container status
make logs       # follow logs of every service
make down       # stop and remove containers (volumes/data untouched)
make stop       # stop containers without removing them
make start      # restart previously stopped containers
make clean      # down + remove locally-built images/volumes/orphans
make fclean     # clean + wipe the data under /home/amakino/data
make re         # fclean + all
```

Under the hood, `make` calls:

```sh
docker compose -f srcs/docker-compose.yml --env-file srcs/.env up --build -d
```

Each of the eight services (`nginx`, `wordpress`, `mariadb`, `redis`, `ftp`,
`adminer`, `static-site`, `backup`) is built from its own Dockerfile under
`srcs/requirements/`, with an image name matching its service name.

## Managing containers and volumes

```sh
docker compose -f srcs/docker-compose.yml ps                         # status
docker compose -f srcs/docker-compose.yml exec wordpress sh          # shell into a container
docker compose -f srcs/docker-compose.yml logs -f mariadb            # follow one service's logs
docker compose -f srcs/docker-compose.yml config                     # print the fully-resolved compose file
docker network inspect srcs_inception                                # inspect the bridge network / DNS
docker volume ls
docker volume inspect srcs_wordpress_data                            # confirm the Mountpoint under /home/amakino/data
```

`memo.md` (kept alongside this file, not part of the graded deliverables but useful
during development/defense) contains a longer cheat-sheet of commands to demonstrate
each subject requirement live: single 443 entry point, enforced TLS versions,
auto-restart on crash, persistence across `down`/`up`, absence of bind mounts, secrets
not leaking into the environment, PID 1 correctness, etc.

## Where project data lives and how it persists

- **WordPress database** — named volume `mariadb_data`, backed by
  `/home/amakino/data/mariadb` on the host, mounted at `/var/lib/mysql` in the
  `mariadb` container.
- **WordPress files** (core, themes, plugins, uploads) — named volume
  `wordpress_data`, backed by `/home/amakino/data/wordpress` on the host, mounted at
  `/var/www/html` in both the `wordpress` and `nginx` containers (so NGINX can serve
  static assets directly) and re-used read/write by the `ftp` container.
- **Database backups** (bonus) — named volume `backup_data`, backed by
  `/home/amakino/data/backups`, mounted at `/backups` in the `backup` container.

Because these are named volumes (not bind mounts) pinned to host paths via
`driver_opts`, the data survives `docker compose down` and container
rebuilds/recreations; it is only removed by an explicit `make fclean` (or `docker
volume rm`).
