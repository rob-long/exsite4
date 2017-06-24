#------------------------------------------------------------------------
# ExSite::ReportBuilder
#----------------------------------------------------------------------------
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

=head1 ReportBuilder

This is a utility for building tabulated reports.  It is
content-agnostic, and simply handles the formatting of data into a
table, depending on the input provided.  If the report is to be
interactive (links, JS, etc.), those features must be included in
the content of the report; ie. you must code the links, divs,
etc. yourself in the values that you pass.

=head2 Input

all input can be passed in a control hash

    title => content for titlebar; <caption>
    headers => array of header content; <th>
    data => array of arrays of data content; <td>
    tools => content for toolbar; <th class="ReportTools">
    foot => content for footer; <td class="ReportFooter">
    nodata => no data warning message
    show_tools_if_nodata => flag controlling tool display if no data
    show_data_if_nodata => flag controlling display of data area if no data
    width => width of report table
    cwidth => widths of columns (array of same size as headers)

The C<show_*> flags are true/false values to control the display of
those report fields/rows if there is no content for the respective
rows.  In other cases, the row is left out completely if there is no
content.

The toolbar is normally used to place links or buttons to operate 
on the report as a whole.  The footer area is used to append more 
information that pertains to the report (such as help text, or 
sub-reports).

You can append additional rows of data using the C<push()> method.  To
add one row, pass the row as an array of values or a reference to an
array of values:

    $rpt->push($dataref);
    $rpt->push(@data);

To add multiple rows, pass an array of rows, each one a reference
to an array of values:

    $rpt->push(@rows);

B<Simple Usage Example:>

    my $rpt = new ExSite::ReportBuilder(
                     title=>"My Report",
                     headers=>["Col 1","Col 2","Col 3"],
                     data=>\@data,
                     tools=>"<a href=\"$url\">do something</a>",
                     foot=>"report generated on ".localtime(),
              );
    $rpt->push($data);  # add another row of data
    $rpt->push(@data);  # add another row, or multiple rows of data
    print $rpt->make;   # generate the report

=head2 Output

ReportBuilder returns the HTML for display the formatted report.

Reports have 3 structures:

=over 4

=item * if data is an array of arrays:

    +----------------------------------------------+
    | title                                        |
    +------------+---------------------+-----------+
    | header1    | header 2            | header 3  |
    +------------+---------------------+-----------+
    | data1A     | data2A              | data3A    |
    +------------+---------------------+-----------+
    | data1B     | data2B              | data3B    |
    +------------+---------------------+-----------+
    | tools                                        |
    +----------------------------------------------+
    | foot                                         |
    +----------------------------------------------+

=item * if data is a simple array:

    +----------------------------------------------+
    | title                                        |
    +------------+---------------------------------+
    | header1    | data1                           |
    +------------+---------------------------------+
    | header2    | data2                           |
    +------------+---------------------------------+
    | header3    | data3                           |
    +------------+---------------------------------+
    | tools                                        |
    +----------------------------------------------+
    | foot                                         |
    +----------------------------------------------+

=item * if data is a scalar

    +----------------------------------------------+
    | title                                        |
    +----------------------------------------------+
    | data                                         |
    +----------------------------------------------+
    | tools                                        |
    +----------------------------------------------+
    | foot                                         |
    +----------------------------------------------+

=back

The HTML output uses the following CSS classes.  Example CSS can be found
in C<_ExSite/css/ExSite.css>.  (If you are using these reports in ExSite 
control panels, you will probably be using this stylesheet by default.)

    table.Report - the entire report
    table.Report caption - the title
    th.ReportTools - the tools row
    th - normal th elements are column headings
    tr.A, tr.B - alternating data rows
    td.rlabel, td.rdata - row elements in the 2nd report style, above
    td.ReportFooter - the footer row, if any

=head2 Dynamic Reports

Dynamic reports use DHTML functions to make the report fully interactive.
You can:

=over 4

=item * paginate the report with varying page lengths

=item * sort on columns

