package ExSite::MySQL;

#------------------------------------------------------------------------
# ExSite::MySQL
#----------------------------------------------------------------------------
#
#   Copyright 2001-2012 Exware Solutions, Inc.  http://www.exware.com
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
# Generic SQL Driver for ExSite web development package.
# (Designed to work with MySQL, but should be easily adaptable to any
# SQL engine, since it goes through Perl DBI.)
#
# ExSite DB drivers have the following methods:
#
# new : make a new database handle
# dbget_tables : retrieve all table names
# dbget_columns : retrieve all column names from a table
# dbget_key : retrieve the primary key for a table
# dbselect : retrieve data from tables
# dbinsert : add new data to tables
# dbupdate : modify old data in tables
# dbdelete : remove data from tables
#
# See the ExSite::DB package for additional wrapper and convenience
# methods to fetch data from and modify the database.
#
# SECURITY NOTE: since the DB package is unaware of the underlying
# engine, it cannot perform proper security checks on the data being
# passed to the DB server.  Therefore all SQL parameters must be 
# validated within each driver, ie. in this file.
#------------------------------------------------------------------------

=pod

=head1 ExSite::MySQL - MySQL database driver for ExSite

The MySQL class serves as a glue layer between ExSite::DB and the Perl
DBI classes.  Perl DBI (DataBase-Indepedent interface) supports many
different database engines, so this class can serve as a model for 
connecting to a variety of back-ends.  As supplied with ExSite, it is 
configured to operate with MySQL.

As with all ExSite Database drivers, ExSite::MySQL implements the following
standard calls:

=over 4

=item new()

make a new database handle

=item dbget_tables()

retrieve all table names

=item dbget_columns()

retrieve all column names from a table

=item dbget_key()

retrieve the primary key for a table

=item dbselect()

retrieve data from tables

=item dbinsert()

add new data to tables

=item dbupdate()

modify old data in tables

=item dbdelete()

remove data from tables

=back

There are two useful concepts for understanding how ExSite represents
data records:

=over 4

=item Data hash 

this is a record stored in a hash, or associative
array.  The hash keys are the column names, and the values are the 
field values for that record.  Groups of records are represented 
as arrays of hash references, so that (for example) the value of the
"price" field in the 3rd record is C<$data[2]{price}>.

=item Match hash

this is similar to a data hash, except that
the hash values represent data to match to.  For instance,
$match{price} = "4.95" will select all records whose price field
contains the value 4.95.  If there are multiple keys/values in the
match hash, all will be matched (ie. they imply a logical AND).
The ExSite::MySQL driver accepts SQL wildcards ("%") in match values.
Escape the '%' symbol with a backslash if it should be taken literally.

=back

Many ExSite::MySQL methods will also accept an explicit SQL WHERE clause
in place of a match hash.  However, that mode of use is not portable,
and is recommended only when the simple AND logic of the standard match
hashes is insufficient.

=cut

use strict;
use Carp;
use DBI;
#use ExSite::Config;
use ExSite::Base;
our @ISA = qw(ExSite::Base);

#------------------------------------------------------------------------

=pod

=head2 C<new(%options)> : MySQL driver constructor

Usage: C<my $db = new ExSite::MySQL(%options);>

Connects to the MySQL server with the appropriate authentication 
information, and prepares to accept database queries.

C<%options> containts the database connection info.  Up to 6 parameters
are expected:

=over 4

=item driver

the DBI driver to use ("mysql" by default)

=item server

the server to connect to

=item port

the port number to connect to (optional)

=item name

the name of the database

=item user

the user name to connect under

=item pass

the password to authenticate with

=back

Example: C<my $db = new ExSite::MySQL(name=E<gt>"my_db",server=E<gt>"my.server.com",user=E<gt>"my_name",pass=E<gt>"my_pwd");>

=cut

#------------------------------------------------------------------------

