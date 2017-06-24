#------------------------------------------------------------------------
# ExSite::Report
#----------------------------------------------------------------------------
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

=pod 

=head1 ExSite::Report - general purpose tools for displaying database data

The Report class inherits from the DB and Auth classes, and is in turn
inherited by the Form class.  This help document describes only the
methods that are unique to the Report class.  Consult the docs for
inherited classes to read about inherited methods.  Code that requires
write access to the database will typically work with the Form class,
but read-only access can use a Report object instead.

Usage:  C<my $db = new ExSite::Report;>

By default, ExSite connects to its default database, which contains all the
web content data.  You can connect to an alternate database using a call like
this:

C<my $db = new ExSite::Report(type=E<gt>"sql",name=E<gt>"mydb",map=E<gt>"mapname",user=E<gt>"username",pass=E<gt>"password");>

=cut

package ExSite::Report;
use strict;
use ExSite::Config;
use ExSite::DB;
use ExSite::ReportBuilder;
use ExSite::Misc;
use ExSite::HTML;
use ExSite::ML;
use MIME::Base64;

# globals:
# @ISA : inheritor
# %use_button : db ops image buttons
# $total_records_in_query : number of records found by most recent query
# @month_name, @month_days : basic calendar definitions

use vars qw(@ISA %use_button $total_records_in_query @row_class
	    @month_name @month_days);

@ISA = qw(ExSite::DB);

@row_class = ( "A", "B" );

@month_name = ( "(month)", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" );

@month_days = ( 0, 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 );

=pod 

=head2 Obtaining Meta-data for Tables

=head3 C<primary_column()> - select the primary display column(s)

Usage: C<$db-E<gt>primary_column($table)>

From a reporting point of view, the primary display column is the
column whose data best represents the record from a human point of
view.  This column will be used to make record titles, and hotlinks to
the record.

This is not the same as the primary key, which is the column that best
represents the record from the computers point of view.  For example,
in a "person" record, the computer's primary key will probably be a
numeric record ID, whereas the human-readable primary display column
will probably be the person's name.  However, if no primary display
column is defined, the primary key will be used by default.

More than one primary display column can be defined in the DBmap, in
which case an array of column names will be returned,
eg. ("first_name","last_name").

=cut

sub primary_column {
    my ($this,$table) = @_;
    my @primary = ();
    my $choice2 = "";
    my $map = $this->{map}->get_map($table);
    # select column to display - use key column by default
    my $ncol = $this->{map}->get_ncol($table);
    for (my $i = 0; $i < $ncol; $i++) {
	if ($map->{display}->[$i] eq "key") {
	    # this is marked as a key column
	    push @primary, $map->{column}->[$i];
	}
    }
    if (@primary > 0) {
	#
	# If called in array context, return all primary display columns.
	# Otherwise, return either the first or last.
	#
	if (wantarray) { return @primary; }
	else { return $config{report}{use_first_key} ?
		   $primary[0] : $primary[-1]; }
    }
    # nothing suitable, use the primary key
    return $this->get_key($table);
}

=pod 

=head3 C<title()> - returns a title for a particular record

Usage: C<$db-E<gt>title($table,$record,$rdata)>

Given a table name (C<$table>), a record ID (C<$record>), and a hash ref
pointing to the record data (C<$rdata>), this routine will compose an 
appropriate title for the record, using the table's primary display
column(s).  The record title is typically:

I<TABLE_NAME "PRIMARY_DISPLAY_COLUMN">

For example, I<Member "John Doe">, or I<Website "Acme Software, Inc.">.

=head3 C<record_label()> - returns a label for a particular record

Usage: C<$db-E<gt>record_label($table,$record,$rdata)>

Same as C<title()>, above, but returns only the quoted part of the title.

=cut

sub title {
    my ($this,$table,$record,$rdata) = @_;
    my $table_title = $this->run_handler("report_title",$table,$record,$rdata);
    return $table_title if (defined $table_title);
    my %data;
    $table_title = $this->{map}->table_title($table);
    return $table_title if (! $record);
    my $label = $this->record_label($table,$record,$rdata);
    return "$table_title \"$label\"";
}

sub record_label {
    my ($this,$table,$record,$rdata) = @_;
    my %data;
    my @pcol = &primary_column($this,$table);
    if (defined $rdata) { %data = %$rdata; }
    else { %data = $this->fetch($table,$record); }
    my @dcol;
    my $goodlabel;
    foreach my $p (@pcol) {
	if ($config{report}{show_foreign_keys_in_record_labels} &&
	    $this->{map}->get_column_attr($table,$p,"datatype") =~ /^key[=:]/) {
	    my (undef,$ftable) = split /[:=]/,$this->{map}->get_column_attr($table,$p,"datatype");
	    push @dcol,$this->record_label($ftable,$data{$p});
	}
	else {
	    push @dcol,$data{$p};
	}
	if ($data{$p}) { $goodlabel = 1; }
    }
    return $goodlabel ? join(" ",@dcol) : "n/a";
}

=pod

=head2 Reporting Data Values

=head3 C<show_data()> - display individual database column values as HTML

The C<show_data()> methods format database column values as HTML
according to their datatype.  Web-enabled datatypes (emails, URLs) are
converted to links, machine-readable datatypes (timestamps, keys) are
converted to human-readable form, and other datatypes are preprocessed
for safe display in a browser.

B<Usage:>

=over 4

=item C<$db-E<gt>show_data($table,$column,$data,$id,$datatype);>

Standard version.  Does authorization checks to validate that the user
has permission to read the given data, and returns an error message if
not.  C<$id> is only needed for file datatypes, and C<$datatype> is
only needed if overriding the datatype in the DBmap.)

=item C<$db-E<gt>show_data_noauth($table,$column,$data,$id,$datatype);>

This version skips the authorization checks.  C<$id> is only needed
for file datatypes, and C<$datatype> is only needed if overriding the
datatype in the DBmap.)

=item C<$db-E<gt>show_data_nomap($datatype,$data);>

This version displays an arbitrary datum as a certain datatype, without
any assumption that the data comes from the database.

=back

B<Parameters:>

=over 4

=item $table

The table the datum comes from.

=item $column

The column the datum comes from.

=item $data

The datum value.

=item $id

The record ID of the record the datum comes from.  This is needed for file
(and bigfile) datatypes, which link back to the file itself.

=item $datatype

The datatype, if different from the default in the DBmap.

=back

=cut

sub show_data {
    my ($this,$table,$column,$data,$id,$datatype) = @_;

    # check permissions
    my $access = $this->authorize;
    my $read = $this->{map}->get($table,$column,"read");
    if ($read > $access) {
      return $config{report}{permission_denied};
    }

    # use handler, if one is defined
    my $out = $this->run_handler("show_data",$table,$column,$data,$id,$datatype);
    if (defined $out) { return $out; }

    return $this->show_data_noauth($table,$column,$data,$id,$datatype);
}

# show_data_noauth can be called directly to ignore DBmap security