=item * filter/search by any string

=back

Set a report to be dynamic by setting the C<dynamic> attribute
when you instantiate the object, or with:

    $rpt->set("dynamic",1);

Dynamic reports use the Jquery framework (and the DataTables plugin) to
perform the dynamic report modifications.

=cut

#--------------------------------------------------------------------

package ExSite::ReportBuilder;
use strict;
use ExSite::Base;
use ExSite::Config;
use ExSite::Input;
use ExSite::Misc;
use ExSite::ML;

use vars qw(@ISA);

@ISA = qw(ExSite::Base);

sub new {
    my ($this,%opt) = @_;
    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;
    # copy options into object
    while (my ($key,$val) = each %opt) {
	$obj->{$key} = $val;
    }
    $obj->initialize_object;
    if ($obj->{data}) { $obj->format; }
    return $obj;
}

sub init {
    my ($this,%opt) = @_;
    # clear previous report parameters
    foreach my $param (qw(title headers data tools foot nodata show_tools_if_nodata format)) {
	delete $this->{$param};
    }
    # copy new parameters into object
    while (my ($key,$val) = each %opt) {
	$this->{$key} = $val;
    }
    if ($this->{data}) { $this->format; }
    return;
}

# can optionally enable jquery dynamic report operations
sub dynamic {
    my $this = shift;
    if ($this->nrow > $config{report}{page_length}) {
	# report is long enough to make dynamic
	if (exists $this->{dynamic}) {
	    # dynamic reporting explicitly set
	    return $this->{dynamic};
	}
	return $config{report}{dynamic};  # system default
    }
    return 0;
}

# content for titlebar
sub title {
    my $this = shift;
    $this->{title} = shift;
}

# CSS class of table
sub class {
    my $this = shift;
    $this->{class} = shift;
}

# array of column headings
sub headers {
    my $this = shift;
    if (ref $_[0] eq "ARRAY") {
	$this->{headers} = $_[0];
    }
    else {
	$this->{headers} = \@_;
    }
}

sub add_headers {
    my $this = shift;
    if (ref $_[0] eq "ARRAY") {
	push @{$this->{headers}}, @{$_[0]};
    }
    else {
	push @{$this->{headers}}, @_;
    }
}

# content for toolbar
sub tools {
    my $this = shift;
    $this->{tools} = shift;
}

# content for footer region
sub foot {
    my $this = shift;
    $this->{foot} = shift;
}

# message if no data exists
sub nodata {
    my $this = shift;
    $this->{nodata} = shift;
}

# does the report actually contain any data?
sub has_data {
    my $this = shift;
    return (ref $this->{data} eq "ARRAY" && scalar @{$this->{data}} > 0);
}

# flag to show toolbar if there is no data
sub show_tools_if_nodata {
    my $this = shift;
    $this->{show_tools_if_nodata} = shift;
}

# flag to show data area if there is no data
sub show_data_if_nodata {
    my $this = shift;
    $this->{show_data_if_nodata} = shift;
}

# the data itself, as an array, or an array of arrays
sub data {
    my ($this,@data) = @_;
    $this->{data} = \@data;
    $this->format;
}

# data rows in the footer (eg. totals)
sub footdata {
    my ($this,@data) = @_;
    $this->{footdata} = \@data;
}

# the data itself, as an array, or an array of arrays
sub clear {
    my ($this) = @_;
    $this->{data} = [];
    $this->{footdata} = [];
}

# decide which format (brief/full/simple) to use
sub format {
    my ($this,$fmt) = @_;
    if ($fmt) { 
	$this->{format} = $fmt; 
	return $fmt;
    }
    return $this->{format} if ($this->{format});
    if (ref $this->{data} eq "ARRAY") {
	if (ref $this->{data}[0] eq "ARRAY" || 
	    scalar @{$this->{data}} == 0) {
	    $this->{format} = "brief";
	    $this->{show_tools_if_nodata} = 1;
	}
	else {
	    $this->{format} = "full";
	    $this->{show_tools_if_nodata} = 0;
	}
    }
    elsif (!ref($this->{data}) && defined($this->{data}) && $this->{data}){
    	$this->{format} = "simple";
	$this->{show_tools_if_nodata} = 1;
    }
    else {
	$this->{format} = "brief";
	$this->{show_tools_if_nodata} = 1;
    }
    return $this->{format};
}

