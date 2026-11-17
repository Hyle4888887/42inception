*This project has been created as part of the 42 curriculum by mpoirier.*

# Inception

## Description

Inception is a 42 system administration project: build a small web infrastructure with Docker, orchestrated by Docker Compose, entirely from scratch. No prebuilt service images are used: every service has its own `Dockerfile` built from `debian:bookworm`.

The stack is made of three isolated containers:

```
                  ┌────────────────────┐
   https :443 ──► │       NGINX        │  TLS 1.2 / 1.3 only
                  └─────────┬──────────┘
                            │ FastCGI :9000
                  ┌─────────▼──────────┐
                  │     WordPress      │  php-fpm (no web server inside)
                  └─────────┬──────────┘
                            │ :3306
                  ┌─────────▼──────────┐
                  │      MariaDB       │
                  └────────────────────┘
```

| Service   | Role                                              | Base image        |
|-----------|---------------------------------------------------|-------------------|
| NGINX     | Single entry point, HTTPS only (port 443)         | `debian:bookworm` |
| WordPress | PHP-FPM application, installed with WP-CLI        | `debian:bookworm` |
| MariaDB   | Database for WordPress                            | `debian:bookworm` |

Design choices:
- Each container runs its main process as PID 1 in the foreground (`nginx -g "daemon off;"`, `php-fpm8.2 -F`, `mysqld`): no `tail -f` or `sleep infinity` hacks.
- NGINX is the only service publishing a port. MariaDB and PHP-FPM are reachable only through the internal Docker network.
- Passwords are provided through Docker secrets; non-sensitive settings through `.env`.
- Two persistent volumes (database, WordPress files) stored under `DATA_PATH` on the host.
- `restart: always` restarts containers after a crash.

## Project structure

```
.
├── Makefile
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
├── secrets/                  # not included in git
│   ├── db_password.txt
│   ├── db_root_password.txt
│   ├── wp_admin_password.txt
│   └── wp_user_password.txt
└── srcs/
    ├── .env.                 # not included in git
    ├── docker-compose.yml
    └── requirements/
        ├── mariadb/   (Dockerfile, conf/, tools/)
        ├── wordpress/ (Dockerfile, conf/, tools/)
        ├── nginx/     (Dockerfile, conf/)
        └── bonus/
```

## Instructions

### Prerequisites

- Docker Engine with the Compose v2 plugin, `make`, `sudo`.
- The four password files listed above in `secrets/` (one password per file).
- A host entry for the domain:

```bash
echo "127.0.0.1 mpoirier.42.fr" | sudo tee -a /etc/hosts
```

### Configuration

Non-secret variables live in `srcs/.env`:

```env
DATA_PATH=/home/mpoirier/data
DOMAIN_NAME=mpoirier.42.fr
MYSQL_DATABASE=wordpress
MYSQL_USER=wp_user
WP_TITLE=Inception
WP_ADMIN_USER=admin_mpoirier
WP_ADMIN_EMAIL=mpoirier@student.42nice.fr
WP_USER=editorM
WP_USER_EMAIL=mpoirier@student.42nice.fr
```

Passwords are **not** in `.env`: they are read from `secrets/` and mounted as Docker secrets.

### Build and run

```bash
make          # create data folders, build images, start containers (detached)
make down     # stop and remove containers (data is kept)
make clean    # down + docker system prune -af
make fclean   # clean + remove all volumes and the data folder
make re       # fclean + make
```

> `clean` and `fclean` affect all of Docker on the machine, not only this project.

Then open https://mpoirier.42.fr (accept the self-signed certificate warning) or https://mpoirier.42.fr/wp-admin for the back office.

More details: [USER_DOC.md](USER_DOC.md) for end users, [DEV_DOC.md](DEV_DOC.md) for developers.

## Technical comparisons

### Virtual Machines vs Docker

