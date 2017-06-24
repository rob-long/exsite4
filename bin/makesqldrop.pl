#!/usr/bin/perl
use ExSite::DBmap;
$d = new ExSite::DBmap(name=>"dbmap");
$d->load_submaps;
$d->make_sql_drop_script;
