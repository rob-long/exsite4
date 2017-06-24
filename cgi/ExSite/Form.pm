package ExSite::Form;

#-----------------------------------------------------------------------
#
#   Copyright 2001-2008 Exware Solutions, Inc.  http://www.exware.com
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

=pod

=head1 ExSite::Form - ExSite form management tools

The Form class provides a variety of tools for composing HTML forms,
reading and parsing form input, and automatically performing standard
database operations (updates, inserts, searches) on forms that 
correspond to database records.

There are two groups of methods in this class:  (1) form processing 
methods, and (2) form composition methods.

The form processing methods are mostly for processing forms that
represent database records;  if these forms are built using the 
C<input_record()> method (below), then they can be automatically
processed (read, parsed, validated, and submitted to the database)
by Form methods.  In other words, you do not need to write the 
script that accepts the form data, in simple cases.

For instance, you can create a form as follows:

C<my $form = new ExSite::Form;>

C<print $form-E<gt>make({table=E<gt>"my_db_table",...});>

This same form can be processed as follows:

C<$form-E<gt>do;>

Note that C<make()> will automatically set the method, action, and
encoding type, so that no form processing code need be written.

Additionally, the Form class inherits from the Report, DB, and SQL
(or other database driver) classes, and includes all of their 
functionality.

=cut

#======================================================================

use strict;
use MIME::Base64;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Util;
use ExSite::Time;
use ExSite::Input;
use ExSite::Report;
use ExSite::FormBuilder;

# inherit from Report (and therefore DB)
use vars qw(@ISA);
@ISA = qw(ExSite::Report);

#========================================================================
# form processing methods
# (page down this file for form construction methods)
#========================================================================
#   get_data : fetch raw input
#   get_action : determine what to do with the data
#   do : process the data
#   do_update : update records
#   do_insert : add new records
#   do_search : find records
#   parse : parse the input
#   validate : validate the data
#========================================================================

=pod

=head1 Form Processing

=head2 get_data() - fetch raw input

This method retrieves the form input and parses it (assuming it comes
from C<input_record>).  It returns the total length of the input data.

=cut 

sub get_data {
    my $this = shift;
    $this->{input} = new ExSite::Input;
    # fetch from POST data preferentially, QUERY_STRING data otherwise
    my $data = $this->{input}->post_or_query("data"); 
    # massage the form inpput
    $this->run_handler("form_input",$data);
    if ($data->{submit_action}) {
	$this->{submit_action} = $data->{submit_action};
	delete $data->{submit_action};
    }
    #### this is redundant (and wasteful, too!)
    $this->{data} = $data;
    
    $this->{form} = &parse($this,%$data);
    return $ENV{CONTENT_LENGTH} || length $ENV{QUERY_STRING};
}

=pod

=head2 get_action() - what are we supposed to do with this data?

This method figures out what to do with the data, by either reading
the action field, or guessing based on the data.  (Forms that specify
primary keys are presumed to be updates;  otherwise they are presumed
to be inserts.)

Valid actions are "insert", "update", "search".

=cut 

sub get_action {
    my $this = shift;
    my $action;
    if ($this->{action}) {
	$action = $this->{action};
    }
    else {
	if (exists $this->{data}{action}) {
	    # this form explicitly declares its action
	    $action = $this->{data}{action};
	    delete $this->{data}{action};
	}
	else {
	    my $sc = $config{form}{sepchar};
	    foreach my $key (keys %{$this->{data}}) {
		if ($key =~ /^\w+${sc}\d+${sc}\w+/) {
		    # looks like a record ID encoded in field name
		    $action = "update";
		    last;
		}
		elsif ($key =~ /^\w+${sc}${sc}\w+/) {
		    # looks like a null record ID encoded in field name
		    $action = "insert";
		    last;
		}
	    }
	}
	$this->set_action($action);
    }
    return $action;
}

sub set_action {
    my ($this,$action) = @_;
    $this->{action} = $action;
}

=pod 

=head2 do() - perform the requested action

C<do()> executes the action suggested by C<get_action()>.

First, however, it checks the submit_action, to make sure the user 
didn't cancel the form.  It also guesses a reasonable reply page, or
uses the reply argument provided by the form.

For updates and inserts, do performs a validation check on the form data,
by calling C<validate()>.  Any validation problems will prevent the
action from proceeding.

=head2 do_db() - perform the do() tasks that directly touch the database

C<do_db()> skips the control-flow logic of form processing (dealing with
cancels, determining the reply page, reporting results), and directly 
invokes the db interaction methods.  This is handy if a non-generic control
program is handling high-level form processing.

=head2 do_update() - perform an automatic update from a form

In cases where C<do()> decides to update the database, it does so by
calling C<do_update()>.

=head2 do_insert() - perform an automatic insert from a form

In cases where C<do()> decides to insert a record into the database, 
it does so by calling C<do_insert()>.

=head2 do_search() - perform an automatic search of a table

In cases where C<do()> decides to search a table in the database, 
it does so by calling C<do_search()>.  Searches are done by looking 
for records that contain all of the provided values (ie. there is an
impled logical AND of the fields);  records are taken as matches if 
they contain the provided values as substrings.

=cut

sub do {
    my ($this,$action) = @_;
    $this->info("ExSite::Form::do called");
    $this->{do_status} = 0;
    my $reply;
    my $out;
    my $redirect = 1;
    if (!$this->{data}) {
	if (! &get_data($this)) {
	    $this->error("do form: Nothing to do!");
	}
    }
    if (!$action) { $action = &get_action($this); }
    $this->{action} = $action;
    
    # fetch the destination URL
    
    if (exists $this->{data}->{reply}) {
	$reply = $this->{data}->{reply};
	delete $this->{data}->{reply};
	if ($reply =~ /$config{prog}{doform}/) {
	    # recursion is perilous
	    $reply = "";
	}
    }
    
    # cancel, if requested

    if ($this->{submit_action} eq "Cancel") {
	# bail
	$this->{do_status} = -1;   # cancelled
	my $out = $this->run_handler("cancel_form");
	if ($out) {
	    return $out;
	}
	if ($reply) {
	    print "Location: $reply\n\n";
	    return;
	}
	else {
	    return $this->ml->h3("Operation cancelled.");
	}
    }

    # do everything that touches the database

    my $errcnt = &AtError();
    $this->do_db($action);

    # report results
    if (&AtError($errcnt)) {
	# uh-oh!
	$out = $this->ml->h3("Problem:");
	$out .= $this->show_diagnostics("error","html");
	$out .= $this->ml->p($this->ml->a("Go back to form.",{href=>"javascript:history.back()"}));
    }
    elsif ($reply) {
	# success; return the user to the original page
	print "Location: $reply\n\n";
    }
    elsif ($this->{output}) {
	# success; return the status report to the user
	return $this->{output};
    }
    else {
	# success; generic confirmation message
	$out = $this->ml->h3("Done!");
    }
    return $out;
}

# do the db steps only - no control flow logic

sub do_db {
    my ($this,$action) = @_;
    $this->info("ExSite::Form::do_db called");
    $this->{do_status} = 0;
    if (!$this->{data}) {
	# in case we didn't come from do()
	if (! &get_data($this)) {
	    $this->error("do form: Nothing to do!");
	}
    }
    
    if ($action eq "search") {
	$this->error(&do_search($this));
    }
    else {
	my @err = $this->validate();
	if (scalar @err == 0) {
	    # modify the DB
	    $this->do_db_changes();
	}
	else {
	    $this->{do_status} = 1;  # failed validation
	}
    }
}

# do_db_changes : do the steps that actual alter the database

sub do_db_changes {
    my ($this) = @_;
    my $stat;
    # loop over tables/records in record order
    foreach my $tr (sort {$a cmp $b} @{$this->{recordlist}}) {
	my ($record,$table) = split /:/,$tr;
	if ($record && $record !~ /^_/) {
	    # a meaningful record id - try to update
	    my $update_data = $this->{form}{$table}{$record};
	    my $pkey = $this->{map}->get_table_attr($table,"key");
	    if (! exists $update_data->{$pkey}) {
		# not enough info in the data to id the record
		# add the primary key
		$update_data->{$pkey} = $record;
	    }
	    $stat = $this->update($table,$update_data);
	    if ($stat) {
		$this->{do_status} = 2;  # db error - see $this->{sql_error};
	    }
	}
	else {
	    # no meaningful record id - try to insert
	    my $rec = $this->{form}->{$table}->{$record};
	    # check for virtual keys
	    my @keys = keys %{$this->{virtual_keys}};
	    if (@keys > 0) {
		# check for virtual key reference in this record
		foreach my $col (keys %$rec) {
		    if ($rec->{$col} =~ /^_/) {
			# looks like a virtual key
			if ($this->{map}->get_column_attr($table,$col,"datatype") =~ /^key[:=]/) {
			    # smells like a virtual key
			    # -> substutite the actual key
			    $rec->{$col} = $this->{virtual_keys}{$rec->{$col}};
			}
		    }
		} 
	    }
	    my $id = $this->insert($table,$rec);
	    # check results
	    if (! $id) {
		$this->error("record not inserted");
		$this->{do_status} = 2;  # db error - see $this->{sql_error};
	    }
	    else {
		if (exists $this->{insert_ids}{$table}) {
		    push @{$this->{insert_ids}{$table}},$id;
		}
		else {
		    $this->{insert_ids}{$table} = [ $id ];
		}
		# add new primary key to the data
		my $pkey = $this->get_key($table);
		$rec->{$pkey} = $id;
		$this->{virtual_keys}->{$record} = $id;
	    }
	}
    }
}

sub do_update {
    my ($this) = shift;
    my @err = ();
    ##### Authorize the user to perform the requested action
    #push @err, &validate($this);
    if (@err > 0) { return @err; }
    my $stat;
    foreach my $table (keys %{$this->{form}}) {
	foreach my $record (keys %{$this->{form}->{$table}}) {
	    $stat = $this->update($table,$this->{form}->{$table}->{$record});
	    # check results
	    if ($stat) {
		push @err, "ERROR: $stat";
	    }
	}
    }
    return @err;
}