| | Virtual Machine | Docker container |
|---|---|---|
| Isolation | Full hardware virtualization by a hypervisor; each VM runs its own complete OS and kernel | Process-level isolation (namespaces, cgroups); all containers share the host kernel |
| Size | Gigabytes (full OS image) | Megabytes to a few hundred MB (only the userland and dependencies) |
| Startup | Tens of seconds to minutes (OS boot) | Seconds or less (just starts a process) |
| Resource usage | High: each VM reserves RAM/CPU for a whole OS | Low: only what the process uses |
| Portability | Disk images, heavier to move and rebuild | Images built from a `Dockerfile`, reproducible and easy to share |
| Security boundary | Stronger (separate kernels) | Weaker (shared kernel), mitigated by namespaces and capabilities |

Why Docker here: the project needs three small, reproducible services that start fast and can be rebuilt from text files. A VM per service would be heavy and slow for no benefit. A VM remains the better choice when you need a different kernel or OS, or stronger isolation.

### Secrets vs Environment variables

| | Docker secrets | Environment variables |
|---|---|---|
| Storage | Files mounted read-only in the container at `/run/secrets/<name>` | Key/value pairs injected into the process environment |
| Visibility | Not shown in `docker inspect` nor in the image; not inherited by child processes | Visible in `docker inspect`, in `/proc/<pid>/environ`, and easily leaked in logs or crash dumps |
| Source | Files on the host (here `secrets/*.txt`, git-ignored) | `.env` / `env_file` / `environment:` |
| Best for | Passwords, API keys, certificates | Non-sensitive configuration (domain, usernames, titles) |

In this project: passwords go through Docker secrets (`db_password`, `db_root_password`, `wp_admin_password`, `wp_user_password`) and scripts read them with `cat /run/secrets/...`. Everything else (database name, domain, user names) goes through `.env`.

### Docker network vs Host network

| | Docker (bridge) network | Host network |
|---|---|---|
| Network stack | Isolated virtual network with its own IPs | Container shares the host's network stack directly |
| Service discovery | Built-in DNS: containers reach each other by service name (`mariadb`, `wordpress`) | None; everything is on the host's interfaces |
| Port exposure | Explicit: only ports listed in `ports:` are published | All container ports are directly open on the host |
| Isolation | Good: services not published are unreachable from outside | None: port conflicts and a larger attack surface |

This project uses a dedicated bridge network (`inception`). Only NGINX publishes `443:443`; WordPress (`:9000`) and MariaDB (`:3306`) are reachable only from other containers on that network. `network: host` and `--link` are forbidden by the subject.

### Docker volumes vs Bind mounts

| | Docker (named) volumes | Bind mounts |
|---|---|---|
| Location | Managed by Docker (`/var/lib/docker/volumes/...`) | Any path on the host chosen by the user |
| Management | `docker volume` commands, independent of host layout | Depends on the host filesystem and its permissions |
| Portability | Works the same on any host with Docker | Tied to a specific host path |
| Typical use | Persistent application data (databases) | Sharing source code or config files, or when data must live at a known host path |

This project uses **named volumes backed by a bind** (`driver_opts: type: none, o: bind, device: ${DATA_PATH}/...`). They are declared and managed as Docker volumes (`docker volume ls`, referenced by name in Compose), while the data is stored at a known host location (`$DATA_PATH/mariadb` and `$DATA_PATH/wordpress`), as required by the subject. The `wordpress` volume is mounted in both the `wordpress` and `nginx` containers so NGINX can serve static files and hand PHP to PHP-FPM.

## Resources

- [Docker documentation](https://docs.docker.com/)
- [Docker Compose file reference](https://docs.docker.com/compose/compose-file/)
- [Dockerfile best practices](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- [Docker secrets](https://docs.docker.com/engine/swarm/secrets/) and [Compose secrets](https://docs.docker.com/compose/how-tos/use-secrets/)
- [NGINX documentation](https://nginx.org/en/docs/)
- [WP-CLI handbook](https://make.wordpress.org/cli/handbook/)
- [MariaDB documentation](https://mariadb.com/kb/en/documentation/)

AI usage: Claude was used to help write the project documentation (`README.md`, `USER_DOC.md`, `DEV_DOC.md`) from the repository's actual configuration. All content was reviewed and its commands checked against the project files.
