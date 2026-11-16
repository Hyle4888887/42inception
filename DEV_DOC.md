# DEV_DOC — Developer Documentation

Environment setup, build, launch, and management of containers and volumes.

## 1. Project structure

```
.
├── Makefile
├── secrets/                     # not versioned (.gitignore)
│   ├── db_password.txt
│   ├── db_root_password.txt
│   ├── wp_admin_password.txt
│   └── wp_user_password.txt
└── srcs/
    ├── .env                     # non-secret variables
    ├── docker-compose.yml
    └── requirements/
        ├── mariadb/   (Dockerfile, conf/50-server.cnf, tools/init.sh)
        ├── wordpress/ (Dockerfile, conf/www.conf, tools/setup.sh)
        ├── nginx/     (Dockerfile, conf/nginx.conf)
        └── bonus/
```

All images are built from `debian:bookworm` (no prebuilt service images).

## 2. Prerequisites and configuration

- Docker Engine + Compose v2 plugin (`docker compose`), `make`, `sudo`.
- `/etc/hosts` entry: `127.0.0.1 mpoirier.42.fr`.

### Environment variables — `srcs/.env`

| Variable           | Purpose                                                        |
|--------------------|----------------------------------------------------------------|
| `DATA_PATH`        | Host folder for persistent data (e.g. `/home/mpoirier/data`)   |
| `DOMAIN_NAME`      | Website domain name (WordPress URL)                            |
| `MYSQL_DATABASE`   | Database name                                                  |
| `MYSQL_USER`       | MariaDB user for WordPress                                     |
| `WP_TITLE`         | Site title                                                     |
| `WP_ADMIN_USER` / `WP_ADMIN_EMAIL` | WordPress administrator account                |
| `WP_USER` / `WP_USER_EMAIL`        | WordPress author account                       |

> The `Makefile` also hardcodes `DATA = /home/mpoirier/data`: keep it identical to `DATA_PATH` in `.env` if either changes.

### Secrets — `secrets/` folder

Passwords never go through `.env`: they are mounted into the containers via Docker secrets (readable at `/run/secrets/<name>`).

| File                    | Used by             |
|-------------------------|---------------------|
| `db_password.txt`       | mariadb, wordpress  |
| `db_root_password.txt`  | mariadb             |
| `wp_admin_password.txt` | wordpress           |
| `wp_user_password.txt`  | wordpress           |

Creation (example):

```bash
mkdir -p secrets
for f in db_password db_root_password wp_admin_password wp_user_password; do
  openssl rand -base64 18 > secrets/$f.txt
done
```

## 3. Build and launch

### With the Makefile

| Command       | Effect                                                                 |
|---------------|------------------------------------------------------------------------|
| `make`        | Creates `$(DATA)/mariadb` and `$(DATA)/wordpress`, then `docker compose up --build -d` |
| `make down`   | `docker compose down`: removes containers, **keeps** images, volumes and data |
| `make clean`  | `down` + `docker system prune -af`: removes **all** unused images/containers/networks on the machine |
| `make fclean` | `clean` + removes **all** Docker volumes + `sudo rm -rf $(DATA)`       |
| `make re`     | `fclean` then `all`: full reinstall                                    |

> ⚠️ `clean` and `fclean` act on **all of Docker on the machine**, not only this project (`system prune -af`, removal of every volume). Avoid them on a machine hosting other containers.

### Directly with Docker Compose

Alias used below: `dc="docker compose -f srcs/docker-compose.yml"`

```bash
dc up --build -d          # build + start in the background
dc up -d --build nginx    # rebuild/restart a single service
dc build --no-cache       # full rebuild without cache
dc down                   # stop + remove containers and network
dc stop / dc start        # stop / resume without removing
dc restart wordpress      # restart a service
```

## 4. Managing containers

```bash
dc ps                          # service status
docker ps -a                   # all containers on the machine
dc logs -f                     # logs of all services (follow)
dc logs -f --tail 100 mariadb  # logs of one service
dc top                         # processes per container (expected PID 1: mysqld, php-fpm8.2, nginx)

docker exec -it wordpress bash # shell inside a container
docker exec -it mariadb bash
docker exec -it nginx bash

docker stats                   # live CPU / RAM
docker inspect <container>     # detailed configuration
```

