# USER_DOC — User Documentation

This document explains how to start Inception and use the WordPress website, without going into technical details (see `DEV_DOC.md` for those).

## 1. Provided services

| Service   | Role                                                          |
|-----------|---------------------------------------------------------------|
| NGINX     | Single entry point, HTTPS only (port 443, TLS 1.2/1.3)        |
| WordPress | The website and its back office (PHP-FPM)                     |
| MariaDB   | WordPress database (not reachable from outside)               |

Only NGINX is exposed: the site is reachable over `https://` only.

## 2. Prerequisites

- Docker and Docker Compose installed (`docker compose version`).
- `make` and `sudo` access (required for the full cleanup).
- The password files in `secrets/` (not versioned, create them once):

```
secrets/db_password.txt
secrets/db_root_password.txt
secrets/wp_admin_password.txt
secrets/wp_user_password.txt
```

Each file contains only the password, on a single line.

- The local domain name in `/etc/hosts` (one-time setup):

```bash
echo "127.0.0.1 mpoirier.42.fr" | sudo tee -a /etc/hosts
```

## 3. Start and stop the project

From the repository root:

```bash
make        # builds the images and starts the 3 services in the background
make down   # stops and removes the containers (data is kept)
```

The first start takes longer: images are built and WordPress installs itself automatically.

## 4. Access the website

| Page           | URL                                  |
|----------------|--------------------------------------|
| Public site    | https://mpoirier.42.fr               |
| Administration | https://mpoirier.42.fr/wp-admin      |

**Browser warning**: the TLS certificate is self-signed. The browser will show "connection not secure": click *Advanced*, then *Proceed to the site*. This is expected in a local environment.

## 5. WordPress accounts

Two accounts are created automatically on first start:

| Account       | Username         | Role          | Password                                     |
|---------------|------------------|---------------|----------------------------------------------|
| Administrator | `admin_mpoirier` | Administrator | content of `secrets/wp_admin_password.txt`   |
| User          | `editorM`        | Author        | content of `secrets/wp_user_password.txt`    |

- The **administrator** manages everything: themes, plugins, users, settings.
- The **author** can write and publish their own posts.

## 6. Managing credentials

- Passwords are stored in `secrets/`: never commit or share them.
- To change a WordPress password, the simplest way is the web interface: *Users → Profile → New password*.
- Editing a file in `secrets/` **does not change** the passwords of an existing installation: they are only read at first initialization. To start from scratch, see `make fclean` in `DEV_DOC.md` (⚠️ this erases all data).

## 7. Check that everything works

```bash
docker compose -f srcs/docker-compose.yml ps
```

The three containers `mariadb`, `wordpress` and `nginx` must be in the `Up` state.

If the site does not respond:

| Symptom                                      | What to check                                                              |
|----------------------------------------------|----------------------------------------------------------------------------|
| "Cannot reach the site"                      | Check the `/etc/hosts` line and that `nginx` is `Up`                       |
| 502 Bad Gateway                              | WordPress has not finished installing: wait ~30 s and reload               |
| "Error establishing a database connection"   | MariaDB is not ready or the password does not match: check the logs (`DEV_DOC.md`) |
| Port 443 already in use                      | Stop the other service using it (e.g. another local web server)            |
