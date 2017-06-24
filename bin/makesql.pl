#!/usr/bin/perl
use ExSite::DBmap;
$d = new ExSite::DBmap(name=>"dbmap");
$d->load_submaps;
$d->make_sql_create_script;

#print "\n\n# WARNING: you must change the login id and password \n\n";
#print "INSERT INTO member (login,password,name,email,access) VALUES (\"EXSITE_LOGIN\",\"EXSITE_PASSWORD\",\"EXSITE_NAME\",\"EXSITE_EMAIL\",3);\n";
