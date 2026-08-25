# User Documentation

## What services are provided

| Service        | What it is                                     | Address (from a browser) |
|----------------|-------------------------------------------------|---------------------------|
| WordPress site | The public website                              | `https://amakino.42.fr` |
| WordPress admin| The WordPress dashboard                        | `https://amakino.42.fr/wp-admin` |
| Adminer        | Web UI to browse/manage the MariaDB database    | `http://amakino.42.fr:8080` (or the port set as `ADMINER_PORT`) |
| Static site    | An independent, PHP-free showcase page          | `http://amakino.42.fr:8081` (or `STATIC_SITE_PORT`) |
| FTP            | File access to the WordPress volume             | `ftp://amakino.42.fr:21` |

Internally, MariaDB, Redis and the backup service are only reachable from other
containers on the `inception` Docker network — they are not exposed to the outside.

Before any of this works, make sure `amakino.42.fr` resolves to the virtual machine's
IP address — add a line such as `192.168.x.x amakino.42.fr` to your `/etc/hosts` file
(see [DEV_DOC.md](./DEV_DOC.md) for how to find the VM's IP).

## Starting and stopping the project

From the repository root, inside the VM:

```sh
make        # build (if needed) and start every service in the background
make down   # stop and remove all containers (data is kept, it lives on the host)
make stop   # stop containers without removing them
make start  # start previously-created, stopped containers again
```

## Accessing the website and the admin panel

1. Open `https://amakino.42.fr` in a browser. The certificate is self-signed, so the
   browser will show a warning — this is expected, accept/continue past it.
2. To manage content, go to `https://amakino.42.fr/wp-admin` and log in with the
   WordPress administrator account (see below for where to find its password).

## Locating and managing credentials

All passwords live in the `secrets/` directory at the repository root (never
committed to Git):

| File                          | Contains |
|--------------------------------|----------|
| `secrets/credentials.txt`      | WordPress administrator password |
| `secrets/wp_users_password.txt`| WordPress second (author) user password |
| `secrets/db_password.txt`      | MariaDB application user (`wp_user`) password |
| `secrets/db_root_password.txt` | MariaDB root password |
| `secrets/ftp_password.txt`     | FTP user password |

Usernames themselves are non-sensitive and set in `srcs/.env` (`WORDPRESS_ADMIN_USER`,
`WORDPRESS_USER`, `MYSQL_USER`, `FTP_USER`).

Inside a running container, secrets are available as plain files under
`/run/secrets/<name>` — for example, from inside the `wordpress` container:
`cat /run/secrets/credentials`.

## Checking that the services are running correctly

```sh
make ps
```

Every service should show a state of `Up`. For a specific service's logs:

```sh
docker compose -f srcs/docker-compose.yml logs -f wordpress
```

A quick end-to-end check:

```sh
curl -vk https://amakino.42.fr        # should return the WordPress homepage over TLS
```

If a container keeps restarting, check its logs first (`docker compose logs
<service>`) — see [DEV_DOC.md](./DEV_DOC.md) for deeper troubleshooting commands.
