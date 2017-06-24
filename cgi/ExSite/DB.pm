package ExSite::DB;
#-----------------------------------------------------------------------
#
#   Copyright 2001-2007 Exware Solutions, Inc.  http://www.exware.com
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

#======================================================================

=pod

=head1 ExSite::DB - generic database driver wrapper for ExSite

The DB class is a wrapper class for one of the db driver classes.
It inherits general query methods from one, but only one of these,
determined at runtime.

DB also provides an assortment of simplified and/or convenience
wrapper methods for accessing the low-level database driver routines.

In addition, the DB class provides an assortment of caching, security,
access control, sorting, and row relationship methods.

The DB class is not normally used directly, unless the program is
doing pure data analysis.  Normally the Form:: and Report:: classes
are preferred for web application work, as these classes inherit all
of DB's methods.

=cut

#======================================================================

use strict;
use ExSite::Config;
#use ExSite::Misc;
use ExSite::Util;
use ExSite::MySQL;
#use ExSite::ASASQL;
use ExSite::Cache;
use ExSite::Text;
use ExSite::DBmap;
use ExSite::Auth;
use MIME::Base64;

### FIXME: we eval the inclusion of MySQL below, but if we remove it
### from the use statements, we get a connection failure???

use vars qw(@ISA %cplog %driver);
@ISA = qw(ExSite::Auth);

# driver name conversion
%driver = (
	   "sql" => "MySQL",
	   "mysql" => "MySQL",
	   "text" => "Text",
	   "asasql" => "ASASQL",
	   );

#======================================================================

=pod

=head2 new(%options) - DB constructor

new() creates a database handle.  The following arguments should be 
specified in the options:

=over 4

=item type

the database type ("sql" and "text" are most common types)

=item name

database name

=item map

map name

=item other...

any other args required by driver (eg. "user" and "pass" may
be required to access SQL databases).

=back

Note that the map is a small database that describes the main database.
The map name is the name of the map database - it will be opened up
using the DBmap class.

=cut

#======================================================================

sub new {
    my ($this, %opt) = @_;
    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;
    # if no options are provided, use default database hash
    my @opkeys = keys %opt;
    if (@opkeys == 0) { %opt = %{$config{server}->{db}}; }
    # setup database
    # inheritance is determined at runtime (!)
    # must copy relevant attributes from our temporary db object into
    # the wrapper object, so that inherited methods are duped into
    # thinking they are working on an object that they created.
    $_ = $opt{type};
    my $db;

    my $driver = exists $driver{$opt{type}} ? $driver{$opt{type}} : $opt{type};
    if ($driver) {
	my $class = "ExSite::$driver";
	$db = eval "new $class(%opt)";
	if ($@) {
	    # error
	    $obj->error("ExSite::DB: bad database driver ($class): $@");
	    return undef;
	}
	else {
	    # success
	    push @ISA, $class;
	    $obj->{dbtype} = $class;
	}
    }
    else {
	# error
	$obj->error("ExSite::DB: no database driver");
	return undef;
    }

    # copy attributes of whatever db type we've created into our db object
    foreach my $key (keys %$db) {
	$obj->{$key} = $db->{$key};
    }
    #$obj->{db} = $db;  ###?

    # setup dbmap
    my $map;
    if ($opt{map}) {
	$map = new ExSite::DBmap( name=> $config{server}->{$opt{map}}->{name},
				  dbname=> $opt{name} );
	#$map = new ExSite::DBmap( %{$config{server}->{map}} );
    }
    else {
	#$map = new ExSite::DBmap( name=> undef );
	$map = new ExSite::DBmap();
	# no explicit list of tables, no real database to look up, so we must
	# manually set the list of mappable tables.
	$map->set_mapped_tables($db->get_tables);
    }

    if (! $map) {
	$obj->error("DB ERROR: no dbmap");
	return undef;
    }
    $obj->{map} = $map;

    # error accumulators - used for user display errors;
    # For loggable system errors, use error() method instead.
    $obj->{errors} = [];      # fatal errors - changes will not be committed

    # store a pointer to the DB object in %share, unless save is disabled
    if (exists $opt{save} ? $opt{save} : 1) {
	$share{DB} = $obj;
    }

    # remember who we are
    $obj->{id} = "$opt{server}:$opt{name}";

    # setup Base class features
    $obj->initialize_object;

    # handlers - done in base class now
    #&install_handlers($obj);

    # setup a default querylib
    $obj->run_handler("setup_querylib");

    # DB cache 
    $share{Cache} = new ExSite::Cache();

    return $obj;
}

#======================================================================

=pod

=head1 Retrieving Data

These methods invoke the low-level methods select, insert, update, and
delete, but otherwise have no knowledge of the underlying driver.
Unlike the low-level driver methods, they can also make use of the
dbmap, if needed.

All fetch methods return datahashes, that is one hash per record with
keys equal to the field names, and values equal to the data for those
fields.  All fields in each record are returned, by default, including
fields that the user is not permitted to access (access control is
performed at a higher level, in Form:: or Report::).

The fetch methods will take an optional SORT argument, which will
attempt to get the database driver to sort the resulting records
according to the value of SORT, which can either be a field name, or a
reference to a list of field names.  If no SORT argument is specified,
the data will be unsorted, but may still be sorted after the fact using the
DB::sort_rows() method.

=head2 C<fetch(), fetch_key()> - fetch a record by its primary key

Usage: C<$db-E<gt>fetch(TABLE, KEY, SORT)>

Returns the single record from C<TABLE> with primary key C<KEY>.  If
more than one record has that primary key, this routine returns the
first one found.  SORT is optional.

The C<fetch()> method is synonymous with C<fetch_key()>.

=head2 C<fetch_match()> - fetch a record using a match hash.

Usage: C<$db-E<gt>fetch_match(TABLE, MATCH, SORT)>

MATCH is a reference to a hash containing field =E<gt> value pairs.
The values are assumed to be text segments that will be used to match
data in the actual database.  The SQL "%" wildcard may be used.
Records that match ALL field =E<gt> value pairs will be returned.
SORT is optional.

=head2 C<fetch_all()> - fetch all records in a table

Usage: C<$db-E<gt>fetch_all(TABLE, SORT)>

Returns all records in the table, optionally sorted according to the
value of SORT.

Obviously this can be a dangerous method to use on a large table.

=head2 C<fetch_child()> - fetch related rows in a sub-table

Usage: C<$db-E<gt>fetch_child(TABLE, PARENT, PARENT_KEY, SORT)>

C<fetch_child()> is a trivial join, fetching all rows from table B
that relate to a single row in table A, where table B references A
using its primary key.  The rows in B are "children" of the row in A.
(There is no need to use a real JOIN mechanism, since we already know
which row in A we are matching to.)  SORT is optional.

