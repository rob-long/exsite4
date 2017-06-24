#!/usr/bin/perl
#-----------------------------------------------------------------------
# cron.pl - scheduled task execution
#
# This program is designed to be executed by the cron process.  The 
# recommended usage is to execute once per hour, close to the hour.
# A crontab entry like the following should do this:
#
#    0 * * * *   cd /path/to/cgi-bin; ./cron.pl
#
# This says to change to the cgi directory and execute this program 
# once per hour on the hour.  You should always execute cron.pl from 
# the CGI directory to make sure you pick up local configurations.
#
# If you have an irregular environment, you may also want to set some
# environment variables in that cron command to spoof what the webserver
# would set, to ensure that autoconfiguration will be able find all of 
# ExSite's parts.  If not, consider manual configuration.
#-----------------------------------------------------------------------
#
#   Copyright 2001-2013 Exware Solutions, Inc.  http://www.exware.com
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

use ExSite::Config;
use ExSite::Form;
use ExSite::Module;
use ExSite::Misc;
use ExSite::Util;
use ExSite::Mail;

if ($ENV{HTTP_USER_AGENT}) {
    # this appears to be an actual web request; abort
    # (in case .pl files are executable from URLs)
    &log("===== Aborting Cron; invalid environment"); 
    exit 1;
}

&exsite_init;
$share{cron} = 1; # cron is running
my $db = new ExSite::Form;
my $ncall = 0;   # number of cron commands issued
my $ndone = 0;   # number of commands actually acted on
my $logging = undef;

# determine whether this run is an hourly, daily, or weekly
my ($hourly,$daily,$weekly);
my @time = localtime(time);
my $hour = $time[2];
my $wday = $time[6];
$hourly = 1;  # this is an hourly job
$daily = ($hour == $config{cron}{hour});
$weekly = ($wday == $config{cron}{day} && $hour == $config{cron}{hour});

# re-publish content on interval publishing
&publish_content;

# pull some stuff off the queue
&queue_content;

# content tasks
&content_tasks;

# run all special crontasks
&crontasks;

&log("Cron finish: $ncall valid task(s) found; $ndone task(s) executed.");
&exsite_close;
close LOG;

# publish content

sub publish_content {
    my $cobj = new ExSite::Content();
    my @content = $db->fetch_match("content",{status=>0,publish=>"hourly"});
    if ($daily) {
	push @content, $db->fetch_match("content",{status=>0,publish=>"daily"});
    }
    if ($weekly) {
	push @content, $db->fetch_match("content",{status=>0,publish=>"weekly"});
    }
    foreach my $cdata (@content) {
	my $c = $cobj->get_content_obj($cdata);
	&log("===== Cron: publishing ".$c->type." ".$c->title);
	$ncall++;
	my $authority = $c->authority("administrator");
	$c->publish(uid=>$authority->{uid});
    }
}

# queue content
# queue_start, queue_end = hours of day when queue runs
# queue_perday = number of queue items to publish in a day
# end-start/perday = number to publish each hour
# foreach hour, sum current daily total, take int; if > int of previous
# hour, publish that many; if last hour, publish remainder

sub queue_content {
    my $cobj = new ExSite::Content();
    my @content = $db->fetch_match("content",{status=>$cobj->wf_istatus("queued")},"mtime");
    if (scalar @content > 0) {
	# we have items in the queue

	# how many items should be published on this pass through the queue?
	my $st = $config{queue}{start};
	my $end = $config{queue}{end};
	my $perday = $config{queue}{perday};
	my $nhour = $end - $st + 1;  # number of queue hours per day
	my $perrun = $nhour > 0 ? $perday / $nhour : 0; # items per hour
	if ($perrun) {
	    my ($nq,$qlast,$nitem);
	    foreach my $h ($st .. $end) {
		$qlast = $nq;    # total number of items published by last run
		$nq += $perrun;  # total number of items published by this run
		if ($h == $hour) {
		    # this run
		    $nitem = int($nq) - int($qlast); # actual number of items
		    if ($nitem) {
			my $ndone = 0;
			foreach my $cdata (@content) {
			    $ndone++;
			    $ncall++;
			    my $c = $cobj->get_content_obj($cdata);
			    $c->wf_publish();
			    last if ($ndone >= $nitem);
			}
		    }
		}
	    }
	}
	else {
	    # there are items in the queue, but the queue setup does not
	    # allow for publishing any of them
	    &log("===== Cron: queue is not setup to publish any items");
	}
    }
}

