#!/usr/bin/perl
#-----------------------------------------------------------------------
# dbcheck.pl : look for discrepancies between the dbmap and DB
#
# Prints the difference as a MySQL script that can be executed to
# reconcile the DB and the map. RUNNING THIS SCRIPT CAN CAUSE DATA LOSS!
# It will drop columns and tables that are not mapped. You should be 
# sure that the affected tables/columns are obsolete before allowing this.
#-----------------------------------------------------------------------
#
#   Copyright 2012 Exware Solutions, Inc.  http://www.exware.com
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

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::DB;

&exsite_init;
my $db = new ExSite::DB;
my $map = $db->{map};
$map->load_submaps();
my @maptable = $map->get_mapped_tables();
my @dbtable = $db->get_tables();
my %dbtable;
my %missingtable;
my $fixit;
foreach my $t (@dbtable) { $dbtable{$t} = 1; }

# missing tables

foreach my $t (@maptable) {
    if (exists $dbtable{$t}) {
	delete $dbtable{$t};
    }
    elsif ($map->get_table_attr($t,"alias") eq $t) {
	# not an alias
	$missingtable{$t} = 1;
	print "\n# Mapped table $t not found in database.\n";
	print $map->make_sql_create_script($t);
    }
}

# tables that don't belong

if (scalar keys %dbtable > 0) {
    foreach my $t (keys %dbtable) {
	print "\n# DB table $t not found in DBmap.\n";
	print $map->make_sql_drop_script($t);
    }
}

# columns

foreach my $t (@maptable) {
    if ($map->get_table_attr($t,"alias") eq $t) {
	# not an alias
	next if ($missingtable{$t}); # already noted
	my @mapcol = $map->get_columns($t);
	my @dbcol = $db->get_columns($t);
	my %dbcol;
	foreach my $c (@dbcol) { $dbcol{$c} = 1; }

	foreach my $c (@mapcol) {
	    next if ! $c;
	    if (exists $dbcol{$c}) {
		### should probably check if the cols are same type
		delete $dbcol{$c};
	    }
	    else {
		my $sqltype = $map->make_sql_column_type($t,$c);
		print "\n# Mapped column $t.$c not found in database.\n";
		print "alter table $t add column $c $sqltype;\n";
	    }
	}

	if (scalar keys %dbcol > 0) {
	    foreach my $c (keys %dbcol) {
		print "\n# DB column $t.$c not found in DBmap.\n";
		print "alter table $t drop column $c;\n";
	    }
	}
    }
}
