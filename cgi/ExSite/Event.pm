#!/usr/bin/perl
#-----------------------------------------------------------------------
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

package ExSite::Event;

use strict;
use ExSite::Config;
use ExSite::Base;
use ExSite::Form;
use ExSite::Misc;
use ExSite::ML;
use ExSite::Content;

use vars qw(@ISA);
@ISA = qw(ExSite::Content);

sub my_subtype { return "event"; }

sub is_activity {
    my $this = shift;
    return ($this->parent->subtype() eq "event");
}

sub main_event {
    my $this = shift;
    my $event = $this;
    while ($event->parent->subtype eq "event") {
	$event = $event->parent;
    }
    return $event;
}

sub activities {
    my $this = shift;
    return $this->get_contents("event"); # returns array, not objectlist!
}

sub has_activities {
    my $this = shift;
    my @act = $this->get_contents("event");
    return scalar @act;
}

# event_group - all related events, as an ObjectList 

sub event_group {
    my $this = shift;
    my $mainevt = $this->main_event;
    my @evt;
    foreach my $edata ($mainevt->get_descendants("event")) {
	push @evt, new ExSite::Event(data=>$edata);
    }
    return @evt;
}

sub has_registration {
    my $this = shift;
    my @fee = $this->get_contents("fee");
    return (scalar @fee > 0);
}

sub filename {
    my $this = shift;
    return $this->name().".html";
}

sub show {
    my ($this,%opt) = @_;
    if (! $this->exists) {
	return $this->error("No such event.");
    }
    my $input = new ExSite::Input;
    my $query = $input->query();
    if ($query->{vcal} && $this->url_is_me()) {
	# generate an ics file instead of an HTML view
	my $p = $share{Page} || $share{ML};
	$p->cancel;
	print "Content-type: text/calendar\ncontent-disposition: attachment; filename=event.ics\n\n";
	print $this->vcalendar();
	return;
    }
    $opt{event_date} = $this->show_event_date(); # in case a format has been defined
    return $this->SUPER::show(%opt);
}

# show a simple date

sub show_event_date {
    my $this = shift;
    my $out;
    my $ml = &get_obj("ML");
    if ($this->wf_status eq "canceled") {
	$out .= $this->warn($msg{"This event has been canceled."});
    }
    my $simple_date = $this->show_date_range;
    if ($simple_date) {
	$out .= $ml->p($simple_date,{class=>"eventDate"});
    }
    return $out;
}

sub preview {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
#    my $out .= $ml->h1($this->title);
#    $out .= $this->show_event_date();
#    $out .= $this->show_revision(%opt);
    my $out = $this->show(%opt);
    $out .= $this->check_publish_rule();
    return $ml->div($out,{class=>"event"});
}

### description could be modified to show locations, event types

sub description { 
    my $this = shift; 
    my $out = $this->dcmeta("description");
    if (! $out) {
	if ($this->has_content) {
	    my $html = $this->revision()->view()->get_html();
	    return &make_teaser_text($html);
	}
    }
    return $out;
}

# summary - used for listings

sub summary {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    my $format = $opt{format} || $config{content}{format}{event_summary} ||
	$ml->div(
	    $ml->div("[[date]]",{class=>"eventDate"}).
	    $ml->div($ml->a("[[label]]",{href=>"[[link]]"}),{class=>"eventLink"}),
	    {class=>"EventSummary"}
	);
    return $this->show_formatted($format,(date=>$this->show_date_range()));
}

# tools (vcal link)

sub tools {
    my $this = shift;
    my $ml = &get_obj("ML");
    my $vcalurl = $this->is_publishable ? $this->httppath . "/" . $this->name . ".ics" : $this->link(vcal=>1);
    return $ml->p($ml->a(&substitute($msg{"Add <i>[[event]]</i> to my calendar."},{event=>$this->label}),{href=>$vcalurl}),{class=>"vCalendarLink"});
}