sub do_insert {
    my ($this) = shift;
    my @err = ();
    ##### Authorize the user to perform the requested action
    if (@err > 0) { return @err; }
    my $id;
    my @reclist = @{$this->{recordlist}};
    my %insert_id;
    while (@reclist > 0) {
	my $rec = shift @reclist;
	#my $data = shift @reclist;
	my ($record,$table) = split /:/,$rec;
	$id = $this->insert($table,$this->{form}{$table}{$record});
	# check results
	if (! $id) {
	    push @err, "ERROR: record not inserted";
	    push @err, $this->{query_error};
	}
	else {
	    # add new primary key to the data
	    my $pkey = $this->get_key($table);
	    $this->{form}->{$table}->{$record}->{$pkey} = $id;
	    $insert_id{$rec} = $id;
	}
    }
    return @err;
}

sub do_search {
    my ($this) = @_;
    my @err = ();
    # can search multiple tables in one call
    foreach my $table (keys %{$this->{form}}) {
	foreach my $record (values %{$this->{form}->{$table}}) {
	    foreach my $col (keys %$record) {
		# delete null-valued keys; add wildcards to the remainder
		#  foreach my $col (values %$key) {
		if ($record->{$col}) {
		    # escape literals
		    $record->{$col} =~ s/%/\\%/g;
		    $record->{$col} =~ s/_/\\_/g;
		    # add wildcards to non-id columns #############
		    if ($col !~ /id$/) {
			$record->{$col} =
			    "%".$record->{$col}."%";
		    }
		}
		else {
		    delete $record->{$col};
		}
	    }
	    #my %udata = &Authorize; ################??
	    if ($this->{handler}->{search}) {
		# special search handler
		$this->{output} = &{$this->{handler}->{search}}($this,$table,$record);
	    }
	    else {
		# don't print to stdout, since do_form doesn't know yet 
		# whether it is outputting a page or redirecting.  Also, 
		# we can't return the HTML, since the return value is for 
		# error messages.  So instead, we simply save the output 
		# in the object, and let "do" figure it out.
		$this->{output} .= $this->report({title=>"Search Results",table=>$table,data=>$record,link=>1,sort=>1});
	    }
	}
    }
    return @err;
}

# status(): give status of most recent do() operation.
#
# -1 : operation cancelled by user
#  0 : no problems - operation proceeded
#  1 : operation cancelled automatically due to failed validation
#  2 : operation failed at DB
#
# If status is true, the operation did not proceed.

sub status {
    my $this = shift;
    return $this->{do_status};
}

sub last_insert_id {
    my ($this,$table) = @_;
    return exists $this->{insert_ids}{$table} ? 
	$this->{insert_ids}{$table}[-1] : undef;
}

=pod

=head2 parse(%data) - decode form data

Parse does more than the usual URL-decoding of form data.  It also:

=over 4

=item * determines which database table, record, and column each form input corresponds to

=item * groups data by record, so that multiple records can be entered into the same form

=item * (using parse_parts) combines multi-part input fields (eg. dates) into single data values

=item * (using parse_parts) mime-encodes file inputs, so they can be managed as text strings

=back

The parsed data is returned in a hash with the following structure:

C<$formdata{TABLE}{ROW}{COLUMN} = VALUE>

where "ROW" is the primary key value (record ID) of the row.  For inserts
in which the primary key is not yet defined, the ROW is C<_> for single-record
inserts, or C<_n> where n = 1,2,3,... for multi-record inserts.

If you rely on the Form class to automatically parse the form data, this
data structure will be stored in the Form object in C<$this->{form}>.

Generic forms encode the table and record directly into each input name:
C<table#record_id#column>.  The C<record_id> can be null, or "_" for a
simple insert, or "_[n]" for multiple distinct inserts.  Note that this
allows the table and record IDs to be tampered with by the user.  Exsite 
has security rules to prevent users from tampering with unauthorized
records, but if this degree of security is insifficient, you should not
rely on generic forms.

=cut

sub parse {
    my ($this,%data) = @_;
    $this->info("parse: auto-parsing form data");
    my %form;
    my $sc = $config{form}{sepchar};
    my @keys;
    if ($this->{input}) {
	# use original input order from form
	@keys = @{$this->{input}->post_or_query("keys")};
    }
    else {
	@keys = sort keys %data;
    }
    $this->{recordlist} = [];
    
    # combine multipart inputs into simple values

    my %input = $this->parse_parts(%data);

    # break down inputs into actual column values
    
    foreach my $key (@keys) {  # loops over inputs in order
	next if ($key !~ /$sc/);
	my ($tab,$irec,$col,$part) = split /$sc/, $key;
	my $newkey = "$tab$sc$irec$sc$col";
	next if (! exists $input{$newkey}); # removed by parse_parts()
	my $val = $input{$newkey};

	my %map = $this->{map}->get_column($tab,$col);
	my $rec = $irec;  # $irec is the input record id from form data
	# set dummy records to "_"
	if (! $rec) { $rec = "_"; }
	if (! exists $form{$tab}) {
	    # new table
	    $form{$tab} = {};
	}
	if (! exists $form{$tab}{$rec}) {
	    # new record
	    $form{$tab}{$rec} = {};
	    push @{$this->{recordlist}}, "$rec:$tab";
	}
	if (exists $form{$tab}{$rec}{$col}) {
	    # already hit this column
	    next;
	}

	# encrypted fields
	### FIXME: this should probably be done at a lower level to ensure
	### that it works on non-generic forms
	if ($map{datatype} eq "crypt") {
	    $val = $this->encrypt($val);
	}

	$form{$tab}{$rec}{$col} = $val;
    }
    return \%form;
}

=pod

=head2 parse_parts(%data) - parses multi-part inputs

Some special form field types generate multiple input elements that
collect different parts of the input value separately.  For example:

=over 4

=item * dates consist of year, month, and day inputs

=item * times consist of hour, minute, and am/pm inputs

=item * checklists consist of multiple items that should be concatenated
together

=item * file uploads consist of a file input, and checkbox to clear 
the existing file

=back

C<parse_parts> takes the raw hash of input values and reassembles the 
multipart inputs into single input values.  For example, the separate
parts of a date input, eg.

    date#year = '2009'
    date#month = '12'
    date#day = '25'

get converted to a single key/value pair,

    date = '2009-12-25'

The hash of unified input values is returned.

=cut

sub parse_parts {
    my ($this,%data) = @_;
    my %form;
    my $sc = $config{form}{sepchar};
    
    # combine multipart inputs into single input values

    foreach my $key (keys %data) {
	my $val = $data{$key};
	my ($field,$part);
	my @subkey = split(/$sc/,$key);
	my $nsubkey = scalar @subkey;
	if ($nsubkey == 1) {
	    # fieldname
	    $field = $subkey[0];
	}
	elsif ($nsubkey == 2) {
	    # name#part
	    $field = $subkey[0];
	    $part = $subkey[1];
	}
	elsif ($nsubkey == 3) {
	    # tab#rec#col
	    $field = join $sc, @subkey;
	}
	else {
	    # tab#rec#col#part
	    $part = pop @subkey;
	    $field = join $sc, @subkey;
	}

	# pre-process certain inputs

	if ($config{form}{trim_whitespace}) {
	    # should this be restricted to certain datatypes??
	    $val =~ s/^\s+//;
	    $val =~ s/\s+$//;
	}

	# multi-part inputs
	if ($part) {
	    # compound value
	    if ($part =~ /^html$/i) {
		# must unmangle any CMS tags that were masked for the editor
		$form{$field} = &restore_cms_tags($data{$key});
	    }
	    elsif ($part eq "filename" || $part eq "clear") {
		# A file:  for regular URL-encoding, only the filename will
		# be passed, but for multipart encoding, the file contents
		# will also be passed.  Either way, the file is encoded in the
		# database as "filename#content_data".  The content_data, if
		# present, is MIME base-64 encoded, so that it can be managed
		# using regular text insert/update statements.
		next if (exists $form{$field});
		if (exists $data{"$field${sc}clear"}) {
		    # clear the field if the delete box is checked
		    $form{$field} = "";
		    next;
		}
		my $in = $this->{input} || new ExSite::Input;
		my $filedata = $in->fetch_file("$field${sc}$part");
		if ($filedata =~ /^[\w-\.]+$sc\S+$/) {
		    # only set the field if we have file data
		    $form{$field} = $filedata;
		}
	    }
	    elsif ($part eq "list" || $part eq "other") {
		# an open (or other) list
		next if (exists $form{$field});
		if (exists $data{"$field${sc}other"}) {
		    # the other box is set; use this value preferentially
		    $form{$field} = $data{"$field${sc}other"};
		}
		else {
		    # use the selector value
		    $form{$field} = $data{"$field${sc}list"};
		}
	    }
	    elsif ($part =~ /key/) {
		# a foreign key reference
		# -> only requires special processing if it points to a 
		# virtual primary key
		if ($val =~ /^_/) {
		    # virtual primary key - not determined until preceeding
		    # records are actually inserted
		    if (! $this->{virtual_keys}) { 
			$this->{virtual_keys} = {}; 
		    }
		    # remember the key for later reference
		    $this->{virtual_keys}{$val} = undef; 
		}
		$form{$field} = $val;
	    }
	    elsif ($part =~ /_set_/) {
		# this is a set item; append the value to the values 
		# already accumulated for this column
		if ($part eq "_set_0") {
		    # dummy data item - represents no selected items.
		    # If there is a value, and no other set items selected,
		    # then we keep the value as a default.  If there is a 
		    # value, and other set items are checked, then we 
		    # ignore the default.  If there is no value, then we
		    # initialize the column as empty.
		    if ($val && ! exists $data{"$field${sc}_set_1"}) {
			# dummy value exists, and no other set data is present
			$form{$field} = $val;
		    }
		    elsif (! $val && ! defined $form{$field}) {
			# dummy value empty, and no other set data has been read
			$form{$field} = "";
		    }
		}
		else {
		    # set value selected; append it to the current value
		    $val =~ s/&\#34;/\"/g;
		    if ($form{$field}) {
			$form{$field} .= $config{form}{multi_sep};
		    }
		    $form{$field} .= $val;
		}
	    }
	    else {
		# this is a date or time (or datetime) value
		my ($year, $month, $day, $hour, $min);
		# 1) check that we haven't already processed the overall column
		if (! exists $form{$field}) {
		    my ($date);
		    # dates
		    if (defined $data{"$field${sc}year"}) {
			$year = $data{"$field${sc}year"};
			$month = $data{"$field${sc}month"};
			$day = $data{"$field${sc}day"};
			$date = join("-",$year,$month,$day);
		    }
		    elsif (defined $data{"$field#date"}) {
			$date = $data{"$field#date"} || "0000-00-00";
		    }
		    # times
		    if (defined $data{"$field${sc}hour"}) {
			$hour = $data{"$field${sc}hour"};
			if ($data{"$field${sc}ampm"} eq $config{form}{pm} && $hour < 12) {
			    $hour += 12;
			}
			elsif ($data{"$field${sc}ampm"} eq $config{form}{am} && $hour == 12) {
			    $hour = 0;
			}
			$min = $data{"$field${sc}min"};
			if ($date) { $date .= " "; }
			$date .= join(":",$hour,$min,"00");
		    }
		    $form{$field} = $date;
		}
	    }
	}
	else {
	    # simple input
	    $val =~ s/&\#34;/\"/g;
	    $form{$field} = $val;
	}
    }
    return wantarray ? %form : \%form;
}

