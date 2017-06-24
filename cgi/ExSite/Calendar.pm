#!/usr/bin/perl
#----------------------------------------------------------------------------
#
#   Copyright 2011 Exware Solutions, Inc.  http://www.exware.com
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

### a calendar is like a blog, but for "events" instead of "articles"

package ExSite::Calendar;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::ML;
use ExSite::HTML;
use ExSite::Util;
use ExSite::URI;
use ExSite::Content;
use ExSite::Event;

use vars qw(@ISA);
@ISA = qw(ExSite::Page);

use vars qw(@wd @wdy @weekday @mon @month @dayinmonth);
@wd = qw(Su Mo Tu We Th Fr Sa);
@wdy = qw(Sun Mon Tue Wed Thu Fri Sat);
@weekday = qw(Sunday Monday Tuesday Wednesday Thursday Friday Saturday);
@mon = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
@month = qw(January February March April May June July August September October November December);
@dayinmonth = qw(31 28 31 30 31 30 31 31 30 31 30 31);

sub my_subtype { return "calendar"; }

sub setup {
    my $this = shift;
    $this->setup_querylib();
    $this->SUPER::setup(@_);
}

sub preview {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    my $r = new ExSite::ReportBuilder(title=>"Events in ".$ml->em($this->name));
    $r->set("dynamic",1);
    $r->headers("Date","Event","Status");
    $this->fetch_events();
    my @date = reverse sort keys %{$this->{events}{start}};
    my %done;
    foreach my $date (@date) {
	foreach my $evtdata (@{$this->{events}{start}{$date}}) {
	    next if $done{$evtdata->{content_id}};
	    my $evt = new ExSite::Event(data=>$evtdata);
	    $r->push(
		$evt->show_date_range(),
		$ml->a($evt->title,{href=>$evt->link()}),
		$evt->showdata("status")
		);
	    $done{$evt->id} = 1;
	}
    }
    return &ExSite::HTML::DynTabBox(
        tabs => [ "preview", "all events" ],
        panes => [ $this->show(),
		   $r->make() ],
        );
}

# index - display a listing of events in the calendar
# options:
# start, end - date range
# limit

sub index {
    my ($this,%opt) = @_;
    $this->setup_querylib();
    my $ml = &get_obj("ML");
    my $out = $this->list_events($opt{start},$opt{end},$opt{limit}) ||
	$ml->p("No upcoming events.");
    return $ml->div($out,{class=>"Calendar"});
}

sub tools {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    my @tool;
    my $diskpath = $this->diskpath();
    my $path = $this->httppath();

    # archives
    if (-e "$diskpath/archive.html") {
	push @tool, $ml->a($ml->img(undef,{src=>"$config{server}{HTMLpath}/_ExSite/images/icons/date.png",width=>16,height=>16})."&nbsp;Archive",{href=>"$path/archive.html"});
    }
    else {
	### secure/dynamic archives ??

    }

    # RSS
    if (-e "$diskpath/index.rss") {
	push @tool, $ml->a($ml->img(undef,{src=>"$config{server}{HTMLpath}/_ExSite/images/icons/rss.png",width=>16,height=>16})."&nbsp;RSS",{href=>"$path/index.rss"});
    }
    else {
	### secure/dynamic RSS ??

    }

    # post event ?

    my $out;
    foreach my $tool (@tool) {
	$out .= $ml->div($tool,{class=>"calendarTool"});
    }
    return $ml->div($out,{class=>"calendarTools"});
}

# fetch_events: load all calendar events from DB