# index: show activities, fees, etc.

sub index {
    my ($this,%opt) = @_;
    my $out;
    my $ml = &get_obj("ML");

    # break index into activities, registration fees, and other

    my @contents = $this->get_contents();
    my (@evt,$feeout,$otherout);
    foreach my $c (@contents) {
	my $type = $c->subtype();
	next if ($c->hide_from("index"));
	if ($type eq "event") {
	    if (! $share{Page}) { $c->set("content_link_type","id"); }
	    push @evt, $c;
#	    $evtout .= $c->summary(format=>$evtfmt,%opt);
	}
	elsif ($type eq "fee") {
	    if (! $share{Page}) { $c->set("content_link_type","id"); }
	    $feeout .= $c->summary(%opt);
	}
	elsif ($c->navtype eq "item") {
	    $otherout .= $c->summary(%opt);
	}
    }

    my @sched;
    my $dates = $this->get_calendar_dates();
    if ($dates->count > 1) {
	# multiple schedule dates
	while (my $date = $dates->next) {
	    my $name = $date->getdata("description") || $this->title;
	    push @sched, { event=>$name, date=>$date->show_date_range(), sort=>$date->getdata("start") };
	}
    }
    if (scalar @evt > 0) {
	# include activities in schedule
	foreach my $evt (@evt) {
	    push @sched, { event=>$ml->a($evt->title,{href=>$evt->link()}), 
			   date=>$evt->show_date_range(),
			   sort=>$evt->get_date->getdata("start"),
	    };
	}
    }
    if (@sched > 0) {
	my @by_date = sort { $a->{sort} cmp $b->{sort} } @sched;
	my $evtout;
	foreach my $evt (@by_date) {
	    $evtout .= $ml->tr($ml->td($evt->{date}).$ml->td($evt->{event}));
	}
	my $schedule_name = $opt{schedule} || "Schedule";
	$out .= $ml->table(
	    $ml->caption($schedule_name).$ml->tbody($evtout),
	    {class=>"eventSchedule"}
	    );
    }
    if ($feeout) {
	$out .= $ml->div(
	    $ml->h2($msg{Registration}).
	    $ml->div($feeout,{class=>"feeIndex"}),
	    {class=>"eventRegistration"}
	    );
    }
    if ($otherout) {
	$out .= $ml->div(
	    $ml->h2($msg{"More Information"}).
	    $ml->div($otherout,{class=>"eventInfo"}),
	    {class=>"eventInfoIndex"}
	    );
    }
    return $ml->div($out,{class=>"eventIndex"});
}

# simple vcalendar implementation
# - each date is output as a separate vevent in the vcalendar object

sub vcalendar {
    my ($this,%opt) = @_;
    my $out;
    $out .= "BEGIN:VCALENDAR\r\n";
    $out .= "VERSION:2.0\r\nPRODID:-//Exware Solutions Inc.//ExSite v$ExSite::Config::VERSION//EN\r\n";
    $out .= $this->vevent(%opt);
    $out .= "END:VCALENDAR\r\n";
    return $out;
}