sub new($%) {
  my($this, %db) = @_;
  my($obj,$class);

  $obj = {};
  $class = ref($this) || $this;
  bless $obj, $class;

  if ($db{debug}) {
    $obj->{debug} = $db{debug};
    delete $db{debug};
  }

  # table info cache
  $obj->{sql_table_info} = {};
  # statement handle cache
  $obj->{sth} = {};

  # initalize internal state
  $obj->reset();

  # NOTE: we do not connect until the database actually gets queried

  # store db access parameters for later lookup
  $obj->{db} = {%db};

  return $obj;
}

#------------------------------------------------------------------------

=pod

=head2 C<get_tables()> : return a list of tables in the database

Example: C<my @tables = $db-E<gt>get_tables();>

=cut

#------------------------------------------------------------------------

sub get_tables($) {
  my ($this) = shift;
  $this->reset;
  my $sth = $this->query("SHOW TABLES");
  if ($sth) {
      my @tables = ();
      # return value has ridiculous formatting; extract important info
      foreach my $tab (@{$sth->fetchall_arrayref}) {
	  push @tables, $tab->[0];
      }
      return @tables;
  }
  return ();
}

#------------------------------------------------------------------------

=pod

=head2 C<get_columns($table)> : return a list of columns in a table

Example: C<my @columns = $db-E<gt>get_columns("sales_data");>

=cut

#------------------------------------------------------------------------

sub get_columns($$) {
  my ($this, $table) = @_;
  if ($table !~ /^\w+$/) {
      # validate args
      $this->error("MySQL::get_columns: invalid table: $table");
      return;
  }
  $this->get_table_info($table);
  return if ($this->{query_error});
  my @columns = ();
  foreach my $col (@{$this->{sql_table_info}->{$table}}) {
    push @columns, $col->{Field};
  }
  return @columns;
}

#------------------------------------------------------------------------

=pod

=head2 C<get_key($table)> : return the primary key of a table

Example: C<my $key = $db-E<gt>get_key("sales_data");>

=cut

#------------------------------------------------------------------------

sub get_key($$) {
  my ($this, $table) = @_;
  if ($table !~ /^\w+$/) {
      # validate args
      $this->error("MySQL::dbget_key: invalid table: $table");
      return;
  }
  $this->get_table_info($table);
  return undef if ($this->{query_error});
  foreach my $col (@{$this->{sql_table_info}->{$table}}) {
    # assume key info is stored in column "Key"
    if ($col->{Key} =~ /^pri/i) {
      # this appears to be a primary key
      return $col->{Field};
    }
  }
  return undef;
}

#------------------------------------------------------------------------

=pod

=head2 C<select($rtable,$rcolumn,$cond,$sort,$limit)> : fetches records from the database

Returns an array of datahashes matching the input criteria:

=over 4

=item $rtable

a table name, or reference to an array of table names

=item $rcolumn

a column name, or reference to an array of column names, 
or references to a hash of tablename => array of column names, or NULL to
select all columns.

=item $cond

a WHERE clause string, or a reference to a match hash

=item $sort

a sort string, or a reference to a list of columns to sort 
the results by

=item $limit

the maximum number of records to fetch

=back

Most of these parameters are optional.

Examples:

C<@data = $db-E<gt>select("telephone");> - fetch all telephone records

C<@data = $db-E<gt>select("telephone",["number","type"]);> - fetch only
the number and type fields of all telephone records

C<@data = $db-E<gt>select("telephone",undef,{type=E<gt>"fax"});> - fetch all 
telephone records whose type field is set to "fax".

C<@data = $db-E<gt>select("telephone",undef,undef,"number"});> - fetch all 
telephone records, sorted by the number field.

C<@data = $db-E<gt>select("telephone",undef,undef,undef,100});> - fetch
the first 100 telephone records

=cut

#------------------------------------------------------------------------

