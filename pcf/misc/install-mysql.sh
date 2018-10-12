#/bin/bash

sudo apt update
sudo apt install mysql-server
sudo mysql_secure_installation

sudo mysql < external-db

sudo vi /etc/mysql/mysql.conf.d/mysqld.cnf
#bind-address            = 0.0.0.0

sudo mysql_ssl_rsa_setup --uid=mysql
