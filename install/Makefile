SHELL = /bin/csh
#----------------------------------------------------------------------------
#
#   Makefile for installing ExSite Webware
#
#   Edit the configuration parameters below first!
#   Run this from your CGI-BIN directory!
#
#   make		print a help message
#   make exsite		install ExSite kernel and plugins
#   make base		install ExSite kernel only
#   make plugins	install ExSite plugins only
#   make PLUGIN_NAME	install a particular plugin only
#   make cgibin		installs kernel files in the CGI-BIN area
#   make html		installs kernel files in the HTDOCS area 
#   make lib		installs kernel libraries
#   make modules	set up the plug-in library area
#   make dbmap		configure the DB map
#   make logs		create the log files
#   make publish.cgi	compile and install the publishing program
#   make crypt_tea	compile and install the encryption tool
#   make db		create and install a database
#   make dbtables	install tables into an existing database
#   make test		check that files were installed properly
#   make clean		archive and clear the current installation
#   make veryclean	delete the current installation
#   make cvsclean	remove CVS files from repositories
#
#   "make exsite" and "make db" are all that is needed to perform a complete
#   installation.  Use "make test" to see if all necessary installation steps
#   have been performed.
#
#-----------------------------------------------------------------------
#
#   Copyright 2001-2016 Exware Solutions, Inc.  http://www.exware.com
#
#   This file is part of ExSite WebWare (ExSite, for short).
#
#   ExSite is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   ExSite is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with ExSite; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#   Users requiring warranty coverage and/or support may arrange alternate
#   commercial licensing for ExSite, by contacting Exware Solutions 
#   via the website noted above.
#
#----------------------------------------------------------------------------

#----------------------------------------------------------------------------
# you can edit the following settings to configure your installation

# location of ExSite distros

BASE_REPOSITORY   = /home/exware/exsite
PLUGIN_REPOSITORY = /home/exware/exsite-plugins

# location of your document root (relative to CGI-BIN, if you like)

DOCROOT = ../html

# plugins to install

PLUGINS = AddrBook Blog Calendar Catalog CMS Comments Content Document \
	Finance Forms Forum Locations Login MailTo MySite ObjectBrowser Pay \
	PhotoAlbum PrintFriendly Search Security SimpleMenu SysMsg \
	Tags Template Trash Users Webtop Zine CMenu ExLib \
	Membership Register

# install method
# cp -r		make private copies of all files
# ln -s		where appropriate, symlink to shareable files

INSTALL  = cp -r
#INSTALL  = ln -s

# MySQL database connection parameters

DB_NAME = exsite_db
DB_USER = my_db_login
DB_PASS = my_db_password
DB_HOST = localhost

# ExSite identity - this is your website administrator account

EXSITE_LOGIN    = admin
EXSITE_PASSWORD = password
EXSITE_NAME     = Your Full Name
EXSITE_EMAIL    = you@yourdomain.com

#----------------------------------------------------------------------------
# do not change anything below this point

# Target groups

BASE = cgibin publish.cgi crypt_tea logs html config

# Pattern rules

# .log sets up log files

%.log:
	touch $*.log
	chmod 666 $*.log

# match-anything rule is used for installing plugins.  
# Use "make PLUGINNAME" to install a plugin, 
# or "make plugins" to install the list of plugins defined above.

%:
	@echo === Installing $* plugin...
	@if (-e Modules/$*.pm) echo $* already installed!
	@if (-e Modules/$*.pm) false
	@if (! -e ${PLUGIN_REPOSITORY}/$*) echo Plugin $* not found in repository
	@if (! -e ${PLUGIN_REPOSITORY}/$*) false
	${INSTALL} ${PLUGIN_REPOSITORY}/$*/cgi/Modules/* Modules
	-cp -r ${PLUGIN_REPOSITORY}/$*/cgi/conf/* conf
	mkdir ${DOCROOT}/_Modules/$*
	if (-e ${PLUGIN_REPOSITORY}/$*/html) ${INSTALL} ${PLUGIN_REPOSITORY}/$*/html/* ${DOCROOT}/_Modules/$*
	if (-e ${PLUGIN_REPOSITORY}/$*/cgi/dbmap) ${INSTALL} ${PLUGIN_REPOSITORY}/$*/cgi/dbmap dbmap/$*

