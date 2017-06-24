#-----------------------------------------------------------------------
#
#   Copyright 2001-2009 Exware Solutions, Inc.  http://www.exware.com
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
# dbmap : database map object
#
# tools for querying the database map
#
# methods:
#   new : create dbmap object
#   get_tablemap : returns map for one table
#   get_dbmap : loads map for all tables
#   get : returns a parameter for a column (same as get_column_attr)
#   get_column : returns all parameters for a column
#   get_column_attr : returns one parameter for a column
#   get_table : returns all parameters for a table (from the .table table)
#   get_table_attr : returns one parameter for a table
#   get_datatype : returns all parameters for a datatype (from the .datatype table)
#   get_datatype_attr : returns one parameter for a datatype
#   get_parents : returns all parents of a table
#   get_children : returns all children of a table
#   make_sql_create_script : prints a SQL script to create a database
#   make_sql_drop_script : prints a SQL script to destroy a database


# The dbmap associates the following parameters with every column
# in the database:
#
# column    the column name in the database
# datatype  the datatype of the column (DBform datatype; this is
#           converted to a SQL datatype using %datatype2sql)
# size      the data size of the column (used in form generation and
#           SQL script generation)
# label     the full column description (used in forms and reports)
# display   display logic:
#           no - do not display this field publicly
#           full - display this field only in full reports
#           brief - also display this field in brief (summary) reports
#           key - primary key for display purposes
# validate  validation logic:
#           no - do not validate data in this field
#           yes - validate any data given for this field
#                 (null data will not be validated)
#           soft - required: validate this field even if null
#                  (administrator may override)
#           hard - required: validate this field even if null
#                  (administrator may not override)
# write     write level (0-4)
# read      read level (0-4)
#
# read/write levels refer to the access level of the current user.
# 0 = public (no authentication performed)
# 1 = user (authenticated)
# 2 = supervisor (user with enhanced privledges)
# 3 = administrator (user with privacy violation priveleges)
# 4 = god (user with unlimited override capabilities)

package ExSite::DBmap;

use strict;
use ExSite::Config;
use ExSite::Text;
use ExSite::Misc;    # columnwise(), keywise()

# dbmap inherits from Text

#use vars (@ISA);
our @ISA = qw(ExSite::Text);

use vars qw(%datatype_default %map_default %tablemap_default %datatype2sql);

##################################################################
# default map info

# default datatype definitions, if none are provided
# these are sufficient to manage the dbmap itself, with a few
# extra common features.
%datatype_default = (
  text => { tag=>"text", regexp=>'.+' },
  string => { tag=>"text", regexp=>'.+' },
  date => { tag=>"text", regexp=>'[0-9]{4}-[0-9]{1,2}-[0-9]{1,2} ?' },
  time => { tag=>"text", regexp=>'[012]?[0-9]:[0-5][0-9](:[0-5][0-9])?' },
  email => { tag=>"text", regexp=>'^[\w](\.?[\w\-]+)*@([\w\-]+\.)+[A-Za-z]{2,4}$' },
  url => { tag=>"text", regexp=>'(http://)?.+\..+' },
  key => { tag=>"text", regexp=>'[0-9]+' },
  'key#' => { tag=>"text", regexp=>'[0-9]+' },
  int => { tag=>"text", regexp=>'[0-9]+' },
  decimal => { tag=>"text", regexp=>'[0-9]+\.?[0-9]+' },
  password => { tag=>"password", regexp=>'.{4,}' },
  money => { tag=>"text", regexp=>'[0-9]*(.[0-9]{2})?' },
  "list:yn" => { tag=>"radio", regexp=>'Y|N' },
  "list:display" => { tag=>"select", regexp=>'no|full|brief|key' },
  "list:validate" => { tag=>"select", regexp=>'no|yes|soft|hard' },
  "list:datatype" => { tag=>"select", regexp=>'text|date|time|email|url|key|int|decimal|password|money|list:yn|list:display|list:validate|list:datatype' },
);

# default table map
%tablemap_default = (
		     "*" => {
			 table => "*",
			 key => "id",
			 title => "",
			 report => $config{report}->{style},
			 read => 0,
			 insert => 3,
			 update => 3,
			 delete => 3,
			 search => 1,
		     }
);