sub select($$;$$$$) {
    my ($this,$rtable,$rcolumn,$cond,$sort,$limit) = @_;
    $this->reset;

    my ($tlist,$clist,$where,$order,$sql,$row,@result);

    $tlist = $this->sql_table($rtable);
    return undef if (! defined $tlist);

    $clist = $this->sql_column($rcolumn);
    return undef if (! defined $clist);

    $where = $this->sql_condition($cond);
    return undef if (! defined $where);

    if ($sort) {
	$order = $this->sql_sort($sort);
	return undef if (! defined $order);
    }
    if ($limit) {
	$limit = $this->sql_limit($limit);
	return undef if (! defined $limit);
    }

    # execute the query
    my $hstat = $this->run_handler("pre_select",@_);
    $sql = "SELECT $clist FROM $tlist $where $order $limit";
    my $sth = $this->query($sql);
    return $this->fetchrows(undef,1,$sth);
}

#-------------------------------------------------------------------------

=pod

=head2 C<count($rtable,$condition)> : returns number of matching records

C<$rtable> = table, or reference to array of tables

C<$cond> = explicit conditional, or a reference to a match hash, which
can optionally contain wildcards

Only C<$rtable> is required for the function to work.

=cut

#-------------------------------------------------------------------------

sub count($$;$) {
    my ($this,$rtable,$cond) = @_;
    $this->reset;

    my $tlist = $this->sql_table($rtable);
    return 0 if (! $tlist);
    my $where = $this->sql_condition($cond);

    # execute the query
    my $sql = "SELECT COUNT(*) FROM $tlist $where";
    my $sth = $this->query($sql);
    if ($sth) {
	my $row = $sth->fetchrow_arrayref;
	return $row->[0];
    }
    return 0;
}

#------------------------------------------------------------------------

=pod

=head2 C<insert($table,$data)> : inserts a new record into a table.

C<$data> is a reference to a datahash.  This is inserted as a new record
into C<$table>.

Returns the primary key of the new record.

=cut

#------------------------------------------------------------------------

sub insert($$$) {
    my ($this,$table,$data) = @_;
    if (ref $data eq "HASH") {
	# pre-handler?
	my $hstat = $this->run_handler("pre_insert",$table,$data);

	# validate column list
	my $clist = join(",", keys %$data);
	if ($clist !~ /^(\w+,)*\w+$/) {
	    $this->error("MySQL::insert: invalid column list: $clist");
	    return 0;
	}

	# lookup table data before composing our query
	my $pkey = $this->get_key($table);

	# get the list of values to insert
	my @values;
	$this->reset;
	for my $val (values %$data) {
	    if (ref $val) {                  # SQL literal - careful!
		push @values, $$val; 
	    }
	    elsif (! defined $val) {         # perl undef == SQL NULL
		push @values, "NULL"; 
	    }
	    else {                           # normal data
		push @values, "?";
		$this->param($val);
	    }
	}
	my $vlist = join(",", @values);

	# compose the query
	my $operation = $data->{$pkey} ? "REPLACE" : "INSERT";
	my $sql = "$operation INTO $table ($clist) VALUES ($vlist)";

	# execute the query
	my $sth = $this->query($sql);
	if ($sth) {
	    my $new_id = $this->dbh()->{mysql_insertid};
	    $this->{last_insert_id} = $new_id;
	    $hstat = $this->run_handler("post_insert",$table,$data);
	    return $new_id;
	}
	else {
	    return 0;
	}
    }
    else {
	$this->error("ExSite::MySQL::insert: bad data reference");
	return 0;
    }
}

#------------------------------------------------------------------------

=pod

=head2 C<update($table,$data,$cond)> : modifies records in a table.

C<$table> is the table that the update operation will be performed on.

C<$data> is a reference to a datahash, containing the fields and the values
they should be changed to.

C<$cond> is an optional match hash.  Only records matching this will
be updated.  

If C<$cond> is undefined, then the primary key of the record to be modified
is taken from C<$data>.  If the primary key is not defined in C<$cond>,
this will throw an exception.

Returns an error messge if there were problems.

Examples:

C<$db-E<gt>update("member",{password=E<gt>"",member_id=E<gt>100});> -
sets an empty password for member #100 (assuming that member_id is
the primary key of the member table).

C<$db-E<gt>update("member",{password=E<gt>""},{status=E<gt>"expired"});> -
clears the password field for all members whose status field is set to
"expired".

=cut

#------------------------------------------------------------------------