=head2 C<fetch_join()> - fetch related rows in a sub-table

Usage: C<$db-E<gt>fetch_join(TABLE_LIST, MATCH_LIST)>

In development.

=head2 C<fetch_m2m()> - fetch rows that are related via a join table.

Usage: C<$db-E<gt>fetch_m2m(TABLE_LIST, MATCH_LIST)>

Say that table A relates to table B via a junction table J that contains
references to the primary keys of both A and B.  fetch_m2m will
perform a join on A,B,J, selecting all members of B that
relate to a specific member of A via the junction table J.

Example:  a singer can have songs on many albums, and an album can
contain many different singers.  If we have tables "singer", "album",
and "singer_album" (which contains the primary keys of particular
singer/album pairs), then we can select all the albums with songs by
singer "XYZ" using:

C<$db-E<gt>fetch_m2m("album","singer","XYZ","singer_album");>

(read this as "fetch albums for singer XYZ using singer_album")

=head2 C<count()> - count records in a table

Usage: C<$db-E<gt>count(TABLE, MATCH)>

Returns the number of records in C<TABLE> that match the passed match
hash.  If C<MATCH> is left off, this returns the number of records
in the table.

=head2 C<get_columns()> - return list of column names in a table 

Usage: C<$db-E<gt>get_columns(TABLE)>

Returns an array of column names in the given table.  This data is
looked up in the DBmap, not in the database itself.  As such, it is
really returning a list of columns that ExSite knows about, not the
full list of columns in the database.

=head2 C<get_key()> - return primary key of a table

Usage: C<$db-E<gt>get_key(TABLE)>

Returns the primary key of the given table, as reported by the DBmap.

=cut

#======================================================================

#----------------------------------------------------------------------
# fetch_key : fetch a row by its primary key

sub fetch {
    my ($this,$table,$key,$sort) = @_;
    # get the true name of the table, and the primary key name
    my $tab = $this->{map}->get_table_name($table);
    #my $pkey = $this->get_key($tab);  # calls DB server
    my $pkey = $this->{map}->get_table_attr($tab,"key");  # no server call
    my @dat = $this->select($tab,undef,{$pkey=>$key},$sort);
    # return only one record
    if (wantarray && @dat > 0) { 
	if (ref $dat[0] ne "HASH") {
	    $this->fatal("Bad table description: $table $key");
	    return undef;
	}
	return %{$dat[0]}; 
    }
    return $dat[0];
}

# fetch_key is synonymous with fetch
sub fetch_key {
    return &fetch(@_);
}

#----------------------------------------------------------------------
# fetch_match : fetch rows using a match hash

sub fetch_match {
    my ($this,$table,$match,$sort,$limit) = @_;
    my $tab = $this->{map}->get_table_name($table);
    if ($tab ne $table) {
	# this is an aliased table - check for fixed fields
	my $ncol = $this->{map}->get_ncol($table);
	for (my $icol = 0; $icol <= $ncol; $icol++) {
	    if ($this->{map}->get($table,$icol,"datatype") eq "fixed") {
		$match->{$this->{map}->get($table,$icol,"column")} = 
		    $this->{map}->get($table,$icol,"default");
	    }
	}
    }
    return $this->select($tab,undef,$match,$sort,$limit);
}

#----------------------------------------------------------------------
# fetch_all : fetch all available rows

sub fetch_all ($$$) {
    my ($this,$table,$sort,$limit) = @_;
    my $tab = $this->{map}->get_table_name($table);
    if ($tab ne $table) {
	# this is an aliased table - check for fixed fields
	my $match = {};
	my $ncol = $this->{map}->get_ncol($table);
	for (my $icol = 0; $icol <= $ncol; $icol++) {
	    if ($this->{map}->get($table,$icol,"datatype") eq "fixed") {
		$match->{$this->{map}->get($table,$icol,"column")} = 
		    $this->{map}->get($table,$icol,"default");
	    }
	}
	return $this->select($tab,undef,$match,$sort,$limit);
    }
    else {
	return $this->select($tab,undef,undef,$sort,$limit);
    }
}

#----------------------------------------------------------------------
# fetch_child : fetch descendant rows
#
# ...uses the DBmap to determine the reference keys.

sub fetch_child {
  my ($this,$table,$parent_table,$parent_id,$sort,$limit) = @_;
  # select rows referring to $parent_id
  my $match;
  my @key = $this->{map}->get_reference_column($table,$parent_table);
  my $tab = $this->{map}->get_table_name($table);
  if (@key == 1) { 
      # we can use a simple select
      return $this->select($tab,undef,{$key[0]=>$parent_id},$sort,$limit);
  }
  # try accumulating all references in one data array
  my @alldata;
  my $keyname = $this->get_key($tab);
  my %keylog;
  foreach my $key (@key) { 
      my $data = $this->select($tab,undef,{$key=>$parent_id},$sort,$limit);
      foreach my $d (@$data) {
	  if (! $keylog{$d->{$keyname}}) {
	      push @alldata,$d;
	  }
	  $keylog{$d->{$keyname}} = 1;
      }
  }
  return wantarray ? @alldata : \@alldata;
}

#----------------------------------------------------------------------
# fetch_m2m : fetch rows via a join table
#
# ...uses the DBmap to determine the reference keys.

sub fetch_m2m {
  my ($this,$table1,$table2,$key2,$jointable,$sort,$limit) = @_;
  my ($ref1,$ref2,$pkey1,$pkey2,@columns);
  my $tab1 = $this->{map}->get_table_name($table1);
  my $tab2 = $this->{map}->get_table_name($table2);
  my $jtab = $this->{map}->get_table_name($jointable);

  # find the join columns that reference the parent tables
  $ref1 = "$jtab.".$this->{map}->get_reference_column($jtab,$tab1);
  $ref2 = "$jtab.".$this->{map}->get_reference_column($jtab,$tab2);

  # get primary keys, with explicit table references added
  $pkey1 = "$tab1.".$this->get_key($tab1);
  $pkey2 = "$tab2.".$this->get_key($tab2);

  # we only want to select the columns from table1
  @columns = $this->get_columns($tab1);
  # add explicit table reference to column names
  foreach my $col (@columns) {
    $col = "$tab1.$col";
  }

  # In SQLese:
  # SELECT FROM A,B,J WHERE B.PKEY="key2" AND J.REF2="key2" AND J.REF1=A.PKEY
  return $this->select([ $tab1, $tab2, $jtab ],
		       \@columns,
		       { $pkey2=>$key2, $ref2=>$key2, $ref1=>\$pkey1 },
		       $sort,$limit);
}