# default map, sufficient for dbmap
%map_default = (
  column => ["column","datatype","size","label","display","read",
        "write","validate"],
  datatype => ["string","string","int","string","list:display","int",
          "int","list:validate"],
  size => [20,20,0,40,10,0,0,10],
  label => ["column","datatype","size","label","display","read",
       "write","validate"],
  display => ["key","brief","brief","brief","brief","brief","brief","brief"],
  read => [1,1,1,1,1,1,1,1],
  write => [1,1,1,1,1,1,1,1],
  validate => ["soft","soft","soft","soft","soft","soft","soft","soft"],
);

# DBmap -> MySQL conversion
%datatype2sql = (
  'key$' => "varchar",
  key => "int",
  'key#' => "int",
  text => "text",
  html => "text",
  string => "varchar",
  variable_name => "varchar",
  int => "int",
  url => "varchar",
  email => "varchar",
  email_list => "varchar",
  date => "date",
  time => "time",
  decimal => "decimal",
  money => "decimal",
  datetime => "datetime",    # MySQL only
  enum => "int",
  list => "varchar",
  olist => "varchar",
  file => "text",            # 64K max, after base64 encoding
  bigfile => "mediumtext",   # 16M max, after base64 encoding
  set => "varchar",
  password => "varchar",
  timestamp => "timestamp",
  crypt => "text",
  mediumtext => "mediumtext",
);

sub new ($%) {
    ### extended version of ExSite::Text constructor
    my ($this,%opt) = @_;

    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;

    # optional config parameters
    if (!exists $opt{name}) {
        # no map named, use the default
        $opt{dbmap} = 1;
        $opt{name} = undef;
    }
    $obj->{name} = $opt{name};
    $obj->{dbmap} = $opt{dbmap};

    if (exists $opt{delim}) {
        $obj->{delim} = $opt{delim};
    }
    else {
        $obj->{delim} = "\t";
    }

    $obj->{mapid} = "dbmap:$opt{dbname}";
    $share{$obj->{mapid}} = $store{$obj->{mapid}};
    if (! ref $share{$obj->{mapid}}) {
	$obj->load();
    }
    return $obj;
}

sub load {
    my $this = shift;

    # map not preloaded;  read from source files
    if (defined $this->{name}) {
	# mapping a real db
	if (-e "$this->{name}/.datatype") {
	    # load custom datatypes
	    $share{$this->{mapid}}{datatype} = keywise("type",$this->fetch_all(".datatype"));
	}
	elsif ($this->{mapid} =~ /^dbmap:$/) {  
	    # use default datatypes on base map only
	    $share{$this->{mapid}}{datatype} = \%datatype_default;
	}
	# table descriptions
	if (-e "$this->{name}/.table") {
	    # load table descriptions
	    $share{$this->{mapid}}{tables} = keywise("table",$this->fetch_all(".table"));
	}
	else {
	    $share{$this->{mapid}}{tables} = \%tablemap_default;
	}
	# table maps
	my $st = tied %store;
	if ($st && $st->is_persistent) {
	    # let's preload the whole dbmap and save in the store
	    # to speed things up
	    $share{$this->{mapid}}{map} = $this->get_dbmap();
	    $st->put($this->{mapid},{datatype=>$share{$this->{mapid}}->{datatype},
				     tables=>$share{$this->{mapid}}->{tables},
				     map=>$share{$this->{mapid}}->{map}},0);
	}
	elsif ($this->{name} =~ /\//) {
	    # this is a submap; preload it now in case we merge with
	    # another dbmap and lose track of our directory structure
	    $share{$this->{mapid}}{map} = $this->get_dbmap();
	}
	else {
	    # let's only load up table data as needed
	    $share{$this->{mapid}}{map} = {};
	}
    }
    else {
	# no map defined - use default datatypes
	# this will be adequate for mapping dbmaps
	$share{$this->{mapid}}{datatype} = \%datatype_default;
	$share{$this->{mapid}}{tables} = \%tablemap_default;
    }
    return;
}

#-----------------------------------------------------------------------
# merge 2 dbmaps together
# This is used to dynamically extend the dbmap, such as when loading
# a plug-in with its own set of tables and definitions.  The plug-in
# defines its own dbmap, and we merge that into the main map.