sub fetch_events {
    my $this = shift;
    return if (exists $this->{events});
    my $db = $share{DB};
    foreach my $event ($db->get_query("all events",$this->id)) {
	if ($event->{start} && $event->{start} !~ /^0/) {
	    my $t = new ExSite::Time($event->{start},"sql_datetime");
	    my $date = $t->write("sql_date");
	    $this->set_event_date("start",$date,$event);
	    if ($event->{end} && $event->{end} !~ /^0/) {
		my $t2 = new ExSite::Time($event->{start},"sql_datetime");
		my $date2 = $t->write("sql_date");
		if ($t->diff($t2) > 0) {
		    $t->add_approximate(1,"day");
		    while ($t->diff($t2) > 0) {
			my $date2 = $t2->write("sql_date");
			$this->set_event_date("on",$date2,$event);
			$t->add_approximate(1,"day");
		    }
		}
		else {
		    # set "on" in cases where end date is invalid
		    $this->set_event_date("on",$date,$event);
		}
	    }
	    else {
		# set "on" in cases where no end date
		$this->set_event_date("on",$date,$event);
	    }
	}
    }
    return $this->{events}
}

# add an event to $this->{events}

sub set_event_date {
    my ($this,$type,$date,$event) = @_;
    if ((ref $this->{events}{$type}{$date}) eq "ARRAY") {
	push @{$this->{events}{$type}{$date}}, $event;
    }
    else {
	$this->{events}{$type}{$date} = [$event];
    }
}

# find events in a time window from $this->{events}

sub select_events {
    my ($this,$start,$end) = @_;
    $this->fetch_events();
    my @event;
    my $date = $start;
    my $t = new ExSite::Time($date,"sql_date");
    if (exists $this->{events}{start}{$date}) {
	push @event, @{$this->{events}{start}{$date}};
    }
    while ($t->compare($end,"sql_date") > 0) {
	$t->add_approximate(1,"day");
	$date = $t->write("sql_date");
	if (exists $this->{events}{start}{$date}) {
	    push @event, @{$this->{events}{start}{$date}};
	}
    }
    return wantarray ? @event : \@event;
}

sub list_events {
    my ($this,$start,$end,$limit) = @_;
    if (! $start) {
	my $t = new ExSite::Time;
	$start = $t->write("sql_date");
	if (! $end) {
	    $t->add(1,"year");
	    $end = $t->write("sql_date");
	}
    }
    my $events = $this->select_events($start,$end);
    my ($out,$nevt,%done);
    my $ml = &get_obj("ML");
    foreach my $evt (@$events) {
	$nevt++;
	next if ($done{$evt->{content_id}});
	$done{$evt->{content_id}} = 1;
	my $e = new ExSite::Event(data=>$evt);
	next if (! $e->is_viewable);
	$out .= $ml->dt($e->show_date_range());
	$out .= $ml->dd($ml->a($e->title(),{href=>$e->get_url()})); #$e->show(view=>"small"));
	last if ($limit && $nevt == $limit);
    }
    if ($out) {
	$out = $ml->dl($out,{class=>"calendarEventList"});
    }
    return $out;
}

# get_archives : build monthly indexes

sub get_archives {
    my ($this,%opt) = @_;
    if (! $this->{archive}) {
	my $ml = &get_obj("ML");
	$this->fetch_events();
	my ($datedir,$current_month);
	my %evtdone;
	foreach my $date (keys %{$this->{events}{on}}) {
	    my $t = new ExSite::Time($date,"sql_date");
	    $datedir = $t->write("/%YYYY/%MM");
	    if (! exists $this->{archive}{$datedir}) {
		$this->{archive}{$datedir} = {};
	    }
	    foreach my $evt (@{$this->{events}{on}{$date}}) {
		$this->{archive}{$datedir}{$evt->{content_id}} = $evt;
	    }
	}
    }
    return $this->{archive};
}

# find - use the calendar itself as the page body

sub find {
    my ($this,$name) = @_;
    my $content = $this->SUPER::find($name);
    if ($name eq "body" && 
	(! $content ||                                 # error
	 ! $content->defined ||                        # nothing found
	 $content->getdata("parent") != $this->id)) {  # templated body
	# if we don't have an explicitly defined body, show the calendar
	$content = $this;
    }
    return $content;
}

# how should calendars be published?

sub publish_rule_heuristic {
    my $this = shift;
    # simple heuristic: list of upcoming events changes daily
    return "daily";
}

# publish - also publish events and feed