# Explicit rules

# Default is to print help

help:
	@echo " "
	@echo Read the installation guide first!
	@echo " "
	@echo make "             " print a help message
	@echo make exsite "      " install ExSite kernel and plugins
	@echo make base "        " install ExSite kernel only
	@echo make plugins "     " install ExSite plugins only
	@echo make PLUGIN_NAME " " install a particular plugin only
	@echo make cgibin "      " installs kernel files in the CGI-BIN area
	@echo make html "        " installs kernel files in the HTDOCS area 
	@echo make lib "         " installs kernel libraries
	@echo make modules "     " set up the plug-in library area
	@echo make dbmap "       " configure the DB map
	@echo make logs "        " create the log files
	@echo make publish.cgi " " compile and install the publishing program
	@echo make crypt_tea "   " compile and install the encryption tool
	@echo make db "          " create and install a database
	@echo make dbtables "    " install tables into an existing database
	@echo make test "        " check that files were installed properly
	@echo make testdb "      " check that database was installed
	@echo make clean "       " archive and clear the current installation
	@echo make veryclean "   " delete the current installation
	@echo make cvsclean "    " remove CVS files from repositories
	@echo " "

# this installs the base system AND a suite of plug-ins
exsite : check $(BASE) plugins
	@echo Done!

# this installs the base system only
base : check $(BASE)
	@echo Done!

# plugins installs the plug-in suite only;
# install a particular plugin using "make PluginName"
plugins: ${PLUGINS}
	@echo Done!

# setup CGI-BIN area