# how many columns?
sub ncol {
    my $this = shift;
    my $format = $this->format;
    if ($format eq "brief") {
	if ($this->{headers}) {
	    if (ref $this->{headers} eq "ARRAY") {
		return scalar @{$this->{headers}};
	    }
	    return 1;
	}
	elsif ($this->{data}) {
	    if (ref $this->{data} eq "ARRAY") {
		if (ref $this->{data}[0] eq "ARRAY" 
		    && scalar @{$this->{data}} > 0) {
		    return scalar @{$this->{data}[0]};
		}
		else {
		    return scalar @{$this->{data}};
		}
	    }
	    return 1;
	}
	return 1;
    }
    elsif ($format eq "simple") {
	return 1;
    }
    else {
	return 2;
    }
}

# how many rows?
sub nrow {
    my $this = shift;
    return ref $this->{data} eq "ARRAY" ? scalar @{$this->{data}} : 0;
}

# append more data to the report

sub push {
    my ($this,@data) = @_;
    $this->append("data",@data);
}

# append more data to the report footer

sub footpush {
    my ($this,@data) = @_;
    $this->append("footdata",@data);
}

# append data to body ("data") or footer ("footdata")

sub append {
    my ($this,$section,@data) = @_;
    $section or $section = "data";
    if (defined $this->{$section}) {
	# we are appending data
	if (ref $this->{$section}[0] ne "ARRAY") {
	    # convert single-row report to multi-row
	    $this->{$section} = [$this->{$section}];
	}
	# add new row(s)
	if (ref $data[0] eq "ARRAY") {
	    # @data is an array of arrayrefs
	    push @{$this->{$section}},@data;
	}
	else {
	    # @data is an array of scalars
	    push @{$this->{$section}},\@data;
	}
    }
    else {
	# this is the first data we've seen
	if (ref $data[0] eq "ARRAY") {
	    # @data is an array of arrayrefs
	    $this->{$section} = \@data;
	}
	else {
	    # @data is an array of scalars
	    $this->{$section} = [\@data];
	}
    }
}

# paginate 

sub paginate {
    my ($this,$page_length,$page) = @_;
    my $in = new ExSite::Input;
    my $indata = $in->combine;
    $page or $page = $this->{page} || $indata->{page} || 1;
    $page_length or $page_length = ($this->{page_length} || $config{report}{page_length});
    if ($this->{data}) {
	my $total = scalar @{$this->{data}};
	if ($total > $page_length) {
	    # trim data down to the pagination length
	    my $start = ($page - 1) * $page_length;
	    my $end = $page * $page_length - 1;
	    if ($end >= $total) {
		$end = $total - 1;
	    }
	    my @new_data;
	    for (my $i = $start; $i <= $end; $i++) {
		push @new_data, $this->{data}[$i];
	    }
	    $this->{data} = \@new_data;
	    my $ipage = 1;
	    my $footer;
	    my $ml = &get_obj("ML");
	    while (($ipage-1) * $page_length < $total) {
		if ($ipage == $page) {
		    $footer .= $ipage;
		}
		else {
		    $footer .= $ml->a($ipage,{href=>&relink(page=>$ipage)});
		}
		$footer .= "\n";
		$ipage++;
	    }
	    $this->{foot} .= $ml->p(&substitute($msg{"Showing page [[page]] of [[total]]. Go to page: "},{page=>$page,total=>($ipage-1)}).$footer);
	}
    }
}