sub update($$$;$) {
    my ($this,$table,$data,$cond) = @_;
    # pre-handler?
    my $hstat = $this->run_handler("pre_update",$table,$data,$cond);

    # lookup table data before composing our query
    my $pkey = $this->get_key($table);

    $this->reset;
    my ($set,$where);
    # data
    if (ref $data eq "HASH") {
	my @set;
	my $value;
	while (my ($key,$val) = each %$data) {
	    if ($key !~ /^\w+$/) {
		return $this->error("MySQL::update: invalid column: $key");
	    }
	    if (ref $val) { 
		# SQL literal - careful!
		$value = $$val;
	    }
	    elsif (! defined $val) {
		# perl undef == SQL NULL
		$value = "NULL";
	    }
	    else { 
		# normal data
		$value = "?";
		$this->param($val);
	    }
	    push @set, "$key=$value";
	}
	$set = join(",",@set);
    }
    else {
	return $this->error("ExSite::MySQL::update: bad data reference");
    }

    # condition
    $where = $this->sql_condition($cond);
    if (! $where) {
	if (! defined $where) {
	    return $this->error("ExSite::MySQL::update: invalid where clause");
	}
	else {
	    # no condition!  Select rows matching the primary key.
	    if ($data->{$pkey}) {
		$where = "WHERE $pkey=?";
		$this->param($data->{$pkey});
	    }
	    else {
		return $this->error("ExSite::MySQL::update: trapped unconditional update");
	    }
	}
    }

    my $sql = "UPDATE $table SET $set $where";

    # update
    my $sth = $this->query($sql);
    my $stat = $this->{query_error};
    # post-handler?
    if ($sth) {
	$hstat = $this->run_handler("post_update",$table,$data,$cond);
    }
    return $stat;
}

#------------------------------------------------------------------------

=pod

=head2 C<delete($table,$cond)> : deletes records from a table.
Deletes records in C<$table> matching the match hash referenced by C<$cond>.
C<$cond> can optionally name an explicit SQL WHERE condition, but this 
is not portable to other drivers.

Examples:

C<$db-E<gt>delete("member",{status=E<gt>"expired"});> -
removes member records whose status field is set to "expired".

=cut

#------------------------------------------------------------------------

sub delete($$$) {
    my ($this,$table,$cond) = @_;
    # pre-handler?
    my $stat = $this->run_handler("pre_delete",$table,$cond);
    $this->reset;

    my $where;
    # condition
    if (ref $cond eq "HASH") {
	# condition is a match hash
	$where = $this->where_match($cond);
	if (! $where) {
	    return $this->error("MySQL::delete: invalid delete condition");
	}
    }
    elsif ($cond && $cond !~ /^\d+$/) {
	# condition is an explicit WHERE clause
	# DANGER: no sanity check!
	$where = "WHERE $cond";
    }
    else {
	return $this->error("ExSite::MySQL::delete: trapped unconditional delete");
    }

    my $sql = "DELETE FROM $table $where";

    # Insert
    my $sth = $this->query($sql);
    $stat = $this->{query_error};
    # post-handler?
    if ($sth) {
	$stat = $this->run_handler("post_delete",$table,$cond);
    }
    return $stat;
}

# alternative entry points to address the above functions to make it
# easy to get by the overloaded functions in ExSite::DB

sub dbget_columns { return &get_columns(@_); }
sub dbget_key { return &get_key(@_); }
sub dbselect { return &select(@_); }
sub dbcount { return &count(@_); }
sub dbinsert { return &insert(@_); }
sub dbupdate { return &update(@_); }
sub dbdelete { return &delete(@_); }

#------------------------------------------------------------------------

=pod

=head1 Internal and non-standard methods

The section describes ExSite::MySQL methods that do not conform to
the ExSite database driver API.  These methods are for internal use 
only, or provide non-portable extensions to the API.

=head2 C<query($sql_statement)> : generic query method

This method prepares and executes an arbitrary SQL query, and
returns the statement handle.  It does not fetch the results.