sub show_data_noauth {
    my ($this,$table,$column,$data,$id,$datatype) = @_;
    
    # use handler, if one is defined
    my $out = $this->run_handler("show_data_noauth",$table,$column,$data,$id,$datatype);
    if (defined $out) { return $out; }    
    
    return "" if (! defined $data);
    my $ml = $this->ml;

    # get datatype
    $datatype or $datatype = $this->{map}->get($table,$column,"datatype");

    # Prepare data for browser display.
    $data =~ s/&quot;/\"/g; # quote conversion

    if ($datatype =~ /^url$/) {
	$data =~ s/^\s+//;
	my $ldata = $data;
	if ($data !~ /^(http|mailto):\/\//) { $ldata = "http://".$data; }
	return $ml->a($data,{href=>$ldata, target=>"_blank"});
    }
    elsif ($datatype =~ /^email$/) {
	if ($config{report}{email} eq "obfuscate") {
	    # attempt to hide the email address from spambots
	    return &ExSite::HTML::MailTo($data);
	}
	else {
	    # show the email address in plain sight
	    return $ml->a($data,{href=>"mailto:$data"});
	}
    }
    elsif ($datatype =~ /^money$/) {
	return 
	    $this->run_handler("show_data_money",$data,$table,$column,$id) ||
	    "$config{report}{currency_char}$data";
    }
    elsif ($datatype =~ /^key[:=]/) {
        # foreign key
	if ($data > 0) {
	    my $stat = $this->run_handler("show_foreign_key",
					  $table,$column,$data,$id,$datatype);
	    return $stat if ($stat);
	    # dereference foreign keys
	    my (undef,$ftable) = split /[:=]/,$datatype;
	    # look up foreign row
	    my %fdata = $this->fetch($ftable,$data);
	    my $fkey = $this->get_key($ftable);
	    return $this->record_label($ftable,$fdata{$fkey},\%fdata);
	    # linked foreign keys now done by handler
	}
	else {
	    return "n/a";
	}
    }
    elsif ($datatype =~ /^date(:\w+)?$/) {
        return "" if (!$data);
        my $t = new ExSite::Time($data,"sql_date");
        return $t->write($config{report}{date}{date});
	#my ($year,$mon,$day) = split /-/,$data;
	#return "$month_name[$mon] $day, $year";
    }
    elsif ($datatype =~ /^time$/) {
        return "" if (!$data);
        my $t = new ExSite::Time($data,"time24");
        return $t->write($config{report}{date}{time});
    }
    elsif ($datatype =~ /^datetime/) {
        return "" if (!$data);
        my $t = new ExSite::Time($data,"sql_datetime");
        return $t->write($config{report}{date}{datetime});
    }
    elsif ($datatype =~ /^timestamp$/) {
      my $t = new ExSite::Time($data,"sql_timestamp");
      return $t->write($config{report}{date}{timestamp});
    }
    elsif ($datatype =~ /^crypt$/) {
	return $this->decrypt_column($data,$table,$id,$column);
    }
    elsif ($datatype =~ /^(medium)?text$/) {
	$data = $this->clean_text($data);
	if ($config{report}{text}{honor_nl}) {
	    my $br = $ml->br();
	    $data =~ s/\n/$br\n/g;       # convert NL to <br>
	}
	else {
	    # insert paragraph tags at any multiple-linebreaks
	    my $nsub;
	    $nsub = ($data =~ s/(\S)(\r\n){2,}(\S)/$1<\/p>\n<p>$3/g);   # handles CR-LF linebreaks
	    $nsub += ($data =~ s/(\S)\n{2,}(\S)/$1<\/p>\n<p>$2/g);      # handles LF linebreaks
	    if ($nsub) { $data = $ml->p($data); }
	}
	return $data;
    }
    elsif ($datatype =~ /^ftext$/) {
	# formatted text
	$data = $this->clean_text($data);
	return $ml->pre($data);
    }
    elsif ($datatype =~ /^html$/) {
	return $this->clean_text($data,2);
    }
    elsif ($datatype =~ /^enum:/) {
	my $re = $this->{map}->regexp($datatype);
        my @opt = split /\|/,$re;
	my %enum;
	foreach my $opt (@opt) {
	    my ($num,$val) = split /:/,$opt,2;
	    $enum{$num} = $val;
	}
	return $enum{$data};
    }
    elsif ($datatype =~ /^(big)?file$/) {
        # The data value for file fields is the record id.
        # fetch the datum:
        #my %fdata = $this->fetch($table,$data);
	if (!$data) { return ""; }
	my ($name,$content) = split /$config{form}->{sepchar}/,$data,2;
	if (!$name) { $name = "download"; }
	$name = &clean_filename($name);
	# guess the mime-type
	my $mimetype = &MimeType($name);
	# estimate the size
	# (multiply by 6/8 to account for Mime base64 encoding overhead)
	my $size = int(length($content)*6/8/100)/10;

	# show the file itself
	if ($config{show_images} && $mimetype =~ /^image\/(gif|png|jpeg)$/) {
	    return $ml->img(undef,{src=>"$config{server}->{CGIpath}/$config{prog}{getdata}/$name?tab=$table&id=$id&col=$column"});
	    ### no dimensions to image in general case...
	}
	else {
	    # Display a link to download the data.
	    if ($size) {
		return $ml->a($name,{href=>"$config{server}->{CGIpath}/$config{prog}{getdata}/$name?tab=$table&id=$id&col=$column"}).
		    "&nbsp;($mimetype,&nbsp;$size&nbsp;K)";
	    }
	    else {
		$this->warn("0-length file in $table:$id:$column");
		return "$name";
	    }
	}
    }
    elsif ($datatype =~ /^filepath$/) {
        # filepath is the path to a file on the local server
	if (!$data) { return ""; }
	if (-e $data) {
	    my @path = split /\//, $data;
	    # guess the mime-type
	    my $mimetype = &MimeType($path[-1]);
	    my $size = int ((-s $data)/100)/10;
	    # show the file path, type, and size
	    if ($this->authorize >= $config{auth}->{root_auth_level} - 1) {
		return "$data ($mimetype, $size K)";
	    }
	    else {
		return "$path[-1] ($mimetype, $size K)";
	    }
	}
	else {
	    $this->warn("$data: file not found");
	    return $ml->span("file not found",{class=>"error"});
	}
    }
    elsif ($datatype =~ /^password$/) {
	return $this->level >= $config{auth}{password_access} ? 
	    $data : "******";
    }
    else {
	return $this->clean_text($data);
    }
}

# show_data_nomap : display data that does not come from a mapped table/column
# or which have an overriden data type.

sub show_data_nomap {
    my ($this,$datatype,$data) = @_;
    return "" if (! $data);

    # get datatype
    $_ = $datatype;

    if (/crypt/) {
	return $this->decrypt($data);
    }
    elsif (/^(big)?file$/) {
	my ($name,$content) = split /$config{form}->{sepchar}/,$data,2;
	if (!$name) { $name = "download"; }
	$name = &clean_filename($name);
	# guess the mime-type
	my $mimetype = &MimeType($name);
	# estimate the size
	# (multiply by 6/8 to account for Mime base64 encoding overhead)
	my $size = int(length($content)*6/8/100)/10;
	if ($size) {
	    return "$name&nbsp;($mimetype,&nbsp;$size&nbsp;K)";
	}
	else {
	    return "$name";
	}
    }
    else {
	return $this->show_data_noauth(undef,undef,$data,undef,$datatype);
    }
}

# clean a text string for browser display
# $text - string to clean
# $html_level =
#     0 for no HTML
#     1 for non-structural markup
#     2 for all HTML
#     3 to allow ExSite HTML as well
# If you don't specify $html_level, it will use the honour_html and 
# safe_html settings in your configuration.

sub clean_text {
    my ($this,$text,$html_level) = @_;

    if ($html_level !~ /^[0123]$/) {
	$html_level = $config{report}{text}{honor_html};
    }

    if ($html_level) {
	if ($html_level < 2 && $config{report}{text}{safe_html}) {
	    $text = &safehtml($text);
	}
    }
    else {
	# neuter all HTML tags
	$text =~ s/</&lt;/g;
	$text =~ s/>/&gt;/g;
    }

    if ($html_level < 3) {
	# neuter CMS
	$text =~ s/<!--([\$\&])/<!-- $1/g;
    }

    # always neuter javascript
    $text =~ s/<(\/?)script(.*?)>/&lt;$1script$2&gt;/g;
    $text =~ s/<([^>]) on(blur|change|click|dblclick|focus|key|load|mouse|reset|select|submit|unload)/<$1 on $2/g;
    return $text;
}

# get a markup handle
sub ml {
    my $this = shift;
    return &get_obj("ML");
}

=pod 

=head2 Reporting Records

=head3 C<report()> - display record(s) from the database as HTML

C<report()> displays one or more records from the database in a formatted
table, automatically selecting which columns/values to display, formatting
each value, hyperlinking active values appropriately, and providing 
options to edit, copy, delete, or view more detailed information.
It returns the report as a string of formatted HTML.

Usage: C<$db-E<gt>report($options);>

C<$options> is a hash reference containing any of the following parameters
that are relevant to the report:

=over 4

=item table

reference to a list of tables to report on

=item data

reference to a list of datahashes, or to a single matchhash

=item query

a query hash (see Queries, below)

=item sort

a column name to sort on, or a reference to a list of column names.

=item columns

Select which columns should be included in the report.  This is normally
determined automatically, but can be overriden manually if desired.
Values of "brief", "full", or [ RE of column types to display ] are 
accepted.

=item max

the maximum number of records to display (default all).

=item start

starting record (default 0)

=back

=head4 DB ops

Any record can be linked to a variety of database operations (DB ops)
that the viewer can perform on the data.  The operations that will be
linked to are determined by the settings of the following DB ops flags.
If the flag is true, the link to the operation will be given.  If the flag
is "1" the link will go to the default URL for handling DB ops (defined
in C<$config{db_ops}>), otherwise the flag is presumed to be a partial
URL to link to for that operation.  The following parameters will be 
appended to the URL:

    tab=TABLENAME&id=RECORD_ID

The DB ops that the system can perform are:

=over 4

=item link, view

These link from a brief summary of the record to a full view of the record data.

=item edit

Links to a form to edit the record.

=item copy

Links to a form to insert a new record with the same data as the current record.

=item delete

Moves the record to the trash bin.

=item new

Links to a form to insert a new record (the form is initialized blank).

=item all_edit

Equivalent to C<edit=E<gt>1, copy=E<gt>1, delete=E<gt>1>.

=back

=head4 Queries

Some reports may include too many records for convenient display on a
single web page.  In this case, we break the report into pages.  By
default we show 20 records per page, but this value can be configured
in C<exsite.conf>.  An index of the report pages is also shown at the
bottom of the report.

A "query" (probably a misnomer) is a QUERY_STRING parameter that lets
us keep track of where we are in a multi-page report, since we may
have to re-generate the report several times as we page through it,
and we need some context information to do that.  The query also keeps
track of which columns we are sorting on, so that we don't lose our
position in the report if we resort somewhere in the middle.  

All of this is handled automatically by ExSite if you use the
C<report()> method, in which case you should never have to interact with
the query methods.

The query parameter is just an encoded hash containing the following values:

=over 4

=item table

The table the records came from.

=item match

A reference to a match hash to select records from the above table.

=item sort

A reference to a list of column names to sort on.

=item start

The first record to display in the current view.

=item num

The number of records to display in the current view.

=back

The query parameters are processed with the following calls:

=over 4

=item C<$db-E<gt>encode_query($query_hashref);>

Converts a query hash to an string that can be embedded into a query string.

=item C<$db-E<gt>decode_query($encoded_query_string);>

Converts a the encoded string back to a hash.  (Returns a reference to this
hash.)

=item C<$db-E<gt>do_query($query_hashref);>

Returns an array of datahashes corresponding to the "slice" of data
specified by the query hashref.

=item C<$db-E<gt>sizeof_query();>

Returns the total number of records matching the last query processed by
C<do_query()> (not just the slice that was returned).

=back

=cut

sub report {
    my ($this,$opt) = @_;
    my %opt = %$opt;
    my $out;

    $this->info("ExSite::Report::report called");

    # use handler to build the report, if one is defined
    if ($this->{handler}->{report}) {
      $out = &{$this->{handler}->{report}} ($this,$opt);
      if ($out) { return $out; }
    }

    my %report = ( 
		   title=>$opt->{title},
		   foot=>$opt->{foot},
		   tools=>$opt->{tools},
		   );  # options for ReportBuilder

    # determine tables to report on
    my ($table,$rlist);
    if (exists $opt{table}) {
	if (! ref $opt{table}) {
	    $table = $opt{table};
	    # reformat for compatibility with queries
	    $opt{table} = [ $table ];
	}
	elsif (ref $opt{table} eq "ARRAY") {
	    # rev.1: only report on first table (ie. no joins)
	    $table = $opt{table}->[0];
	}
	else { 
	    return $this->error("report: no table specified");
	}
    }
    elsif (exists $opt{query}) {
	if (exists $opt{query}->{table}) {
	    $table = $opt{query}->{table}->[0];
	}
	else { 
	    return $this->error("report: no table specified");
	}
    }
    else {
	return $this->error("report: no table specified");
    }

    # determine the data source
    if (ref $opt{data} eq "ARRAY") {
	# data has been directly specified; report all records with no paging
	$rlist = $opt{data};
	# sort
	if (exists $opt{sort}) {
	    if (ref $opt{sort} eq "ARRAY") {
		# sort gives a list of columns to sort on
		my @list = $this->sort_rows($table,$rlist,@{$opt{sort}});
		$rlist = \@list;
	    }
	    else {
		# no sort keys; sort on main column
		my @list = $this->sort_rows($table,$rlist,
					    $this->primary_column($table));
		$rlist = \@list;
	    }
	}
    }
    else {
	# use a query to select and page through the data
	if (! exists $opt{query}) {
	    my $page_length = $opt{max} ? $opt{max} : $config{report}->{page_length};
	    $opt{query} = { table=>[$table], start=>0, num=>$page_length, 
			    link=>$opt{link}, edit=>$opt{edit} };
	    if (ref $opt{data} eq "HASH") { $opt{query}->{match} = $opt{data}; }
	    if (ref $opt{sort} eq "ARRAY") {
		$opt{query}->{sort} = $opt{sort};
	    }
	}
	my @data = $this->do_query($opt{query});
	$rlist = \@data;
    }

    if (@$rlist == 0) {
      my $title = $this->{map}->table_title($table,1);
      $report{nodata} = "No $title found.";
      goto ADD_NEW;
    }

    $opt{key} = $this->get_key($table);

    # fetch the columns to appear in this report
    if (! exists $opt{columns}) { $opt{columns} = "brief"; }
    my @colmap;
    if (ref $opt{columns} eq "ARRAY") {
      # columns to report are provided by the calling agent
      foreach my $col (@{$opt{columns}}) {
	my %colmap = $this->{map}->get_column($table,$col);
	push @colmap, \%colmap;
      }
    }
    else {
      # select all columns of type $opt{columns}
      my $ncol = $this->{map}->get_ncol($table);
      for (my $icol = 0; $icol < $ncol; $icol++) {
	my %colmap = $this->{map}->get_column($table,$icol);
	# "key" columns are _ALWAYS_ included
	if (($colmap{display} eq "key") || 
	    ($colmap{display} =~ /$opt{columns}/)) {
	  push @colmap, \%colmap;
	}
	elsif ($opt{type} eq "full" && $colmap{display} eq "full") {
	  push @colmap, \%colmap;
        }
      }
      if (@colmap == 0) {
	  return $this->error("report: no columns in $table can be displayed");
      }
    }

    # save default sort key
    my ($default_sort_key, $desc);
    if (!$opt{query}->{sort}){$opt{query}->{sort} = [ $this->primary_column($table) ];}
    $default_sort_key = $opt{query}->{sort};
    if (substr($default_sort_key->[0],0,1) ne "-"){$desc=1;}else{$desc=0;}
    
    # report header

    $report{headers} = [];
    my $reporturl = $config{db_ops}{report}{url};
    $reporturl .= $config{db_ops}{report}{url} =~ /\?/ ? "&" : "?";
    if ($reporturl !~ /^(http|\/)/) {
	$reporturl = "$config{server}{CGIpath}/$reporturl";
    }
    my $re_sort_columns = exists $opt{re_sort} ? $opt{re_sort} : 1;
    # control options
    if ($opt{type} ne "full" && $config{report}->{link_position} eq "before") {
	if ($opt{link} || $opt{edit} || $opt{delete} || $opt{copy} || $opt{list}) {
	    push @{$report{headers}},"Options";
	}
    }
    foreach my $column (@colmap) {
	if (exists $opt{query} && $re_sort_columns && $opt{type} ne "full") {
	    # re-sort option only available on queries
	    my $newquery = $opt{query};
	    my $colname = ($desc && $default_sort_key->[0] eq $column->{column}) ? "-".$column->{column} : $column->{column};
	    $newquery->{sort} = [ $colname ];
	    my $encoded_query = $this->encode_query($newquery);
	    my $anchor = "$column->{label} ";
	    if ($desc && ($default_sort_key->[0] eq $column->{column})) {
		$anchor .= " +";
	    }
	    elsif ($default_sort_key->[0] eq "-".$column->{column}) {
		$anchor .= " -";
	    }
	    my $hdr = $this->ml->a($anchor,
				   {href=>"${reporturl}query=$encoded_query&link=$opt{link}&all_edit=$opt{all_edit}"});
	    push @{$report{headers}},$hdr;
	}
	else {
	    # fixed report format
	    push @{$report{headers}},"$column->{label}";
	}
    }
    # reset sort key
    if (exists $opt{query}) {
	if ($default_sort_key) {
	    $opt{query}->{sort} = $default_sort_key;
	}
	else {
	    delete $opt{query}->{sort};
	}
    }
    # control options
    if ($opt{type} ne "full" && $config{report}->{link_position} ne "before") {
	if ($opt{link} || $opt{edit} || $opt{delete} || $opt{copy} || $opt{list}) {
	    push @{$report{headers}}, "Options";
	}
    }

    # report data

    my $key = $this->get_key($table);
    my @alldata;
    foreach my $rdata (@$rlist) {
	my @data;
	# extra functions - display as if another column
	if ($opt{type} ne "full" && $config{report}->{link_position} eq "before") {
	    if ($opt{link} || $opt{all_edit} || $opt{edit} ||
		$opt{copy} || $opt{delete} || $opt{view}) {
		push @data, &report_links($this,$table,$rdata->{$key},%opt);
	    }
	}
	foreach my $col (@colmap) {
	    push @data, $this->show_data($table,$col->{column},
					 $rdata->{$col->{column}},
					 $rdata->{$key});
	}
	# extra functions - display as if another column
	if ($opt{type} ne "full" && $config{report}->{link_position} ne "before") {
	    if ($opt{link} || $opt{all_edit} || $opt{edit} ||
		$opt{copy} || $opt{delete} || $opt{view}) {
		push @data, &report_links($this,$table,$rdata->{$key},%opt);
	    }
	}
	# extra functions for full record reports
	if ($opt{type} eq "full") {
	    $report{tools} .= &report_links($this,$table,$rdata->{$key},%opt);
	}
	push @alldata, \@data;
    }
    if (@alldata > 0) { 
	if ($opt{type} eq "full") {
	    $report{data} = $alldata[0];    # single-record "full" report
	}
	else {
	    $report{data} = \@alldata;      # multi-record "brief" report
	}
    }

    # now output paging links

    my $linkargs = $this->make_link_args(%opt);
    if (exists $opt{query} && $opt{type} ne "full") {
	my $qout;
	my $query = $opt{query};
	my $start = $query->{start} + 1;
	my $end = $query->{start}+$query->{num} < $total_records_in_query ?
	    $query->{start}+$query->{num} : $total_records_in_query;
	if ($start != 1 || $end != $total_records_in_query) {
	    $qout .= "Records $start-$end of $total_records_in_query.".
		$this->ml->br().
		"Page: ";
	    for (my $irec = 0; $irec <= $total_records_in_query; $irec += $config{report}->{page_length}) {
		my $ipage = int($irec / $config{report}->{page_length}) + 1;
		if ($irec == $start - 1) {
		    $qout .= "$ipage ";
		}
		else {
		    $query->{start} = $irec;
		    my $q = $this->encode_query($query);
		    $qout .= $this->ml->a($ipage,{href=>"${reporturl}query=$q$linkargs"});
		}
	    }
	}
	# reset query to original state
	$query->{start} = $start - 1;

	if ($query->{start} > 0) {
	    # previous link
	    $query->{start} -= $query->{num};
	    if ($query->{start} < 0) { $query->{start} = 0; } 
	    my $q = $this->encode_query($query);
	    my $qlink = $this->ml->a("previous $query->{num}",{href=>"${reporturl}query=$q$linkargs"});
	    $qout .= "[$qlink]\n";
	    $query->{start} += $query->{num};
	}
	if ($total_records_in_query > $end) {
	    # might be more data
	    ### FIXME: on last page, "next N" should give number of remaining records
	    $query->{start} += $query->{num};
	    my $q = $this->encode_query($query);
	    my $qlink = $this->ml->a("next $query->{num}",{href=>"${reporturl}query=$q$linkargs"});
	    $qout .= "[$qlink] ";
	    $query->{start} -= $query->{num};
	}
	if ($qout) { $report{tools} .= $qout.$this->ml->br(); }
    }

    # finally, the optional insert link

  ADD_NEW:
    $report{tools} .= $this->report_links($table,undef,%opt);
    my $r = new ExSite::ReportBuilder(%report);
    return $r->make;
}

=pod

=head3 C<report_row()> - display a single row in verbose format

This displays all viewable columns of a selected record.  The results
are formatted in a two-column table, with labels (user-friendly column
names) on the left, and values on the right.  The report is returned
as a string of HTML.

Usage: C<$db-E<gt>report_row($table,$row,%opt);>

=over 4

=item $table

The table the record (row) is taken from.

=item $row

The record ID or a reference to the record datahash.

=item %opt

Options to be passed to C<report()>, if desired.  For example
C<(edit=E<gt>1)>.

=back

=cut

sub report_row {
    my ($this,$table,$row,%opt) = @_;

    $this->info("ExSite::Report::report_row called");

    # fetch data for this row
    my %data;
    if (ref $row eq "HASH") {
      # the data has been passed directly
      %data = %$row;
    }
    else {
      # assume the data has been passed as a record id
      %data = $this->fetch($table,$row);
    }
    #my $key = $this->get_key($table);

    # no "add new" link for report_row
    $opt{new} = 0;

    my $out = $this->report({ table=>$table, data=>[\%data], columns=>"full|brief",
			   type=>"full", %opt });

    #$out .= &report_links($this,$table,$data{$key},0,(all_edit=>$opt{all_edit}));
    return $out;

}

=pod

=head3 C<report_db()> - display top-level database view

This lists all viewable tables in the database, with options to
view the contents of the table, search the table, or add a new record
to the table.

Usage: C<$db-E<gt>report_db($options);>

C<$options> is a hash containing the following parameters:

=over 4

=item class

select sub-category of tables to show, if the DBmap defines table classes.

=item count

count

display record counts for each table, if true.

=item title

include title/intro text.

=item [op]

optional db_ops settings, if you want to modify the allowed operations.

=back

=cut

sub report_db {
    my ($this,$opt) = @_;

    $this->info("ExSite::Report::report_db called");

    my $title;
    my @table = $this->{map}->get_mapped_tables;

    my $access = $this->authorize;

    my %report = ( headers=>[], data=>[] );

    if ($opt->{title} == 1) {
	$report{title} = "Database Index - All Tables";
    }
    elsif ($opt->{title}) {
	$report{title} = $opt->{title};
    }
    if ($config{report}->{link_position} eq "before") {
	push @{$report{headers}}, "Operations";
    }
    push @{$report{headers}},( "Table", "Record Count" );
    if ($config{report}->{link_position} ne "before") {
	push @{$report{headers}}, "Operations";
    }
    foreach my $tab (sort @table) {
	my @data;
	my $table_par = $this->{map}->get_table($tab);
	if ($access >= $table_par->{read}) {
	    if (! $opt->{class} || $table_par->{class} =~/$opt->{class}/) {
		$title = $this->{map}->table_title($tab,1);
		if ($config{report}->{link_position} eq "before") {
		    push @data, $this->report_links($tab,undef,%$opt);
		}
		my $tablename = $table_par->{alias} ne $tab ? "alias->$table_par->{alias}" : $tab;
		my %dl;
		$dl{dt} = $this->ml->strong($title)." ".$this->ml->em($tablename);
		if (exists $table_par->{description}) {
		    $dl{dd} = $table_par->{description};
		}
		my $tabdesc .= $this->ml->dl(\%dl);
		push @data, $tabdesc;
		push @data, $this->count($tab);
		if ($config{report}->{link_position} ne "before") {
		    push @data, $this->report_links($tab,undef,%$opt);
		}
	    }
	}
	push @{$report{data}}, \@data;
    }
    my $r = new ExSite::ReportBuilder(%report);
    return $r->make;
}

=pod

=head3 C<report_relational()> - displays records and their relations

This method generates contextual views of the database.  A viewer may be
looking at a specific record, a table, or nothing.  

In the case of nothing, C<report_db()> is called.

In the case of a table, C<report()> is called.

In the case of a specific record, we call C<report_row()> on that
record, and then recursively generate summary reports for every child
record of this record.  Each of these child records can in turn be
visited to generate new relational reports from that context.  Parent
records can be visited by following the links in the the record's
data.  This is the usual method for navigating/browsing the database.

b<Usage:> C<$db-E<gt>report_relational($options);>

HMTL for the combined report is returned in a string.

C<$options> is a hash containing the following parameters, all of which
are optional:

=over 4

=item tab,table

the primary table to report on.  If none specified, all tables are listed.

=item id

the key of a particular record in the above table.  Without this parameter, 
all members of the table are listed for selection.  With this parameter, 
the associated members of the subtables are listed, with options to edit, 
delete, or add to the table.

=item stab

the subtable(s) to manage.  By default, all known subtables are shown.
This parameter can be used to restrict which subtables are shown.

=item ptab

=item pid

(Both of these must be specified at once.)  These parameters select which
members of the table are listed.  By default, all members of the table
are shown.

=item other...

All remaining options are passed to the other report() methods.

=back

=cut

sub report_relational {
    my ($this,$opt) = @_;

    $this->info("ExSite::Report::report_relational called");

    my ($out,$alias);
    if (! exists $opt->{tab} && exists $opt->{table}) { 
        $opt->{tab} = $opt->{table}; 
    }
    $alias = $this->{map}->get_table_attr($opt->{tab},"alias");
    if (! $alias) { $alias = $opt->{tab}; }
    if (!$opt->{tab}) {
        return $this->report_db($opt);
    }
    elsif (! $this->approve("read",$opt->{tab})) {
        return $this->ml->p("You do not have permission for this operation.",
			    {class=>"error"});
    }
    elsif (defined $opt->{id}) {
        # a specific record has been selected; show children of this record
        my $title;
        if ($opt->{title} == 1) {
            $title = $this->title($opt->{tab},$opt->{id});
        }
        elsif ($opt->{title}) {
            $title = $opt->{title};
        }

        my $option={"all_edit"=>(exists($opt->{all}) ? $opt->{all} : 1)};
        if ($opt->{reply}) {
            $option= {%$option, "reply"=>$opt->{reply}};
        }

        # get related tables to report on
        #my @children = $this->{map}->get_children($opt->{tab});
        my @children = $this->{map}->get_children($alias);
        if (defined $opt->{stab}) {
            # a specific sub table (child table) has been requested
            @children = grep(/^$opt->{stab}$/,@children);
        }
        elsif (exists $opt->{stab}) {
            # do not show any subtables
            @children = ();
        }

        my $cout;
        foreach my $child (@children) {
            my %crep;
            my $refcol = $this->{map}->get_reference_column($child,$alias);
            my %match;
            $match{$refcol} = $opt->{id};
            
            my $title = $this->{map}->table_title($child,1)." for ".
                $this->title($opt->{tab},$opt->{id});
            my $newurl;
            if ($config{report}->{linkmode} eq "exsite") {
                $newurl = &relink(action=>"new",tab=>$child,ptab=>$opt->{tab},pid=>$opt->{id});
            }
            elsif ($config{report}->{linkmode} eq "cgi") {
                $newurl = "$config{server}->{CGIpath}/$config{db_ops}->{new}->{url}";
                $newurl .= (($newurl =~ /\?/) ? "&" : "?");
                $newurl .= "tab=$child&ptab=$opt->{tab}&pid=$opt->{id}";
            }
            $cout .= $this->ml->p(
				  $this->report({title=>$title, 
						 table=>$child, 
						 data=>\%match, 
						 link=>(exists($opt->{link}) ? $opt->{link} : 1),all_edit=>(exists($opt->{all}) ? $opt->{all} : 1),new=>(exists($opt->{new}) ? ($opt->{new} ? $newurl : 0) : $newurl),sort=>1})
				  );
        }

        # report_row

        $out .= $this->ml->p(
			     $this->report_row($opt->{tab},$opt->{id},
					       (title=>$title,foot=>$cout,%$option))
			     );
    }
    else {
        # no specific record has been selected; list valid records
        my $title = $this->{map}->table_title($opt->{tab},1);
        my $newurl;
        if ($config{report}->{linkmode} eq "cgi") {
            $newurl = "$config{server}{CGIpath}/$config{db_ops}{new}{url}";
        }
        else {
            #$newurl = "$config{server}->{CGIpath}/page.cgi?_id=".$share{Page}->id."&action=new";
            $newurl = &relink(action=>"new");
        }
        $newurl .= (($newurl =~ /\?/) ? "&" : "?");
        $newurl .= "tab=$opt->{tab}&ptab=$opt->{ptab}&pid=$opt->{pid}";
        if (! exists $opt->{pid}) {
            # show all rows
            $out .= $this->ml->p(
				 $this->report({title=>$title,table=>$opt->{tab},link=>1,all_edit=>1,sort=>1,new=>$newurl})
				 );
        }
        else {
            # show only those rows belonging to the parent
            my %data = $this->fetch($opt->{ptab},$opt->{pid});
            my $keycol = $this->primary_column($opt->{ptab});
            $out .= $this->ml->h2("$title for \"$data{$keycol}\"");
            my $refcol = $this->{map}->get_reference_column($opt->{tab},$opt->{ptab});
            my %match = ( $refcol => $opt->{pid} );
            $out .= $this->report({table=>$opt->{tab}, data=>\%match, link=>1,all_edit=>1,sort=>1,new=>$newurl});
        }
    }

    return $out;
}

=pod

=head3 C<report_links()> - show DB ops links in a report

This is an internal method used to generate the DB ops links in the
above reports. Links will use graphic buttons, if those are found
where they are expected, but will default to text links if not.
C<report_links()> can be invoked for a table or record to generate
all of the appropriate links for that entity.

Usage: C<$db-E<gt>report_links($table,$id,%options)>

=over 4

=item C<$table>

The table that is being operated on.

=item C<$id>

The record ID that is being operated on.  (If none, then it is assumed
we are operating on the table as a whole.)

=item C<%options>

Flags for the DB ops that should be included.  
The DB ops that this method supports are:

=over 4

=item link, view

These link from a brief summary of the record to a full view of the 
record data.

=item edit

Links to a form to edit the record.

=item copy

Links to a form to insert a new record with the same data as the 
current record.

=item delete

Moves the record to the trash bin.

=item new

Links to a form to insert a new record (the form is initialized blank).

=item list

Links to a summary report of all records in a table.

=item search

Links to a form to search for matching records in a table.

=item all_edit

Equivalent to C<edit=E<gt>1, copy=E<gt>1, delete=E<gt>1>.

=back

If the flag is set to 1, the option will be linked to the default
URL defined in $config{db_ops}.  Otherwise, you can set the flag to 
your own URL to perform that operation.  The following parameters will
be appended to your URL:

    tab=TABLENAME&id=RECORD_ID

=back

=head3 C<link()> - generate a single db ops link

Usage: C<$db-E<gt>link($op,$arg,$script)>

C<$op> is the db operation (eg. "view", "edit", "search", etc.).
C<$arg> is an explicit query string to include, or a hash ref to 
a set of parameters to convert to a query string.
C<$script> is a CGI program name to use in place of the default
db_ops CGI program.

C<link()> returns links in one of two formats, depending on the value
of C<$config{report}{linkmode}>.  If the linkmode is "exsite", the
current URL is edited to include the new parameters, on the assumption 
that an appropriate plug-in will act on those parameters.  Otherwise
if the linkmode is "cgi", the link URL will be taken from C<$config{db_ops}>.

=cut

sub report_links {
    my ($this,$table,$id,%opt) = @_;

    # check for handler to manage all links
    my $out = $this->run_handler("report_links",$table,$id,%opt);
    return $out if (defined $out);
    
    my %opflag;

    while (my ($key,$val) = each %opt) {
	if (grep /$key/, keys %{$config{db_ops_grps}}) {
	    foreach my $op (@{$config{db_ops_grps}->{$key}}) {
		if (! defined $opt{$op}) { $opt{$op} = $val; }
	    }
	}
    }

    $this->check_for_buttons;
    my $query = "tab=$table";
    if ($id) { $query .= "&id=$id"; }
    my %db_ops = %{$config{db_ops}};

    # std ops
    foreach my $op (@{$config{db_ops_order}}) {
	# check if this op was requested
	if ($opt{$op}) {
	    # check if this op is valid
	    if ($id xor $config{db_ops}->{$op}->{table} == 1) {
		# check if this op is permitted
		if ($this->approve($db_ops{$op}->{approve},$table,$id)) {
		    my $linkurl;
		    my $cgiprog = undef;
		    if ($opt{$op} && $opt{$op} != 1) { 
			$cgiprog = $opt{$op}; 
			if ($cgiprog !~ /\?.+/) { 
			    # in case custom URL has predefined query
			    $query = undef; 
			}
		    }
		    $out .= $this->link($op,$query,$cgiprog);
		}
	    }
	}
    }

    # check for handler to add extra links
    $out .= $this->run_handler("report_links_extra",$table,$id,%opt);
    
    return $out;
}

#--------------------------------------------------------------------
# make_link_args : encode the dbops parameters as an URL argument
#--------------------------------------------------------------------

sub make_link_args {
  my ($this, %opt ) = @_;
  my @args = ( "" );
  if ($opt{link}) { push @args, "link=$opt{link}"; }
  if ($opt{view}) { push @args, "view=$opt{view}"; }
  if ($opt{all_edit}) { push @args, "all_edit=$opt{all_edit}"; }
  if ($opt{edit}) { push @args, "edit=$opt{edit}"; }
  if ($opt{copy}) { push @args, "copy=$opt{copy}"; }
  if ($opt{delete}) { push @args, "delete=$opt{delete}"; }
  if ($opt{new}) { push @args, "new=$opt{new}"; }
  foreach my $arg (@args) {
    # escape argument separators
    $arg =~ s/\&/\%26/g;
  }
  return join("&",@args);
}

# look for graphic buttons

sub check_for_buttons {
    my $this = shift;
    return if scalar(keys %use_button) > 0;  # already done
    my %db_ops = %{$config{db_ops}};
    my $imgpath = "$config{server}->{HTMLroot}$config{server}->{HTMLpath}/_Modules/WebDB";
    foreach my $op (keys %db_ops) {
	$use_button{$op} = (-e "$imgpath/$db_ops{$op}->{img}");
    }
    return;
}

# link : return an HTML link for a db operation

sub link {
    my ($this,$op,$arg,$script) = @_;
    my $out;
    my $query = ref $arg eq "HASH" ? &EncodeHash(%$arg) : $arg;
    my $default_script;
    if ($config{report}->{linkmode} eq "exsite") {
	$default_script = &relink(action=>$op);
    }
    elsif ($config{report}->{linkmode} eq "cgi") {
	$default_script = $config{db_ops}->{$op}->{url};
    }

    if (! $script) { $script = $default_script; }
    if ($script !~ /^\//            # if no cgipath already included
	&& $script !~ /^\w+:/ ) {   # and no protocol given, then
	$script = "$config{server}->{CGIpath}/$script";  # add CGIpath
    }
    my $url = $script;
    if ($url !~ /\?/) { 
	# add the query if no query is defined
	$url .= "?$query";
    }
    elsif ($url !~ /[&?]$query&?/) { 
	# add the query if no matching query parameter is found
	$url .= "&$query";
    }
    $this->check_for_buttons;
    my %db_ops = %{$config{db_ops}};
    
    # check for graphic buttons

    if ($use_button{$op}) {
	# use graphic button
	$this->{ui} or $this->{ui} = &get_obj("UI");
	$out = $this->{ui}->UnicodeTool($op,label=>$db_ops{$op}->{label},url=>$url);
#	$out = $this->ml->a(
#			    $this->ml->img(undef,
#					   {src=>"$config{server}->{HTMLpath}/_Modules/WebDB/$db_ops{$op}->{img}",
#					    height=>"$db_ops{$op}->{img_height}",
#					    width=>"$db_ops{$op}->{img_width}",
#					    border=>0,
#					    alt=>$db_ops{$op}->{label},
#					    title=>$db_ops{$op}->{label} }
#					   ),
#			    {href=>$url},
#			    );
    }
    else {
	# use text link
	$out = "[&nbsp;".
	    $this->ml->a($db_ops{$op}->{label},
			 { href=>$url }).
	       "&nbsp;]\n";
    }
    return $out;
}

=pod

=head3 C<helplink()> - display help tops for DB fields

This method generates help links for DB fields in forms.
Help data is found in C<dbmap/help/$table/$column>.

Usage: C<$db-E<gt>helplink($table,$column,$anchor,$css)>

C<$table> and C<$column> refer to the DB column that help is 
needed for.  C<$anchor> is the anchor text for the help link.
C<$css> is a boolean flag that makes us use CSS help popups
(you must be using the ExSite stylesheet or equivalent);  otherwise
we use JavaScript popups.  It will generate a popup window if help 
is available.  There is no output if the help files are not found.

=cut

sub helplink {
    my ($this,$table,$column,$anchor,$css) = @_;
    return undef if (! $table || ! $column);
    my $out;
    if (! $anchor) { $anchor = "help"; }
    my $helpfile = "$config{server}{CGIroot}/$config{server}{map}{name}/help/$table/$column";
    # alternate kludge that works in simple cases
    #my $helpfile = $ENV{SCRIPT_FILENAME};
    #$helpfile =~ s/\/\w+\.cgi$//;
    #$helpfile .= "/$config{server}->{map}->{name}/help/$opt{table}/$opt{column}";
    if (-e $helpfile) {
	if ($css) {
	    if (! $share{help_css}) {
		# this is cheating - style tags are technically forbidden in 
		# the body;  however, it does work on all major browsers...
		$out .= $this->ml->style("div.help_popup {
    border: 2px solid #996600;
    background-color:#ffff99;
    color:black;
    padding:10px;
    position:relative;
    width:300px;
    display:none;
}
span.help_hotspot {
    border:1px solid #9999cc; 
    padding-left:2px; 
    padding-right:2px; 
    font-size:80%; 
    color:#9999cc; 
    position:relative; 
    top:-2px;
}");
		$share{help_css} = 1;
	    }
	    my $helptext = &get_file($helpfile);
	    $out .= &ExSite::HTML::HelpPopup(message=>$msg{$helptext},label=>$msg{$anchor});
	}
	else {
	    if (! $share{js_misc}) {
		$out .= $this->ml->script(undef,{langauge=>"JavaScript",
						 src=>"$config{server}{HTMLpath}/_ExSite/js/misc.js"});
		$share{js_misc} = 1;
	    }
	    $out .= $this->ml->a($msg{$anchor},
				 {href=>"javascript:popup_small('$config{server}{CGIpath}/$config{prog}{help}/$config{server}{map}{name}/help/$table/$column')"});
	}
    }
    return $out;
}

=pod

=head2 Bulk Data Imports and Exports

Bulk imports/exports are typically done to/from some spreadsheet
format.  Exports can be done to tab-delimted text or Excel formats.
Imports are done from tab-delimited text files.

=head3 C<export()>

Usage: C<$db-E<gt>export($options)>

C<$options> is a hash ref containing:

=over 4

=item table

the table to export.

=item column

ref to a list of columns to export.

=item format

"text" or "excel" (default is text)

=item outfile

output filename or "-" for stdout (default is stdout)

=item header

set this to "label" to get friendly column headings in the export.  
Otherwise the column headings default to the database column name.

=item heading

hash of headings for columns (default is taken from dbmap)

=item data

ref to a list of datahashes of preselected records.

=item match 

ref to a match hash to select records.

=item owner

export all records owned by this UID

=item group

export all records owned by this GID

=item readable_fkey

If true, convert foreign keys to a readable form (ie. replace numeric foreign
keys with a descriptive string indicating the foreign record)

=back

By default, all records in a table are exported, unless one of 
data, match, owner, or group is given.

=head3 C<import()>

Usage: C<$db-E<gt>import($options);>

C<$options> is a hash ref containing:

=over 4

=item table

the table to import into.

=item delim

the field delimiter (TAB by default).

=item file

input file name.

=item method

C<insert> or C<update>.  Update can be used if the imported file is
from a previous export, and includes appropriate primary keys 
indicating which records are being updated.  Insert should be used
for new data.

=back

=cut

sub export {
    my ($this,$arg) = @_;
    my $table = $arg->{table};
    return "" if (! $table);

    my $out;
    my $access = $this->authorize;
    if (! $access) {
	$this->warn("export: permission denied");
	return "";
    }

    # default to text format
    if (!exists $arg->{format}) { $arg->{format} = "text"; }

    # default to stdout
    if (!exists $arg->{outfile}) { $arg->{outfile} = "-"; }

    # fetch records to appear in report
    my $rlist;
    if ($arg->{match}) {
	# select matching records
	$rlist = $this->fetch_match($table,$arg->{match});
    }
    elsif ($arg->{data}) {
	# preselected data
	$rlist = $arg->{data};
    }
    elsif ($arg->{owner}) {
	# select records by owner
	my $all = $this->fetch_all($table);
	foreach my $rec (@$all) {
	    if ($this->find_owner($table,$rec,"user") == $arg->{owner}) {
		push @$rlist,$rec;
	    }
	}
    }
    elsif ($arg->{group}) {
	# select records by group
	my $all = $this->fetch_all($table);
	foreach my $rec (@$all) {
	    if ($this->find_owner($table,$rec,"group") == $arg->{group}) {
		push @$rlist,$rec;
	    }
	}
    }
    else {
	# select everything
	$rlist = $this->fetch_all($table);
    }

    if ($arg->{readable_fkey}) {
	my $ncol = $this->{map}->get_ncol($table);
	foreach my $r (@$rlist) {
	    for (my $i = 0; $i < $ncol; $i++) {
		my $datatype = $this->{map}->get($table,$i,"datatype");
		if ($datatype =~ /^key[=:]/) {
		    my $col = $this->{map}->get($table,$i,"column");
		    my (undef,$ftable) = split /[:=]/,$datatype;
		    $r->{$col} = $this->record_label($ftable,$r->{$col});
		}
	    }
	}
    }

    # report columns or labels
    my $header = $arg->{header}? $arg->{header} : "column";

    # fetch columns to appear in report
    my (@column,@header);
    if (! defined $arg->{column}) {
        # report all readable columns by default
	my $ncol = $this->{map}->get_ncol($table);
	for (my $i = 0; $i <= $ncol; $i++) {
	    if ($this->{map}->get($table,$i,"read") <= $access) {
	        push @column,$this->{map}->get($table,$i,"column");
	        push @header,$this->{map}->get($table,$i,$header);
	    }
	}
    }
    else {
	# report only the requested columns
	@column = @{$arg->{column}};
	foreach (@column) {
	    push @header, ($arg->{heading}{$_} || $this->{map}->get($table,$_,$header));
	}
    }

    # export the data

    if ($arg->{format} eq "text") {
	# print column headings
	my $out = join("\t",@header)."\r\n";
	# print data
	my @data;
	foreach my $dhash (@$rlist) {
	    foreach my $col (@column) {
		# escape control characters
		$dhash->{$col} =~ s/\%/\%37/g;  # %
		$dhash->{$col} =~ s/\n/\%0A/g;  # newline
		$dhash->{$col} =~ s/\r/\%0D/g;  # CR
		$dhash->{$col} =~ s/\t/\%09/g;  # tab
		push @data,$dhash->{$col};
	    }
	    $out .= join("\t",@data)."\r\n";
	    @data = ();
	}
	if ($arg->{outfile} ne "-") {
	    open F,">$arg->{outfile}";
	    print F $out;
	    close F;
	}
	else {
	    print $out;
	}
    }
    elsif ($arg->{format} eq "excel") {
	my @Colarray;
	foreach my $column (@column) {
	    my $head = shift @header;
	    push @Colarray, "$head;$column";
	}
	require ExSite::Excel;
	&ExSite::Excel::ExcelExport($rlist,$arg->{outfile},\@Colarray);
    }
}

#--------------------------------------------------------------------
# export_text : exports data in tab-delimited text format
# (for backwards compatibility only)
#
# INPUT:
#    1) table name
#    2) match hash
#    3) reference to list of columns to report
#       (if null, display all reportable columns)
#
# OUTPUT:
#    returns the text report in a string
#--------------------------------------------------------------------

sub export_text {
    my ($this,$table,$rmatch,$rshow) = @_;
    return $this->export({table=>$table,format=>"text",column=>$rshow,match=>$rmatch});
}

sub import {
    my ($this,$arg) = @_;
    my $table = $arg->{table};
    return 0 if (! $table);
    my $access = $this->authorize;
    return 0 if (! $access);
    my $file = $arg->{file};
    return 0 if (! -e $file);
    my $delim = $arg->{delim} || "\t";
    my $method = $arg->{method};

    my $out;
    open F, "<$file" or return 0;
    my $hdr = <F>;
    chomp $hdr;
    my @hdr = split(/$delim/,$hdr);
    my %data;
    while (<F>) {
	chomp;
	my @data = split /\t/;
	foreach my $key (@hdr) {
	    $data{$key} = shift @data;
	}
	my $stat = $this->run_handler("import_record",\%data);
	# return value can be ignored;  \%data is unchanged if no
	# handler is present
	if ($method eq "update") {
	    $this->update($table,\%data);
	}
	else {
	    $this->insert($table,\%data);
	}
    }
    close F;
    return 1;
}		

#------------------------------------------------------------------------
# Queries
#
# A query is a reference to a hash specifying a set of records:
#
# table=>the table the records come from
# match=>ref to a match hash to select records from the table
# sort=>ref to a list of columns to sort on
# start=>first record to display
# num=>number of records to display
#
#   do_query - fetches the records specified by a query
#   sizeof_query - return total number of records in last query
#   encode_query - converts a query to a printable string
#   decode_query - creates a query from an encoded string
#------------------------------------------------------------------------

sub do_query {
    my ($this,$query) = @_;
    if (! $query->{table}) { return (); };
    if (! $query->{start}) { $query->{start} = 0; }
    if (! $query->{num}) { $query->{num} = $config{report}->{page_length}; }
    my $data;
    if (exists $query->{match}) {
	# select matching data
        $data = $this->fetch_match($query->{table}->[0],$query->{match});
    }
    else {
	# no match condition; fetch everything!!!  (use with caution)
	$data = $this->fetch_all($query->{table}->[0]);
    }
    my @data;
    if (ref $query->{sort} eq "ARRAY") {
	# sort requested
	@data = $this->sort_rows($query->{table}->[0],$data,@{$query->{sort}});
    }
    else {
	# no sort
	#@data = @$data;
	# sort on default key - primary display column
	@data = $this->sort_rows($query->{table}->[0],$data,
				 &primary_column($this,$query->{table}->[0]));
    }
    # save total number of records as a package global for later reference
    $total_records_in_query = scalar @data;
    my $start = $query->{start};
    my $end = $query->{start}+$query->{num}-1 < $total_records_in_query - 1 ?
	$query->{start}+$query->{num}-1 : $total_records_in_query - 1;

    return @data[$start..$end];
}

sub sizeof_query {
    return $total_records_in_query;
}

sub encode_query {
    my ($this,$query) = @_;
    my %qhash = %$query;
    if (exists $query->{match}) {
	$qhash{match} = encode_base64(&EncodeHash(%{$query->{match}}),"");
    }
    if (exists $query->{sort}) {
	$qhash{sort} = join ",",@{$query->{sort}};
    }
    my $qurl = &EncodeHash(%qhash);
    return encode_base64($qurl,"");
}

sub decode_query {
    my ($this,$qstr) = @_;
    my $qurl = decode_base64($qstr);
    my %qhash = &DecodeString($qurl);
    if (exists $qhash{match}) {
	my $match_url = decode_base64($qhash{match});
	my %match = &DecodeString($match_url);
	$qhash{match} = \%match;
    }
    if (exists $qhash{sort}) {
	my @sort = split /,/, $qhash{sort};
	$qhash{sort} = \@sort;
    }
    if (exists $qhash{table}) {
	my @tables = split /,/, $qhash{table};
	$qhash{table} = \@tables;
    }
    return \%qhash;
}

#------------------------------------------------------------------------
# Templates
#
# A report template is a string with marker tags to accept data from
# an arbitrary datahash.
#------------------------------------------------------------------------

sub set_template {
    my ($this,$table,$template) = @_;
    if (! $this->{report_template}) {
	$this->{report_template} = {};
    }
    $this->{report_template}{$table} = $template;
    return;
}

sub get_template {
    my ($this,$table) = @_;
    if (ref $this->{report_template} eq "HASH") {
	return $this->{report_template}{$table};
    }
    return undef;
}

1;