sub publish_self {
    my $this = shift;
    my $ml = &get_obj("ML");
    my $ui = &get_obj("UI");
    my $out;

    # publish calendar
    $this->is_publishable ?
	$this->publish_formatted() : $this->publish_redirect();

    # compile the archives
    my (%annual,$path);
    my $archive = $this->get_archives();

    # determine range of archives
    my @archive_date = sort keys %$archive;
    my $start = new ExSite::Time($archive_date[0],"/%YYYY/%MM");
    my $startyear = $start->get_YYYY;
    my $startmonth = $start->get_M;
    my $end = new ExSite::Time($archive_date[-1],"/%YYYY/%MM");
    my $endyear = $end->get_YYYY;
    my $endmonth = $end->get_M;

    # publish the archives
    my $base = $this->basedir;
    foreach my $year ($startyear .. $endyear) {
	foreach my $month (1 .. 12) {
	    next if ($year == $startyear && $month < $startmonth);
	    next if ($year == $endyear && $month > $endmonth);
	    $out = $ml->h1($this->title);
	    my $m = sprintf("%02d",$month);
	    my $date = "/$year/$m";
	    my $t = new ExSite::Time([$year,$month,1],"raw");
	    my $datehdr = $t->write("%MMMM %YYYY");
	    my $isodate = $t->write("iso_date");

	    # calendar navigation/header
	    my ($nextlink,$prevlink,$title);
	    $title = $t->write("%MMMM, %YYYY");
	    if ($year != $endyear || $month < $endmonth) {
		# next month link
		$t->add_approximate(1,"month");
		$path = $this->httppath . $t->write("/%YYYY/%MM");
		$nextlink = $ml->span($ml->a($t->write("%MMMM, %YYYY").$ui->FAIcon("right"),{href=>$path}),{class=>"calendarNextMonth"});
	    }
	    if ($year != $startyear || $month > $startmonth) {
		# previous month link
		$t->add_approximate(-2,"month");
		$path = $this->httppath . $t->write("/%YYYY/%MM");
		$prevlink = $ml->span($ui->FAIcon("left").$ml->a($t->write("%MMMM, %YYYY"),{href=>$path}),{class=>"calendarPrevMonth"});
	    }
	    my $header = $nextlink . $prevlink . $title;

	    # now compile the archives for this month
	    my $monthlist;
	    my @eventlist = sort { $a->{start} cmp $b->{start} } values %{$archive->{$date}};
	    foreach my $event (@eventlist) {
		my $evt = new ExSite::Event(data=>$event);
		$monthlist .= $ml->dt($evt->show_date_range());
		$monthlist .= $ml->dd($evt->summary(format=>"summary"));
	    }

	    $out .= $this->show_month({date=>$isodate,header=>$header},@eventlist);
	    if ($monthlist) {
		$out .= $ml->dl($monthlist);
	    }

	    # compile annual archives
	    #my $year = $t->write("raw_year");
	    #my $ym = $t->write("/%YYYY/%MM");
	    $annual{$year}{$date} .= $ml->div($ml->a($datehdr,{href=>$this->httppath.$date}),{class=>"calendarMonthLink"});

	    # publish month
	    $this->unexpand();
	    my $arch_out = $this->expand(content=>{body=>$out});
	    $path = $this->subdir . $date;
	    my $diskfile = new ExSite::Diskfile( base => $base,
						 path => $path,
						 filename => "index.html",
						 contents => $arch_out );
	    print $ml->li("Publishing $date archives");
	    $diskfile->publish();
	}
    }

    # publish years - only need to publish years with actual events

    my $allout;
    my $title = $ml->h1($this->title);
    my $subdir = $this->subdir;
    foreach my $year (reverse sort keys %annual) {
	$out = $ml->h2($year);
	foreach my $month (sort keys %{$annual{$year}}) {
	    $out .= $annual{$year}{$month};
	}
	$allout .= $ml->div($out,{class=>"calendarArchiveYear"});
	# publish year
	$this->unexpand();
	my $arch_out = $this->expand(content=>{body=>$ml->div($title.$out,{class=>"calendarArchive"})});
	my $subdir = "$subdir/$year";
	my $diskfile = new ExSite::Diskfile( base => $base,
					     path => $subdir,
					     filename => "index.html",
					     contents => $arch_out );
	print $ml->li("Publishing $year archives");
	$diskfile->publish();
    }

    # master archive index

    $this->unexpand();
    my $arch_out = $this->expand(
	content=>{
	    body=>$ml->div($title.$allout,{class=>"calendarArchive"})
	}
	);
    my $diskfile = new ExSite::Diskfile( base => $base,
					 path => $this->subdir,
					 filename => "archive.html",
					 contents => $arch_out );
    print $ml->li("Publishing master archive index");
    $diskfile->publish();

    if ($share{publish_content} != $this->id) {
	# publishing related files; we're probably done with the object data
	# try to unload to save memory
	$this->unload();
	$share{DB}{diagnostics}{info} = [];
    }
}