If the query contains '?' parameter placeholders, then the internal
C<parameters> attribute is used to provide data to fill these placeholders.
Some statement generation methods will automatically generate statements 
with placeholders and parameter lists.

Status and errors are stored in the object for later reporting.  

Examples: 

    $db->query("SELECT * FROM SALESDATA");
    $db->query("SELECT * FROM INVOICE WHERE DATE > ?");  # uses parameters

=head2 C<get_sth($sql_statement)> : get a statement handle

Returns a statement handle for the given SQL statement.  It tries to reuse
an existing handle, if the query has already been executed.  (This is not
likely if you are not parameterizing your statements, since that would 
mean you are re-executing the same statement.)

=head2 C<reset()> : clear internal state

The state of the previous query is retained in the object for
status handling purposes.  The reset function clears the state for a
new query.

=head2 C<param(@values)> : parameter handling

If one or more values is passed, they are added to the parameters list
for the current query.  No sanity check is performed to ensure that the
length of the parameter list equals the number of placeholders in the
statement.

If no values are passed, the current parameter list is return in list mode,
or the number of parameters in the list is returned in scalar mode.

=head2 C<max_select($number)> : return records in groups

This limits the number of records that will be returned in one call to
C<select()> or C<custom_query()> to C<$number>. After the initial group
of records is returned, additional groups may be fetched using C<fetchrows()>.
Note that query results are not cached if using this feature.

=head2 C<fetchrows($number,$select,$statement_handle)> : return another group of records

Returns the next group of records after the initial call to
C<select()> or C<custom_query()>, if C<max_select()> is in use.
If all records have already been fetched, it returns an empty array.

All parameters are optional; in most cases, just use C<$db->fetchrows()>
to fetch the next group of records.  Use C<$count> to fetch a group of
a different size.  Set C<$select> to a true value if the query is a simple
select statement and you want to use the select handlers.  Do not set
C<$statement_handle> if you are fetching the next group of records from
the current statement handle;  only set this parameter when starting a
new query.

=cut

#------------------------------------------------------------------------

sub query ($$) {
    my ($this, $sql) = @_;
    # clear the error status
    $this->{query_error} = undef;
    # log the query
    my $msg = $this->{parameters} ? 
	$sql." (".join(",",@{$this->{parameters}}).")" : $sql;
    if ($sql =~ /^(select|show)/i) {
	# read-only operation
	$this->info($msg);
    }
    else {
	# possible write operation
	$this->audit($msg);
    }
    $this->{last_query} = $sql;
    # prepare the statement
    my $sth = $this->get_sth($sql);
    if (! $sth) {
	# failure
	$this->error("ExSite::MySQL::query - failed to prepare \"$sql\"; $DBI::errstr; $!");
	return undef;
    }
    # execute the statement
    my $stat = $this->param() > 0 ?
	$sth->execute($this->param()) :
	$sth->execute(); 
    if (! $stat) {
	# failure
	$this->error("ExSite::MySQL::query - failed to execute \"$sql\"; $DBI::errstr; $!");
	return undef;
    }
    $this->{last_sth} = $sth;
    return $sth;
    # calling routine is responsible for getting the results, if any
}

sub get_sth($$) {
    my ($this,$sql) = @_;
    if (! exists $this->{sth}{$sql}) {
	# we have not run this statement before
	$this->{sth}{$sql} = $this->dbh()->prepare($sql);
    }
    return $this->{sth}{$sql};
}

sub reset {
    my $this = shift;
    # clear all internal state reflecting previous queries
    $this->{last_query} = undef;
    $this->{parameters} = undef;
    $this->{last_insert_id} = undef;
    $this->{query_error} = undef;
    return;
}

sub param {
    my ($this,@value) = @_;
    if (@value > 0) {
	# add a parameter to the parameter list
	push @{$this->{parameters}}, @value;
	return undef;
    }
    else {
	# report the current parameters
	if (ref $this->{parameters} eq "ARRAY") {
	    return wantarray ? 
		@{$this->{parameters}} :        # return the parameters, or
		scalar @{$this->{parameters}};  # return the number of parameters
	}
	else {
	    return wantarray ? () : 0;
	}
    }
}

