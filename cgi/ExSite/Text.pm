#-------------------------------------------------------------------------
# ExSite::Text - text database driver for ExSite web development package
#----------------------------------------------------------------------------
#
#   Copyright 2001-2004 Exware Solutions, Inc.  http://www.exware.com
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
#
# This driver will perform a set of SQL-like operations on a simple
# plain text database.  The following assumptions are made about the
# structure of the database and its text files:
#
# - the database is contained in a single directory
# - each table consists of its own file
# - each record consists of one line in the file
# - each column consists of a delimited section of a line
# - the first column is the primary key of the table
# - the first line in each table contains delimited headers (ie. column names)
# - lines (other than the 1st) may be commented out using '#' in column 1
#
# Databases conforming to this format are easily editable using any
# text editor, and can also be imported into most spreadsheet programs.
#
# All ExSite DB drivers must contain the following methods:
#
# new
# get_tables
# get_columns
# get_key
# select
# insert
# update
# delete
#
# All remaining methods are unique to the Text driver, and should not be
# used if portability to other drivers is desired.  They are intended
# to be used internally only.
#-------------------------------------------------------------------------
# TODO:
# file locking
# joining
# bring update, insert, delete up to API specs
# sort, limit
#-------------------------------------------------------------------------

package ExSite::Text;
use strict;
use ExSite::Base;
use vars qw(@ISA);
@ISA = qw(ExSite::Base);

#------------------------------------------------------------------------
# new : "open" a flat file database
# options :
#   delim => RE that delimits columns ("\t" by default)
#   name => directory containing the database ("." by default)
#------------------------------------------------------------------------

sub new ($%) {
    #my ($this,%option) = @_;
    my ($this,%opt) = @_;

    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;

    # optional config parameters
    if (!exists $opt{name}) {
	$opt{name} = ".";
    }
    $obj->{name} = $opt{name};

    if (exists $opt{delim}) {
	$obj->{delim} = $opt{delim};
    }
    else {
	$obj->{delim} = "\t";
    }

    # table cache
    $obj->{columns} = {};
    $obj->{key} = {};

    return $obj;
}

# can only have one table open at a time

sub open_table {
    my ($this,$table) = @_;
    open TABLE, "$this->{name}/$table" or return 0;
    return 1;
}

sub open_table_append {
    my ($this,$table) = @_;
    open TABLE, ">>$this->{name}/$table" or return 0;
    return 1;
}

sub close_table {
    my ($this) = @_;
    close TABLE;
}

#------------------------------------------------------------------------
# handler : install a handler to override package behaviours
#
# Handlers can be installed by the application to handle custom logic.
# Most handlers have names identical to or related to the name of the
# method in which they are called (sometimes with pre_ and post_ prefixes
# if they do pre- and post-processing relative to some action.)
# Handlers are usually set up in the Config module.
#------------------------------------------------------------------------

sub handler {
  my ($this,$name,$handler_ptr) = @_;
  $this->{handler}->{$name} = $handler_ptr;
}

#------------------------------------------------------------------------
# STATUS METHODS
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# get_tables : assume any file in DB directory is a table; return
#              list of all such files
#------------------------------------------------------------------------

sub get_tables {
    my $this = shift;
    if (exists $this->{table_name}) { return keys %{$this->{table_name}}; }
    opendir DB, $this->{name};
    # ignore hidden files
    my @files = grep /^\w/, readdir DB;
    my @tables = grep !/^(CVS|\.*~)$/, @files;
    closedir DB;
    $this->{table_name} = {};
    foreach my $table (@tables) {
      $this->{table_name}->{$table} = $table;
    }
    return @tables;
}

#------------------------------------------------------------------------
# get_columns : assume first record of a table contains the column names
#------------------------------------------------------------------------

sub get_columns {
    my ($this,$table) = @_;
    if (exists $this->{columns}->{$table}) { 
	return @{$this->{columns}->{$table}}; 
    }
    if (&open_table($this,$table)) {
	my $head = <TABLE>;
	&close_table($this);
	chomp $head;
	my @columns = split /$this->{delim}/, $head;
	$this->{columns}->{$table} = \@columns; 
	$this->{key}->{$table} = $columns[0]; 
	return @columns;
    }
    else {
	return undef;
    }
}

#------------------------------------------------------------------------
# get_key : assume first field of table is the primary key
#------------------------------------------------------------------------