=pod

=head2 formpush() - push new data onto the end of the form

C<formpush()> is used to manually add new data items onto the form, 
after the form data has already been parsed.  This is typically used
by handlers and wizards to place extra data into the form after the
form has been submitted.

The new data is only added to the {form} attribute, not to the
raw form data, nor to the input object.  It is always added to the
end of the form.

=cut

sub formpush {
    my $this = shift;
    my $key = shift;
    my $val = shift;
    while ($key) {
	my $sc = $config{form}{sepchar};
	my ($tab, $irec, $col, $part) = split(/$sc/,$key);
	if ($part) {
	    # problem - we only push simple form values, no multipart values
	    $this->error("cannot push multipart form values");
	    return;
	}
	else {
	    my %map = $this->{map}->get_column($tab,$col);
	    my $rec = $irec;  # $irec is the input record id from form data
	    # set dummy records to "_"
	    if (! $rec) { $rec = "_"; }
	    if (! exists $this->{form}{$tab}) {
		# new table
		$this->{form}{$tab} = {};
	    }
	    if (! exists $this->{form}{$tab}{$rec}) {
		# new record
		$this->{form}{$tab}{$rec} = {};
		push @{$this->{recordlist}}, "$rec:$tab";
	    }
	    $this->{form}{$tab}{$rec}{$key} = $val;
	}
	$key = shift;
	$val = shift;
    }
    return;
}

=pod 

=head1 Form Validation

All of the validation routines return error messages (either single, or 
an array) if invalid data is found, or undef/empty array if no invalid
data was detected.

Every datatype known to ExSite has its own validation regular expression.
Validation of inputs conists of comparing the input value to this regular 
expression.  ExSite determines the appropriate datatype to compare to
by looking up the table and column associated with the input field, in 
the DBmap.

Additional validations that are performed incluide:

=over 4

=item * testing for required fields (on inserts)

=item * testing permissions for linking records (ie. setting foreign key 
values).

=item * testing length/size of data

=item * checking for forbidden words (content filtering)

=item * custom user-defined validations

=back

Note: The validation routines are automatically invoked by C<do()>.

=head2 validate() - validate form data

Validate operates on the results of C<parse()> that were stored in the
Form object.  It determines the validity of all form data that was
entered, as well as detecting missing required data.

=head2 validate_record($table,$datahash) - validate a datahash

C<validate_record()> validates the values in the passed C<$datahash>,
returning an array of error messages for values that do not correspond
to the accepted values for the given column.  It determines the
validity of all data present in the datahash, as well as detecting
missing required data.  It can be called directly, without actually
processing a form.

The rules it follows are different depending on whether the record
is for an insert or an update;  if the form action (C<$this->{action}>)
is not defined either way, an insert will be assumed, which is more
restrictive.

=head2 validate_column($table,$column,$datum) - validate a column value

C<validate_column()> validates a single value for a specific column in
the database.  An error message is returned if the value does not
match expected values.  C<undef> is returned if the datum validates
correctly.  It can be called directly, without actually processing a
form.

=head2 validate_datatype($type,$datum) - validate a data value

C<validate_datatype()> checks that a data value conforms to the
allowed values for a datatype.  It returns an error message if not, or
C<undef> if valid.  It can be called directly, without actually
processing a form.

=head2 validate_language($text,@forbidden) - validates that $text uses "clean" language

If the C<wordfilter> feature is enabled, this validation method will
be invoked automatically on any public text content (ie. all string,
text, and html columns that are readable at level 1 or lower).  

If the C<wordfilter> action is B<reject>, then the validation routine
will throw validation errors if bad words are detected.  For other
actions (B<censor> and B<semi-censor>), the text will be altered, and
warnings thown instead.  Warnings will pass validation, but may still
generate messages on screen.  If the user is of a sufficiently high
level (3 by default), their content is trusted, and always generates
warnings rather than errors.

C<validate_language()> returns the (modified) text, plus a list of
error messages if validation has failed.  For censoring actions, there
should be no errors (unless the wordfilter has not been configured
properly), while for non-censoring actions, the text should not be
modified.  It is the caller's responsibility to replace the original
text with the modified text.

The list of forbidden words is taken from a config file, by default
C<conf/badwords.txt>.  If the C<wordfilter> feature is turned off,
this method will do nothing using this dictionary of forbidden words.
However, you can still invoke this method directly for special cases, 
and provide your own list of forbidden words after the text parameter.

=cut

# validate a form

sub validate {
    my ($this) = @_;
    $this->info("validate: auto-validating form data");
    my @errors = ();
    foreach my $table (keys %{$this->{form}}) {
	foreach my $row (keys %{$this->{form}->{$table}}) {
	    my @err = $this->validate_record($table,
					     $this->{form}{$table}{$row});
	    my $rowname = $row eq "_" ? "" : $row;
	    foreach my $err (@err) {
		push @errors, "$table $rowname: $err";
	    }
	    
	    # custom validation handler: note that this does not 
	    # override validate(), but adds to it.

	    my $stat = $this->run_handler("validate",$this->{action},$table,$row,$this->{form}{$table}{$row});
	    if (defined $stat) {
		push @errors, @$stat;
	    }
	}
    }
    if (@errors > 0) {
	$this->error(join("; ",@errors));
    }
    return @errors;
}

sub validate_record {
    my ($this,$table,$data) = @_;
    if ($this->{action} eq "update") {
	return $this->validate_record_update($table,$data);
    }
    else {
	return $this->validate_record_insert($table,$data);
    }
}