sub merge {
    my ($this,$map) = @_;

    # don't try to merge if already done
    if (! $this->{merged}{$map->{mapid}}) {

	# datatypes
	foreach my $datatype (keys %{$share{$map->{mapid}}{datatype}}) {
	    if (exists $share{$this->{mapid}}{datatype}{$datatype}) {
		$this->warn("duplicate datatype found in $map->{mapid}: $datatype");
	    }
	    else {
		$share{$this->{mapid}}{datatype}{$datatype} = 
		    $share{$map->{mapid}}{datatype}{$datatype};
	    }
	}

	# tables
	foreach my $table (keys %{$share{$map->{mapid}}{tables}}) {
	    if (exists $share{$this->{mapid}}{tables}{$table}) {
		$this->warn("duplicate table found in $map->{mapid}: $table");
	    }
	    else {
		$share{$this->{mapid}}{tables}{$table} = 
		    $share{$map->{mapid}}{tables}{$table};
	    }
	}
    
	# maps
	foreach my $table (keys %{$share{$map->{mapid}}{map}}) {
	    if (exists $share{$this->{mapid}}{map}{$table}) {
		$this->warn("duplicate table found in $map->{mapid}: $table");
	    }
	    else {
		$share{$this->{mapid}}{map}{$table} = 
		    $share{$map->{mapid}}{map}{$table};
	    }
	}

	$this->{merged}{$map->{mapid}} = 1;
    }

#    my $st = tied %store;
#    if ($st && $st->is_persistent) {
#	$st->put($this->{mapid},$share{$this->{mapid}},0);
#    }
}

# find and merge submaps
# pass the list of modules to read in @mod
# otherwise we load everything we can find

sub load_submaps {
    my ($this,@mod) = @_;
    if (@mod == 0) {
	if (opendir(DBMAP,$this->{name})) {
	    while (my $file = readdir(DBMAP)) {
		next if ($file =~ /^\./);
		if (-e "$this->{name}/$file/.table") {
		    # looks like a submap
		    push @mod, $file;
		}
	    }
	}
	closedir DBMAP;
    }
    foreach my $mod (@mod) {
	my $map = new ExSite::DBmap(
				    name=>"$this->{name}/$mod",
				    dbname=>$mod,
				    );
	$this->merge($map);
    }
}

#-----------------------------------------------------------------------
# fetch raw maps...  
# use with caution: no guarantee these data structures will be stable.

# get map for a single table - sorted columnwise because column order is significant

sub get_map {
    my ($this,$table) = @_;
    if (! $share{$this->{mapid}}{map}{$table}) {
	if (! defined $this->{name}) {
	    # undefined map
	    $share{$this->{mapid}}{map}{$table} = \%map_default;
	}
	else {
	    my @all = $this->fetch_all($table);
	    $share{$this->{mapid}}{map}{$table} = columnwise(\@all);
	}
    }
    return $share{$this->{mapid}}{map}{$table};
}

# get maps for all tables

sub get_dbmap {
    my ($this,$map) = shift;
    $map or $map = $share{$this->{mapid}};
    foreach my $table ($this->get_mapped_tables) {
	if (! $map->{map}{$table}) {
	    if (! defined $this->{name}) {
		$map->{map}{$table} = \%map_default;
	    }
	    else {
		my @all = $this->fetch_all($table);
		$map->{map}{$table} = columnwise(\@all);
	    }
	}
    }
    return $map->{map};
}

# fetch the mapped list of columns for a table.  This is different from
# $DB->get_columns, which returns the columns known to the database engine.
# This routine also returns map order, which is preferred for forms and 
# reports.

sub get_columns {
    my ($this,$table) = @_;
    if (! $share{$this->{mapid}}{map}{$table}) {
	# load map for this table
	return undef if (! $this->get_map($table));
    }
    return wantarray ? 
	@{$share{$this->{mapid}}{map}{$table}{column}} : 
	$share{$this->{mapid}}{map}{$table}{column};
}

#-----------------------------------------------------------------------
# see if database supports a given table (and, optionally, column)
# Database must explicitly map the table/column;  "*" tables do not count.

sub is_mapped {
    my ($this,$table,$id) = @_;
    return 0 if (! $share{$this->{mapid}}{tables}{$table});
    if ($id) {
	return 0 if (! $this->get_column($table,$id));
    }
    return 1;
}

#-----------------------------------------------------------------------
# fetch map parameters...

#-----------------------------------------------------------------------
# fetch column parameters
# columns may be specified by name or number