sub vevent {
    my ($this,%opt) = @_;
    my @vcal;
    my $now = new ExSite::Time();
    my $dates = $this->get_calendar_dates();
    my $owner = $this->owner; ######
    while (my $date = $dates->next()) {
	push @vcal, "BEGIN:VEVENT";
	push @vcal, "UID:ExSite-Event-".$this->id()."-".$opt{uid}."@".$config{server}{domain};
	push @vcal, "DTSTAMP:".$now->write("iso_basic");

	my $t1 = $date->get_start();
	my $t2 = $date->get_end();
	
	if ($t1->has_time) {
	    push @vcal, "DTSTART:".$t1->write("iso_basic");
	    if ($t1->diff($t2) > 0) {
		push @vcal, "DTEND:".$t2->write("iso_basic");
	    }
	}
	else {
	    # iso dates with hyphens don't seem to be accepted by icalendar
	    push @vcal, "DTSTART:".$t1->write("%YYYY%MM%DD");
	    if ($t1->diff($t2) > 0) {
		$t2->add(1,"day");  # because vcal dates are non-inclusive
		push @vcal, "DTEND:".$t2->write("%YYYY%MM%DD");
	    }
	}

	# include date description in summary
	my $summary = $this->name;
	my $date_descr = $date->getdata("description");
	if ($date_descr) {
	    $summary .= " - ".$date_descr;
	}
	push @vcal, "SUMMARY:".$summary;
	
	my $evt_descr = &html_to_plaintext($this->get_html());
	if ($evt_descr) {
	    $evt_descr =~ s/\r?\n/\\n/g;
	    push @vcal, "DESCRIPTION:$evt_descr";
	}

	my $child = $this->get_children();
	if ($child->{evt_location}) {
	    push @vcal, "LOCATION:".$this->location();
	}

	push @vcal, "URL;VALUE=URI:".$this->get_uri()->write_full();

	# cancellations
	if ($this->wf_status =~ /cancel/) {
	    push @vcal, "METHOD:CANCEL";
	    push @vcal, "STATUS:CANCELLED";
	}

	push @vcal, "END:VEVENT";
    }

    my $out;
    { # limit lines to 75 bytes
	use bytes;
	foreach my $line (@vcal) {
	    if (length($line) > 73) {
		my $l = substr $line, 0, 73, "";
		$out .= "$l\r\n";
		while (length($line) > 72) {
		    $l = substr $line, 0, 72, "";
		    $out .= " $l\r\n";
		}
		if ($line) { $out .= " $line\r\n"; }
	    }
	    else {
		$out .= "$line\r\n";
	    }
	}
    }
    return $out;
}

# use date directories for events in calendars

sub my_subdir {
    my $this = shift;
    if ($this->parent->subtype eq "calendar") {
	my $date = $this->get_date();
	if ($date) {
	    return $date->show_date($date->get_start(),"%YYYY/%MM");
	}
	# undated "events" are published direct to the calendar directory
    }
    # activities will use their parent's dir, so should end up in the same place
    return undef;
}

sub publish_rule_heuristic {
    my $this = shift;
    # events with registration should be dynamic, so that fees and pricing
    # are accurately displayed
    return "dynamic" if ($this->has_registration() && $this->in_future());
    return $this->SUPER::publish_rule_heuristic();
}

# publish_content: publish event, and all containers up to the section
# Publishing an event may affect the calendar upcoming view, and there 
# may be previews right up to the home page.

sub publish_content {
    my ($this,%opt) = @_;
    # do not publish if we came from an alias
    return undef if ($this->alias);
    $this->{publish} = 1;
    my $ml = &get_obj("ML");
    print $ml->li("Publishing event " . $ml->em($this->name));
    print "<ul>\n";
    $this->subpublish(%opt);  # descendants
    $this->publish_up(%opt);  # ancestors
    print "</ul>\n";
}

sub publish_self {
    my ($this,%opt) = @_;
    # do not publish if we came from an alias
    return undef if ($this->alias);
    # publish event
    $this->SUPER::publish_self(%opt);
    my $diskfile = new ExSite::Diskfile( base => $this->basedir,
					 path => $this->subdir,
					 filename => $this->name() . ".ics",
					 contents => $this->vcalendar() ); 
   if ($this->is_publishable) {
	# publish ics file
	$diskfile->publish();
    }
    elsif ($diskfile->exists) {
	# remove ics file
	$diskfile->unpublish();
    }
}

#=== Date queries

# display the date

sub date { &show_date(@_); }
sub show_date {
    my ($this,$type,%opt) = @_;
    my $date = $this->get_date();
    if ($date && $date->defined) {
	return $this->format_date($date->get_start);
    }
    return undef;
}