sub content_tasks {
    my $cobj = new ExSite::Content();
    my $now = new ExSite::Time;
    my $time = $now->write("sql_datetime");
    
    # automatic content tasks are type 'task'

    my @tasks = $db->custom_query("select * from content_date where type='task' and status='active' and start < ? order by start, content_date_id",$time);
    foreach my $task (@tasks) {
	my $action = $task->{description};
	my $c = $cobj->get_content_obj($task->{content_id});
	$c->task($task->{description});
	$task->{status} = "completed";
	$db->update("content_date",$task);
    }

    # manual content tasks are type 'todo'
    # execute only if the ToDo app is installed

    if ($daily &&
	-e "$config{server}{CGIroot}$config{server}{CGIpath}/Modules/ToDo.pm") {
	$now->add(1,"day");
	my $time = $now->write("sql_datetime");
	@tasks = $db->custom_query("select * from content_date where type='todo' and status='active' and start < ?",$time);
	if (@tasks > 0) {
	    my @list;
	    foreach my $task (@tasks) {
		my $c = $cobj->get_content_obj($task->{content_id});
		push @list, $c->subtype()." ".$c->id." (".$c->label."): ".$task->{description};
	    }
	    my $ml = &get_obj("ML");
	    my $msg = 
		$ml->p("$config{site}{name} to-do list for today:").
		$ml->ul(\@list).
		$ml->p($ml->a("View your to-do list",{href=>"$config{server}{server}$config{server}{CGIpath}/$config{prog}{admin}/ToDo"}));
	    &ExSite::Mail::send(
		    to=>$config{server}{administrator},
		    from=>$config{server}{administrator},
		    subject=>"$config{site}{name} to-do list",
		    body=>$msg);
	}
    }
}

# crontasks: load/execute all special tasks

sub crontasks {
    
    my @task = $db->fetch_all("crontask","crontask_id");

    &log("===== Cron: scanning ".scalar @task." tasks.");

    foreach my $t (@task) {
	if ($t->{status} eq "active") {
	    &reinit();

	    # set UID
	    if ($t->{uid}) {
		my $u = $db->fetch("member",$t->{uid});
		$u->{login} ? $db->do_login_temp($u->{login},1) : $db->logout;
	    }
	    else {
		&log("Warning: Task $t->{crontask_id}: no UID to run task under");
		$db->logout;
	    }

	    # do the task
	    if ($t->{method} eq "preset") {
		&do_task($t);
	    }
	    elsif ($t->{method} eq "hourly") {
		&do_task($t);
	    }
	    elsif ($t->{method} eq "daily" && $daily) {
		&do_task($t);
	    }
	    elsif ($t->{method} eq "weekly" && $weekly) {
		&do_task($t);
	    }
	}
    }
}

# do_task: run a particular task

sub do_task {
    my $task = shift;
    if ($task->{module}) {
	my $mod = &ExSite::Module::get_module($task->{module});
	if ($mod) {
	    my $cron = $mod->ioctl('Cron');
	    if (ref $cron eq "CODE") {
		# issue cron command to the module
		$ncall++;
		my $result;
		eval { $result = $mod->$cron($task->{command},
					     $task->{type},
					     $task->{id}); };
		if ($@) { 
		    # task crashed
		    $result .= " ERROR: $@"; 
		}
		else {
		    # mark the task as executed
		    my $time = new ExSite::Time;
		    $task->{exectime} = $time->write("sql_datetime");
		    if ($task->{method} eq "preset") {
			$task->{status} = "completed";
		    }
		    $db->update("crontask",$task);
		    $ndone++;
		}
		if ($result) { 
		    # log the result
		    &log("Task $task->{crontask_id}: $result"); 
		}
	    }
	    else {
		&log("!! Task $task->{crontask_id}: $task->{module} does not support task scheduling.");
	    }
	}
	else {
	    if ($@) {
		# module is broken
		&log("!! Task $task->{crontask_id}: $task->{module} failed to instantiate: $@");
	    }
	    else {
		# permission denied, probably
		&log("!! Task $task->{crontask_id}: no permission to run $task->{module}");
	    }
	}
    }
    else {
	&log("!! Task $task->{crontask_id} is misconfigured (no module).");
    }
    return;
}

# log the results of a cron task

sub log {
    my $message = shift;
    if (! defined $logging) {
	if ($config{log}{cron}) {
	    if (-w $config{log}{logfile}{cron}) {
		if (open LOG, ">>$config{log}{logfile}{cron}") {
		    $logging = 1;
		}
		else {
		    $db->error("failed to open cron logfile");
		}
	    }
	    else {
		$db->error("cron logfile is not writeable");
	    }
	}
	$logging = defined $logging ? $logging : 0;
    }
    if ($logging) {
	my $time = localtime;
	print LOG "$time\t$message\n";
    }
    # it's safe to leave this file open until the end of this pass through
    # the cron system, because there is no contention for it
}

sub reinit {
    foreach my $key (keys %share) {
	next if ($key =~ /^(Cache|ENV|DB)$/ || $key =~ /^dbmap:/);
	delete $share{$key};
    }
    %session = ();
}