sub get_key {
    my ($this,$table) = @_;
    if (exists $this->{key}->{$table}) {
	return $this->{key}->{$table};
    }
    my @columns = &get_columns($this,$table);
    return $columns[0];
}


#------------------------------------------------------------------------
# DATABASE ACCESS METHODS
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# select : retrieve a set of records
#



sub select ($$;$$$$) {
    my ($this,$table,$column,$match,$sort,$limit) = @_;

    #
    # currently supports only single-table lookups (no joins)
    # sort and limit are ignored
    #
    
    my @columns;
    if ($column) {
	@columns = @$column;
    }
    else {
	@columns = &get_columns($this,$table);
    }

    if (@columns > 0) {
	my @records = ();
	my %record;
	&open_table($this,$table) or return;
	# ignore column headers
	$_ = <TABLE>;
      record:
	while (<TABLE>) {
	    next if (/^\#/);
	    chomp;
	    # make datahash for this record
	    my @data = split /$this->{delim}/, $_;
	    for (my $i = 0; $i < $#columns + 1; $i++) {
		$record{$columns[$i]} = $data[$i];
	    }
	    # test for match (assume SQL-type wildcards, ie. '%')
	    if (defined $match) {
		my @mkey = keys %$match;
		if (@mkey > 0) {
		    while (my ($key,$val) = each %$match) {
			# protect escaped %
			$val =~ s/\\%/~_wqxkz_~/g;
			# convert SQL wildcards to regexp format
			$val =~ s/%/.*/g;
			next record if ($record{$key} !~ /$val/);
			# unprotect escaped %
			$val =~ s/~_wqxkz_~/\\%/g;
		    }
		}
	    }
	    # we have a match; append record to current list
	    push @records, {};
	    foreach my $col (@columns) {
		$records[-1]->{$col} = $record{$col};
	    }
	}
	&close_table($this);
	if (wantarray) { return @records; }
	return \@records;
    }
    return undef;
}

#------------------------------------------------------------------------
# insert : append a new record
#------------------------------------------------------------------------

sub insert {
    my ($this,$table,$rdata) = @_;
    my @columns = &get_columns($this,$table);
    # build record with columns in proper sequence
    my @data;
    foreach my $col (@columns) {
	push @data,$rdata->{$col};
    }
    # append record to end of file
    if (&open_table_append($this,$table)) {
	print TABLE join("$this->{delim}",@data)."\n";
	&close_table($this);
	return 1;
    }
    return 0;
}

#------------------------------------------------------------------------
# update : replace an existing record
#          - load entire table into memory
#          - replace matching record
#          - write out entire table to disk
#------------------------------------------------------------------------

sub update {
    my ($this,$table,$rdata) = @_;
    my @columns = &get_columns($this,$table);
    my $key = &get_key($this,$table);
    # build record with columns in proper sequence
    my @data;
    foreach my $col (@columns) {
	push @data,$rdata->{$col};
    }
    # read table into memory
    return 0 if (! &open_table($this,$table));
    my @records = <TABLE>;
    &close_table($this);
    # update memory copy
    foreach my $rec (@records) {
	if ($rec =~ /^$data[0]$this->{delim}/) {
	    $rec = join("$this->{delim}",@data)."\n";
	    last;
	}
    }
    # write table back to disk
    return 0 if (! &open_table($this,$table));
    print TABLE @records;
    &close_table($this);
    return 1;
}

#------------------------------------------------------------------------
# delete : remove a record
#          - load entire table into memory
#          - delete matching record
#          - write out entire table to disk
#------------------------------------------------------------------------

sub delete {
    my ($this,$table,$rdata) = @_;
    my @columns = &get_columns($this,$table);
    my $key = &get_key($this,$table);
    # build record with columns in proper sequence
    my @data;
    foreach my $col (@columns) {
	push @data,$rdata->{$col};
    }
    # read table into memory
    return 0 if (! &open_table($this,$table));
    my @records = <TABLE>;
    &close_table($this);
    # update memory copy
    my $irec = 0;
    foreach my $rec (@records) {
	last if ($rec =~ /^$data[0]$this->{delim}/);
	$irec++;
    }
    splice(@records,$irec,1);
    # write table back to disk
    return 0 if (! &open_table($this,$table));
    print TABLE @records;
    &close_table($this);
    return 1;
}

1;