# display start and end date as a single value
# different from Date::show_date_range, which shows the range for a single
# date record; this shows the date range across all date records.

sub show_date_range {
    my ($this) = @_;
    my ($start,$end) = $this->get_date_range();
    return undef if (! $start);
    my $t1 = new ExSite::Time($start,"sql_datetime");
    if ($start eq $end) {
        return $this->format_date($t1);
    }
    # start and end are different
    my $t2 = new ExSite::Time($end,"sql_datetime");

    if ($t1->diff($t2) <= 0) {
	$this->warn("Event end date is before start date");
	return $this->format_date($t1);
    }

    if ($t2->write("sql_date") ne $t1->write("sql_date")) {
	# different days
	if ($t1->write("time24") !~ /^[\s0]0:00/ || $t2->write("time24") !~ /^[\s0]0:00/) {
	    # time is significant, show complete dates
	    return $this->format_date($t1) . " - " . $this->format_date($t2);
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
    return undef; # can we ever get here?
}

sub format_date { 
    my ($this,$date,$format) = @_;  # $date is a Time object
    if (! ref $date) {
	my $start = $this->get_date();
	$date = new ExSite::Time($start,"sql_datetime");
    }
    if ($format) {
	return $date->write($format);
    }
    if ($date->write("time24") =~ /^[\s0]0:00/) {
	# ignore 00:00 times
	return $date->write("date_long");
    }
    else {
	return $date->write("datetime2");
    }
}

# get all event dates as an ObjectList

sub get_calendar_dates {
    my ($this) = @_;
    my $list = $this->get_dates("calendar");
    $list->sort("start");
    return $list;
}

# return first datetime and last datetime in the date data
# NB: returns datetime scalars, not date objects

sub get_date_range {
    my ($this) = @_;
    my $dates = $this->get_calendar_dates();
    my @date;
    while (my $d = $dates->next) {
	next if ($d->getdata("status") ne "active");
	push @date, $d->getdata("start");
	my $end = $d->getdata("end");
	if ($end && $end !~ /^0/) {
	    push @date, $end;
	}
    }
    if (@date > 0) {
	my @sorted_date = sort { $a cmp $b } @date;
	return ($sorted_date[0],$sorted_date[-1]);
    }
    return (undef,undef);
}

# return best individual date for the event (earliest active start date)
# NB: returns date object

sub get_date {
    my ($this) = @_;
    my $dates = $this->get_calendar_dates();
    while (my $d = $dates->next) {
	next if ($d->getdata("status") ne "active");
	return $d;
    }
    return ExSite::Date->new();
}

# in_future, in_past : test for relative dates
# if $end is true, test against the event end date instead of the start date

sub in_future {
    my ($this,$end) = @_;
    my $date = $this->get_date();
    if ($date) {
	my $now = new ExSite::Time();
	my $comptime = $end ? $date->get_end() : $date->get_start();
	return ($now->diff($comptime) > 0);
    }
    return undef;
}

sub in_past {
    my ($this,$end) = @_;
    my $date = $this->get_date();
    if ($date) {
	my $now = new ExSite::Time();
	my $comptime = $end ? $date->get_end() : $date->get_start();
	return ($now->diff($comptime) < 0);
    }
    return undef;
}

#=== locations

sub venues {
    my $this = shift;
    my @loc = $this->get_contents("location");
    return wantarray ? @loc : \@loc;
}

sub venue {
    my $this = shift;
    my @loc = $this->venues();
    if (@loc > 0) {
	return $loc[0];
    }
    return undef;
}

#=== DB

# load the record and metadata

sub loaded {
    my $this = shift;
    if (! $this->{data} || ! $this->{children}) {
	return $this->load();
    }
    return $this->{data};
}

sub load {
    my $this = shift;
    if ($this->SUPER::load()) {
	$this->load_children();
    }
    return $this->{data};
}

1;