# rss - Calendar RSS shows upcoming events, soonest first

sub rss {
    my ($this,%opt) = @_;
    my $date = new ExSite::Time();
    my $today = $date->write("sql_date");
    $date->add(1,"year");
    my $next_year = $date->write("sql_date");
    my @evt = $this->select_events($today,$next_year);
    if (@evt > 0) {
	my $nitem;
	my $rss = new ExSite::RSS(xml=>1);
	$rss->title($this->title);
	$rss->description($this->description);
	$rss->link($this->get_url);
	while (my $c = shift @evt) {
	    $nitem++;
	    my $e = new ExSite::Event(data=>$c);
	    $rss->item($e->title,$e->show_date_range,$e->get_url);
	}
	return $rss->write() if $nitem;
    }
    return undef;
}

# today: return y, m, d

sub today {
    my $this = shift;
    if (! $this->{today}) {
	my $t = new ExSite::Time;
	$this->{today} = $t->write("sql_date");
    }
    return wantarray ? split("-", $this->{today}) : $this->{today};
}

# fetch an individual Event

sub fetch_event {
    my ($this,$evt) = @_;
    my $db = $share{DB};
    my $e;
    if (ref $evt) {
	$e = new ExSite::Event(data=>$evt);
    }
    elsif ($evt =~ /^\d+$/) {
	$e = new ExSite::Event(id=>$evt);
    }
    elsif ($this->{evt}) {
	# no change
	return $this->{evt};
    }
    else {
	$this->error("Undefined event");
	return undef;
    }
    $this->{evt} = $e;
    # validate that event belongs to this calendar
    if ($e->getdata("parent") != $this->id) {
	delete $this->{evt};
	return undef;
    }
    return $this->{evt};
}

# fetch events after a certain date

sub fetch_future_events {
    my ($this,$date) = @_;
    my $db = $share{DB};
    if ($date !~ /^\d{4}-\d{1,2}-\d{1,2}$/) { $date = $this->today; }
    return $db->get_query("events after date",$date,$this->id);
}

# fetch a number of events before a certain date

sub fetch_past_events {
    my ($this,$date) = @_;
    my $db = $share{DB};
    if ($date !~ /^\d{4}-\d{1,2}-\d{1,2}$/) { $date = $this->today; }
    return $db->get_query("events before date",$date,$this->id);
}

# fetch_events_by_date : year, month required; day and limit are optional

sub fetch_events_by_date {
    my ($this,$date) = @_;
    my $db = $share{DB};
    if ($date !~ /^\d{4}-\d{1,2}-\d{1,2}$/) { $date = $this->today; }
    my $t = new ExSite::Time($date,"sql_date");
    $t->add(1,"day");
    my $enddate = $t->write("sql_date");
    return $db->get_query("events by date",$date,$enddate,$this->id);
}

sub fetch_events_by_month {
    my ($this,$date) = @_;
    my $db = $share{DB};
    if ($date !~ /^\d{4}-\d{1,2}(-(\d{1,2})?)?$/) { $date = $this->today; }
    my ($y,$m,undef,$d) = ($date =~ /^(\d{4})-(\d{1,2})(-(\d{0,2}))?$/);
    my $date = "$y-$m-01";
    $m++;
    if ($m > 12) {
	$m = 1;
	$y++;
    }
    my $enddate = "$y-$m-01";
    return $db->get_query("events by date",$date,$enddate,$this->id);
}