### TODO:
#
# fetch_tree() - fetch all records to a certain depth in a simple tree
#                "simple" tree means all nodes come from one table
# fetch_graph() - fetch all records to a certain depth in a simple graph
#                "simple" graph means all nodes come from one table
#
# These will probably require a SQL engine.

#======================================================================
# wrappers for low-level database driver methods insert, update,
# delete, select.  Allows us to apply DBmap logic to our database
# requests - in particular, table aliases.

sub get_columns {
    my ($this,$table) = @_;
    my $dbtable = $this->{map}->get_table_name($table);

    # check the cache - we DO NOT use the table name as the cache
    # primary key, because modifications to the table data does not
    # affect the cached column names.
    my @cache_key = (undef,"get_columns",$dbtable,$this->{id});
    my $dat = $share{Cache}->get(@cache_key);
    if ($dat) {
	return @$dat; 
    }
    else {
	#my @dat = $this->dbget_columns($dbtable);
	my @dat = $this->SUPER::get_columns($dbtable);
	# cache the result
	if ($this->is_cacheable()) {
	    $share{Cache}->save(\@dat,@cache_key);
	}
	return @dat;
    }
}

sub get_key {
    my ($this,$table) = @_;
    my $dbtable = $this->{map}->get_table_name($table);

    # check the cache - we DO NOT use the table name as the cache
    # primary key, because modifications to the table data does not
    # affect the table primary key.
    my @cache_key = (undef,"get_key",$dbtable,$this->{id});
    my $dat = $share{Cache}->get(@cache_key);
    if ($dat) {
	return $dat; 
    }
    else {
	#$dat = $this->dbget_key($dbtable);
	$dat = $this->SUPER::get_key($dbtable);
	# cache the result
	if ($this->is_cacheable()) {
	    $share{Cache}->save($dat,@cache_key);
	}
	return $dat;
    }
}

#### include security checks for access to tables, columns, rows

sub select {
    my ($this,$table,$column,$cond,$sort,$limit) = @_;
    my $dbtable;
    
    # ** Fix table names
    # map DBmap table names to low-level table names
    if (ref $table eq "ARRAY") {
	# array of tables was passed
	my @tables;
	foreach my $t (@$table) {
	    push @tables, $this->{map}->get_table_name($t);
	}
	# replace $table with unaliased version
	$dbtable = \@tables;
    }
    else {
	# single table was passed as a scalar - unalias it
	$dbtable = $this->{map}->get_table_name($table);
    }

    # check the cache first
    my @dat;
    my @cache_key = ($dbtable,$column,$cond,$sort,$limit,$this->{id});
    my $dat = $share{Cache}->get(@cache_key);
    # (Note that we append the database name to the cache keys.  This is 
    # just in case we have a cache that is shared amongst several databases.
    # The extra key should keep the cached items in separate data spaces.  
    # It does no harm if your caches are well-separated to start with.)
    if ($dat) {
	# this record has already been fetched
	@dat = @$dat;
    }
    else {
	# look up the record
	#@dat = $this->dbselect($dbtable,$column,$cond,$sort,$limit);
	@dat = $this->SUPER::select($dbtable,$column,$cond,$sort,$limit);
	# cache the result
	if ($this->is_cacheable()) {
	    $share{Cache}->save(\@dat,@cache_key);
	}
    }
    return wantarray ? @dat : \@dat;
}

sub count {
    my $this = shift;
    my $table = shift;
    my $dbtable;
    # map DBmap table names to low-level table names
    if (ref $table eq "ARRAY") {
	# array of tables was passed
	my @tables;
	foreach my $t (@$table) {
	    push @tables, $this->{map}->get_table_name($t);
	}
	# replace $table with unaliased version
	$dbtable = \@tables;
    }
    else {
	# single table was passed as a scalar - unalias it
	$dbtable = $this->{map}->get_table_name($table);
    }

    # check the cache first - add a "count" to the cache keys to distinguish
    # this result from a regular select
    my @cache_key = ($dbtable,"count",@_,$this->{id});
    my $dat = $share{Cache}->get(@cache_key);
    if ($dat) {
	return $dat;
    }
    else {
	# look up the record
	#$dat = $this->dbcount($dbtable,@_);
	$dat = $this->SUPER::count($dbtable,@_);
	# cache the result
	if (! $this->is_cacheable()) {
	    $share{Cache}->save($dat,@cache_key);
	}
	return $dat;
    }
}

sub title {
    my ($this,$table,$record,$rdata) = @_;
    return ucfirst($table)." ".$record;
}

=pod

=head1 Removing Records

Records can be removed to the trash bin (from which they can be 
recovered), or can be deleted irrecoverably.

=head2  Trash

The trash bin is simply a database table called "trash", which stores
sufficient information to reconstruct lost records if they are needed.
Each trash record corresponds to the deletion of one or more records.
Reconstruction information is written to the trash record, and then
the original records are deleted.  The C<data> field of the trash record
is a text value consisting of one line for each deleted record.  The line
is a perl snippet with the following format:

C<"table",{column1=E<gt>"value1",column2=E<gt>"value2",...}>

ie. the table the data came from, and a text representation of the
datahash representing the record.

Because a trash record can store multiple deleted records together,
the records can be removed and restored as a bunch, in the style of
transactions.

Deleting records from the trash table is equivalent to "emptying the trash".
(Yes, you can move trash records to the trash, but that would be pointless.)

=head3 C<trash_key()> - trash a single record

Usage: C<$db-E<gt>trash_key($table,$record_id)>

=head3 C<trash_r()> - trash a record and its descendants.  

Usage: C<$db-E<gt>trash_r($table,$record_id,$skip_check)>

The latter call finds all related records, and removes them as part of the
same trash "transaction".  If restored, all of the records will be restored
as a group.  The C<$skip_check> flag bypasses regular record ownership 
checks, if true.

=head3 C<undelete()> - restore trashed records

Usage: C<$db-E<gt>undelete($table,$record_id)>

This reverses one of the previous trash calls.  Because the record ID
is included in the reconstruction data, and we normally use serial number
primary keys, which are never recycled, the restored data should just drop
into its original positions without a problem.  Your mileage may vary if 
using a different type of primary key, however.

=head2 Deleting Records

Regular deletions are permanent and irreversible.

=head3 C<delete_key()> - delete a single record

Usage: C<$db-E<gt>delete_key($key)>

=head3 C<delete_r()> - delete a record and its descendants

Usage: C<$db-E<gt>delete_r($table,$key)>

Note that some records (eg. a website section) can have an awful lot of
descendants, so this call can permanently remove large sections of the
database.

=head3 C<delete()> - delete all matching records

Usage: C<$db-E<gt>delete($table,$match)>

This call deletes all records that match the match hash.

=head3 C<bulk_delete()> - perform numerous deletions at once