sub max_select {
    my ($this,$max) = @_;
    $this->{max_select} = $max;
}

sub fetchrows {
    my ($this,$count,$select,$sth) = @_;
    $count or $count = $this->{max_select};
    $this->{is_cacheable} = (defined $sth);
    $sth or $sth = $this->{last_sth};
    my @result;
    if ($sth) {
	while (my $row = $sth->fetchrow_hashref) {
	    push @result, $row;
	    if ($count && scalar @result >= $count) {
		$this->{is_cacheable} = 0;
		last;
	    }
	}
	if (scalar @result < $count) {
	    # no more fetching on this statement handle
	    delete $this->{last_sth};
	}
	$this->run_handler("post_select",@_) if ($select);
    }
    return wantarray ? @result : \@result;
}

#------------------------------------------------------------------------

=pod

=head2 C<where_match($match_hash)> : constructs a WHERE clause

Returns a WHERE clause built from the passed match hash,
which is a set of column->value pairs.  Each pair is related using 
a SQL operator (one of '=', 'IS', or 'LIKE', depending on the type
of data in the value), and all are concatenated using '&&'.

If the value is a scalar reference, it is explicitly inserted into 
the clause, and if 'NULL' then the operator is also changed to IS.

If the value contains unescaped wildcards ('%'), then the operator
is changed to 'LIKE'.

All user data is parameterized, which means the where clause takes a
'?' parameter placeholder, and the actual value is added to the 
statement's parameter list.  Substitutions of values into the statement
occurs when the statement is executed, which provides for safer 
handling of user data.

This is an internal routine, not normally called from outside.

Example: C<my $where = $db-E<gt>where_match(quantity=E<gt>9, size=E<gt>"L");>

=cut

#------------------------------------------------------------------------

sub where_match ($$) {
    my ($this,$match) = @_;
    my (@wlist,$op,$value,$where);
    while (my ($key, $val) = each(%$match)) {
	# sanity check on keys
	if ($key !~ /^[\w\.]+$/) {
	    $this->error("MySQL::where_match: invalid column: $key");
	    return undef;
	}
	$op = "=";
	if (ref $val) {
	    # values passed by reference are SQL literals
	    if ($$val =~ /^null$/i) { 
		$op = "IS"; 
	    }
	    $value = $$val;
	}
	else {
	    # normal values are user data
	    if ($val =~ /%/) {
		if ($val =~ /(?<!\\)%/) {  # any occurence of % not preceeded by \
		    $op = "LIKE";
		}
		$val =~ s/\\%/%/g;
	    }
	    $value = "?";
	    $this->param($val);
	}
	push @wlist, "$key $op $value";
    }	    
    if (scalar @wlist) {
	$where = "WHERE ".join(" && ", @wlist);
    }
    return $where;
}

#------------------------------------------------------------------------

=pod

=head2 C<get_table_info($table)> : fetches table attributes

This is an internal utility routine that is used by C<get_key> and C<get_columns>.

=cut

#------------------------------------------------------------------------

sub get_table_info($$) {
    my ($this, $table) = @_;
    if ($table !~ /^\w+$/) {
	# validate args
	$this->error("MySQL::get_columns: invalid table: $table");
	return;
    }
    $this->reset;
    if (! $this->{sql_table_info}->{$table}) {
	my $sth = $this->query("SHOW COLUMNS FROM $table");
	if ($sth) {
	    $this->{sql_table_info}->{$table} = [];
	    while (my $row = $sth->fetchrow_hashref) {
		push @{$this->{sql_table_info}->{$table}},$row;
	    }
	}
    }
    return;
}

#------------------------------------------------------------------------

=pod

=head2 C<custom_query($sql_statement,@parameters)> : 
perform an explicit SQL query.

This method prepares and executes an arbitrary SQL query.  Unlike the
lower-level C<query()> method, this method fetches the results and
returns them in an array of datahashes.  This makes it a more user-friendly
way to execute SQL statements that are more complex than the standard
API allows for.

