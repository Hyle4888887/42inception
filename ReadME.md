# Inception

Projet système de l'école 42 : mise en place d'une petite infrastructure conteneurisée avec Docker, orchestrée par `docker-compose`, entièrement construite « from scratch » (pas d'images officielles toutes faites, chaque service part d'une image de base type `alpine` ou `debian`).

## Objectif

Reproduire une infrastructure web classique composée de plusieurs services isolés dans des conteneurs distincts, communiquant entre eux via un réseau Docker dédié, avec persistance des données via des volumes.

## Architecture

```
                        ┌────────────────────┐
                        │       NGINX         │  :443 (TLS only)
                        └─────────┬───────────┘
                                  │
                        ┌─────────▼───────────┐
                        │      WordPress       │  (php-fpm)
                        └─────────┬───────────┘
                                  │
                        ┌─────────▼───────────┐
                        │      MariaDB         │
                        └──────────────────────┘
```

Tous les conteneurs sont reliés par un réseau Docker interne (`inception_network` ou équivalent) et communiquent par leur nom de service (résolution DNS interne de Docker Compose).

## Services

| Service   | Rôle                                              | Image de base       |
|-----------|---------------------------------------------------|----------------------|
| NGINX     | Reverse proxy, seul point d'entrée, TLS (v1.2/1.3) | `debian:bullseye` / `alpine` |
| WordPress | Application PHP-FPM (sans nginx intégré)           | `debian:bullseye` / `alpine` |
| MariaDB   | Base de données pour WordPress                     | `debian:bullseye` / `alpine` |

Chaque service possède son propre `Dockerfile` dans `srcs/requirements/<service>/`.

## Arborescence

```
.
├── Makefile
├── secrets/
│   ├── credentials.txt
│   ├── db_password.txt
│   └── db_root_password.txt
├── .env
└── srcs/
    ├── docker-compose.yml
    └── requirements/
        ├── nginx/
        │   ├── Dockerfile
        │   ├── conf/
        │   └── tools/
        ├── wordpress/
        │   ├── Dockerfile
        │   ├── conf/
        │   └── tools/
        └── mariadb/
            ├── Dockerfile
            ├── conf/
            └── tools/
```

## Variables d'environnement (`.env`)

```env
DOMAIN_NAME=mpoirier.42.fr
MYSQL_DATABASE=wordpress
MYSQL_USER=wp_user
WP_ADMIN_USER=admin_mpoirier
WP_ADMIN_EMAIL=admin@mpoirier.42.fr
WP_TITLE=Inception
```

Les mots de passe ne passent **pas** par le `.env` mais par des fichiers dans `secrets/`, montés en Docker secrets.

## Build & lancement

```bash
make            # build + up -d
make down       # arrête et supprime les conteneurs
make clean      # + supprime images et volumes
make fclean     # nettoyage complet (volumes, données WP/DB, réseau)
make re         # fclean + make
```

Le `Makefile` s'appuie en interne sur :

```bash
docker-compose -f srcs/docker-compose.yml up --build -d
```

## Points clés du sujet à respecter

- Chaque service tourne dans son propre conteneur, construit à partir d'un Dockerfile (pas de `docker pull` d'image déjà faite pour le service lui-même, hors image de base).
- Pas de `latest` comme tag d'image de base.
- Pas de `network: host`, pas de `--link`.
- Pas de process en boucle style `tail -f /dev/null` ou `sleep infinity` pour maintenir le conteneur en vie : chaque conteneur doit tourner via son process principal (PID 1) en foreground (ex : `php-fpm -F`, `nginx -g "daemon off;"`, `mysqld_safe`).
- NGINX comme unique point d'entrée, en HTTPS uniquement (TLSv1.2 ou 1.3), sur le port 443.
- Volumes pour la persistance : un pour la base de données, un pour les fichiers WordPress.
- Redémarrage automatique des conteneurs en cas de crash (`restart: always` ou équivalent).
- Réseau Docker dédié entre les conteneurs.

## Accès

Ajouter dans `/etc/hosts` :

```
127.0.0.1   login.42.fr
```

Puis se rendre sur `https://mpoirier.42.fr`.

## Bonus (optionnel)

- Redis (cache pour WordPress)
- FTP server
- Static website supplémentaire
- Adminer
- Tout autre service pertinent

## Notes

- Les images de base et paquets doivent correspondre à la version stable de Debian/Alpine utilisée (pas de `docker pull` de l'image finale, tout se construit depuis une image de base minimale).
- Bien gérer les healthchecks / dépendances (`depends_on`) entre MariaDB, WordPress et NGINX pour éviter les erreurs de démarrage.
