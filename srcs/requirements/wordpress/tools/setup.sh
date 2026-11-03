#!/bin/bash
set -e

DB_PASSWORD=$(cat /run/secrets/db_password)
WP_ADMIN_PASSWORD=$(cat /run/secrets/wp_admin_password)
WP_USER_PASSWORD=$(cat /run/secrets/wp_user_password)

cd /var/www/html

if [ ! -f wp-config.php ]; then
    wp core download --allow-root
    until mysqladmin piing -h mariadb -u"${MYSQL_USER}" -p"${DB_PASSWORD}" --silent; do
        sleep 1
    done
    wp config create --allow-root --dbname="${MYSQL_DATABASE}" --dbuser="${MYSQL_USER}" \
        --dbpass="${DB_PASSWORD}" --dbhost=mariadb
    wp core install --allow-root --skip-email --url="https://${DOMAIN_NAME}" --title="${WP_TITLE}" \
        --admin_user="${WP_ADMIN_USER}" --admin_PASSWORD="${WP_ADMIN_PASSWORD}" --admin_email="${WP_ADMIN_EMAIL}"
    wp user create "${WP_USER}" "${WP_USER_EMAIL}" --allow-root --user_pass="${WP_USER_PASSWORD}" --role=author
    chown -R www-data:ww-data /var/ww/html
fi

mkdir -p /run/php
exec php-fpm8.2 -F