sub get_column {
    my ($this,$table,$id) = @_;
    if (! $share{$this->{mapid}}{map}{$table}) {
	# load map for this table
	return undef if (! $this->get_map($table));
    }
    my $i;
    if ($id =~ /^[0-9]*$/) { $i = $id; }
    else {
	# Appears to be a column name - see above.
	for ($i = 0; $i <= $#{$share{$this->{mapid}}{map}{$table}{column}}; $i++) {
	    if ($share{$this->{mapid}}{map}{$table}{column}[$i] eq $id) {
		last;
	    }
	}
    }
    if ($i <= $#{$share{$this->{mapid}}{map}{$table}{column}}) {
	my %data;
	foreach my $key (keys %{$share{$this->{mapid}}{map}{$table}}) {
	    $data{$key} = $share{$this->{mapid}}{map}{$table}{$key}->[$i];
	}
	return %data;
    }
    else {
	# could not find any matching column
	return undef;
    }
}

# return one attribute for a given column

sub get_column_attr {
    my ($this,$table,$id,$param) = @_;
    if (! $share{$this->{mapid}}{map}{$table}) {
	# load map for this table
	return undef if (! $this->get_map($table));
    }
    if ($id =~ /^[0-9]*$/) { #################### does this work for numbers?
	# appears to be a column number (fast)
	return $share{$this->{mapid}}{map}{$table}{$param}[$id];
    }
    else {
	# Appears to be a column name - must search for the column (slow).
	# Could speed this up by also indexing the map by column name, but
	# the time savings would be offset by the time to actually build the
	# map.  Since these sorts of lookups are generally infrequent,
	# it is probably more efficient to use this low-speed method.
	for (my $i = 0; $i <= $#{$share{$this->{mapid}}{map}{$table}{$param}}; $i++) {
	    if ($share{$this->{mapid}}{map}{$table}{column}[$i] eq $id) {
		return $share{$this->{mapid}}{map}{$table}{$param}[$i];
	    }
	}
    }
    # could not find any matching column
    return undef;
}

# return number of columns in a table

sub get_ncol {
    my ($this,$table) = @_;
    &get_map($this,$table);
    return $#{$share{$this->{mapid}}{map}{$table}{column}} + 1;
}

#### deprecated methods:

# get is synonymous with get_column_attr

sub get {
    return &get_column_attr(@_);
}


#-----------------------------------------------------------------------
# datatype queries...

sub get_datatype {
    my ($this,$datatype) = @_;
    if (exists $share{$this->{mapid}}{datatype}{$datatype}) {
	return $share{$this->{mapid}}{datatype}{$datatype};
    }
    return {};
}

sub get_datatype_attr {
    my ($this,$datatype,$par) = @_;
    if (exists $share{$this->{mapid}}{datatype}{$datatype}) {
	return $share{$this->{mapid}}{datatype}{$datatype}->{$par};
    }
    return undef;
}

sub is_num {
    my ($this,$table,$col) = @_;
    my $datatype = $this->get_column_attr($table,$col,"datatype");
    return $datatype =~ /^(int|money|decimal|key)/;
}

#### deprecated methods:

# get datatype map - sorted keywise

sub get_typemap {
    my ($this) = shift;
    return $share{$this->{mapid}}{datatype};
}

sub get_datatypes {
    my ($this) = shift;
    return $share{$this->{mapid}}{datatype};
}

# return tag for a particular datatype

sub tag {
    my ($this,$datatype) = @_;
    return $this->get_datatype_attr($datatype,"tag");
}

# return regexp for a particular datatype

sub regexp {
    my ($this,$datatype) = @_;
    return $this->get_datatype_attr($datatype,"regexp");
}

#-----------------------------------------------------------------------
# tablemap queries...

# return all attributes of a table
sub get_table {
    my ($this,$table) = @_;
    if (exists $share{$this->{mapid}}{tables}) {
	if (exists $share{$this->{mapid}}{tables}{$table}) {
	    return $share{$this->{mapid}}{tables}{$table};
	}
	elsif (exists $share{$this->{mapid}}{tables}{"*"}) {
	    return $share{$this->{mapid}}{tables}{"*"};
	}
    }
    return {};
}

# return a particular attribute of a table
sub get_table_attr {
    my ($this,$table,$attr) = @_;
    if (exists $share{$this->{mapid}}{tables}) {
	if (exists $share{$this->{mapid}}{tables}{$table}) {
	    if (exists $share{$this->{mapid}}{tables}{$table}{$attr}) {
		return $share{$this->{mapid}}{tables}{$table}{$attr};
	    }
	}
	elsif (exists $share{$this->{mapid}}{tables}{"*"}) {
	    if (exists $share{$this->{mapid}}{tables}{"*"}{$attr}) {
		return $share{$this->{mapid}}{tables}{"*"}{$attr};
	    }
	}
    }
    return undef;
}

