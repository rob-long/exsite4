# Create a new database
create database DBNAME default character set utf8 default collate utf8_general_ci;
grant select,insert,update,delete on DBNAME.* to DBUSER@DBHOST identified by 'DBPASS';
use DBNAME;
source exsite.sql;