cgibin: lib modules dbmap
	${INSTALL} ${BASE_REPOSITORY}/cgi/*.pl .
	${INSTALL} ${BASE_REPOSITORY}/cgi/*.cgi .
	${INSTALL} ${BASE_REPOSITORY}/cgi/*.c .
	cp ${BASE_REPOSITORY}/cgi/*.pm .
	mkdir conf
	cp ${BASE_REPOSITORY}/cgi/conf/exsite.conf conf

lib:
	${INSTALL} ${BASE_REPOSITORY}/cgi/ExSite .

modules:
	mkdir Modules
	cd Modules; ${INSTALL} ${BASE_REPOSITORY}/cgi/Modules/BaseDCD.pm .

dbmap:
	mkdir dbmap
	${INSTALL} ${BASE_REPOSITORY}/cgi/dbmap/* dbmap
	cp ${BASE_REPOSITORY}/cgi/dbmap/.table dbmap
	cp ${BASE_REPOSITORY}/cgi/dbmap/.datatype dbmap

logs : db.log cms.log general.log
	@echo Done!

# publish wrapper must be compiled and SUID
publish.cgi:
	cc -o publish.cgi publish.c
	chmod +s publish.cgi

# 64-bit encrypter required on 64-bit servers
crypt_tea:
	cc -o crypt_tea crypt_tea.c

html:
	if (! -e ${DOCROOT}/_ExSite) ${INSTALL} ${BASE_REPOSITORY}/html/_ExSite ${DOCROOT}
	if (! -e ${DOCROOT}/_Modules) mkdir ${DOCROOT}/_Modules
	${INSTALL} ${BASE_REPOSITORY}/html/_Modules/icon.gif ${DOCROOT}/_Modules

# create the database

db:
	mv ${BASE_REPOSITORY}/install/exsite.sql ${BASE_REPOSITORY}/install/exsite-orig.sql
	perl ${BASE_REPOSITORY}/bin/makesql.pl > ${BASE_REPOSITORY}/install/exsite.sql
	sed -e 's/EXSITE_LOGIN/${EXSITE_LOGIN}/' -e 's/EXSITE_PASSWORD/${EXSITE_PASSWORD}/' -e 's/EXSITE_NAME/${EXSITE_NAME}/' -e 's/EXSITE_EMAIL/${EXSITE_EMAIL}/' ${BASE_REPOSITORY}/install/exsite.sql > exsite.sql
	sed -e 's/DBNAME/${DB_NAME}/g' -e 's/DBUSER/${DB_USER}/g' -e 's/DBPASS/${DB_PASS}/g' -e 's/DBHOST/${DB_HOST}/g' ${BASE_REPOSITORY}/install/create.sql > create.sql
	@echo " "
	@echo " "
	@echo This will create your database, grant access permissions, and 
	@echo create your tables.  The MySQL root password is required.  If your
	@echo database is already created and you only need to create your
	@echo tables, then use \"make dbtables\" instead.
	@echo " "
	@echo -n Continue \[type Y to install\] \?
	@set PROMPT = $$< ; if ($$PROMPT != "Y" && $$PROMPT != "y") false
	@echo " "
	@echo Please enter the MySQL root password when prompted.
	@echo " "
	mysql -h ${DB_HOST} -u root -p < create.sql
	rm create.sql exsite.sql
	@echo " "
	@echo Done!

dbtables:
	echo "use ${DB_NAME}" > exsite.sql
	sed -e 's/EXSITE_LOGIN/${EXSITE_LOGIN}/' -e 's/EXSITE_PASSWORD/${EXSITE_PASSWORD}/'  -e 's/EXSITE_NAME/${EXSITE_NAME}/' -e 's/EXSITE_EMAIL/${EXSITE_EMAIL}/' ${BASE_REPOSITORY}/install/exsite.sql >> exsite.sql
	cat ${BASE_REPOSITORY}/install/content-setup.sql >> exsite.sql
	@echo " "
	@echo " "
	@echo This will create a set of tables in your existing database. 
	@echo Your MySQL user password is required.  If your database does 
	@echo not yet exist and needs to be created, then use \"make db\"
	@echo instead.
	@echo " "
	@echo -n Continue \[type Y to install\] \?
	@set PROMPT = $$< ; if ($$PROMPT != "Y" && $$PROMPT != "y") false
	@echo " "
	@echo Please enter the password for MySQL user ${DB_USER} when prompted.
	@echo " "
	mysql -h ${DB_HOST} -u ${DB_USER} -p < exsite.sql
	rm exsite.sql
	@echo " "
	@echo Done!

# configuration file

config:
	@if (! -e conf/exsite.conf) echo No configuration file in conf/
	@if (! -e conf/exsite.conf) false
	sed -e "s/site.administrator *=.*/site.administrator = ${EXSITE_EMAIL}/" \
	-e "s/server.db.name *=.*/server.db.name = ${DB_NAME}/" \
	-e "s/server.db.user *=.*/server.db.user = ${DB_USER}/" \
	-e "s/server.db.pass *=.*/server.db.pass = ${DB_PASS}/" \
	-e "s/server.db.server *=.*/server.db.server = ${DB_HOST}/" \
	conf/exsite.conf > exsite.conf
	mv conf/exsite.conf conf/exsite.conf.orig
	mv exsite.conf conf/exsite.conf

# tests

# check:  pre-installation check to see if our sources and destinations exist

check :
	@if (! -e ${BASE_REPOSITORY}) \
		echo Base repository \(${BASE_REPOSITORY}\) not found!
	@if (! -e ${BASE_REPOSITORY}) false
	@if (! -e ${PLUGIN_REPOSITORY}) \
		echo Plugin respository \(${PLUGIN_REPOSITORY}\) not found!
	@if (! -e ${PLUGIN_REPOSITORY}) false
	@if (! -e ${DOCROOT}) \
		echo Document root \(${DOCROOT}\) not found!
	@if (! -e ${DOCROOT}) false
	@if (-e conf/exsite.conf) \
		echo exsite.conf already exsits - cannot reinstall \(try make clean\)
	@if (-e conf/exsite.conf) false
	@if (-e ${PLUGIN_REPOSITORY}/CVS) \
		echo CVS files found in plugin repository.  Run \"make cvsclean\" before installing.
	@if (-e ${BASE_REPOSITORY}/CVS) \
		echo CVS files found in repository.  Run \"make cvsclean\" before installing.
	@if (-e ${BASE_REPOSITORY}/CVS) false
	@if (-e ${PLUGIN_REPOSITORY}/CVS) \
		echo CVS files found in plugin repository.  Run \"make cvsclean\" before installing.
	@if (-e ${PLUGIN_REPOSITORY}/CVS) false