# generate the report
sub make {
    my $this = shift;

    # use handler to build the report, if one is defined
    my $out = $this->run_handler("report_generic",$this);
    return $out if (defined $out);

    my $ml = &get_obj("ML");

    my $ncol = $this->ncol;

    # proceed with standard generic report

    my ($caption,$thead,$tbody,$tfoot);
    if ($this->{title}) {
	$caption = $this->{title};
    }

    if ($this->format eq "brief") {
	my $ndat = ref $this->{data} eq "ARRAY" ? scalar @{$this->{data}} : 0;
	if ($ndat) {
	    if ($this->{headers}) {
		my $row;
		foreach my $head (@{$this->{headers}}) {
		    my $width = undef;
		    if (exists $this->{cwidth} && ref $this->{cwidth} eq "ARRAY") {
			$width = shift @{$this->{cwidth}};
		    }
		    my %thopt = ( scope=>"col" );
		    if ($width) { $thopt{width} = $width; }
		    $row .= $ml->th($head, \%thopt);
		}
		$thead .= $ml->tr($row);
		#$tbody .= $ml->tr($row);
	    }
	    if ($this->{data}) {
		my $nrow = 0;
		foreach my $row (@{$this->{data}}) {
		    my $rowtext;
		    my @cclass = (exists $this->{cclass} && ref $this->{cclass} eq "ARRAY") ?
			@{$this->{cclass}} : ();
		    foreach my $col (@$row) {
			my %tdopt;
			my $cclass = shift @cclass;
			if ($cclass) { $tdopt{class} = $cclass; }
			$rowtext .= $ml->td($col,\%tdopt);
		    }
		    # alternate row classes A/B for CSS highlighting purposes
		    my $rowattr = $this->dynamic ? {} : {class=>($nrow % 2 ? "B" : "A")};
		    $tbody .= $ml->tr($rowtext,$rowattr);
		    $nrow++;
		}
	    }
	}
	else {
	    if (! $this->{show_data_if_nodata}) {
		my $nodata = $this->{nodata} || "No data";
		$tbody .= $ml->tr(
				  $ml->td(
					  $ml->span($nodata,{class=>"error nodata"}),
					  {colspan=>$this->ncol}
					  )
				  );
	    }
	    if (! $this->{show_tools_if_nodata}) {
		# don't show the tools
		delete $this->{tools};
	    }
	}
    }
    elsif ($this->format eq "simple") {
    	$tbody .= $ml->tr(
			  $ml->td($this->{data},{class=>"data"})
			  );
    }
    else {
	if ($ncol == 2) {
	    while (scalar @{$this->{headers}}) {
		my $head = shift @{$this->{headers}};
		my $data = shift @{$this->{data}};
		$tbody .= $ml->tr(
				  $ml->th($head,{class=>"rlabel", scope=>"row"}).
				  $ml->td($data,{class=>"rdata"})
				  );
	    }
	}
	else {
	    if ($this->{show_data_if_nodata}) {
		$tbody .= $ml->tr(
				  $ml->th(
					  $ml->p($this->{nodata},
						 {class=>"error"})
					  )
				  );
	    }
	    if (! $this->{show_tools_if_nodata}) {
		# don't show the tools
		delete $this->{tools};
	    }
	}
    }

    if ($this->{footdata} && $this->format eq "brief") {
	my $nrow = 0;
	foreach my $row (@{$this->{footdata}}) {
	    my $rowtext;
	    my @cclass = (exists $this->{cclass} && ref $this->{cclass} eq "ARRAY") ?
		@{$this->{cclass}} : ();
	    foreach my $col (@$row) {
		my %tdopt;
		my $cclass = shift @cclass;
		if ($cclass) { $tdopt{class} = $cclass; }
		$rowtext .= $ml->td($col,\%tdopt);
	    }
	    # alternate row classes A/B for CSS highlighting purposes
	    my $rowattr = $this->dynamic ? {} : {class=>($nrow % 2 ? "B" : "A")};
	    $tfoot .= $ml->tr($rowtext,$rowattr);
	    $nrow++;
	}
    }
    if ($this->{tools}) {
	$tfoot = $ml->tr(
			 $ml->th($this->{tools},{class=>"ReportTools", colspan=>$ncol})
			 );
    }
    if ($this->{foot}) {
	$tfoot .= $ml->tr(
			 $ml->td($this->{foot},{class=>"ReportFooter", colspan=>$ncol})
			 );
    }
    
    my %tabledata;
    if ($caption) { $tabledata{caption} = $caption; }
    if ($thead) { $tabledata{thead} = $thead; }
    if ($tfoot) { $tabledata{tfoot} = $tfoot; }
    if ($tbody) { $tabledata{tbody} = $tbody; }

    my $class = $this->{class} || "Report";
    if ($this->nrow > 0 && $this->ncol >= $config{report}{compact_columns}) {
	$class .= " compact";
    }
    if ($this->dynamic) {
	# dataTables preamble
	$class .= " dataTable";
	my $dtconf;
	if (require JSON) {
	    # datatables is fully configurable using report.dataTable in
	    # the config settings, if JSON is available.
	    my %dtconf = (keys %{$config{report}{dataTable}} > 0) ?
		%{$config{report}{dataTable}} : 
		( sPaginationType => "full_numbers",
		  aaSorting => [],
		 # bAutoWidth => JSON::false(),
		);
	    if ($config{report}{dynamic_page_length}) {
		$dtconf{iDisplayLength} = $config{report}{dynamic_page_length} + 0;
	    }
	    # set column sort rules - based on 1st row data
	    my @sort;
	    for (0 .. $ncol - 1) {
		my $datum = $this->{data}[0][$_];
		if ($datum =~ /(<[a-zA-Z]{1,8}( [^>]+?)?>)/) {
		    push @sort, { sType=>"html" };
		}
		elsif ($datum =~ /^[0-9]+$/) {
		    push @sort, { sType=>"numeric" };
		}
		else {
		    push @sort, undef; #"null";
		}
	    }
	    $dtconf{aoColumns} = \@sort;
	    $dtconf = JSON::to_json(\%dtconf);
	}
	else {
	    # non-configurable
	    $dtconf = '{ "sPaginationType" : "full_numbers" }';
	}

	$out .= &insert_js("jquery");
	$out .= &insert_js("jquery.dataTables.js");
	$out .= &insert_js("\n\$(document).ready(function() {
\$('.dataTable').dataTable(
$dtconf
);
} );\n");
    }

    my %tableattributes = ( class=>$class );
    if ($this->{width}) { $tableattributes{width} = $this->{width}; }

    $out .= $ml->table(\%tabledata,\%tableattributes);
    return $ml->div($out,{class=>"ReportWrapper"});
}