sub get_all_events {
    my ($this) = @_;
    my @event = $share{DB}->get_query("all events",$this->id);
    return wantarray ? @event : \@event;
}

sub search_index {
    my ($this,$search) = @_;
    my $ml = &get_obj("ML");
    my $br = $ml->br;
    my $name = $this->subtype." ".$ml->em($this->name);
    my $stat = $this->can_index();
    return "$name already indexed - skipping...$br" if ($stat < 0);
    return "$name - permission denied$br" if (! $stat);

    # index the category title only
    $search->index_url(
	content => { title => $this->title },
	weight => { title => 10 },
	language => $this->getdata("langauge"),
	url => $this->get_url_canonical,
	access => $this->getdata("access"),
	section_id => $this->my_section->id,
	);
    return "indexed $name...$br\n";
}

sub setup_querylib {
    my ($this) = @_;
    $this->SUPER::setup_querylib();
    my $db = $share{DB};
    $db->set_query("events after date",
		   ( 
		     sql => "select e.*,ed.start,ed.end from content e,content_date ed,content_type type where e.type=type.content_type_id and type.name='event' and ed.content_id=e.content_id and ed.start >= ? and e.parent=? order by ed.start desc",
		     nparam => 2,
		     mode => "r",
		     keys => ["content","content_date","content_type"],
		     )
		   );
    $db->set_query("events before date",
		   ( 
		     sql => "select e.*,ed.start,ed.end from content e,content_date ed,content_type type where e.type=type.content_type_id and type.name='event' and ed.content_id=e.content_id and ed.start < ? and e.parent=? order by ed.start desc",
		     nparam => 2,
		     mode => "r",
		     keys => ["content","content_date","content_type"],
		     )
		   );
    $db->set_query("my events",
		   ( 
		     sql => "select e.*,ed.start,ed.end from content e,content_date ed,content_type type,content_key key where e.type=type.content_type_id and type.name='event' and ed.content_id=e.content_id and key.content_id=e.content_id and e.parent=? and key.member_id=? order by ed.start desc",
		     nparam => 2,
		     mode => "r",
		     keys => ["content","content_date","content_type","content_key"],
		     )
		   );
    $db->set_query("events by date",
		   ( 
		     sql => "select e.*,ed.start,ed.end from content e,content_date ed,content_type type where e.type=type.content_type_id and type.name='event' and ed.content_id=e.content_id and (ed.end = '0000-00-00' or ed.end > ?) and ed.start <= ? and e.parent=? order by ed.start desc",
		     nparam => 3,
		     mode => "r",
		     keys => ["content","content_date","content_type"],
		     )
		   );
    $db->set_query("all events",
		   ( 
		     sql => "select e.*,ed.start,ed.end from content e,content_date ed,content_type type where e.type=type.content_type_id and type.name='event' and ed.content_id=e.content_id and e.parent=? order by ed.start desc",
		     nparam => 1,
		     mode => "r",
		     keys => ["content","content_date","content_type"],
		     )
		   );
}

#------- month views ----------

# show_month : display calendar month, with links to events