# set list of mapped tables
sub set_mapped_tables {
    my ($this) = shift;
    $this->{mapped_tables} = \@_;
}

# get list of mapped tables
sub get_mapped_tables {
    my ($this) = shift;
    if ($this->{mapped_tables}) { 
	return @{$this->{mapped_tables}};
    }
    elsif ($this->{tables}->{"*"}) {
	# wildcard applies to all tables known to the underlying database
	return $this->get_tables;  ## this doesn't work
    }
    else {
	# only recognize the mapped tables
	return keys %{$share{$this->{mapid}}{tables}};
    }
}

# table_title : returns a title for a given table
#
# looks for "title" and "plural" attributes, otherwise, makes up
# a title based on the table name.
#
# INPUT:
#    - table name
#    - plural flag (try to pluralize title, if true)
#
# OUTPUT:
#    - returns a title string

sub get_table_title {
    my ($this,$table,$plural) = @_;
    # title the table
    my $table_title;
    my $tmap = $share{$this->{mapid}}{tables};
    if ($tmap) {
      if ($tmap->{$table}) {
	if ($plural && $tmap->{$table}{plural}) {
	  return $tmap->{$table}{plural};
	}
	elsif ($tmap->{$table}{title}) {
	  $table_title = $tmap->{$table}{title};
	}
      }
    }
    # no table title defined
    if (! $table_title) { $table_title = $table; } #### non-capitalized

    # pluralize, if required
    if ($plural) {
      # no plural defined; make something up
      $table_title =~ s/_/ /g;
      $table_title =~ s/y$/ie/;
      return $table_title."s";
    }
    else {
      return $table_title;
    }
}

# return the name of the table in the low-level DB

sub get_table_name {
    my ($this,$table) = @_;
    my $tmap = $share{$this->{mapid}}{tables}{$table};
    return $tmap->{alias} ? $tmap->{alias} : $table;
}

#### deprecated methods:

sub table_title {
    return &get_table_title(@_);
}

sub table {
    return &get_table_attr(@_);
}

# get entire table attribute map - sorted keywise
sub get_tablemap {
    my ($this) = shift;
    return $share{$this->{mapid}}{tables};
}

#-----------------------------------------------------------------------
# table relationships...

# return parents of a table

sub get_parents {
    my ($this,$table) = @_;
    if (! $share{$this->{mapid}}{map}{$table}) {
	return undef if (! $this->get_map($table));
    }
    my @fkeys = grep /^key:/, @{$share{$this->{mapid}}{map}{$table}{datatype}};
    foreach my $key (@fkeys) {
	$key =~ s/^key://;
    }
    return @fkeys;
}

# return children of a table

sub get_children {
    my ($this,$table) = @_;
    $this->get_dbmap();
    my @fkeys;
    my @children;
    foreach my $ctable (keys %{$share{$this->{mapid}}{map}}) {
	next if ($ctable =~ /^\.|^db$/);
	@fkeys = grep /^key:/, @{$share{$this->{mapid}}{map}{$ctable}{datatype}};
	if (grep(/^key:${table}$/,@fkeys) > 0) {
	    push @children, $ctable;
	}
    }
    return @children;
}

# return the column in table $child that references table $parent
#
# if $strong_match is true, looks for key:parent relationships only,
# otherwise, looks for key[:=]parent relationships

sub get_reference_column {
    my ($this,$child,$parent,$strong_match) = @_;
    my $map = $this->get_map($child);
    my $ncol = $this->get_ncol($child);
    my @refs;
    for (my $i; $i < $ncol; $i++) {
	if ($strong_match) {
	    if ($map->{datatype}->[$i] =~ /^key:$parent$/) {
		if (wantarray) {
		    push @refs, $map->{column}->[$i];
		}
		else {
		    # return the first matching column in scalar context
		    return $map->{column}[$i];
		}
	    }
	}
	else {
	    if ($map->{datatype}->[$i] =~ /^key[:=]$parent$/) {
		if (wantarray) {
		    push @refs, $map->{column}->[$i];
		}
		else {
		    # return the first matching column in scalar context
		    return $map->{column}[$i];
		}
	    }
	}
    }
    return wantarray ? @refs : $refs[0];
}

#-----------------------------------------------------------------------
# some useful functions from DB

#------------------------------------------------------------------------
# fetch_all : get all records
# arguments:
#   $table : table to read from
# returns an array of datahashes
#------------------------------------------------------------------------