Usage: C<$db-E<gt>bulk_delete($table,$match,$match,$match,...)>

This call accepts a list of match hash references, and performs the
corresponding delete operation for each of them. This is faster 
than deleting them individually.

=cut

#----------------------------------------------------------------------
# trash_key : move a single record to the trash bin

sub trash_key {
  my ($this,$table,$key) = @_;
  my $tab = $this->{map}->get_table_name($table);
  my $pkey = $this->get_key($tab);

  # build a trash record to preserve the data (temporarily)
  my %data = $this->fetch($table,$key);
  my $trashdata = "\"$table\",{";
  foreach my $key (keys %data) { 
      if (defined $data{$key}) {
	  # escape line breaks
	  $data{$key} =~ s/\r?\n/\\n/g;
	  # escape perl-sensitive characters
	  $data{$key} =~ s/([\"\$\@\%])/\\$1/g;
	  $trashdata .= "$key=>\"$data{$key}\","; 
      }
  }
  $trashdata .= "}\n";
  my $title = $this->title($table,$key);
  $share{Cache}->clear("trash");
  #my $trash_id = $this->dbinsert("trash",{member_id=>$this->my_uid,
  my $trash_id = $this->SUPER::insert("trash",{uid=>$this->my_uid||0,
					       description=>"$title ($table $key )",
					       data=>$trashdata});

  # delete the original record
  return $this->delete($tab,{$pkey=>$key});
}

#----------------------------------------------------------------------
# trash : move a group of records to the trash bin
# specify data as table1, id1, table2, id2, table3, id3, ...
# With a single table and ID, this is synonymous with trash_key().

sub trash {
  my $this = shift;

  # concatenate trash items together into a recovery blob
  my ($trashdata,$title,$ndel);
  $ndel = 0;
  for (my $i = 0; $i < (scalar @_); $i += 2) {
      my $table = $_[$i];
      my $key = $_[$i+1];
      next if (! $table || ! $key);
      # build a trash record to preserve the data (temporarily)
      my %data = $this->fetch($table,$key);
      $trashdata .= "\"$table\",{";
      foreach my $key (keys %data) { 
	  if (defined $data{$key}) {
	      # escape line breaks
	      $data{$key} =~ s/\r?\n/\\n/g;
	      # escape perl-sensitive characters
	      $data{$key} =~ s/([\"\$\@\%])/\\$1/g;
	      $trashdata .= "$key=>\"$data{$key}\","; 
	  }
      }
      $trashdata .= "}\n";
      if (! $title) { $title = $this->title($table,$key)."... ($table $key... "; }
      $ndel++;
  }
  $title .= "$ndel records total)";
  # add the trash record
  $share{Cache}->clear("trash");
  #my $trash_id = $this->dbinsert("trash",{member_id=>$this->my_uid,
  my $trash_id = $this->SUPER::insert("trash",{uid=>$this->my_uid||0,
					       description=>$title,
					       data=>$trashdata});

  # delete the original records
  my %del;
  for (my $i = 0; $i < (scalar @_); $i += 2) {
      my $table = $_[$i];
      my $key = $_[$i+1];
      next if (! $table || ! $key);
      my $tab = $this->{map}->get_table_name($table);
      my $pkey = $this->get_key($tab);
      if (exists $del{$tab}) {
	  push @{$del{$tab}}, {$pkey=>$key};
      }
      else {
	  $del{$tab} = [ {$pkey=>$key} ];
      }
  }
  foreach my $tab (keys %del) {
      $this->bulk_delete($tab,@{$del{$tab}});
  }
}

#----------------------------------------------------------------------
# trash_r : recursively move related records to the trash bin
#
# permission is granted if the user owns the initial row only, or if
# the code explicitly overrides the ownership check

sub trash_r {
    my ($this,$table,$key,$skip_check) = @_;
    my $stat = $this->run_handler("trash_r",$table,$key,$skip_check);
    return $stat if (defined $stat);
    if ($skip_check || $this->user_owns($table,$key)) {
	my $title = $this->title($table,$key) || '?';
	my $del = $this->find_descendants($table,$key);
	my ($trashdata,$ndel);
	foreach my $deltab (keys %$del) {
	    foreach my $delrow (@{$del->{$deltab}}) {

		# build trash record to preserve the data (temporarily)
		my %data = $this->fetch($deltab,$delrow);
		$trashdata .= "\"$deltab\",{";
		foreach my $key (keys %data) { 
		    if (defined $data{$key}) {
			# escape line breaks
			$data{$key} =~ s/\r?\n/\\n/g;
			# escape perl-sensitive characters
			$data{$key} =~ s/([\"\$\@\%])/\\$1/g;
			$trashdata .= "$key=>\"$data{$key}\","; 
		    }
		}
		$trashdata .= "}\n";
		### use bulk_delete ??
		my $stat = $this->delete_key($deltab,$delrow);
		$ndel++;
		### check status???
	    }
	}
	$share{Cache}->clear("trash");
	#my $trash_id = $this->dbinsert("trash",{member_id=>$this->my_uid,
	my $trash_id = $this->SUPER::insert("trash",{uid=>$this->my_uid||0,
						     description=>"$title ($table $key - $ndel records total)",
						     data=>$trashdata});
    }
}

#----------------------------------------------------------------------
# undelete : restore records from the trash

sub undelete {
    my ($this,$table,$key) = @_;
    my ($trash,$error);
    if ($table eq "trash") {
	$trash = $this->fetch("trash",$key);
    }
    else {
	my @trash = $this->fetch_match("trash",{description=>"%($table $key %"});
	if (@trash > 0) {
	    $trash = $trash[-1];
	}
    }
    if (ref $trash eq "HASH") {
	if ($this->is_admin || $this->my_uid == $trash->{uid}) {
	    my @rec = split(/\r?\n/,$trash->{data});
	    foreach my $rec (@rec) {
		if ($rec && $rec =~ /^\"(\w+)\",{.+}$/) {
		    if ($this->get_key($1)) {
			# table seems to exist
			my $restore_cmd = "\$this->insert($rec)";
			if (! eval $restore_cmd) {
			    $error = "failed to restore from $1: $@; aborting undelete";
			    return $this->error($error);
			}
			# restore seemed to work - remove the trash record
			$this->delete("trash",{trash_id=>$trash->{trash_id}});
			# we're not sure which table the trash restored to,
			# so we're gonna play safe and clear our entire cache
			$share{Cache}->clear_all();
		    }
		    else {
			$error = "cannot restore from $1: no such table";
			return $this->error($error);
		    }
		}
		else {
		    $error = "cannot restore from $1: malformed trash data";
		    return $this->error($error);
		}
	    }
	}
	else {
	    $error = "permission denied";
	    return $this->error("permission denied");
	}
    }
    else {
	$error = "could not find $table $key in trash";
	return $this->warn($error);
    }
    return undef;
}

#----------------------------------------------------------------------
# delete_key : delete a row by its primary key
#
# ROW IS PERMANENTLY DELETED - NO UNDELETE
# Use trash tools (above) if you want undelete.

sub delete_key {
  my ($this,$table,$key) = @_;
  my $stat = $this->run_handler("delete_key",$table,$key);
  return $stat if (defined $stat);
  my $tab = $this->{map}->get_table_name($table);
  my $pkey = $this->get_key($tab);
  return $this->delete($tab,{$pkey=>$key});
}

#----------------------------------------------------------------------
# delete_r : recursive delete of a row and its descendants
#
# permission is granted if the user owns the initial row only, or if
# the code explicitly overrides the ownership check
#
# ROWS ARE PERMANENTLY DELETED - NO UNDELETE
# Use trash tools (above) if you want undelete.

sub delete_r {
    my ($this,$table,$key,$skip_check) = @_;
    if ($skip_check || $this->user_owns($table,$key)) {
	my $del = $this->find_descendants($table,$key);
	foreach my $deltab (keys %$del) {
	    foreach my $delrow (@{$del->{$deltab}}) {
		my $stat = $this->delete_key($deltab,$delrow);
		### check status???
	    }
	}
    }
}

#----------------------------------------------------------------------
# delete : general-purpose delete
#
# usage: $this->delete($table,$condition);
#        $this->bulk_delete($table,$condition,$condition,...);
#
# $condition is a match hash or explicit where clause;
#
# ROWS ARE PERMANENTLY DELETED - NO UNDELETE
# Use trash tools (above) if you want undelete.

sub delete {
    my $this = shift;
    my $table = shift;
    my $dbtable = $this->{map}->get_table_name($table);
    # clear the cache entries for this table, since they might become
    # invalid with this deletion
    $share{Cache}->clear($dbtable);
    # proceed with delete
    #return $this->dbdelete($dbtable,@_);
    return $this->SUPER::delete($dbtable,@_);
}

sub bulk_delete {
    my $this = shift;
    my $table = shift;
    my $dbtable = $this->{map}->get_table_name($table);
    my @stat;
    while (my $data = shift) {
	push @stat, $this->SUPER::delete($dbtable,$data);
    }
    # clear cache entries for this table, since they might become
    # invalid with this update. Clear after deleting, in case deletions
    # take a long time.
    $share{Cache}->clear($dbtable);
    if (wantarray) {
	return @stat;
    }
    my $ok = 0;
    foreach my $stat (@stat) { 
	if ($stat) { $ok++; }
    }
    return $ok;
}

#----------------------------------------------------------------------
# copy : copy a record
# if the recursive flag is true, will recusively copy all descendant records

#### DANGER: copying records that have multiple references to a parent table
#### will not be able to accurately copy the foreign key references.

# sub copy {
#     my ($this,$table,$rec,$recursive) = @_;
#     %cplog = ();            # initialize the infinite loop trap
#     my $id = &copy_1(@_);   # copy the head record
#     if ($recursive) {
# 	&copy_r(@_);   # copy descendant records
#     }
# }
# 
# # copy single record
# 
# sub copy_1 {
#     my ($this,$table,$rec) = @_;
#     my $data;
#     if (ref $rec) {
# 	$data = $rec; 
#     }
#     else {
# 	$data = $this->fetch($table,$rec);
#     }
#     my $key = $this->get_key($table);
#     my $keytype = $this->{map}->get($table,$key,"datatype");
#     if ($keytype = "key#") {
# 	delete $data->{$key};
#     }
#     my $id = $db->insert($table,$data);
#     $cplog{"$table:$rec"} = 1;
#     return $id;
# }
# 
# # recursive copy routine
# 
# sub copy_r {
#     my ($this,$table,$rec,$pcol,$newpid) = @_;
#     return if ($cplog("$table:$rec"));  # infinite loop trap
#     &copy_1(@_);
#     if ($recursive) {
# 	my @childtables = $this->{map}->get_children($table);
# 	foreach my $ctab (@childtable) {
# 	    my @child = $this->fetch_child($ctab,$table,$rec);
# 	    my $ckey = $this->get_key($ctab);
# 	    foreach my $crec (@child) {
# 		$this->copy_r($ctab,$crec->{$ckey},1);
# 	    }
# 	}
#     }
# }

=pod

=head1 Modifying Data

=head2 C<insert()> - add a new record 

Usage: C<$db-E<gt>insert(TABLE,DATA);>

Inserts a single record into TABLE, where DATA is a datahash reference.  
If you are using normal serial-number primary key tables, the datahash 
will normally contains no primary key.  The insert function returns the
primary key of the new record on success.

If DATA contains the primary key, ExSite performs a REPLACE instead of an
INSERT in SQL databases.

=head3 C<bulk_insert()> - insert numerous records at once

Usage: C<$db-E<gt>bulk_insert(TABLE,DATA,DATA,DATA,...)

This call accepts a list of data hash references, and performs the
corresponding insert operation for each of them. This is faster 
than inserting them individually.

=head2 C<update()> - modify existing records

Usage: C<$db-E<gt>update(TABLE,DATA,CONDITION);>

Updates TABLE, modifying the values to those in DATA (a datahash of 
columns to change, and the values to change them to).

If CONDITION is specified as a match hash, all records matching the
data will be modified.  If no CONDITION is given, C<update()> will
modify the record whose primary key matches the primary key value
specified in DATA.  This allows you to fetch a datahash using
C<fetch()>, set some new values, and then pass the whole datahash back
to C<update()> to save it without explicitly defining a condition.

=head3 C<bulk_update()> - perform numerous updates at once

Usage: C<$db-E<gt>bulk_update(TABLE,COND,COND,COND,...)

This call accepts a list of conditions, and performs the
corresponding update operation for each of them. This is faster 
than updating them individually. The condition can either a data
hashref, or an arrayref containing both a datahash and a condition.

=cut

sub insert {
    my $this = shift;
    my $table = shift;
    my $dbtable = $this->{map}->get_table_name($table);
    # clear cache entries for this table, since they might become
    # invalid with this insert
    $share{Cache}->clear($dbtable);
    #return $this->dbinsert($dbtable,@_);
    return $this->SUPER::insert($dbtable,@_);
}

sub update {
    my $this = shift;
    my $table = shift;
    my $dbtable = $this->{map}->get_table_name($table);
    # clear cache entries for this table, since they might become
    # invalid with this update
    $share{Cache}->clear($dbtable);
    #return $this->dbupdate($dbtable,@_);
    return $this->SUPER::update($dbtable,@_);
}

sub bulk_insert {
    my $this = shift;
    my $table = shift;
    my $dbtable = $this->{map}->get_table_name($table);
    my @stat;
    while (my $data = shift) {
	if (ref $data eq "HASH") {
	    push @stat, $this->SUPER::insert($dbtable,$data);
	}
	else {
	    $this->error("Bad data: bulk insert to $table");
	}
    }
    # clear cache entries for this table, since they might become
    # invalid with this insert. Clear after inserting, in case inserts
    # take a long time.
    $share{Cache}->clear($dbtable);
    if (wantarray) {
	return @stat;
    }
    my $ok = 0;
    foreach my $stat (@stat) { 
	if ($stat) { $ok++; }
    }
    return $ok;
}

sub bulk_update {
    my $this = shift;
    my $table = shift;
    my $dbtable = $this->{map}->get_table_name($table);
    my @stat;
    while (my $data = shift) {
	if (ref $data eq "HASH") {
	    push @stat, $this->SUPER::update($dbtable,$data);
	}
	elsif (ref $data eq "ARRAY") {
	    push @stat, $this->SUPER::update($dbtable,@$data);
	}
	else {
	    $this->error("Bad data: bulk update to $table");
	}
    }
    # clear cache entries for this table, since they might become
    # invalid with this update. Clear after updating, in case updates
    # take a long time.
    $share{Cache}->clear($dbtable);
    if (wantarray) {
	return @stat;
    }
    my $ok = 0;
    foreach my $stat (@stat) { 
	if ($stat) { $ok++; }
    }
    return $ok;
}

#======================================================================

=pod

=head1 Record Ownership

In a simple sense, a database record is "owned" by its parent record(s).
A single record can therefore own its own descendant records directly, 
and their descendants indirectly (and so on...).  When you do a recursive
record search (such as in C<trash_r()> and C<delete_r()>, above), you are
recursively finding all the data that is owned by the starting record.
This search is performed by C<find_descendants()>, below.

If the starting record is a user record (ie. a record from the
C<member> table), then the descendant records are literally owned by
that user.  That user gains special priveleges over that data that
other users do not have.  (For instance, they may be allowed to edit 
their own data, but only view the data of others.)

If group management is supported, then you can also proceed from an
originating group record to see what the group owns.  Group managers
have permission to alter the data in their group, which could
encompass the data of multiple users.  Groups can be defined in different
ways, but by default a group corresponds to a website and its users.

=head2 user_owns() - determine whether the current user "owns" the given row

Usage: C<$db-E<gt>user_owns( TABLE, RECORD );>

TABLE is the table being operated on.  RECORD is a record id, or a
datahash reference

Returns true if:

=over 4

=item user level 1

the record is related to the current user's member record

=item user level 2

the record is related to the current user's group record

=item user level 3 or 4

these users own everything

=back

This presumes a 4-level user model, which is common, but not universal.

=head2 group_owns() - determine whether the current group "owns" the given row

Usage: C<$db-E<gt>group_owns( TABLE, RECORD );>

TABLE is the table being operated on.  RECORD is a record id, or a
datahash reference

Returns true if:

=over 4

=item user level 1 or 2

the record is related to the current user's group record (section, by default)

=item user level 3 or 4

these users own everything

=back

=head2 find_owner() - determine who owns the given row

Usage: C<$db-E<gt>find_owner( TABLE, RECORD, TYPE );>

TABLE is the table being operated on.  RECORD is a record id, or a
datahash reference.  TYPE is the owner type, either "user" or "group".
The UID or GID of the record is returned.

=head2 fetch_ancestor() - find ancestor row to a specific row

Usage: C<$db-E<gt>fetch_ancestor( TABLE, DESCENDANT_TABLE, DESCENDANT_RECORD );>

A is an ancestral row of B, if B is among A's descendant records.  In
this routine you pass the table that A is from, along with the table
and record of B.  The routine returns a record from A that is an
ancestor of the record from B.  In principle, there could be multiple
tables from A that are ancestral to B, but this method only returns
the first one found.  It returns a datahash (or datahash reference),
in the same manner as C<fetch()>.

=head2 find_descendants() - find all records that descend from a particular record

Usage: C<$db-E<gt>find_descendants( TABLE, RECORD );>

Each row has rows that reference it, and rows that references those,
and so on.  The find_descendants method returns pointers to all
rows that descend from a single ancestral row.  It is useful for
locating all data pertaining to a specific data item.

The return value is a reference to hash, formatted as follows:
C<$ref-E<gt>{table1} =E<gt> [ key1, key2, ... ], $ref-E<gt>{table2} =E<gt> [ ... ], ...>

=cut

#======================================================================

sub user_owns {
  my ($this,$table,$record) = @_;
  #print "checking ownership of $table $record\n";
  my $stat = $this->run_handler("user_owns",$table,$record);
  return $stat if (defined $stat);
  my $level = $this->authorize();
  my ($uid, $gid, $row_id);
  if ($level >= 3) {
    # current user is an administrator;
    # they are permitted to operate on anything
    return 1;
  }
  elsif ($level == 2) {
    # group leaders own everything in their group
    return $this->group_owns($table,$record);
  }
  elsif ($this->my_uid() == $this->find_owner($table,$record,"user")) {
    # regular user owns this row
    return 1;
    ### FIXME: my_uid = 0 matches any unowned row
  }
  else {
    # no ownership match
    return 0;
  }
}

#----------------------------------------------------------------------
# group_owns : determine whether the current user's group "owns" the
#              given row.
#
# Arguments:
# table - the table being operated on
# row - a record id, or a datahash reference
#
# Returns true if:
#   - user level 1 or 2: the record is related to the current user's
#                        group record
#   - user level 3 or 4: these users own everything

sub group_owns {
  my ($this,$table,$record) = @_;
  #print "checking ownership of $table $record\n";
  my $stat = $this->run_handler("group_owns",$table,$record);
  return $stat if (defined $stat);
  my $level = $this->authorize();
  if ($level >= 3) {
    # current user is an administrator;
    # they are permitted to operate on anything
    return 1;
  }
  my $gid = $this->my_gid();
  if ($gid && ($gid == $this->find_owner($table,$record,"group"))) {
    return 1;
  }
  else {
    return 0;
  }
}

#----------------------------------------------------------------------
# find_owner : determine who owns the given row
#
# Arguments:
# table - the table being operated on
# row - a record id, or a datahash reference
# owner_type - "user" or "group" - returns the uid or the gid that
#              owns the row, respectively.

sub find_owner {
  my ($this,$table,$record,$owner_type) = @_;
  if (!$owner_type) { $owner_type = "user"; }
  my $stat = $this->run_handler("find_owner",$table,$record,$owner_type);
  return $stat if (defined $stat);
  my $level = $this->authorize();
  my $row_id;
#  my ($uid, $gid, $row_id);
#  if ($owner_type eq "group") {
#      $gid = $this->my_gid();
#  }
#  $uid = $this->my_uid();

#  my $tablemap = $this->{map}->get_table($table);

  my @parent = ($table);
  my @pid;
  $row_id = ref $record ? $record->{$this->get_key($table)} : $record;
  if (exists $this->{ownership}->{"$table:$row_id:$owner_type"}) {
    # already checked this row before
    return $this->{ownership}->{"$table:$row_id:$owner_type"};
  }
  @pid = ($row_id);
  my %beenthere;
  if (!exists $this->{ownership}) { $this->{ownership} = {}; }

  # perform a recursive search through all related tables
  while (@parent > 0) {
    my $parent = shift @parent;
    my $pid = shift @pid;

    # ignore null references, unless it's from the passed record data
    # which might be a pending insert with no primary key
    if (!$pid && !($parent eq $table && $pid==$row_id)) { next; } 

    if ($owner_type eq "group") {
      if ($parent eq $config{auth}->{group_table}) {
	$this->{ownership}->{"$table:$row_id:group"} = $pid;
	return $pid;
      }
    }
    else {
      if ($parent eq $config{auth}->{user_table}) {
	$this->{ownership}->{"$parent:$row_id:user"} = $pid;
	return $pid;
      }
    }

    # add parents of this record to the search list
    my @new_parents = $this->{map}->get_parents($parent);
    foreach my $new_parent (@new_parents) {
      my $col = $this->{map}->get_reference_column($parent,$new_parent);
      my %data;
      if ($parent eq $table && $pid == $row_id) {
	  # first row;  was data already passed to us?
	  %data = (ref $record ? %$record : $this->fetch($parent,$pid));
      }
      else {
	  %data = $this->fetch($parent,$pid);
      }
      # watch out for infinite recursion!
      if ($beenthere{"$new_parent:$data{$col}"}) { next; }
      $beenthere{"$new_parent:$data{$col}"} = 1;
      push @parent,$new_parent;
      push @pid,$data{$col};
    }
  }
  # no ownership match found
  $this->{ownership}->{"$table:$row_id:$owner_type"} = 0;
  return 0;
}

#======================================================================
# ANCESTOR/DESCENDANT SEARCHES
#
# Each row has rows that reference it, and rows that references those,
# and so on.  find_ancestor() searches upward through these references
# to find a single ancestral record.  find_descendants() searches
# downwards through these references to find ALL descendant records.

#----------------------------------------------------------------------
# fetch_ancestor :
#
# A is an ancestral row of B, if B is among A's descendant records.
#
# Arguments:
# table - fetch a record from this table
# desc_table, desc_record - the table/id of the descendant record 
#
# Returns ancestral row datahash (or a ref to it in scalar context).
#
# NB: no guarantee that the returned ancestor is the ONLY ancestor; 
# merely that it is the first ancestor located.

sub fetch_ancestor {
    my ($this,$table,$desc_table,$desc_record) = @_;
    my $stat = $this->run_handler("find_ancestor",
				  $table,$desc_table,$desc_record);
    return $stat if (defined $stat);

    # initialize
    my @parent = ($desc_table);
    my $row_id = ref $desc_record ? 
	$desc_record->{$this->get_key($desc_table)} : $desc_record;
    my @pid = ($row_id);
    my %beenthere;

    # perform a recursive search through all related tables
    while (@parent > 0) {
	my $parent = shift @parent;
	my $pid = shift @pid;
	print "searching for ownership in $parent $pid\n";
	if (!$pid) { next; } # null reference

	# find parents of this record
	my @new_parents = $this->{map}->get_parents($parent);
	foreach my $new_parent (@new_parents) {
	    my $col = $this->{map}->get_reference_column($parent,$new_parent);
	    my %data = $this->fetch($parent,$pid);
	    #print "$new_parent:$data{$col}\n";
	    next if (! $data{$col});  # no parent record
	    if ($parent eq $table) {
		# found an ancestor!
		return wantarray ? %data : \%data;
	    }
	    #-- watch out for infinite recursion!
	    if ($beenthere{"$new_parent:$data{$col}"}) { next; }
	    $beenthere{"$new_parent:$data{$col}"} = 1;
	    #--
	    push @parent,$new_parent;
	    push @pid,$data{$col};
	}
    }
    return undef;
}

#-------------------------------------------------------------------------
# find_descendants : find all descendant rows
#
# The find_descendants method returns pointers to all
# rows that descend from a single ancestral row.  It is useful for
# locating all data pertaining to a specific data item.
#
# The return value is a reference to hash, formatted as follows:
# $ref->{table1} => [ key1, key2, ... ]
#     ->{table2} => [ ... ]
#     ...
#
# BUG: should have a flag to select exclusive/non-exclusive relationships.
# No ownership check on descendants - shouldn't matter in simple case.

sub find_descendants {
    my ($this,$table,$record) = @_;
    my $row_id;
    if (ref $record) {
	$row_id = ($record->{$this->get_key($table)});
    }
    else {
	$row_id = ($record);
    }
    my (%relative,%done);
    $relative{$table} = [ $row_id ];
    my @table_list = ($table);
    my @id_list = ($row_id);
    while (@table_list > 0) {
	my $tab = shift @table_list;
	my $key = shift @id_list;
	foreach my $child ($this->{map}->get_children($tab)) {
	    my $rlist = $this->fetch_child($child,$tab,$key);
	    my $childkey = $this->get_key($child);
	    foreach my $rdata (@$rlist) {
		my $dbtable = $this->{map}->get_table_name($child);
		# check if this row already found
		next if ($done{"$dbtable:$rdata->{$childkey}"});
		# add this row to the list
		if (exists $relative{$child}) {
		    push @{$relative{$child}},$rdata->{$childkey};
		}
		else {
		    $relative{$child} = [ $rdata->{$childkey} ];
		}
		# add all children to the search list
		push @table_list,$child;
		push @id_list,$rdata->{$childkey};
		# flag this row as found, to avoid infinite loops
		$done{"$dbtable:$rdata->{$childkey}"} = 1;
	    }
	}
    }
    return \%relative;
}

#======================================================================

=pod

=head1 Query Library

If you have a lot of specialized queries, you can index and store them
in a query library for reuse and caching of results.  Each query is
registered with a unique name, and invoked using that name.  This has
the following benefits:

=over 4

=item a given SQL query is only coded (and debugged) in one place

=item simpler code/syntax for performing complex data fetches

=item effective caching of results on customized queries

=back

=head2 set_query() - register a special re-useable query

Usage: C<$db-E<gt>set_query( "NAME", %opt );>

NAME is a string that is used to reference the query.  C<%opt> can
have the following parameters:

=over 4

=item sql

This is the actual SQL statement that will be executed, with optional
substitution markers '?'.  If you want to override the SQL syntax in a 
particular installation (for instance if using a non-MySQL database
and need to alter syntax appropriately), specify the alternate sql in
exsite.conf using the setting 

    querylib.NAME = your sql statement here...

=item nparam

This is the number of query parameters, used to validate actual queries (but
is ignored if not defined).  It must match the number of "?" placeholders
in the SQL statement.

=item mode

"r" (for readonly data fetches) or "w" (for operations that write to or 
otherwise modify the database).  This is used for cache management.

=item keys

This is a table name or arrayref of table names affected by this
query, and is used for cache management.  If undef, the query results
will not be cached.  If defined but blank, the query results are
considered static, and will not be cleared from the cache when the
database is modified.

=back

=head2 get_query() - request data from a special re-useable query

Usage: C<$db-E<gt>get_query( NAME, SUBSTITUTIONS, ... );>

NAME refers to a query that was previously registered using
C<set_query()>, above.  SUBSTITUTIONS is a list of parameters to 
substitute into the query, and should match the parameter placeholders
in the query SQL statement.

=cut

#------------------------------------------------------------------------

sub set_query {
    my ($this, $name, %opt) = @_;
    # $name, $query, $mode, $nparam, $keys) = @_;

    # setup the query library, if this is the first visit here
    if (! defined $share{querylib}) {
	$share{querylib} = {};
    }

    # ignore attempts to redefine a given query
    return if (exists $share{querylib}{$name});
    return if (! $name || ! $opt{sql});
    $opt{mode} or $opt{mode} = "r";  # read is the default

    # save the query info
    $share{querylib}{$name} = \%opt;

    # allow local site to override query syntax
    # (can be useful for irregular SQL flavours)
    if ($config{querylib}{$name}) {
	$share{querylib}{$name}{sql} = $config{querylib}{$name};
    }

    return;
}

sub get_query {
    my ($this, $name, @substitutions) = @_;
    return undef if (! defined $share{querylib});
    my $data;
    my $q = $share{querylib}{$name};
    my $readonly = ($q->{mode} =~ /^r/i);

    if (defined $q->{nparam} &&	$q->{nparam} != scalar @substitutions) {
	$this->error("get_query: invalid parameters to query '$name'");
	return undef;
    }

    my $is_cacheable = (defined $q->{keys}) && $readonly;
    my @cache_key;
    if ($is_cacheable) {
	# check the cache for any previous results of this query
	@cache_key = ($q->{keys},$name,@substitutions,$this->{id});
	$data = $share{Cache}->get(@cache_key);
	if ($data) {
	    return wantarray ? @$data : $data;
	}
    }

    # execute the query
    $data = $this->custom_query($q->{sql},@substitutions);

    if ($is_cacheable && $this->is_cacheable()) {
	# cache the results
	$share{Cache}->save($data,@cache_key);
    }
    elsif (! $readonly) {
	# this query changes the database;  clear the affected cache keys
	if (ref $q->{keys}) {
	    $share{Cache}->clear(@{$q->{keys}});
	}
	elsif ($q->{keys}) {
	    $share{Cache}->clear($q->{keys});
	}
    }

    return wantarray ? @$data : $data;
}

#======================================================================

=pod

=head1 Sorting

The sort method orders lists of datahashes.

Usage: C<@sorted = db-E<gt>sort_rows($table,$list,@columns);>

where C<$list> is a list of datahashes, and C<@columns> is a list of columns
to sort on.  Determination of whether to use alphabetic or numeric
comparisons for a given column is done automatically, using the dbmap.

NOTE: you can also sort by passing the sortable column list to
the DB fetch/select methods.  Those sorts are performed by the DB
engine, if that is supported.  This sort method, on the other hand,
is performed by the webserver, and works for all drivers.  Which is
the more efficient approach depends on the relative loads experienced
by the two servers.

=cut

# FIXME: if @columns is not defined, automatically sort on the key
# display column(s)

#------------------------------------------------------------------------

sub sort_rows {
    my ($this,$table,$list,@columns) = @_;
    return () if (ref $list ne "ARRAY");
    my $desc = 0;
    for (my $c = 0; $c < @columns; $c++) {
	if (substr($columns[$c],0,1) eq "-") {
	    $desc = 1;
	    $columns[$c] = substr($columns[$c], 1, length($columns[$c]));
	}
    }
    # determine whether numeric comparisons are needed to sort each column
    my @numeric = ();
    foreach my $col (@columns) {
	my $datatype = $this->{map}->get($table,$col,"datatype");
	if ($datatype =~ /^(int|decimal|money|key\#)$/) { push @numeric,1; }
	else { push @numeric,0; }
    }
    return sort {
	my $stat;
	#foreach my $col (@columns) {
	for (my $i = 0; $i <= $#columns; $i++) {
	    if ($numeric[$i]) {
		$stat = $desc ? $b->{$columns[$i]} <=> $a->{$columns[$i]} : $a->{$columns[$i]} <=> $b->{$columns[$i]};
	    }
	    elsif ($config{report}{case_insensitive_sort}) {
		$stat = $desc ? uc($b->{$columns[$i]}) cmp uc($a->{$columns[$i]}) : uc($a->{$columns[$i]}) cmp uc($b->{$columns[$i]});
	    }
	    else {
		$stat = $desc ?  $b->{$columns[$i]} cmp $a->{$columns[$i]} : $a->{$columns[$i]} cmp $b->{$columns[$i]};
	    }
	    last if ($stat);
	}
	return $stat;
    } @$list;
}

#========================================================================
# Encryption Tools

sub decrypt_column {
    my ($this,$data,$table,$rec,$col) = @_;
    my $access_type = $config{crypt}{access};
    my $access = $this->authorize;
    # are we allowed to view encrypted data?
    if ($access_type eq "owner") {
	if ($access < $config{auth}{root_auth_level} - 1 &&
	    ! $this->user_owns($table,$rec)) {
	    $this->warn("unable to decrypt $table $rec $col");
	    return undef;
	}
    }
    else {
	if (! $this->is_admin) {
	    $this->warn("unable to decrypt $table $rec $col");
	    return undef;
	}
    }
    return $this->decrypt($data);
}

sub encrypt {
    my ($this,$data,%opt) = @_;
    my $c = $share{Crypt} || ($share{Crypt} = new ExSite::Crypt(%opt));
    return $c->encrypt($data);
}

sub decrypt {
    my ($this,$data,%opt) = @_;
    my $c = $share{Crypt} || ($share{Crypt} = new ExSite::Crypt(%opt));
    return $c->decrypt($data);
}

1;