sub show_month {
    my ($this,$opt,@events) = @_;
    my $date = $opt->{date} || $this->{date};
    return $this->warn("No date selected.") if (! $date);
    my $t = new ExSite::Time($date,"iso_date");
    my ($year,$mon,$day) = split /-/, $date;
    $mon = sprintf "%02d",$mon;
    $day = sprintf "%02d",$day;

    # get events
#    if (@events == 0) {
#	@events = $this->fetch_events_by_month($this->{date},$this->{section_id});
#    }

    # flag the days with events
    my (%day,%dayevt);
    foreach my $edata (@events) {
	my $evt = new ExSite::Event(data=>$edata);
	next if (! $evt->is_viewable && ! $evt->allow("update"));
	next if ($evt->getdata("access") && $opt->{hide_private_events} 
		 && $evt->getdata("access") > $share{DB}->level);
	my ($date,$time) = split / /, $edata->{start};
	my ($enddate,$endtime) = split / /, $edata->{end};
	my ($sy,$sm,$sd) = split /-/, $date;
	my ($ey,$em,$ed) = (! $enddate || $enddate =~ /^0/) ?
	    ($sy,$sm,$sd) : 
	    split /-/, $enddate;
	
	next unless ("$sy$sm" le "$year$mon" &&
		     "$ey$em" ge "$year$mon");

	my $beginday = ($sm == $mon ? $sd : "01");
	my $endday = (($em == $mon && $ey == $year) ? $ed : $t->days_in_month($mon));
	
	foreach my $eventday ($beginday..$endday) {
	    next if ($dayevt{$eventday}{$evt->id}); # already got it for this day
	    if ((ref $day{$eventday}) ne "ARRAY") {
		$day{$eventday} = [];
	    }
	    push @{$day{$eventday}},$evt;
	    $dayevt{$eventday}{$evt->id} = 1; # so we don't add same event multiple times on one day
	}
    }

    return $this->show_month_calendar(year=>$year,month=>$mon,events=>\%day,%$opt);
}

# show_month_calendar
# display a month view for a certain year/month
# events can be one of:
# hash of days => URLs -> calendar can shrink to a compact size
# hash of days => array of events -> calendar should be fullscreen
# header is the calendar titlebar

# options:
# year, month
# events = hash of day => event objects for that date
# header = HTML to place in calendar "title bar"
# linktype = normal, popup

sub show_month_calendar {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    my $out;
    my $year = $opt{year};
    my $month = $opt{month};
    my $events = $opt{events};
    my $header = $opt{header};
    my $t = new ExSite::Time("$year-$month-01","iso_date");
    my @cal = $t->get_month_calendar();
    if (! $header) {
	my $lmonth = $t->write("month_long");
	$header = "$lmonth $year";
    }
    
    # if the current month, note today for special highlighting
    my ($thisyear,$thismonth,$thisday) = $this->today();
    if ($thisyear != $year || $thismonth != $month) {
	$thisday = undef;
    }

    # build the calendar HTML

    my $week;
    foreach my $day ($opt{popup} ? @wd : @weekday) {
	$week .= $ml->th($msg{$day});
    }
    my $cal = $ml->tr($week);
    foreach my $wk (@cal) {
	$week = "";
	foreach my $d (@$wk) {
	    my $day = $d < 10 ? "0$d" : $d;
	    if ($day) {
		if ($events->{$day}) {
		    my $links;
		    foreach my $evt (@{$events->{$day}}) {
			my $url = $share{Page} ? $evt->get_url : $this->link(id=>$evt->id);
			$links .= $ml->div($ml->a($evt->title,{href=>$url}),{class=>"calendarEvent"});
		    }
		    if ($opt{popup}) {
			my $date = new ExSite::Time("$year-$month-$day","iso_date");
			$week .= $ml->td(
			    &ExSite::HTML::Popup(
				 label=>$d,
				 pane=>$ml->strong($date->write("date")).$links,
			    )
			    );
		    }
		    else {
			$week .= $ml->td($d.$links,{class=>"EvtDay"});
		    }
		}
		elsif ($d == $thisday) {
		    $week .= $ml->td($d,{class=>"Today"});
		}
		else {
		    $week .= $ml->td($d);
		}
	    }
	    else {
		$week .= $ml->td(undef,{class=>"NoDay"});
	    }
	}
	$cal .= $ml->tr($week);
    }
    $out .= $ml->table(
	$ml->caption($header).$ml->tbody($cal),
	{class=>"calendarMonth"}
	);
    
    return $out;
}

sub today {
    my $this = shift;
    if (! $this->{today}) {
	my $t = new ExSite::Time;
	$this->{today} = $t->write("sql_date");
    }
    return wantarray ? split("-", $this->{today}) : $this->{today};
}

1;
