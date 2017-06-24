#------------------------------------------------------------------------
# ExSite::Excel
#
# Excel integration tools
#
# Methods:
#   ExcelExport : takes an array of datahashes, and exports them to
#                 an MS-Excel file which can be written to disk or stdout
#-----------------------------------------------------------------------
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

package ExSite::Excel;
use ExSite::Config;
use Encode;
use strict;
use Carp;

require Exporter;
use vars qw(@ISA @EXPORT);
@ISA = qw(Exporter);
@EXPORT = qw(&ExcelExport);

#------------------------------------------------------------------------
# Excel tools - for importing/exporting Excel spreadsheets
# 
# $name is the excel file you want to write to, or "-" for stdout
# $records is the reference to the record you want to write to excel
# $col_to_print is the columns in the recored you want to print to excel; 
#    if not defined, writes all the columns.
# say we have @col_to_print=(A;B), where A is the name of the 
# corresponding column you want it printed on excel and B is the actual 
# name of the column in the database
#------------------------------------------------------------------------

sub ExcelExport{
    my ($records, $name, $col_to_print,$title)=@_;

    require Spreadsheet::WriteExcel;
    #require Spreadsheet::ParseExcel;
    #require Spreadsheet::ParseExcel::Simple;

    my $workbook=Spreadsheet::WriteExcel->new($name);
    my $format=$workbook->addformat();    
    my $worksheet=$workbook->addworksheet();
    # keep leading zeros for things like zipcodes
    $worksheet->keep_leading_zeros();

    my $increment;
    if (defined $title){$increment=1; $worksheet->write(0,0,$title,$format);}
    else{$increment=0;}
    my $i=0+$increment;
    my $j;
    my $passed=0;
    
    my @r_record;
    
    if (ref($records) eq "HASH"){@r_record=keys(%$records);}
    elsif (ref($records) eq "ARRAY"){@r_record=@$records;}
    else{ croak "record does not match the required format in Excel::Export<br>";}
    
    # if the data is UTF-8 then it needs special handling.
#    my $writer = ($config{server}->{db}->{charset} eq "UTF-8")? \&write_utf8 : \&write;
    my $writer = ($config{charset} eq "UTF-8")? \&write_utf8 : \&write;
    
    foreach my $temp(@r_record) #used to be @$records
    {
	$j=0;
	if (defined $col_to_print->[0]) 
	{
	    foreach my $temp2(@$col_to_print)
	    {
		my @splitlist=split(/;/, $temp2);
		if ($passed==0)
		{
			my $value = $splitlist[0];
		    $format->set_bold();			
		    &$writer($worksheet, 0+$increment,$j,$value,$format);
 		}
		if (ref($records) eq "HASH"){
			my $value = $records->{$temp}->{$splitlist[1]};
			my $format = &get_format($workbook,$value);
		    &$writer($worksheet, $i+1,$j,$value,$format);
		}
		elsif (ref($records) eq "ARRAY"){
			my $value = $temp->{$splitlist[1]};		
			my $format = &get_format($workbook,$value);
		    &$writer($worksheet, $i+1,$j,$value,$format);
		}
		$j++;
	    }
	}
	else
	{
	    foreach my $temp2(keys(%{$temp}))
	    {
		if ($passed==0){
		    &$writer($worksheet, 0+$increment,$j,$temp2); #prints the titles of cols
		}
		if (ref($records) eq "ARRAY"){
		    &$writer($worksheet, $i+1,$j,$temp->{$temp2}); #prints the contents if the record is an ref. to an array
		}
		elsif (ref($records) eq "HASH"){
		    &$writer($worksheet, $i+1,$j,$records->{$temp}->{$temp2}); #prints the contents if the record is an ref. to a hash
		}
		$j++;
	    }
	}
	$passed=1;
	$i++;
    }
    $workbook->close();
}

sub get_format {
	my ($workbook,$value) = @_;
	# set the default format for dates.
	# match dates in the following format: yyyy-mm-dd with optional time mm:ss:dd	
	if ($value =~ qr[^(\d{4})\-(\d{2})\-(\d{2})\s?(\d{2})?:?(\d{2})?:?(\d{2})?]) {
	# change to the date format required by write_date_time().
	my $date = sprintf "%4d-%02d-%02dT%02d:%02d:%02d", $1, $2, $3, $4, $5, $6;	
	if ($4 && $5 && $6) {
		return $workbook->add_format(num_format => 'yyyy-mm-dd hh:mm');
	} 
	else {
		return $workbook->add_format(num_format => 'yyyy-mm-dd');
	}
	}
	return undef;
}

# us the default write method
sub write {
    my ($ws, $i, $j, $value, $format)=@_;
	if ($value =~ qr[^(\d{4})\-(\d{2})\-(\d{2})\s?(\d{2})?:?(\d{2})?:?(\d{2})?]) {
	# change to the date format required by write_date_time().
	my $date = sprintf "%4d-%02d-%02dT%02d:%02d:%02d", $1, $2, $3, $4, $5, $6;		
	$ws->write_date_time($i, $j, $date, $format);
	}
    elsif ($value =~ /^[\+\-\.\dEe]+$/) {
	# let $ws figure out if this is a number or not
	$ws->write($i, $j, $value, $format);
    }
    else {
	# non-numeric characters - force to string so that we don't
	# accidentally interpret raw data as formulas
	$ws->write_string($i, $j, $value, $format);
    }
}

# we are receiving raw UTF-8 data, so we have to decode it first
sub write_utf8 {
    my ($ws, $i, $j, $value, $format)=@_;
    &write($ws,$i,$j,Encode::decode('UTF-8', $value),$format);
}

1;
