#!/usr/bin/perl
#-----------------------------------------------------------------------
#
#   Copyright 2015 Exware Solutions, Inc.  http://www.exware.com
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

package ExSite::Date;

use strict;
use ExSite::Config;
use ExSite::Base;
use ExSite::Form;
use ExSite::Misc;
use ExSite::Time;
use ExSite::ML;
use ExSite::Object;

use vars qw(@ISA);
@ISA = qw(ExSite::Object);
#@ISA = qw(ExSite::Time ExSite::Object);

sub my_type { return "content_date"; }

sub name {
    my $this = shift;
    if ($this->defined()) {
	return $this->getdata("description") || $this->getdata("type");
    }
    return "n/a";
}

sub has_range {
    my $this = shift;
    return ($this->getdata("enddate") !~ /^0/);
}

sub show {
    my ($this,%opt) = @_;
    return $this->name . ": " . $this->show_date_range();
}

# display start and end date as a single value
# can optionally pass the start/end datetimes

sub show_date_range {
    my ($this,$startdate,$enddate,$ndate) = @_;
    $ndate or $ndate = 1;
    my $t1 = $startdate ? 
	new ExSite::Time($startdate,"sql_datetime") : $this->get_start();
    my $t2 = $enddate ? 
	new ExSite::Time($enddate,"sql_datetime") : $this->get_end();

    if ($t1->diff($t2) <= 0) {
	return $this->show_start($t1);
    }

    if ($t2->write("sql_date") ne $t1->write("sql_date")) {
	# different days
	if ($ndate==1 && ($t1->write("time24") !~ /^[\s0]0:00/ || $t2->write("time24") !~ /^[\s0]0:00/)) {
	    # time is significant, show complete dates
	    return $this->show_start($t1) . " - " . $this->show_end($t2);
	}
	elsif ($t1->write("year") != $t2->write("year") || $t1->write("raw_month") != $t2->write("raw_month")) {
	    # different months
 	    return $t1->write("date_long") . " - " . $t2->write("date_long");
 	}
 	elsif ($t1->write("raw_day") != $t2->write("raw_day")) {
	    # different days in same month
 	    return $t1->write("month_long") . " " . $t1->write("raw_day") . " - " . $t2->write("raw_day") . ", " . $t1->write("year");
 	}
    }
    else {
	# same day 
        my $out = $t1->write("date")." ";

	if ($t1->write("time") != /^[\s0]0:00/) {
	    $out .= $t1->write("time");
	}
        if ($t2->write("time") ne $t1->write("time") && $t2->write("time") != /^[\s0]0:00/) {
	    $out .= " - " . $t2->write("time");
	}
	return $out;
    }
}

sub show_start {
    my ($this,$start) = @_;
    $start or $start = $this->get_start();
    return $this->show_date($start);
}

sub show_end {
    my ($this,$end) = @_;
    $end or $end = $this->get_end();
    return $this->show_date($end);
}

sub show_date {
    my ($this,$time,$format) = @_;
    $time or $time = $this->get_start();
    if ($format) {
	return $time->write($format);
    }
    elsif ($time->write("time24") =~ /^[\s0]0:00/) {
	# ignore 00:00 times
	return $time->write("date_long");
    }
    else {
	return $time->write("datetime2");
    }
}

# convert to ExSite::Time objects

sub get_start {
    my ($this,%opt) = @_;
    my $t = new ExSite::Time;
    $t->set($this->getdata("start"),"sql_datetime");
    return $t;
}

sub get_end {
    my ($this,%opt) = @_;
    my $t = new ExSite::Time;
    $t->set($this->getdata("end"),"sql_datetime");
    return $t;
}

# is_on_date: true if the passed date matches the evt_date (not time)

sub is_on_date {
    my ($this,$date) = @_;  # $date should be a Time object
    if ((ref $date) =~ /Time/) {
	my $date_day = $date->write("sql_date");
	my ($st_day,$end_day);
	$st_day = $this->getdata("date");
	$end_day = $this->getdata("enddate");
	if ($end_day =~ /^0/) {
	    # no end date
	    return ($date_day eq $st_day);
	}
	else {
	    # we must fall between start and end days
	    return ($st_day le $date_day && $end_day ge $date_day);
	}
    }
    else {
	$this->error("is_on_date: Invalid date");
    }
    return 0;
}

# is_at_time : true if passed date & time matches this evt_date

sub is_at_time {
    my ($this,$date) = @_;
    if ((ref $date) =~ /Time/) {
	my $date_day = $date->write("sql_date");
	my $date_time = $date->write("time24");
	my ($st_day,$st_time,$end_day,$end_time);
	$st_day = $this->getdata("date");
	$st_time = $this->getdata("time");
	if ($this->has_range) {
	    $end_day = $this->getdata("enddate");
	    $end_time = $this->getdata("endtime");
	    if ($date_time =~ /^0?0:00$/ || 
		($st_time =~ /^0?0:00$/ && $end_time =~ /^0?0:00$/)) {
		# time values not significant
		return 1 if ($st_day le $date_day && $end_day ge $date_day);
	    }
	    else {
		# times are significant - our datetime must fall between
		# the start and end datetimes
		my $date = "$date_day $date_time";
		my $st = "$st_day $st_time";
		my $end = "$end_day $end_time";
		return 1 if ($st le $date && $end ge $date);
	    }
	}
	else {
	    # no end date/time
	    if ($date_time && $st_time) {
		# must be an exact date/time match
		return 1 if ($date_day eq $st_day && $date_time eq $st_time);
	    }
	    else {
		# need only match the day
		return 1 if ($date_day eq $st_day);
	    }
	}
    }
    else {
	$this->error("is_on_date: Invalid date");
    }
    return 0;
}

# process forms

### FIXME: we don't run this if we go through doform

sub validate {
    my $this = shift;
    my @err;
    if ($this->defined) {
	if ($this->{data}{enddate} && $this->{data}{enddate} !~ /^0000-00-00$/) {
	    my $sttime = $this->{data}{time} || "00:00";
	    my $endtime = $this->{data}{endtime} || "00:00";
	    my $st = new ExSite::Time("$this->{data}{date} $sttime","sql_datetime");
	    my $diff = $st->diff("$this->{data}{enddate} $endtime","sql_datetime");
	    if ($st->diff("$this->{data}{enddate} $endtime","sql_datetime") < 0) {
		push @err, "End date is before start date";
	    }
	}
    }
    push @err, $this->SUPER::validate();
    return @err;
}

1;