sub fetch_all ($$$) {
    my ($this,$table) = @_;
    return $this->select($table);
}

#-----------------------------------------------------------------------
# SQL functions...

# make sql script to create a database

sub make_sql_create_script {
    my ($this,@table) = @_;
    &get_dbmap($this);
    if (scalar @table == 0) {
	print "# MySQL create script - autogenerated by ExSite::DBmap\n\n";
	print "# create all tables\n\n";
	@table = keys %{$share{$this->{mapid}}{map}};
    }
    foreach my $table (@table) {
	next if (! $table);
	next if ($table =~ /^\.|^db$/);
	next if ($table eq "CVS");
	next if ($table ne $share{$this->{mapid}}{tables}{$table}{alias});
	my @indexes;
	if ($share{$this->{mapid}}{tables}{$table}{index}) {
	    # this table uses indexes
	    @indexes = split /;/,$share{$this->{mapid}}{tables}{$table}{index};
	}
	print "CREATE TABLE IF NOT EXISTS `$table` (\n";
	my $ncol = $#{$share{$this->{mapid}}{map}{$table}{column}};
	for (my $i=0; $i <= $ncol; $i++) {
	    my $column = $share{$this->{mapid}}{map}{$table}{column}->[$i];
	    print "        `$column`";
	    my ($datatype,$datatype_option) =
		split /[:=]/, $share{$this->{mapid}}{map}{$table}{datatype}[$i];
	    print " ";
	    print $this->make_sql_column_type($table,$i);
	    if ($i < $ncol || @indexes > 0) { print ",\n"; }
	}
	if (@indexes > 0) {
	    foreach my $index (@indexes) {
		if ($index =~ /[^\s]*/) {
		    print "\tINDEX($index)";
		}
		if ($index ne $indexes[-1]) { print ",\n"; }
	    }
	}
	print "\n        );\n";
    }
}

sub make_sql_column_type {
    my ($this,$table,$col) = @_;
    my $out;
    my $icol;
    my $column;
    if ($col =~ /^\d+$/) {
	$icol = $col;
	$column = $share{$this->{mapid}}{map}{$table}{column}[$icol];
    }
    else {
	my $ncol = $#{$share{$this->{mapid}}{map}{$table}{column}};
	for ($icol=0; $icol <= $ncol; $icol++) {
	    $column = $share{$this->{mapid}}{map}{$table}{column}[$icol];
	    last if ($column eq $col);
	}
	if ($column ne $col) {
	    # no match
	    return undef;
	}
    }

    my ($datatype,$datatype_option) =
	split /[:=]/, $share{$this->{mapid}}{map}{$table}{datatype}[$icol];
    $out .= $datatype2sql{$datatype};
    if ($datatype =~ /^money$/) {
	my $size = $share{$this->{mapid}}{map}{$table}{size}[$icol];
	$out .= $size ? "($size)" : "(8,2)";
    }
    elsif ($datatype2sql{$datatype} =~ /^(varchar|varbinary|decimal|char)$/) {
	################ make configurable
	my $size = $share{$this->{mapid}}{map}{$table}{size}[$icol];
	if (!$size) {
	    print STDERR "WARNING: no size given for $datatype2sql{$datatype}\n";
	}
	$out .= "($size)";
    }
    if ($share{$this->{mapid}}{map}{$table}{validate}[$icol] eq "hard" ||
	$share{$this->{mapid}}{map}{$table}{datatype}[$icol] =~ /key[:=]/) {
	$out .= $share{$this->{mapid}}{map}{$table}{datatype}[$icol] eq "key#" ? " NOT NULL" : " NOT NULL DEFAULT 0";
    }
    if ($share{$this->{mapid}}{map}{$table}{datatype}[$icol] =~ /key[\$\#]?$/) {
	$out .= " PRIMARY KEY";
    }
    if ($share{$this->{mapid}}{map}{$table}{datatype}[$icol] =~ /key\#/) {
	$out .= " AUTO_INCREMENT";
    }
    return $out;
}

# make sql script to destroy a database

sub make_sql_drop_script {
    my ($this,@table) = @_;
    &get_dbmap($this);
    if (scalar @table == 0) {
	print "# drop all tables\n";
	@table = keys %{$share{$this->{mapid}}{map}};
    }
    foreach my $table (@table) {
	if ($table =~ /^%/) { next; }
	next if ($table =~ /^\.|^db$/);
	print "drop table $table;\n";
    }
}

1;