#--------------- export report to various formats --------------

sub export {
    my $this = shift;
    if ($this->format eq "simple") {
	return "Simple format reports cannot be exported";
    }
    $_ = shift;  # format
    if (/html/i) {
	return $this->make();
    }
    elsif (/csv/i) {
	return $this->export_csv($this->export_data());
    }
    elsif (/tab/i) {
	return $this->export_tab_delimited($this->export_data());
    }
    elsif (/excel|xls/i) {
	return $this->export_excel($this->export_data());
    }
    return "Unknown export format";
}

# export to CSV
sub export_csv {
    my $this = shift;
    my @row = @_;
    my $export_data;
    foreach my $row (@row) {
	my @data;
	foreach my $col (@$row) {
	    my $quote = 0;
	    $quote = ($col =~ /^\s/ || 
		      $col =~ /\s$/ ||
		      $col =~ /,/ ||
		      $col =~ /\r|\n/ ||
		      $col =~ /\"/);
	    $col =~ s/\"/\"\"/g;
	    push @data, $quote ? "\"$col\"" : $col;
	}
	$export_data .= join(",",@data)."\n";
    }
    return $export_data;
}

# export to tab-delimited
sub export_tab_delimited {
    my $this = shift;
    my @row = @_;
    my $export_data;
    foreach my $row (@row) {
	my @data;
	foreach my $col (@$row) {
	    $col =~ s/\n/\\n/g;
	    $col =~ s/\t/\\t/g;
	    push @data, $col;
	}
	$export_data .= join("\t",@data)."\n";
    }
    return $export_data;
}

# export to .xls - WARNING: this dumps to stdout
sub export_excel {
    my $this = shift;
    my @row = @_;

    require Spreadsheet::WriteExcel;
    my $workbook = Spreadsheet::WriteExcel->new("-");
    my $worksheet = $workbook->addworksheet();
    $worksheet->keep_leading_zeros();    
    my $i = 0;  # row
    my $j;      # col

    if ($this->{title}){
	my $format=$workbook->addformat();
	$format->set_bold();
	$worksheet->write(0,0,Encode::encode("ISO-8859-1", Encode::decode($config{charset}, $this->{title})),$format);
	$i++;
    }

    foreach my $row (@row) {
	$j = 0;
	foreach my $dat (@$row) {
	    my $clean_data = &html_to_plaintext($dat);
		# match dates in the following format: yyyy-mm-dd with optional time mm:ss:dd	    
		if ($clean_data =~ qr[^(\d{4})\-(\d{2})\-(\d{2})\s?(\d{2})?:?(\d{2})?:?(\d{2})?]) {
		# change to the date format required by write_date_time().
		my $date = sprintf "%4d-%02d-%02dT%02d:%02d:%02d", $1, $2, $3, $4, $5, $6;
		my $date_format;
		if ($4 && $5 && $6) {
			$date_format = $workbook->add_format(num_format => 'yyyy-mm-dd hh:mm');
		} else {
			$date_format = $workbook->add_format(num_format => 'yyyy-mm-dd');
		}
		$worksheet->write_date_time($i, $j, $date, $date_format);
		}
		elsif ($clean_data =~ /^[\+\-\.\dEe]+$/) {
		# let $worksheet figure out if this is a number or not
		$worksheet->write($i, $j, $clean_data);
	    }
	    else {
		# non-numeric characters - force to string so that we don't
		# accidentally interpret raw data as formulas
		$worksheet->write_string($i, $j, $clean_data);
	    }
	    $j++;
	}
	$i++;
    }
    $workbook->close();
}

# get the export data - returns a 2-D array of the report values
sub export_data {
    my $this = shift;
    my @row;
    if ($this->format eq "brief") {
	my $ndat = ref $this->{data} eq "ARRAY" ? scalar @{$this->{data}} : 0;
	if ($this->{headers}) {
	    my @head;
	    foreach my $h (@{$this->{headers}}) { push @head, $this->export_datum($h); }
	    push @row, \@head;
	}
	if ($this->{data}) {
	    my @data;
	    foreach my $row (@{$this->{data}}) {
		my @rowdata;
		foreach my $r (@$row) { push @rowdata, $this->export_datum($r); }
		push @data, \@rowdata;
	    }
	    push @row, @data;
	}
	if ($this->{footdata}) {
	    my @data;
	    foreach my $row (@{$this->{footdata}}) {
		my @rowdata;
		foreach my $r (@$row) { push @rowdata, $this->export_datum($r); }
		push @data, \@rowdata;
	    }
	    push @row, @data;
	}
    }
    else {
	if ($this->ncol == 2) {
	    while (scalar @{$this->{headers}}) {
		my $head = $this->export_datum(shift @{$this->{headers}});
		my $data = $this->export_datum(shift @{$this->{data}});
		push @row, [ $head, $data ];
	    }
	}
    }
    return @row;
}

sub export_datum {
    my ($this,$data) = @_;
    $data = &html_to_plaintext($data);
    $data =~ s/^\s+//;
    $data =~ s/\s+$//;
    require Encode;
	if ($data =~ /[^[:ascii:]]/) {
		# ascii characters are present
		if ($config{charset} !~ /ISO-8859-1/i) {
		$data = Encode::encode("ISO-8859-1", Encode::decode($config{charset}, $data));
		}
	}    
    return $data;
}

1;