### Useful diagnostic commands

```bash
# Validate the Compose config (resolved variables)
dc config

# Test the database from the WordPress container
docker exec -it wordpress sh -c 'mysql -h mariadb -u"$MYSQL_USER" -p"$(cat /run/secrets/db_password)" "$MYSQL_DATABASE" -e "SHOW TABLES;"'

# Check the NGINX configuration and TLS
docker exec nginx nginx -t
openssl s_client -connect mpoirier.42.fr:443 -tls1_2 </dev/null 2>/dev/null | grep -E "Protocol|Cipher"

# WP-CLI inside the container
docker exec -it wordpress wp --allow-root --path=/var/www/html user list
```

## 5. Managing images, network and volumes

### Images and network

```bash
docker images                  # built images (mariadb, wordpress, nginx)
docker image rm mariadb        # remove an image (container must be stopped)
docker network ls              # the project network is prefixed (e.g. srcs_inception)
docker network inspect srcs_inception
```

### Volumes

The project declares two named volumes **bind-mounted on the host** (`driver_opts: type none, o bind`): data is directly visible in `$DATA_PATH`.

| Volume (Compose) | Mounted in                           | Host folder            | Content                                   |
|------------------|--------------------------------------|------------------------|-------------------------------------------|
| `mariadb`        | `mariadb:/var/lib/mysql`             | `$DATA_PATH/mariadb`   | Database                                  |
| `wordpress`      | `wordpress` and `nginx:/var/www/html`| `$DATA_PATH/wordpress` | WordPress files (shared php-fpm ↔ nginx)  |

The actual Docker name is prefixed with the Compose project name (`srcs_mariadb`, `srcs_wordpress` by default).

```bash
docker volume ls                               # list volumes
docker volume inspect srcs_mariadb             # show the device/host path
docker volume rm srcs_mariadb srcs_wordpress   # remove (containers must be stopped)
docker volume prune                            # remove unused volumes

ls -la $DATA_PATH/mariadb $DATA_PATH/wordpress # data on the host
```

### Backup and restore

```bash
# Database backup
docker exec mariadb sh -c 'mysqldump -uroot -p"$(cat /run/secrets/db_root_password)" "$MYSQL_DATABASE"' > backup.sql

# Restore
docker exec -i mariadb sh -c 'mysql -uroot -p"$(cat /run/secrets/db_root_password)" "$MYSQL_DATABASE"' < backup.sql

# WordPress files backup
sudo tar czf wordpress-backup.tar.gz -C $DATA_PATH wordpress
```

## 6. Data persistence and initialization

Entrypoint scripts only run their setup once, based on the state of the volumes:

- **MariaDB** (`init.sh`): if `/var/lib/mysql/$MYSQL_DATABASE` does not exist → `mysql_install_db`, creation of the database and user, root password. Then `exec mysqld` (PID 1).
- **WordPress** (`setup.sh`): if `wp-config.php` does not exist → core download, wait for MariaDB, `wp config create`, `wp core install`, creation of the author user. Then `exec php-fpm8.2 -F` (PID 1).
- **NGINX**: self-signed certificate generated at **build** time (`openssl req -x509`, valid 365 days, CN `mpoirier.42.fr`); `nginx -g "daemon off;"`.

Consequences:

- `make down` / restart: data persists, nothing is reinitialized.
- Editing `secrets/*.txt` or `.env` **has no effect** on an already initialized installation. To re-apply: `make fclean && make` (⚠️ data loss), or change the password manually in MariaDB / via WP-CLI.
- To regenerate the certificate: `dc build --no-cache nginx && dc up -d nginx`.

## 7. Network architecture

- `inception` bridge network: services reach each other by name (`mariadb:3306`, `wordpress:9000`).
- Only `nginx` publishes a port on the host (`443:443`); MariaDB and PHP-FPM are reachable only from the internal network.
- `depends_on` orders startup (mariadb → wordpress → nginx) but does not wait for services to be *ready*: `setup.sh` loops on `mysqladmin ping` to wait for MariaDB.
- `restart: always` restarts containers after a crash or a Docker daemon reboot.