The complete statement can be provided, or a parameterized statement
can be given, along with a list of parameter values.  The latter is
safer when handling untrusted data values.

This method is not portable to other ExSite database drivers.

=cut

#------------------------------------------------------------------------

sub custom_query {
    my ($this,$statement,@param) = @_;
    $this->reset();
    $this->param(@param);
    my $sth = $this->query($statement);
    return $this->fetchrows(undef,undef,$sth);
}

=pod

=head2 close() : close the DB connection

=cut

sub close {
    my $this = shift;
    if ((ref $this->{sth}) eq "HASH") {
	foreach my $query (keys %{$this->{sth}}) {
	    $this->{sth}{$query}->finish();
	    delete $this->{sth}{$query};
	}
    }
    if ($this->{dbh}) {
	$this->{dbh}->disconnect();
	delete $this->{dbh};
    }
}

=pod

=head2 dbh() : return a handle to the (DBI) DB driver

This is an internal method that delays connecting to the database
until a query is actually executed.  Requests that rely on cached 
data will thus be able to avoid the overhead of a SQL connection 
entirely.

=cut

sub dbh {
    my $this = shift;
    return $this->{dbh} if ($this->{dbh});

    # Connect!
    # typical $connect values
    # dbi:DriverName:database_name
    # dbi:DriverName:database_name@hostname:port
    # dbi:DriverName:database=database_name;host=hostname;port=port
    # BUT . . .
    # I'm following MySQL format by default and inserting
    #     modifications for other drivers
    # dbi:DriverName:database_name;host=hostname;port=port
    
    my $db = $this->{db};
    if (! $db->{driver}) { $db->{'driver'} = "mysql"; }

    my $connect = join(":", "dbi", $db->{'driver'}, $db->{'name'});
    if ($db->{'server'}) {
	$connect .= ";host=".$db->{'server'};
	if ($db->{'port'}) {
	    $connect .= ";".$db->{'port'};
	}
    }
    $this->{dbh} = DBI->connect($connect, $db->{'user'}, $db->{'pass'},
				{ AutoCommit=>1, RaiseError=>0, PrintError=>0 });
    if (! $this->{dbh}) {
	$this->error("ExSite::MySQL - failed to connect: $DBI::errstr; $!");
    }
    $this->info("database connection established");
    if ($db->{'charset'}) {
	$this->{dbh}->do("SET NAMES '".$db->{'charset'}."'");
	$this->info("database connection charset set to ".$db->{'charset'});
    }
    return $this->{dbh};
}

#-------------------------------------------------------------------------
# convert perl args to SQL snippets

sub sql_table {
    my ($this,$rtab) = @_;
    my $tlist;
    # table(s) to select from
    if (ref $rtab eq "ARRAY") {
	# array of tables was passed
	$tlist = join(",",@$rtab);
	if ($tlist !~ /^(\w+,)*\w+$/) {
	    # validate 
	    $this->error("MySQL::tlist: invalid table list: $tlist");
	    return undef;
	}
    }
    else {
	# single table was passed as a scalar
	$tlist = $rtab;
	if ($tlist !~ /^\w+$/) {
	    # validate 
	    $this->error("MySQL::tlist: invalid table: $tlist");
	    return undef;
	}
    }
    return $tlist;
}

sub sql_column {
    my ($this,$rcolumn) = @_;
    my $clist;
    # column(s) to select
    if (ref $rcolumn eq "ARRAY") {
	# array of columns was passed
	$clist = join(",",@$rcolumn);
	if ($clist !~ /^([\w\.]+,)*[\w\.]+$/) {
	    $this->error("MySQL::sql_column: invalid column list: $clist");
	    return undef;
	}
    }
    elsif (ref $rcolumn eq "HASH") {
	# hash of table => reference_to_column_list was passed
	my @joinlist = ();
	while (my ($table,$list) = each %$rcolumn) {
	    if ($table !~ /^\w+$/) {
		$this->error("MySQL::sql_column: invalid table: $table");
		return undef;
	    }
	    foreach my $col (@$list) {
		if ($col !~ /^\w+$/) {
		    $this->error("MySQL::sql_column: invalid column: $col");
		    return undef;
		}	
		push @joinlist,"$table.$col";
	    }
	}
	$clist = join(",",@joinlist);
    }
    elsif ($rcolumn) {
	# single column or explicit list was passed as a scalar
	#if ($rcolumn !~ /^\w+$/) {
	if ($rcolumn !~ /^((\w+\.)?\w+(\+0)?( as \w+)?,?)+$/) {
	    $this->error("MySQL::sql_column: invalid column selector: $rcolumn");
	    return undef;
	}
	$clist = $rcolumn;
    }
    else {
	# no columns passed, select all columns
	$clist = "*";
    }
    return $clist;
}