sub validate_record_insert {
    my ($this,$table,$data) = @_;
    my @err;

    # For inserts, we must check for all required columns, as well as
    # validating the data that was provided.

    # loop over columns in dbmap
    my $ncol = $this->{map}->get_ncol($table);
    if ($ncol < 1) { return ("$table: invalid table"); }
    for (my $icol=0; $icol<$ncol; $icol++) {
	my %column = $this->{map}->get_column($table,$icol);
	my $col = $column{column};
	# okay to have missing serial number primary key on inserts
	next if ($column{datatype} =~ /^key\#$/ && ! $data->{$col});
	my $stat = $this->validate_column($table,$col,$data->{$col});
	if ($stat) { push @err, $stat; }

	if ($config{wordfilter}{mode} eq "auto" && 
	    $data->{$col} &&
	    $column{datatype} =~ /string|text|html/ && 
	    $column{read} <= $config{wordfilter}{threshold}) {
	    # automatic word filtering is enabled
	    my ($text,$error) = $this->validate_language($data->{$col});
	    if ($error) {
		# validation errors
		push @err, "$table: $error";
	    }
	    if ($text ne $data->{$col}) {
		# update with censored text
		$data->{$col} = $text;
	    }
	}
    }
    return @err;
}

sub validate_record_update {
    my ($this,$table,$data) = @_;
    my @err;
    my $ncol = $this->{map}->get_ncol($table);
    if ($ncol < 1) { return ("$table: invalid table"); }

    # For updates, we only need to check the validity of the data that
    # was provided, since the required columns are already in the database.

    my $id = $data->{$this->{map}->get_table_attr($table,"key")};
#    if ($this->{map}->get_table_attr($table,"update") &&
#	! $this->user_owns($table,$id)) { 
    if (! $this->user_owns($table,$id)) { 
	push @err, "$table: ownership mismatch - you do not have permission to update $table $id";
    }

    foreach my $key (keys %$data) {
	my %column = $this->{map}->get_column($table,$key);
	my $stat = $this->validate_column($table,$key,$data->{$key});
	if ($stat) { push @err, "$table: $stat"; }

	if ($config{wordfilter}{mode} eq "auto" && 
	    $data->{$key} &&
	    $column{datatype} =~ /string|text|html/ && 
	    $column{read} <= $config{wordfilter}{threshold}) {
	    # automatic word filtering is enabled
	    my ($text,$error) = $this->validate_language($data->{$key});
	    if ($error) {
		# validation errors
		push @err, "$table: $error";
	    }
	    if ($text ne $data->{$key}) {
		# update with censored text
		$data->{$key} = $text;
	    }
	}
    }
    return @err;
}

sub validate_column {
    my ($this,$table,$column,$datum) = @_;
    my $stat = $this->run_handler("validate_column",$table,$column,$datum);
    return $stat if (defined $stat);
    # return undef to continue below; return 0 to skip
	
    my %column = $this->{map}->get_column($table,$column);
    my $datatype = $column{datatype};
    if (! $datatype) {
	return "unknown column: $column";
    }
    if ($datum || $datum =~ /^0$/) {
	# we have data - check its validity
	# fixed datatypes
	if ($datatype eq "fixed") {
	    if ($datum ne $column{default}) {
		return "\"$datum\" is not a valid value for \"$column{label}\"";
	    }
	}
	# variable datatypes
	if ($column{validate} ne "no") {
	    # check data pattern
	    my $stat = $this->validate_datatype($column{datatype},$datum);
	    if ($stat eq "invalid data/format") {
		# validate_datatype returns an unfriendly error message
		return "\"$datum\" is not a valid value for \"$column{label}\"";
	    }
	    elsif ($stat) {
		return $stat;
	    }
	}
	# check length of data
	if ($datatype =~ /^(string|email|url|password|filepath|list|set)$/) {
	    if (length $datum > $column{size}) {
		return "\"$column{label}\" is too long - maximum length is $column{size} characters";
	    }
	}
    }
    else {
	# no data...
	if ($column{datatype} eq "key\#" && $this->{action} eq "insert") {
	    # serial number primary keys not required on inserts
	    return undef;
	}
	return undef if ($column{validate} =~ /yes/);  # data is optional
	if ($column{validate} eq "soft") {
	    return "you must provide a value for \"$column{label}\"";
	}
	elsif ($column{validate} eq "hard") {
	    return "no $column{label} defined";
	}
    }
    return undef;
}

sub validate_datatype {
    my ($this,$type,$datum) = @_;
    
    my $stat = $this->run_handler("validate_datatype",$type,$datum);
    return $stat if (defined $stat);
    
    # check data against legal patterns
    my $datatype = $type =~ /^key/ ? "key" : $type;
    my $re = $this->{map}->regexp($datatype);
    if ($datatype eq "key") {
	# foreign keys can be real or virtual
	if ($datum !~ /^($re|_\d*)$/) {
	    return "invalid foreign key reference";
	}
    }
    elsif ($datatype =~ /^set:/) {
	# test each value separately
	my @errors;
	foreach my $v (split(/$config{form}{multi_sep}/,$datum)) {
	    if ($v !~ /^($re)$/) {
		push @errors, "invalid value: \"$v\"";
	    }
	}
	return join("; ",@errors) if (@errors > 0);
    }
    elsif ($datatype =~ /file/) {
	# check upload file sizes
	if ($datatype eq "file" && length $datum > 65535) {
	    return "uploaded file is too large (48K max)";
	}
	elsif ($datatype eq "bigfile" && 
	       length $datum > $config{form}{bigfile_maxsize} * 4 / 3 ) {
	    my $fmax = int($config{form}{bigfile_maxsize} / 1024);
	    return "uploaded file is too large ($fmax kb max)";
	}
    }
    elsif ($datatype =~ /^enum:/) {
	my @num;
        my @opt = split /\|/,$re;
	foreach my $opt (@opt) {
	    my ($num,undef) = split /:/,$opt,2;
	    push @num, $num;
	}
	my $new_re = join("|",@num);
	if ($datum !~ /^$new_re$/) {
	    return "$datum is not a valid value for $datatype";
	}
    }
    elsif ($re && $datatype !~ /^olist:/ && $datum !~ /^$re$/) {
	# everything else is just tested against a regex
	# except olists, which can take any value, technically
	return "invalid data/format";
    }

    # additional tests...

    # test password strength
    if ($datatype =~ /^password$/ && $config{auth}{strong_passwords}) {
	return $this->validate_password($datum);
    }

    # check for legal, not just syntactically correct, dates
    if ($datatype =~ /^date/) {
	# dates may pass regexp check, but still be invalid
	return undef if ($datum =~ /^0+-0+-0+ ?/);  # null date
	my $timetype = $datatype eq "datetime" ? "sql_datetime" : "sql_date";
	my $t = new ExSite::Time($datum,$timetype);
	return $t->validate();
    }

    # check ownership of foreign keys
    if ($type =~ /^key[=:]/) {
	if ($this->authorize < $config{auth}->{foreign_link_level}) {
	    my (undef,$ftable) = split /[:=]/,$type;
	    if (! $this->user_owns($ftable,$datum)) { 
		return "ownership mismatch - you do not have permission to link to $ftable $datum";
	    }
	}
    }

    return undef;
}

sub clean_datatype {
    my ($this,$type,$datum) = @_;
    
    ##### try to reformat datum for better consistency

}

# test password strength

sub validate_password {
    my ($this,$password,$login,$access) = @_;
    # login and access level are optional, but will allow for extra tests
    my $stat = $this->run_handler("validate_password",$password,$login,$access);
    return $stat if (defined $stat);
    $login or $login = $this->my_login();
    $access or $access = 3;
    my $strength = $this->password_strength($password,$login);
    my $min_strength = $config{auth}{password_strength}{$access} || $access;
    return ($strength >= $min_strength) ? undef :
        $msg{"Password is too weak.  Strengthen it with more text, numbers, upper-case, or punctuation characters."};
}

# validate_language: check for forbidden words in content

sub validate_language {
    my ($this,$text,@badwords) = @_;
    my $error;

    if (@badwords == 0) {
	return ($text,undef) if ($config{wordfilter}{mode} eq "off");
	# get a forbidden word list
	if (ref $share{badwords} eq "ARRAY") {
	    @badwords = @{$share{badwords}};
	}
	elsif (-e "conf/$config{wordfilter}{file}") {
	    if (open F, "<conf/$config{wordfilter}{file}") {
		@badwords = <F>;
		chomp @badwords;
		$share{badwords} = \@badwords;
	    }
	    else {
		$error = "Failed to open forbidden word file conf/$config{wordfilter}{file}";
	    }
	}
	return ($text,$error) if (@badwords == 0);
    }

    my $badword_re = join("|",grep(/\w/,@badwords));
    my @detected_badwords;
    while ($text =~ /\b($badword_re)\b/i) {
	# bad word detected
	my $badword = $1;
	push @detected_badwords, $badword;
	if ($config{wordfilter}{method} eq "censor") {
	    # CENSOR: delete the bad word entirely
	    $text =~ s/\b$1\b/$config{wordfilter}{censor_string}/ig;
	}
	elsif ($config{wordfilter}{method} eq "semi-censor") {
	    # SEMI-CENSOR: strikeout the interior characters of the bad word
	    my $censortext = $badword;
	    $censortext =~ s/(?<=\w).(?!\b)/$config{wordfilter}{censor_char}/g;
	    $text =~ s/\b$badword\b/$censortext/ig;
	}
	else {
	    # escape the badword with an improbable character sequence
	    $text =~ s/\b($badword)\b/\#\_ZZ$1\_\#/ig;
	}	    
    }
    

    # throw errors, as needed
    if (@detected_badwords > 0) {
	if ($config{wordfilter}{method} =~ /censor/) {
	    my $warning = "censored the following words: ".
		join(", ",@detected_badwords);
	    $this->warn($warning);
	    # since the text has been sanitized, 
	    # we don't throw errors in this case
	}
	else {
	    # senior admins 
	    if ($this->level >= $config{wordfilter}{override}) {
		$this->warn("text contains forbidden words: ".
		    join(", ",@detected_badwords));
	    }
	    else {
		$error = "text contains forbidden words: ".
		    join(", ",@detected_badwords);
	    }
	    # unescape our badwords
	    $text =~ s/\#\_ZZ(\w+)\_\#/$1/g;
	}
    }

    # WARNING: the first parameter returned is the censored text, 
    # NOT an error message
    return ($text,$error);
}

# delete_record : remove a record from the parsed form data so that it
# won't be processed.

sub delete_record {
    my ($this,$table,$rec) = @_;
    if (exists $this->{form}{$table}{$rec}) {
	$this->info("delete_record: removing $table $rec from form data");
	delete $this->{form}{$table}{$rec};
	for (my $irec = 0; $irec < scalar @{$this->{recordlist}}; $irec++) {
	    my $r = $this->{recordlist}[$irec];
	    my ($rname,$tname) = split(/:/,$r);
	    if ($tname eq $table && $rname eq $rec) {
                splice(@{$this->{recordlist}},$irec,1);        
		return 1;
	    }
	}
    }
    return 0;  # nothing removed
}

=pod

=head1 Form Construction

The form construction methods are used to compose HTML forms that are
compatible with the form processing methods, above.  Developers can 
redirect these forms to their own processing methods, but by default
they will direct themselves to the automatic-processing methods.

=head2 C<make(%options)> - build a completely self-contained form

C<make()> builds forms for inserting or updating records into the
database, or for conducting searches on particular database tables.
By default, the form automatically sets its action so that it will
be automatically processed, executed, and the user will be returned
to an appropriate page when done.

=head3 Typical Examples:

Make a blank form to add a new record: C<$form-E<gt>make(table=E<gt>$table_name)>

Make a form to add a new record, prefilled with defaults : C<$form-E<gt>make(table=E<gt>$table_name,data=E<gt>$datahash)>

Make a form to update an existing record: C<$form-E<gt>make(table=E<gt>$table_name,record=E<gt>$record_id)>

Make a form to search a table: C<$form-E<gt>make(table=E<gt>$table_name,search=E<gt>1)>

=head3 C<make()> options

=over 4

=item B<table> 

the table the form will be operating on.  Optionally, 
a reference to an array of table names may be given.

=item B<record> 

the record ID of the record the form will be operating on.
If an array of table names was passed in C<table>, then a corresponding
array of record IDs should be passed here.  This parameter can be left off
or set to C<undef> for inserts.

=item B<hide> 

ref to an array of column names that should be excluded
from the form.

=item B<show> 

ref to an array of column names that should be shown on 
the form.  This defaults to all editable columns in the DBmap, but a
different list can be provided here to change the form presentation.

=item B<extra> 

ref to a hash of additional keys/values that should
be included in the form (as hidden inputs).  This is typically used to
include control directives such as a reply URL (key "C<reply>") to 
go to after the form is processed.

=item B<search> 

true/false flag indicating whether this form
should be processed as a table search operation.  Searches return
generic reports of all matching records.

=item B<action> 

the form action, ie. the URL to process the form input.
By default this is C<doform.cgi>, which simply executes the automatic
form processing methods detailed above.  A custom form processing URL
can be specified here instead.

=item B<method> 

the form method, "POST" by default.

=item B<data> 

ref to a datahash containing presets/defaults for the form.

=item B<debug> 

if true, directs the form to C<debug.cgi>, which simply
displays the form contents to the developer, without processing the data.

=back

=head2 C<make_form_buttons()>

This generates standard submit, reset, and cancel buttons for a form.
It does not depend on C<make()> and may be invoked by any form.  Note
that "Cancel" submits the form, but sets the C<submit_method> form 
parameter to "Cancel".  The form processing routine should check for 
this value, before processing the form.

=head2 C<edit($table,$record,$hide,$show,$extra)>

This is a wrapper for C<make()> that generates a form to edit an 
existing record.

=head2 C<append($table,$record,$hide,$show,$extra)>

This is a wrapper for C<make()> that generates a form to insert a new record.

=head2 C<search_query($table,$hide,$show,$extra)>

This is a wrapper for C<make()> that generates a form to search a table.

=cut

sub form {
    my $this = shift;
    if (exists $this->{FormBuilder}) {
	if ((ref $this->{FormBuilder}) =~ /FormBuilder/) {
	    if (@_ > 0) {
		$this->{FormBuilder}->init(@_);
	    }
	}
    }
    else {
	$this->{FormBuilder} = new ExSite::FormBuilder(@_);
    }
    return $this->{FormBuilder};
}

sub make {
    my ($this,%opt) = @_;
    $this->info("ExSite::Form::make: called");
    my (@tables,@records);
    if (ref $opt{table} eq "ARRAY") { @tables = @{$opt{table}}; }
    else { @tables = ( $opt{table} ); }
    if (ref $opt{record} eq "ARRAY") { @records = @{$opt{record}}; }
    else { @records = ( $opt{record} ); }
    delete $this->{error};

    # form method - can customize the initialization of our FormBuilder
    # object by passing custom params in $opt{form}
    my %form = $opt{form} ? %{$opt{form}} : ();
    $form{method} = $opt{method} || "POST";
    # this forces a FormBuilder reset if there are multiple forms on the page:
    $this->form(%form);

    my $nrec = 0;
    while (@tables > 0) {
	$nrec++;
	my $table = shift @tables;
	my $record = shift @records;
	if (! $record) { $record = "_$nrec"; }
	if ($opt{search}) {
	    # explicit search form
	    $this->{action} = "search";
	    $this->input_record({table=>$table,
				 hide=>$opt{hide},
				 show=>$opt{show},
				 group=>$opt{group},
				 data=>$opt{data},
				 simplename=>$opt{simplename},
			        });
	}
	elsif (! $record || $record =~ /^_/) {
	    # no record info; this is a completely blank insert
	    $this->{action} = "insert";
	    $this->input_record({data=>$opt{data},
				 table=>$table,
				 hide=>$opt{hide},
				 show=>$opt{show},
				 group=>$opt{group},
				 simplename=>$opt{simplename},
			        });
	}
	elsif ($opt{data}) {
	    ### check this

	    # record is a reference to a datahash containing defaults and/or
	    # foreign key references
	    $this->{action} = "insert";
	    $this->input_record({table=>$table,
				 data=>$record,
				 hide=>$opt{hide},
				 show=>$opt{show},
				 group=>$opt{group},
				 simplename=>$opt{simplename},
			        });
	}
	else {
	    # record is a key of an existing record
	    my %data = $this->fetch($table,$record);
	    $this->{action} = "update";
	    $this->input_record({table=>$table,
				 data=>\%data,
				 hide=>$opt{hide},
				 show=>$opt{show},
				 group=>$opt{group},
				 simplename=>$opt{simplename},
			        });
	}
    }
    
    return $this->{error} if ($this->{error});
	
    foreach my $key (keys %{$opt{extra}}) {
	$this->form()->input(type=>"hidden",
			     name=>$key,
			     value=>$opt{extra}{$key});
    }
    if (!exists $opt{extra}{action}){
	$this->form()->input(type=>"hidden",
			     name=>"action",
			     value=>$this->{action});
    }
    
    # form action
    if ($opt{action}) {
	# explicit action
	$this->form()->action($opt{action});
    }
    elsif ($opt{debug}) {
	# debug - just dump the inputs to screen
	$this->form()->action("$config{server}{CGIpath}/$config{prog}{debug}");
    }
    elsif ($config{form}{mode} eq "cgi") {
	# generic action (doform.cgi)
	$this->form()->action("$config{server}{CGIpath}/$config{prog}{doform}"); 
    }
    else { 
	# generic action (using WebDB plugin)
	# redundancy here: WebDB action passed in QUERY and in POST
	my $pid = $share{Page}->id;
	$this->form()->action("$config{server}{CGIpath}/$config{prog}{page}?_id=$pid");
    }

    return $this->form()->make();
}

sub make_form_buttons {
    my $this = shift;
    return $this->form()->buttons();
}

=pod

=head2 C<input_record($opt)> - make labels and input tags for a whole record

Generates the input labels and tags corresponding to a database record.
C<$opt> is a ref to an option hash:

=over 4

=item C<table> 

the table the record belongs to

=item C<record> 

the record ID of the record (for updates)

=item C<data> 

preset default values (for inserts)

=item C<hide> 

ref to array of columns to NOT display

=item C<show> 

ref to array of columns to display

=item C<group> 

in some DBmaps, columns can have a group attribute,
allowing you to specify multiple columns with a single group identifier.
The C<group> parameters works like C<show>, but for groups of columns.

=back

C<input_record()> includes security checks to determine whether the
user is permitted to read/write each field.  The corresponding inputs
are not generated if the checks indicate otherwise.

=cut

#--------------------------------------------------------------------
# input_record : loop over the columns of a table, generating an
#                appropriate input tag for each
#--------------------------------------------------------------------

sub input_record {
    my $this = shift;
    my ($opt,%opt,$table,$record,$rdata,$rhide,$rshow,$group);
    if (scalar @_ == 1) {
	# support older calling convention
	$opt = shift;
	$table = $opt->{table};
	$record= $opt->{record};
	$rdata = $opt->{data};
	$rhide = $opt->{hide};
	$rshow = $opt->{show};
	$group = $opt->{group};
    }
    else {
	%opt = @_;
	$table = $opt{table};
	$record= $opt{record};
	$rdata = $opt{data};
	$rhide = $opt{hide};
	$rshow = $opt{show};
	$group = $opt{group};
    }
    # check that the user is allowed to edit/insert this record
    if (! $this->approve($this->{action},$table,$rdata)) {
	return ($this->{error} = $this->error("Permission denied ($this->{action} to $table)"));
    }
    my ($out, $sc, $map, $typemap);
    $sc = $config{form}->{sepchar};
    $map = $this->{map}->get_map($table);
    if (!defined $map) {
	return ($this->{error} = $this->error("unknown table $table"));
    }
    my $authlevel = $this->authorize;

    my (%data,@hide,@show);
    if (defined $rdata) { %data = %$rdata; }
    if (defined $rhide) { @hide = @$rhide; }
    if (defined $rshow) { @show = @$rshow; }
    
    my $pkey = $this->get_key($table);
    if (! $record) { $record = $data{$pkey}; }
    
    my ($write, %column);
    my $ncols = $this->{map}->get_ncol($table);
    
    for (my $icolumn = 0; $icolumn < $ncols; $icolumn++) {
        %column = $this->{map}->get_column($table,$icolumn);
	if (! $column{label}) { $column{label} = $column{column}; }

	if ($this->{action} eq "search" && $column{search} eq "no"){next;}

	$write = ($column{write} <= $authlevel);

	# is this row displayed by default?
	#$write = $write && ($column{display} ne "no");
	# options to vary default logic

	# select which columns to show based on show and hide lists
	my $showflag;
	my $hideflag;
	if ($#show >= 0) {
	    $showflag = scalar grep(/^$column{column}$/,@show);
	    $write = $write && $showflag;
	}
	if ($#hide >= 0 || $column{datatype} eq "fixed") {
	    $hideflag = scalar grep(/^$column{column}$/,@hide) ||
		$column{datatype} eq "fixed";
	    $write = $write && ! $hideflag;
	}

	# select columns based on column groups
	if ($group && $write) {
	    if ($column{group} !~ /$group/) { $write = 0 }
	}
	
	# don't put timestamps in forms (unless explicitly allowed)
	next if ($column{datatype} eq "timestamp" && ! $config{form}{editable_timestamps});

	# set data value for fixed fields
	if ($column{datatype} eq "fixed") { 
	    $data{$column{column}} = $column{default};
	}

	if (! $write) {
	    # don't put hidden passwords in forms	    
	    if ($authlevel != $config{auth}->{root_auth_level} &&
		$column{datatype} eq "password") { next; }
	    # show readonly fields...
	    if ($config{form}->{show_readonly} &&  # if requested, and
		$column{read} <= $authlevel &&     # read is permitted, and
		(($#show >= 0 && $showflag) ||     # the field is explicitly
		! $hideflag)) {                    # shown or not hidden
		$column{datatype} = "readonly";
		$write = 1;
	    }
	}

	my $go;  #build input for this field?
	if ($this->{action} eq "search") {
	    $go = $authlevel >= $column{read} && 
		$authlevel >= $this->{map}->get_table_attr($table,'search') &&
		$column{search} ne "no" &&
		$write;
		#$column{search} =~ /yes|general/;
	}
	else {
	    # insert/update
	    $go = $write || $authlevel == $config{auth}->{root_auth_level};
	}

	if ($go) {
	    # emphasize required fields
	    my $required = ($column{validate} =~ /soft|hard/ && 
			    $this->{action} ne "search");
	    $out .= $this->input_column(
					table=>$table, 
					column=>$column{column},
					size=>$column{size},
					record=>$record, 
					datatype=>$column{datatype},
					value=>$data{$column{column}},
					required=>$required,
					templated=>1,   ### ???
					simplename=>$opt->{simplename},
					);
	}
	elsif (defined $data{$column{column}}) {
	    # Only include hidden columns if they contain meaningful data.
	    # But, do not resubmit existing data on updates, unless it's 
	    # the primary key.
	    if ($this->{action} ne "update" || $column{column} eq $pkey) {
		$data{$column{column}} =~ s/\"/&\#34;/g;
		my $name = $opt->{simplename} ?
		    "$column{column}" :
		    "${table}${sc}${record}${sc}$column{column}";
		$out .= $this->form()->input(
					     type=>"hidden",
					     name=>$name,
					     value=>$data{$column{column}},
					     );
	    }
	}
    }
    return $out;
}

=pod

=head2 C<input_column(%opt)> - make the input tag(s) for a database column

Generates the HTML input tag(s) corresponding to a single database
column.  C<%opt> is an option hash (not a ref, as in C<input_record()>).
The input label is not generated.

For some datatypes, a single column may result in multiple input
fields (eg. dates, which prompt for year, month, and day separately.)
In cases where multipart input fields are generated, ExSite appends 
a part marker to the input field name, eg. C<input_name#part>.  It is
the responsibility of the decoding routines to patch these parts 
back together into a single input value.  The automatic form processing
tools above do this for you.

Options:

=over 4

=item C<table> 

the table the value belongs to

=item C<column> 

the column the value belongs to

=item C<record> 

the record ID of the record the value belongs to (for updates)

=item C<value> 

the value of the column.

=item C<data> 

a datahash for the record, from which the C<record> and
C<value> can be inferred, if not passed explicitly.

=item C<datatype> 

the datatype that should be used to determine the
input rules for this column.  This defaults to the value indicated by
the DBmap, and is not normally required unless you want to override
the map.

=item C<size> 

the size of the allowed data, used to determine the
dimensions of the input field.  This defaults to the value indicated by
the DBmap, and is not normally required unless you want to override
the map.

=back

Note: no security checks are made on C<input_column()>;  if using this
routine to generate custom forms, you must decide for yourself
whether the user is allowed to alter the column in question.

=cut

sub input_column {
    my ($this,%opt) = @_;

    # fetch the datatype, if required
    if (! $opt{datatype}) {
	$opt{datatype} = $this->{map}->get_column_attr($opt{table},$opt{column},"datatype");
    }

    # set size and maxlength
    my $dblen = $this->{map}->get_column_attr($opt{table},$opt{column},"size");
    $opt{size} or $opt{size} = $dblen;
    if (! $opt{maxlength}) {
	if ($opt{datatype} =~ /^(string|email|url|int|password|filepath)$/) {
	    $opt{maxlength} = $dblen;
	}
	elsif ($opt{datatype} =~ /^(decimal|money)$/) {
	    $opt{size} =~ /^(\d*)/;
	    $opt{maxlength} = $1;
	}
    }

    # custom handler
    my $out = $this->run_handler("input_column",%opt);
    return $out if ($out);

    if ($opt{data}) {
	if (! $opt{record}) {
	    $opt{record} = $opt{data}->{$this->get_key($opt{table})};
	}
	if (! $opt{value}) {
	    $opt{value} = $opt{data}->{$opt{column}};
	}
    }
    elsif (! $opt{record} && ! $opt{value} && $this->{action} ne "search") {
	# blank form - use default values, if any
	my $dflt = $this->{map}->get_column_attr($opt{table},$opt{column},"default");
	if ($dflt) { $opt{value} = $dflt; }
    }

    my $sc = $config{form}{sepchar};
    if (! $opt{name}) {
	$opt{name} = $opt{simplename} ?
		    "$opt{column}" :
		    "$opt{table}${sc}$opt{record}${sc}$opt{column}";
	#$opt{name} = "$opt{table}${sc}$opt{record}${sc}$opt{column}";
    }
    if (! $opt{prompt}) {
	$opt{prompt} = $this->{map}->get_column_attr($opt{table},$opt{column},"label");
    }
#    if (! $opt{tail}) {
	# add help text
	my $helpfile = "$config{server}{CGIroot}/$config{server}{map}{name}/help/$opt{table}/$opt{column}";
	if (-e $helpfile) {
	    $opt{tooltip} = &get_file($helpfile);
	}
#	$opt{tail} = $this->helplink($opt{table},$opt{column},"hint",1);
#    }

    # translations

    $opt{prompt} = $msg{$opt{prompt}};

    ### required flag?

    # generate the actual input field

    return $this->input_exsite(%opt);
}

=pod

=head2 C<input_exsite(%opt)> - make the input tag(s) for an ExSite datatype

Generates the HTML input tag(s) corresponding to an ExSite datatype.

This works similarly to C<input_column()>, except that we have no
database data or DBmap metadata to tell us about the column, so we
have to provide values, datatypes, input sizes, and other values manually.

=head3 General Input Options:

=over 4

=item datatype 

the ExSite datatype of the input

=item name

the name of the input

=item value

the default value of the input

=back

=head3 Datatype-specific Input Options:

B<date/datetime>

=over 4

=item null_date_type 

"today" or "null" (indicates how to preset date inputs, if no preset is provided)

=item date_input_format

"simple", "picker", or "select" (determines the input method)

=back 

B<time/datetime>

=over 4

=item minstep

minutes increment for minutes option menu (default is 15 minute increments)

=back

B<set>

=over 4

=item dummy

value to use for the dummy set indicator.  This is a dummy
hidden input used to flag the presence of a set input.  Set inputs are a
series of checkboxes, but if none are checked, the checkboxes do not appear
in the form data at all.  This can make it difficult for the form processing 
routines to determine whether a required set input was left blank, or if
it was not in the original form at all.  The dummy set input is always 
present, and tells the form processing code that checkboxes were present
even if none were checked.

=back

B<foreign keys>

=over 4

=item fmatch

match hash to select foreign keys to select from

=item table

table this form is for

=item column

the column in this table containing the foreign reference

=item record

the id of the record containing the data being modified

=item ftable

foreign table being referred to

=back 

B<encrypted fields>

=over 4

=item table

table this form is for

=item column

the column being encrypted

=item record

the id of the record containing the encrypted value

=back

Note: no security checks are made on C<input_exsite()>;  the form
processing routines are responsible for security validation of
the form data.

=cut

sub input_exsite {
    my ($this,%opt) = @_;
    my $out = $this->run_handler("input_exsite",%opt);
    if ($out) {
	if ($opt{type} eq "file") {
	    # switch to multipart encoding to accept full file uploads
	    $this->form()->multipart();
	}
	# We let FormBuilder compose the tag.
	$opt{input} = $out;
	return $this->form()->input(%opt);
    }

    my $sc = $config{form}{sepchar};
    if ($opt{datatype}) {
	if (ref $opt{datatype}) {
	    $_ = $opt{datatype}->{type};
	}
	elsif ($opt{datatype} =~ /^key[:=]/) {
	    $_ = $opt{datatype};
	    $opt{datatype} = $this->{map}->get_datatype("key");
	}
	else {
	    $_ = $opt{datatype};
	    $opt{datatype} = $this->{map}->get_datatype($_);
	}
    }
    else {
	return $this->error("ExSite::Form::input_exsite: no datatype specified");
    }

    # set &input_html options
    my %htmlopt = %opt;
    my @opt;
    if ((/^o?list:/ && $opt{datatype}->{tag} eq "select") ||
	(/^set:/ && $this->{action} eq "search")) {
	push @opt, ["", $msg{"== select =="}];
	foreach my $opt (split /\|/,$opt{datatype}->{regexp}) {
	    push @opt, [ $opt, $opt ];
	}
	$htmlopt{options} = \@opt;
	if (/^set:/ && $this->{action} eq "search") {
	    # switch to list
	    $opt{datatype}{tag} = "select";
	}
    }
    elsif (/^(o?list|set):/) {
        my @opt = split /\|/,$opt{datatype}->{regexp};
        $htmlopt{options} = \@opt;
    }
    elsif (/^enum:/) {
        my @opt = split /\|/,$opt{datatype}->{regexp};
	my @inopt = ["", $msg{"== select =="}];
	foreach my $opt (@opt) {
	    my ($num,$val) = split /:/,$opt,2;
	    push @inopt, [ $num, $val ];
	}
        $htmlopt{options} = \@inopt;
    }
    $htmlopt{type} = $opt{datatype}->{tag};

    # new generate the inputs

    if (/^readonly$/) {
	return $opt{value};
    }
    if (/^html$/ && $this->{action} !~ /search/) {
	return $this->input_htmleditor(%opt);
    }
    elsif (/^(medium|f)?text$/ || (/^html$/)) {
	if ($htmlopt{size} > $config{form}->{max_cols} &&
	    $this->{action} !~ /search/) {
	    # use textarea for large inputs, unless searching
	    $htmlopt{type} = "textarea";
	}
	else {
	    $htmlopt{type} = "text";
	}
	return $this->input_html(%htmlopt);
    }
    elsif (/^crypt$/) {
	# similar to text, but decrypt the data first
	# abort if we're not allowed to view the data
	if ($htmlopt{value}) {
	    my $data = $this->decrypt_column($htmlopt{value},
					     $htmlopt{table},
					     $htmlopt{record},
					     $htmlopt{column});
	    if ($this->errorcheck("warn")) {
		return $this->ml->span("This field contains encrypted data, which you do not have permission to decrypt and edit.", { class=>"error" });
	    }
	    $htmlopt{value} = $data;
	}
	# use text logic
	if ($htmlopt{size} > $config{form}->{max_cols} ||
	    $this->{action} !~ /search/) {
	    # use textarea for large inputs, unless searching
	    $htmlopt{type} = "textarea";
	}
	else {
	    $htmlopt{type} = "text";
	}
	return $this->input_html(%htmlopt);
    }
    elsif (/^list:/ || (($this->{action} eq "search") && /^set:/)) {
	$out .= $this->input_html(%htmlopt);
    }
    elsif (/^olist:/) {
	my $name = "$htmlopt{name}#list";
	my $value = $htmlopt{value};
	my $input = $this->form->select(
					name=>$name,
					options=>$htmlopt{datatype}{regexp},
					nullvalue=>"== select ==",
					value=>$value,
					);
	$name = "$htmlopt{name}#other";
	if ($value =~ /^$htmlopt{datatype}{regexp}$/) {
	    $value = undef;
	}
	$input .= $msg{Other}.":&nbsp;".
	    $this->form->inputtag(
				  name=>$name,
				  type=>"text",
				  value=>$value,
				  size=>10,
				  );
	$htmlopt{input} = $input;
	$out .= $this->input_html(%htmlopt);
    }
    elsif (/^set:/) {
	# multipart input
	$opt{type} = "checkbox";
	my @values = split /; /,$opt{value};
	my $n = 0;  # dummy set item differentiator
	# dummy set input - to ensure set is represented in form data,
	# even if all items are deselected
	my $name = $opt{name};
	$out = $this->form()->inputtag(type=>"hidden",
				       name=>"$name${sc}_set_$n",
				       value=>"$opt{dummy}");
	my $stack = (scalar @{$htmlopt{options}} >= $config{form}{stack_checkboxes});
	foreach my $item (@{$htmlopt{options}}) { 
	    $n++;
	    my %setopt = (type=>"checkbox", name=>"$htmlopt{name}${sc}_set_$n", value=>$item, label=>$item);
	    my $item_re = quotemeta $item;
	    if (grep(/^$item_re$/,@values) > 0) { $setopt{checked} = 1; }
	    $out .= $this->form()->inputtag(%setopt);
	    if ($stack) { $out .= $this->ml->br; }
	}
	$opt{input} = $out;
	if ($opt{required} > 0) { $opt{required} = -1; }
	$out = $this->form()->input(%opt);
    }
    elsif (/^date(:(\w+))?$/) {
	my $datefmt = $2;
	if ($datefmt) { $htmlopt{date_input_format} = $datefmt; }
	return $this->input_date(%htmlopt);
    }
    elsif (/^time$/) {
	return $this->input_time(%htmlopt);
    }
    elsif (/^datetime(:(\w+))?$/) {
	my $datefmt = $2;
	if ($datefmt) { $htmlopt{date_input_format} = $datefmt; }
	my ($dval,$tval) = split(/ /,$opt{value});
	my $tail = $htmlopt{tail};
	my $name = $htmlopt{name};
	$htmlopt{value} = $dval;
	$htmlopt{datatype} = "date";
        $htmlopt{tail} = ",&nbsp;&nbsp;&nbsp;";
	$out = &input_exsite($this,%htmlopt);
	$htmlopt{value} = $tval;
	$htmlopt{datatype} = "time";
        $htmlopt{tail} = $tail;
        $htmlopt{name} = $name;
	$out .= &input_exsite($this,%htmlopt);
	return $out;
    }
    elsif (/^key[:=]/) {
	my (undef,$ftable) = split /[:=]/;
	my $rdata;
	my $select_key = 1;
	$htmlopt{type} = "select";
	if (scalar keys %{$opt{fmatch}}) {
	    # select only form foreign rows matching the match hash
	    $rdata = $this->fetch_match($ftable,$opt{fmatch});
	}
	else {
	    # check if a handler has been provided to filter appropriate
	    # foreign keys to choose from
	    if (! $opt{table}) {
		($opt{table},$opt{record},$opt{column},undef) = 
		    split /$config{form}{sepchar}/,$opt{name};
	    }
	    $rdata = $this->run_handler("select_foreign_key",$opt{table},$opt{record},$opt{column},$ftable);
	    if (ref $rdata ne "ARRAY") {
	    	# nothing!
	    	# select from all foreign rows - could be dangerous
		# count the rows first
		my $n_ftable = $config{form}{max_foreign_key_select} ?
		    $this->count($ftable) : 0;
		if ($n_ftable <= $config{form}{max_foreign_key_select}) {
		    $rdata = $this->fetch_all($ftable);
		    # trim the data, by choosing only rows that are owned
		    # by the current user
		    if (! $this->is_admin) {
			my $rdata_owned = [];
			my $key = $this->get_key($ftable);
			foreach my $d (@$rdata) {
			    if ($this->user_owns($ftable,$d->{$key})) {
				push @$rdata_owned, $d;
			    }
			}
			$rdata = $rdata_owned;
		    }
		}
		else {
		    # too many records; don't use a select control
		    $rdata = [];
		    $select_key = 0;
		}
	    }
	}
	# make the menu
	my @options;
	if (! $select_key) {
	    $htmlopt{type} = "text";
	    $opt{no_name_modifier} = 1;
	}
	elsif (@$rdata == 0) {
	    my $title = $this->{map}->table_title($ftable,1);
	    push @options, [0, "WARNING: no $title defined!"];
	}
	else {
	    # sort the foreign keys
	    my @sort_key = $this->primary_column($ftable);
	    my @data = $this->sort_rows($ftable,$rdata,@sort_key);
	    my @show = $this->primary_column($ftable);
	    my $key = $this->get_key($ftable);
	    my $title = $this->{map}->table_title($ftable,0);
	    push @options, ["", &substitute("== select [[title]] ==",{title=>$title})];
	    foreach my $dat (@data) {
		my $label = $this->run_handler("select_foreign_key_label",
					       $ftable,$dat,$key,@show);
		if (! $label) {
		    foreach my $col (@show) {
			$label .= "$dat->{$col} ";
		    }
		    # can optionally add IDs to distinguish between similar records
		    if ($config{form}{show_foreign_key_id}) {
			$label .= "[$dat->{$key}]";
		    }
		}
		push @options, [$dat->{$key}, $label];
	    }
	}
	if (! $opt{no_name_modifier}) { $htmlopt{name} .= "#key"; }
	$htmlopt{options} = \@options;
	$out = $this->input_html(%htmlopt);
	return $out;
    }
    elsif (/^money$/) {
	$htmlopt{head} = "\$";
	$htmlopt{size}=8;   ### use config value?
	$out .= $this->input_html(%htmlopt);
	return $out;
    }
    elsif (/file$/) {
	my $name = $htmlopt{name};
	my $value = $htmlopt{value};
	$htmlopt{name} = "$name#filename";
	# not meaningful at this time to pass a value for file fields, and it
	# just clogs the page with Mime-encoded file data.
	$htmlopt{value} = undef;
	if ($htmlopt{size} > 100) { $htmlopt{size} = $config{form}{max_cols}; }
	$out .= $this->input_html(%htmlopt);
	if ($value) {
	    # we need to kludge the input field to add a checkbox for clearing
	    # the image;  we do this using the "append" hack in FormBuilder
	    my %rmopt = %htmlopt;
	    $rmopt{append} = $htmlopt{name};
	    $rmopt{name} = "$name#clear";
	    $rmopt{type} = "checkbox";
	    $rmopt{value} = "remove this file";
	    my $br = $this->ml()->br();
	    my $rmout = "${br}$msg{currently}:$br".
		$this->show_data($htmlopt{table},$htmlopt{column},
				 $value,$htmlopt{record}).
		$br.$msg{'Remove this file'}.": ".
		$this->ml->input(undef,{value=>"remove this file", name=>"$name#clear", type=>"checkbox"});
	    $rmopt{input} = $rmout;
	    delete $rmopt{tail};
	    $this->input_html(%rmopt);
	    $out .= $rmout;
	}
    }
    elsif (/^fixed$/) {
	$htmlopt{type} = "hidden";
	#$htmlopt{type} = "text";
	#$htmlopt{readonly} = 1;
	$htmlopt{value} = $this->{map}->get_column_attr($htmlopt{table},
							$htmlopt{column},
							"default");
	$out .= $this->input_html(%htmlopt);
    }
    elsif (/^password$/) {
	my $type = $config{auth}{password_storage_method};
	if ($this->level >= $config{auth}{password_access}) {
	    $htmlopt{type} = "text";
	    if ($type ne "cleartext") {
		$htmlopt{tail} .= $this->warn($msg{"Password is encrypted; editing this value may make the password unusable."});
	    }
	    $out .= $this->input_html(%htmlopt);
	}
	else {
	    if ($type eq "cleartext") {
		$out .= $this->input_html(%htmlopt);
	    }
	    else {
		$htmlopt{type} = "preformatted";
		$htmlopt{input} = $this->warn($msg{"Password is encrypted and cannot be edited from this screen."});
		$out .= $this->input_html(%htmlopt);
	    }
	}
    }
    else {
	$out .= $this->input_html(%htmlopt);
    }
    return $out;
}

# input_date: dates are compound fields (three separate inputs, which are
# aggregated by parse() into a single datum).  This requires some special 
# treatment.

sub input_date {
    my ($this,%opt) = @_;
    my $out = $this->run_handler("input_date",%opt);
    return $out if ($out);
    my $ml = &get_obj("ML");
    my $sc = $config{form}{sepchar};
    my $datefmt = $opt{date_input_format} || $config{form}{date_input_format};
    if ($datefmt eq "simple") {

	# use a simple text field to accept a fully-formatted date

	$opt{placeholder} = "YYYY-MM-DD";
	$opt{type} = "text";
	$opt{size} = 12;
	return $this->form()->input(%opt);
    }
    elsif ($datefmt eq "picker") {

	# use a JS date picker - good for dates close to the current date

	$opt{placeholder} = "YYYY-MM-DD";
	$opt{type} = "text";
	$opt{class} = "date-pick";
	$opt{size} = 12;
	if (! $share{datePicker}) {
	    # should include the datePicker code once on the page
	    $share{datePicker} = 1;
	    my $head;
	    $head .= &insert_js("date.js");
	    $head .= &insert_js("jquery.datePicker.js");
	    $head .= $ml->link(undef,{rel=>"stylesheet",type=>"text/css",media=>"screen",href=>"$config{server}{HTMLpath}/_ExSite/css/datePicker.css"});
	    $head .= $ml->script("Date.firstDayOfWeek = 0;\nDate.format = 'yyyy-mm-dd';\n\$(function() {\n\$('.date-pick').datePicker({startDate:'$config{form}{date_picker_start_date}'});\n});\n",
				 {type=>"text/javascript",charset=>"utf-8"});
	    $opt{head} = $head;
	}
	my $name = $opt{name};
	$opt{name} = "$name${sc}date";
	$out .= $this->form()->inputtag(%opt);
	$opt{name} = $name;
	$opt{input} = $out;
	return $this->form()->input(%opt);
    }
    else {
	
	# use selectors to pick Y, M, D separately

	if (! $opt{null_date_type}) { 
	    $opt{null_date_type} = $config{form}->{default_date}; 
	}
	# value must be in YYYY-MM-DD format
	my ($year,$month,$day);
	if ($opt{value}) {
	    ($year,$month,$day) = split(/-/,$opt{value});
	    if ($month =~ /^0[1-9]$/) {
		# chomp that leading 0 so we can use string equiv operators
		$month = substr($month,1,1);
	    }
	}
	else {
	    if ($opt{null_date_type} eq "today" || $opt{required}) {
		(undef,undef,undef,$day,$month,$year,undef,undef,undef) =
		    localtime(time);
		$month += 1;
		$year += 1900;
	    }
	    else {
		# use null date by default
		$year = 0;
		$month = 0;
		$day = 0;
	    }
	}

	my ($imonth, @months);
	$imonth = 0;
	foreach my $mname (@ExSite::Report::month_name) {
	    push @months, [$imonth,$mname];
	    $imonth++;
	}
	$out = $this->form()->select(name=>"$opt{name}${sc}month",
				     options=>\@months,
				     value=>$month);
	if ($config{form}{day} eq "select") {
	    $day =~ s/^0+//; # ensures we preselect the right day
	    $out .= $this->form()->select(name=>"$opt{name}${sc}day",
					  options=>[[0,$msg{"(day)"}],1..31],
					  value=>$day);
	}
	else {
	    $out .= $this->form()->inputtag(type=>"text",
					    name=>"$opt{name}${sc}day",
					    size=>2,
					    value=>$day);
	}
	$out .= ",&nbsp;";
	if ($config{form}{year} eq "select") {
	    my @date = localtime(time);
	    my $this_year = $date[5] + 1900;
	    my $base_year = ($year && $year !~ /^0+$/) ? $year : $this_year;
	    my $range = $config{form}{year_range};
	    my $uprange = $config{form}{year_uprange} || $range;
	    my $downrange = $config{form}{year_downrange} || $range;
	    my $start_year = $base_year < ($this_year - $downrange) ? 
		$base_year : $this_year - $downrange;
	    my $end_year = $base_year > ($this_year + $uprange) ? 
		$base_year : $this_year + $uprange;
	    $out .= $this->form()->select(name=>"$opt{name}${sc}year",
					  options=>[[0,$msg{"(year)"}],$start_year..$end_year],
					  value=>$year);
	}
	else {
	    $out .= $this->form()->inputtag(type=>"text",
					    name=>"$opt{name}${sc}year",
					    size=>4,
					    value=>$year);
	}
	$opt{input} = $ml->span($out,{class=>"dateInput"});

	# turn off JS validation of dates, because the basic JS validation 
	# cannot handle the multipart date fields
	$opt{required} = - $opt{required};

	return $this->form()->input(%opt);
    }
}

sub input_time {
    my ($this,%opt) = @_;
    my ($hour,$min,$ampm);
    my $ml = &get_obj("ML");
    my $use_24hr_clock = ($config{form}{clocktype} == 24);
    my $sc = $config{form}{sepchar};
    if ($opt{minstep} <= 0) { $opt{minstep} = $config{form}{minstep}; }
    if (defined $opt{value} && $opt{value} !~ /^0?0:00:00$/) {
	($hour,$min,undef) = split(/:/,$opt{value});
	$ampm = ($hour >= 12 ? $config{form}{pm} : $config{form}{am});
    }
    else {
	$min = "00";
	$hour = $use_24hr_clock ? "00" : "12";
	$ampm = $config{form}{am};
    }
    my $hour2 = $hour > 12 ? $hour - 12 : $hour;
    $hour2 =~ s/^0//;
    
    my @hours = $use_24hr_clock ? 
	(0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23) :
	(1,2,3,4,5,6,7,8,9,10,11,12);
    my $out = $this->form()->select(name=>"$opt{name}${sc}hour",
				 options=>\@hours,
				 value=> $use_24hr_clock ? $hour : $hour2);
    $out .= ":";
    my @minutes;
    for (my $i = 0; $i < 60; $i += $opt{minstep}) {
	push @minutes, sprintf "%02d",$i;
    }
    $out .= $this->form()->select(name=>"$opt{name}${sc}min",
				  options=>\@minutes,
				  value=>$min);
    if (! $use_24hr_clock) {
	$out .= $this->form()->select(name=>"$opt{name}${sc}ampm",
				      options=>[$config{form}{am},$config{form}{pm}],
				      value=> $ampm);
    }
    $opt{input} = $ml->span($out,{class=>"timeInput"});
    return $this->form()->input(%opt);
}

=pod

=head2 input_html(%opt) - generate a single HTML input tag

This method outputs the tags for a single HTML form input.

Options:

=over 4

=item name

the input field name

=item type

the HTML input type (eg. text, radio, textarea, select, ...)

=item value

the default preset input value

=item size

the width of the input field

=item readonly

prevent editing of the field, if true

=item rows

height of a textarea input

=item cols

width of a textarea input

=item options

for selector inputs (radios, selects), an array of possible
input values, formatted as:

=over 4

=item * array of simple values, or

=item * array of array references containing [ actual form value, human-readable value ], or

=item * array of hash references containing { actual form value => human-readable value }

=back

=back

=cut

#--------------------------------------------------------------------
# input_html : generate an HTML input tag
#--------------------------------------------------------------------

sub input_html {
    my ($this,%opt) = @_;
    if (! $opt{name}) {
	return $this->error("ExSite::Form::input_html: unnamed input");
    }
    if ($opt{type} eq "file") {
	# switch to multipart encoding to accept full file uploads
	$this->form()->multipart();
    }
    # We let FormBuilder compose the tag.
    return $this->form()->input(%opt);
}

#-------------------------------------------------------------------
# use_wysiwyg : check the client's browser for wysiwyg editor compatability
#-------------------------------------------------------------------
sub use_wysiwyg {
    my $this = shift;
    return 1;
}

=pod

=head2 C<input_htmleditor(%opt)> - place an HTML editor into a form

The editable content is specified as one of:

=over 4

=item table, record, column

a field in the database

=item file

a path to a file on disk

=item url

an external URL (this in no way implies that we can save over
the external URL)

=back

Other Options:

=over 4

=item value

the HTML to edit

=item name

the name of the input that will hold the HTML

=item editor_height, editor_width

the dimensions (pixels) of the editor's IFRAME

=item complete_html_content

if true, edits everything inside the
E<lt>htmlE<gt> tags.  Otherwise, edit everything inside the
E<lt>bodyE<gt> tags.

=item editor

ref to a hash of editor options to override those in C<$config{htmleditor}>

=back

=cut

sub input_htmleditor {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    my $sc = $config{form}{sepchar};
    my $value = $opt{value};
    my $input_name = $this->{htmleditor} = $opt{name}."#html";
    my ($table,$record,$column,$section_id);
    if ($opt{table}) {
	$table = $opt{table};
	$record = $opt{record};
	$column = $opt{column};
	$section_id = $opt{section};
    }else {
	($table,$record,$column) = split(/$sc/,$opt{name});
    }
    # Find section_id
    if (!$section_id){
	if ($share{Section}) {
	    $section_id = $share{Section}->id;
	}
	elsif ($record && $table eq "content_data"){
	    require ExSite::ContentData;
	    my $cd = new ExSite::ContentData(id=>$record);
	    $cd->set_context();
	    $section_id = $cd->id("section");
	}elsif ($opt{page}){
	    require ExSite::Page;
	    my $cd = new ExSite::Page(id=>$opt{page});
	    $cd = $cd->get();
	    $section_id = $cd->{section_id}
	}
    }
    # Fetch content
    if ($table && $column && $record){
	if (! $this->{map}->is_mapped($table)) {
	    $this->{map}->load_submaps();
	    if (! $this->{map}->is_mapped($table)) {
		return "Error - no such table as ".$ml->strong($table);
	    }
	} 
	if ($record  && $table eq "content_data") {
	    # potential for CMS substitutions
	    require ExSite::ContentData;
	    my $cdata = new ExSite::ContentData(id=>$record);
	    if ($cdata->content_type() eq "text/html") {
		# expand the content so it looks more realistic in the editor
		# - use dummy placeholders for content, modules so that we
		#   know how to convert them back to tags
		# - use real URL replacements, which look better, but use
		#   dynamic mode so we know how to convert them back to tags
		$value = $cdata->expand(method=>"url,dummy-page,dummy-content,dummy-module",mode=>"dynamic");
	    }
	}elsif ($record =~ /^\d+$/){
	    my %data = $this->fetch($table,$record);
	    if (! exists $data{$column}) {
		return "Error - cannot retrieve column ".$ml->strong($column)." in table ".$ml->strong($table)." where ".$ml->strong("id=${record}").$ml->br()."You do not have permission to access this data.";
	    } 
	    $value = $data{$column};
	}
    }

    my $content_id = 0;
    if ($share{Content}){
	$content_id = $share{Content}->id || 0;
    }
    if (!$content_id){
	my $i = new ExSite::Input;
	my $in = $i->combine;
	$content_id = $in->{id} || 0;
    }
    
    require ExSite::Dialog;
    my $tinymce = new ExSite::Dialog::TinyMCE();
    my $tsetting = $tinymce->setting(\%opt,$content_id);

    my $input_id = &safetext($input_name);
    require JSON;
    my $out;
    $out .= &insert_js("jquery");
    $out .= &insert_js("jqueryui");

    $tsetting->{init}{selector} = "textarea#${input_id}";
    $out .= $tinymce->css;
    $out .=  $ml->script("tinymce.init(".JSON::to_json($tsetting->{init}).");").$ml->textarea($value,{id=>$input_id,cols=>$config{form}{max_cols},rows=>$config{form}{max_rows},name=>$input_name});

    # add this to the form under construction
    $opt{input} = $out;

    my $required = $opt{required};
    $opt{required} = -1 if ($opt{required} > 0);

    $this->form()->input(%opt);

    # 3rd-party callers can give us their form object in %opt, 
    # so we can auto-patch it for the HTML editor
    my $form = $opt{form} || $this->form();
    
    # include the CSS and JS to run the editor
    $form->set("head",$this->editor_javascript(undef,$tsetting->{conf}));

    # return the basic editor HTML for do-it-yourself programs
    return $out;
}

=pod

=head2 C<editor_javascript($section_id)> 

Returns the javascript that is needed to enable the HTML editor functions.
This is automatically invoked by C<input_htmleditor()>, but may have to be 
manually inserted into custom forms to enable the editor.  The C<$section_id> 
argument is required by certain dialogs (link, image) if you want to 
automatically fetch pages and images to work with.

=cut

sub editor_javascript {
    my ($this,$cnfg) = @_;
    my $ml = &get_obj("ML");
    require ExSite::Dialog;
    my $tinymce = new ExSite::Dialog::TinyMCE();
    return $ml->script($tinymce->jq_detect,{type=>"text/javascript"}).$ml->script("",{type=>"text/javascript",src=>"$config{server}{server}$config{server}{HTMLpath}$config{form}{tinymce}{path}/".($cnfg->{file} || $config{form}{tinymce}{file})});
}

1;