# test: post-installation check to see if files were installed in the 
# expected locations;  this does not do a thorough test of webserver and
# database connectivity.

test:
	@echo Running post-installation tests...
	@if (! -e ExSite/Config.pm) echo BASE: ExSite libraries missing
	@if (! -e Modules/BaseDCD.pm) echo BASE: Base plugin missing
	@if (! -e dbmap/.datatype) echo BASE: datatype file missing
	@if (! -e dbmap/.table) echo BASE: table list missing
	@if (! -e dbmap/content) echo BASE: DB map files missing
	@if (! -e ex.cgi) echo BASE: cgi programs missing
	@if (! -e conf/exsite.conf) echo BASE: no configuration file found
	@if (! -e ${DOCROOT}/_ExSite) echo HTML: ExSite static files missing
	@if (! -e ${DOCROOT}/_Modules/icon.gif) echo HTML: ExSite generic icon missing
	@set plugcount = `ls Modules/*.pm|wc -w`; if ($$plugcount <= 1) echo PLUGINS: no plugins have been installed
	@if (! -e Modules/CMS.pm) echo PLUGINS: WARNING: no CMS plugin
	@echo DB: WARNING: no database tests run\; use \"make testdb\" to test database
	@echo " "
	@echo All tests completed.  Issues, if any, are noted above.
	@echo You should also use your browser to visit /cgi-bin/exsite-test.cgi
	@echo to test whether the webserver is configured to serve these files
	@echo and can connect to your database.
	@echo " "

testdb:
	@echo To check if your database tables are installed correctly,
	@echo make has to connect to your database.
	@echo " "
	@echo -n Continue \[type Y to connect to DB\] \?
	@set PROMPT = $$< ; if ($$PROMPT != "Y" && $$PROMPT != "y") false
	@echo " "
	@echo Please enter the password for MySQL user ${DB_USER} when prompted.
	@echo " "
	@echo "show tables; select * from user where access>4 and password='password'" | mysql -h ${DB_HOST} -u ${DB_USER} -p ${DB_NAME} > sqlout.txt
	@if (`wc -l sqlout.txt | awk '{print \$1}'` < 10) echo DB: too few tables found
	@if (`tail -1 sqlout.txt` == 'admin') echo DB: WARNING: admin account has default username/password - INSECURE!
	@rm -f sqlout.txt
	@echo " "
	@echo Database tests completed.  Issues, if any, are noted above.
	@echo You should also use your browser to visit /cgi-bin/exsite-test.cgi
	@echo to test whether the webserver can connect to your database.
	@echo " "

# cleanup
# clean - roll up existing files into an archive and clear for a new install
# veryclean - removes everything including the archive
# cvsclean - removes CVS directories if working from a direct checkout

clean:
	-mv cgi.Archive cgi.Archive.old
	mkdir cgi.Archive
	-mv ExSite Modules dbmap conf *.* crypt_tea cgi.Archive
	-mv ${DOCROOT}/_Archive ${DOCROOT}/_Archive.old
	mkdir ${DOCROOT}/_Archive
	-mv ${DOCROOT}/_ExSite ${DOCROOT}/_Modules ${DOCROOT}/_Archive.old ${DOCROOT}/_Archive

veryclean: clean
	rm -r cgi.Archive
	rm -r ${DOCROOT}/_Archive

cvsclean:
	@echo " "
	@echo This removes all CVS files/directories from your code repositories,
	@echo so they do not interfere with installation.  However, it will prevent
	@echo you from using your respositories as a CVS working directory.
	@echo To avoid this problem you should make a copy of the repositories,
	@echo remove the CVS files from the copy, and install from there.
	@echo " "
	@echo -n Continue \[type Y to clear CVS files from the repositories\] \?
	@set PROMPT = $$< ; if ($$PROMPT != "Y" && $$PROMPT != "y") false
	-find ${BASE_REPOSITORY} -name CVS -exec rm -r '{}' ';'
	-find ${PLUGIN_REPOSITORY} -name CVS -exec rm -r '{}' ';'