sub sql_condition {
    my ($this,$cond) = @_;
    my $where = "";
    # condition to select on
    if (ref $cond eq "HASH") {
	# condition was passed as a match hash -
	# the selected records must match all elements of the hash.
	$where = $this->where_match($cond);
	if (! $where) {
	    $this->error("MySQL::sql_condition: invalid where clause");
	    return undef;
	}	
    }
    elsif ($cond) {
	# assume condition is a scalar explicitly stating the condition.
	# WARNING: use of this feature is potentially non-portable to other
	# ExSite DB drivers.
	# Also, no sanity check on $cond, so be careful about using tainted data
	$where = "WHERE $cond";
    }
    return $where;
}

sub sql_sort {
    my ($this,$sort) = @_;
    my $order = "";
    # sort, if asked
    if ($sort) {
	my @ords = ();
	if (ref $sort eq "ARRAY") {
	    # sort is a list of columns to sort in default order
	    foreach my $col (@$sort) {
		if ($col =~ /^\w+$/) {
		    push @ords, $col;
		}
		elsif (ref($col) eq "HASH") {
		    while (my($key,$val) = each(%$col)) {
			if ($key !~ /^[\w\.]+$/ || $val !~ /^(asc|desc)$/i) {
			    $this->error("MySQL::sql_sort: invalid sort column: $col");
			    return undef;
			}
			push @ords, "$key $val";
		    }
		}
		else{
		    $this->error("MySQL::sql_sort: invalid sort column: $col");
		    return undef;
		}
	    }
	    $order = join(",", @ords);
	}
	elsif (ref $sort eq "HASH") {
	    # sort is a hash of column => direction

	    # WARNING - hash keys have an undefined order, so this may not
	    # sort well if more than one key is given

	    while (my ($col, $dir) = each(%$sort)) {
		if ($col !~ /^[\w\.]+$/ || $dir !~ /^(asc|desc)$/i) {
		    $this->error("MySQL::sql_sort: invalid sort directive: $col $dir");
		    return undef;
		}
		push @ords, "$col $dir";
	    }
	    $order = join(",", @ords);
	}
	else {
	    # explicit sort list
	    # WARNING: may not be portable to other ExSite DB drivers.
	    if ($sort !~ /^([\w\.]+( (asc|desc))?,\s*)*([\w\.]+( (asc|desc))?\s*)$/i) {
		$this->error("MySQL::sql_sort: invalid sort directive: $sort");
		return undef;
	    }
	    $order = $sort;
	}
	$order = "ORDER BY $order";
    }
    return $order;
}

sub sql_limit {	
    my ($this,$limit) = @_;
    if (! $limit) { $limit = ""; }
    # limit, if asked
    if ($limit) {
	if ($limit !~ /^(\d+,\s*)?\d+$/) {
	    $this->error("MySQL::sql_limit: invalid limit directive: $limit");
	    return undef;
	}
	$limit = "LIMIT $limit";
    }
    return $limit;
}

sub is_cacheable {
    my $this = shift;
    return $this->{is_cacheable} && ! &ExSite::MySQL::error($this);
}

sub error {
    my ($this,$message) = @_;
    if ($message) {
	# remember our error state
	$this->{query_error} = $message;
	# log the error
	$this->SUPER::error($message);
    }
    return $this->{query_error};
}

1;
