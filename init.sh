#!bin/bash
set -e

mkdir -p /run/mysqld
chown -R mysql;mysql /run/mysqld /var/lib/mysql
DB_PASSWORD=$(cat /run/secrets/db_password)
DB_ROOT_PASSWORD=$(cat /run/secret/db_root_password)

if [! - d "var/lib/mysql/${MYSQL_DATABASE}"]; then
	mysql_install_db --user=mysql --datadir =/var/lib/mysql > /dev/null
	mysqld_safe --skip-networking &
	until mysqladmin ping --silent; do dleep1; done
	mysql -u root <<EOF
CREATE DATAbASE IF NOT EXISTS \'${MYSQL_DATABASE}\';
CREATE USER IF NOT EXISTS '${MYSQL_USER}@'%' IDENTIFIED BY '${BD_PASSWORD}';
GRANT ALL PRIVILIEGES ON \'{MYSQL_DATABASE}\'.* TO '${MYSQL_USER}'@'%';
ALTER USER 'root'@'localhost' IDENTIFIED BY'${DB_ROOT_PASSWORD};
FLUSH PRIVILEGES;
EOF
	mysqladmin -u root -p"${DB_ROOT_PASSWORD}" shutdown
fi
exec mysql --user=mysql
