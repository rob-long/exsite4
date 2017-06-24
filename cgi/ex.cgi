#!/usr/bin/perl
#!/usr/bin/speedy
#-----------------------------------------------------------------------
# ex - ExSite Webware MCP
#
#     /ex/method/module/path_info?query
#
# method is one of:
#     app - run a plugin app (formerly dcd.cgi)
#     admin - manage an app (formerly ctrl-panel.cgi)
#     captcha - generate captchas
#     debug - debug utility
#     dialog - dialog box
#     doform - process generic form input
#     file - retrieve a file from the data repository
#     help - display help information
#     home - send user to most appropriate place (DEFAULT ACTION)
#     login - authenticate a user
#     logout - de-authenticate a user
#     op - operate on an object
#     page - display page
#     peek - display datum (formerly getdata.cgi)
#     post - user submissions
#     publish - write files
#     view - view content
###   TEST - run system tests
#
#-----------------------------------------------------------------------
#
#   Copyright 2001-2011 Exware Solutions, Inc.  http://www.exware.com
#
#   This file is part of ExSite WebWare (ExSite, for short).
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

debug mode init

init
    - exsite_init for most
    - partial init for som (eg. captcha)
    - no init for some (eg. debug, help)

killswitch
    - app, page

inputs

db
    - authentication

page setup
    - templates ?

content generation
    - form content, substitutions

page generation

wrap-up

=cut

my ($utime1,$stime1,$cutime1,$cstime1,$rtime);
BEGIN {
  ($utime1,$stime1,$cutime1,$cstime1) = times;
  $rtime = time;
}

use strict;
use CGI::Carp  qw(fatalsToBrowser);
use ExSite::Config;
use ExSite::Form;
use ExSite::Page;
use ExSite::Session;
use ExSite::Misc;
use ExSite::Util;
use ExSite::Dialog;
use ExSite::Input;
use ExSite::URI;
use ExSite::Module;
use ExSite::Captcha;
use JSON;

use vars qw(%action %init $action $OKAY $access $input $db $module $ml $ui);

# auth => minimum access level to run this action
# trust => the trustlevel of this action, if we have trusted IPs
# db => whether we need to make any DB queries
# kill => whether this action obeys killswitches
#         1 => silently killed
#         2 => verbosely killed

%action = (
    admin   => { auth=>5, db=>1, kill=>0, trust=>5 },
    app     => { auth=>0, db=>1, kill=>1, trust=>0 },
    captcha => { auth=>0, db=>0, kill=>1, trust=>0 },
    debug   => { auth=>0, db=>0, kill=>1, trust=>0 },
    dialog  => { auth=>5, db=>1, kill=>0, trust=>5 },
    dispatch=> { auth=>0, db=>1, kill=>1, trust=>0 },
    doform  => { auth=>0, db=>1, kill=>0, trust=>0 },
    file    => { auth=>5, db=>1, kill=>1, trust=>5 },
    help    => { auth=>5, db=>1, kill=>2, trust=>5 },
    home    => { auth=>0, db=>1, kill=>2, trust=>0 },
    login   => { auth=>0, db=>1, kill=>1, trust=>0 },
    logout  => { auth=>0, db=>1, kill=>0, trust=>0 },
    null    => { auth=>0, db=>0, kill=>0, trust=>5 },
    op      => { auth=>0, db=>1, kill=>1, trust=>0 },
    page    => { auth=>0, db=>1, kill=>2, trust=>0 },
    peek    => { auth=>0, db=>1, kill=>1, trust=>5 },
    post    => { auth=>0, db=>1, kill=>1, trust=>0 },
    publish => { auth=>7, db=>1, kill=>1, trust=>5 },
    test    => { auth=>0, db=>1, kill=>1, trust=>5 },
    view    => { auth=>0, db=>1, kill=>1, trust=>5 },
    );

# can define specific initializations to perform for each action; otherwise
# we perform all initializations.
# Possible values are store, config, cookie, msg, session

%init = (
    captcha => [ "store", "config", "msg" ],
    debug   => [ "store", "config" ],
#    dialog  => [ "store", "config", "cookie", "msg" ],
    null    => [ "store", "config" ],
    peek    => [ "store", "config", "cookie" ],
    );

# have to manually parse path_info before our setup is complete
{
    my $path_info = $ENV{PATH_INFO};
    my @path = split /\//, $ENV{PATH_INFO};
    shift @path;
    $action = shift @path;
    $OKAY = 1;
    $access = 0;
}

# initialize ExSite

&init();
&run_action() if $OKAY;
&exsite_close();

if ($access > 1 || $config{debug}) {
    # report diagnostics (appended to end of output - may cause invalid HTML)
    my $errors = &ExSite::Config::show_diagnostics();
    if ($errors) {
	print $ml->div(
	    $ui->ErrorBox(title=>"Errors",pane=>$errors, width=>"600px"),
	    {style=>"margin:25px"}
	    );
    }
}

END {
    # report performance
    # crude benchmarking tool for ExSite developers
    if ($config{debug}) {
	my ($utime2,$stime2,$cutime2,$cstime2) = times;
	my $rtime2 = time;
	my $benchmarks = "Real time: ".($rtime2-$rtime)."; User time: ".($utime2-$utime1)."; System time: ".($stime2-$stime1)."; Child User time: ".($cutime2-$cutime1)."; Child System time: ".($cstime2-$cstime1);
	if ($ENV{EXSITE_BENCHMARK}) {
	    print "\n<div class='benchmarks'>$benchmarks</div>";
#	    open FILE, ">>benchmark.log";
#	    print FILE "ex.cgi/action: $benchmarks\n";
#	    close FILE;
	}
    }
}

#=================================================================================

sub init {
    $action or $action = "null";
    if ($action && exists $action{$action}) {
	if (ref $init{$action} eq "ARRAY") {
	    # initialize only some subsystems
	    foreach my $subinit (@{$init{$action}}) {
		eval "&ExSite::Config::exsite_init_$subinit";
		if ($@) { return &Error("Could not initialize $subinit: $@"); }
	    }
	}
	else {
	    # full initialization
	    &exsite_init;
	}
	$ml = &get_obj("ML");
	$ui = new ExSite::UI;
	if ($OKAY) { 

	    # initalization went oaky; see if we need to kill this request

	    if (! $action{$action}{kill} || ! &kill()) {

		# setup input
		
		$input = new ExSite::Input;
		$input->path_info;
		$input->path("ExSiteAction",$action);

		# connect to DB if necessary

		if ($action{$action}{db}) {
		    $db = new ExSite::Form;

		    # get user's authorization level

		    $access = &adjust_level();  # this also checks trusted hosts
		    if ($access < $action{$action}{auth}) { 
			&AccessDenied("$action: permission denied."); 
		    }
		}
	    }
	}
    }
    else {
	$ui = new ExSite::UI;
	&ExSite::Config::exsite_init_store;
	&ExSite::Config::exsite_init_config;
	&Error("Unknown command: $action");
    }
}

# demote our access level if necessary

sub adjust_level {
    my $level = $db->level;
    if ($level >= $config{auth}{trust_level}) {
#    if ($level >= $action{$action}{trust}) {  ############
	if ($config{auth}{trusted_hosts}) {
	    if ($ENV{REMOTE_ADDR} =~ /$config{auth}{trusted_hosts}/) {
		# we're from a safe IP
		return $level;
	    }

	    # not a trusted host

	    $db->warn("You are accessing this screen from an untrusted location. Permissions have been downgraded.");
	    my $new_level = $action{$action}{trust} - 1;
	    $db->set_level($new_level);
	    return $new_level;
	}
    }
    return $level;
}

# The kill function decides whether or not to kill the current request.
# It returns a non-zero value if the request should be killed; if the $kill
# parameter is true, it actually performs the kill.

sub kill {
    my $killlevel = $action{$action}{kill};
    if ($killlevel) {
	if ($config{kill}) {
	    # gaah!  We've been killed!
	    &kill_page($killlevel);
	    return 1;
	}
	elsif ($config{busy} || 
	       $config{throttle}{user}{rate} || 
	       $config{throttle}{system}{rate}) {
	    # rate limiters are enabled
	    if ($ENV{REQUEST_METHOD} eq "GET") {
		# only rate-limit GET requests (eg. crawlers)
		if (! $config{priority_page} || 
		    $ENV{REQUEST_URI} !~ /$config{priority_page}/) {
		    # URLs matching priority page regex are never throttled
		    if ($config{busy} && (&sysload() > $config{busyload})) {
			# system is swamped; delay the page
			&busy_page($killlevel);
			return 2;
		    }
		    elsif (($config{throttle}{user}{rate} || 
			    $config{throttle}{system}{rate}) && 
			   &throttle()) {
			# someone is making too many requests; delay the page
			&throttle_page($killlevel);
			return 3;
		    }
		}
	    }
	}
    }
    return 0;
}

# The kill page is displayed if the killswitch is tripped.  You can use this
# feature when performing system maintenance, or for disabling the
# most resource-intensive parts of a site for overload handling.

sub kill_page {
    my $killlevel = shift;
    if ($killlevel == 2) {
	my $killurl = $config{killurl} || 
	    "$config{server}{HTMLpath}/_ExSite/notavailable.html";
	print "Location: $killurl\n\n";
    }
    else {
	print "Content-type: text/html\n\nService unavailable.\n";
    }
    $OKAY = 0;
    return;
}

# The busy page is displayed if you have the busy switch enabled, and the
# 1 minute load average exceeds a certain threshold.  This serves primarily
# to limit the impact of DOS attacks and bad robots, but gives real readers
# a chance to reload.

sub busy_page {
    my $killlevel = shift;
    if ($killlevel == 2) {
	my $busyurl = $config{busyurl} || 
	    "$config{server}{HTMLpath}/_ExSite/serverbusy.html";
	print "Location: $busyurl\n\n";
    }
    else {
	print "Content-type: text/html\n\nService unavailable.\n";
    }
    $OKAY = 0;
    return;
}

# The throttle page is displayed if you have the traffic throttler enabled, 
# and the request rate exceeds the allowed rate.  It enforces a wait until the
# request rate drops to an acceptable level.

sub throttle_page {
    my $killlevel = shift;
    if ($killlevel == 2) {
	my $busyurl = $config{throttle}{url} || 
	    "$config{server}{HTMLpath}/_ExSite/throttle.html";
	print "Location: $busyurl\n\n";
    }
    else {
	print "Content-type: text/html\n\nService unavailable.\n";
    }
    $OKAY = 0;
    return;
}

# return the system load

sub sysload {
    if (! exists $share{sysload}) {
	open LOAD, "</proc/loadavg" or return 0;
	my $loadavg = <LOAD>;
	close LOAD;
	($share{sysload},undef) = split /\s/,$loadavg,2;
    }
    return $share{sysload};
}

# ask the throttler if we should deny this request
# NB: note that you must enable the persistent store to get throttling

sub throttle {
    my ($history,$score,$time,$last,$rate,$deltatime);
    $time = time;

    # check request history of this IP
    if ($config{throttle}{user}) {
	$history = $store{"throttle:$ENV{REMOTE_ADDR}"};
	my @abuse;
	# get list of recent hits within the abuse threshold
	if (ref $history eq "ARRAY") {
	    pop @$history if (scalar @$history > $config{throttle}{user}{history});
	    unshift @$history,$time;
	    $last = $time;
	    foreach my $req (@$history) {
		# do not consider any hits at longer gaps than the abuse threshold
		last if ($last - $req > $config{throttle}{user}{threshold});
		push @abuse, $req;
		$last = $req;
	    }
	}
	else {
	    $history = [$time];
	}
	# calculate the request rate
	my $nabuse = scalar @abuse;
	if ($nabuse >= $config{throttle}{user}{min}) {
	    $deltatime = $time - $abuse[-1];
	    $rate = ($deltatime > 0) ? $nabuse / $deltatime : 9999;
	}
	else {
	    $rate = 0;
	}
	# log the request, even if we throttle it, so that badly-behaved 
	# agents will make their situation worse if they continue to hammer 
	# the system after being throttled.
	$store{"throttle:$ENV{REMOTE_ADDR}"} = $history;
	return $rate if ($rate > $config{throttle}{user}{rate});
    }

    # now check general request history for the system
    if ($config{throttle}{system}) {
	$history = $store{"throttle:ALL"};
	my @abuse;
	# get list of recent hits within the abuse threshold
	if (ref $history eq "ARRAY") {
	    pop @$history if (scalar @$history > $config{throttle}{system}{history});
	    unshift @$history,$time;
	    $last = $time;
	    foreach my $req (@$history) {
		# do not consider any hits at longer gaps than the abuse threshold
		last if ($last - $req > $config{throttle}{system}{threshold});
		push @abuse, $req;
		$last = $req;
	    }
	}
	else {
	    $history = [];
	}
	# calculate the request rate
	my $nabuse = scalar @abuse;
	if ($nabuse >= $config{throttle}{system}{min}) {
	    $deltatime = $time - $abuse[-1];
	    $rate = ($deltatime > 0) ? $nabuse / $deltatime : 9999;
	}
	else {
	    $rate = 0;
	}
	# we log system requests only if we don't throttle them, so that 
	# good agents still have a chance, even in the face of a DDOS attack.
	return $rate if ($rate > $config{throttle}{system}{rate});
	$store{"throttle:ALL"} = $history;
    }

    # throttler is happy, allow the request
    return 0;
}

sub run_action {
    # action should already have been validated in init()
    eval "&${action}()";
    &Error($@) if ($@);
}

sub Error {
    my $error = shift;
    &diagnostic($error);
    $ml or $ml = &get_obj("ML");
    my $br = $ml->br;
    $error =~ s/\n/$br\n/g;
    &simple_page($ml->div($ml->p($error,{class=>"error"}),{class=>"body"}),"Error");
    $OKAY = 0;
}

sub AccessDenied {
    my $error = shift;
    $error or $error = "Access denied.";
    $ml or $ml = &get_obj("ML");
    &diagnostic($error);
    my $out = $ml->p($error,{class=>"error"});
    $out .= $db->login_form(undef,$ENV{REQUEST_URI});
    &simple_page($ml->div($out,{class=>"body"}));
    $OKAY = 0;
}

sub debug_footer {
    if ($config{debug}) {
	return $ui->Overlay(
	    label=>"Debug Info",
	    title=>"Debug Info",
	    pane=>&debug_status($utime1,$stime1,$cutime1,$cstime1),
	    size=>"s",  # button size
	    tone=>"warning",  # button tone
	    );
    }
    return undef;
}

#------------------------------------------------------------------------
# debug_status : report debugging information about the current request
# Can optionally pass the output of time to get benchmarking info.
#------------------------------------------------------------------------

sub debug_status {
    my $out = $ml->h1("Debug Info");
    if (@_ > 0) {
	$out .= $ml->h2("Benchmarks");
	my ($utime1,$stime1,$cutime1,$cstime1) = @_;
	my ($utime2,$stime2,$cutime2,$cstime2) = times;
	$out .= $ml->pre("\nUser time:         ".($utime2-$utime1).
			 "\nSystem time:       ".($stime2-$stime1).
			 "\nChild User time:   ".($cutime2-$cutime1).
			 "\nChild System time: ".($cstime2-$cstime1).
			 "\nTotal Real Time:   ".(time - $^T)."\n");
    }
    my $diag = &ExSite::Config::show_diagnostics("html",($config{debug} > 2 ? 1 : 2));
    if ($diag) {
	$out .= $ml->h2($config{debug} >  2 ? "Diagnostic Messages" : "Warnings &amp; Errors");
	$out .= $diag;
    }
    my $debug;
    $out .= $ml->h2("Input");
    if ($share{input}{get}{raw}) {
	$out .= $ml->h3("GET data");
	$out .= $ml->pre($share{input}{get}{raw},{style=>"overflow:auto"});
    }
    if ($share{input}{post}{raw}) {
	$out .= $ml->h3("POST data");
	$out .= $ml->pre($share{input}{post}{raw},{style=>"overflow:auto"});
	if ($ENV{CONTENT_TYPE} =~ /multipart\/form-data/) {
	    # cannot see post data, so print it out explicitly
	    my $post;
	    my $in = $share{input}{post}{raw};
	    my @loginput;
	    foreach my $par ($in->param) {
		my $val = $in->param($par);
		$post .= $ml->li($par . " = " . &html_escape($val));
	    }
	    $out .= $ml->ol($post);
	}
    }
    if (scalar keys %cookie > 0) {
	$out .= $ml->h3("Cookies");
	$out .= &ShowHash(\%cookie);
    }
    $out .= $ml->h2("Environment");
    $out .= &ShowHash(\%ENV);
    $out .= $ml->h2("CLI debugger syntax");
    my ($cmd1,$cmd2);
    $cmd1 = "./cgi -d ";
    if ($share{input}{post}{raw}) {
	if (ref $share{input}{post}{raw}) {
	    $cmd1 .= "-e CGI_INPUT='".
		&EncodeHash(%{$share{input}{post}{data}}).
		"' ";
	}
	else {
	    $cmd1 .= "-e CGI_INPUT='$share{input}{post}{raw}' ";
	}
    }
    $cmd2 = $cmd1;
    foreach my $c (keys %cookie) {
	$cmd1 .= "-c '$c=$cookie{$c}' ";
	next if ($c eq $config{site}{identity_cookie});
	$cmd2 .= "-c '$c=$cookie{$c}' ";
    }
    $cmd1 .= "'$config{server}{server}$ENV{SCRIPT_NAME}$ENV{PATH_INFO}?$share{input}{get}{raw}'\n";
    $cmd2 .= "'$config{server}{server}$ENV{SCRIPT_NAME}$ENV{PATH_INFO}?$share{input}{get}{raw}'\n";

    if ($cmd1 eq $cmd2) {
	$out .= $ml->pre($cmd1,{style=>"overflow:auto"});
    }
    else {
	$out .= $ml->h3("Automatic login");
	$out .= $ml->pre($cmd1,{style=>"overflow:auto"});
	$out .= $ml->h3("Manual login");
	$out .= $ml->pre($cmd2,{style=>"overflow:auto"});
    }
    return $ml->div($out,{class=>"ExSiteDebug"});
}

#===================================================================================
# page layout

sub simple_page {
    my ($body,$title,$bodyclass,$closebutton) = @_;
    $title or $title = $config{site}{name};
    if ($closebutton) {
	$body = $ml->div(
	    $ml->a("&times;&nbsp;&nbsp;close",{href=>"javascript:window.close()"}),
	    {class=>"close_button"} 
	    ) . $body;
    }
    $body .= &debug_footer;

    $ml->Doctype($config{doctype});
    $ml->Doc($body);
    $bodyclass or $bodyclass = "simple_page";
    $ml->__body({class=>$bodyclass});
    $ml->Prepend(
	$ml->head(
	    $ml->title($title).
	    $ml->link(undef,
		      {rel=>"stylesheet",
		       type=>"text/css",
		       href=>"$config{server}{HTMLpath}/_ExSite/css/ExSite.css"})
	)
	);
    $ml->__html();
    $ml->PrintWithHeader();
    return;
}

sub redirect_page {
    my ($goto,$message) = @_;
    $ml->Doctype($config{doctype});
    my $out = $message . $ml->p("Redirecting to ".$ml->a($goto,{href=>$goto}).".");
    $ml->Doc($out);
    $ml->__body();
    $ml->Prepend(
	$ml->head(
	    $ml->link(undef,{rel=>"stylesheet",
			     type=>"text/css",
			     href=>"$config{server}{HTMLpath}/_ExSite/css/ExSite.css"}).
	    $ml->meta(undef,{'http-equiv'=>"Refresh",content=>"0;URL=$goto"}))
	);
    $ml->__html();
    $ml->PrintWithHeader();
    return;
}

sub ctrl_panel {
    my %mod = @_;
    my $out;
    if (! $mod{ctrl_panel}) {
	$out .= $ml->h1($msg{"Error executing $module control panel"});
	$out .= &debug_footer;
    }
    my $app = $mod{mod};
    my $panel = $mod{ctrl_panel};
    $out = ( eval { $app->$panel } || join $ml->br,(split /\n/,$@) );
    if ($out && $out !~ /^<(!doctype|html)/i) {
	# not a complete document; merge into ctrlpanel template
	$out .= &debug_footer;
	my $q = $input->query();
	if ($q->{_bare} != 2) {
	    $out = $ml->div($out,{class=>"ctrlpanel"});
	}
    }
    return $out;
}

#================================================================================
# modules

sub get_module {
    my @path = $input->path();
    my ($mod,$modname);
    if (scalar @path > 0) {
	$modname = $path[0];
	$input->new_path("module",$modname);
	$mod = &ExSite::Module::get_module($modname);
    }
    return $mod;
}

sub module_info {
    my ($module,$mod) = @_;
    if ($module && ! $mod) {
	$mod = &ExSite::Module::get_module($module);
    }
    elsif ($mod && ! $module) {
	$module = ref $mod;
	$module =~ s/.+:://;
    }
    if ($mod) {
	my %modinfo = (
	    module => $module,
	    mod => $mod,
	    name => $mod->ioctl('ModuleName') || $module,
	    icon => &ExSite::Module::icon($module,$config{iconset}),
	    path => "$config{server}{HTMLroot}$config{server}{HTMLpath}/_Modules/$module",
	    httppath => "$config{server}{HTMLpath}/_Modules/$module",
	    access => $mod->ioctl('Access'),
	    ctrl_panel => $mod->ioctl("ControlPanel"),
	    );
	my $q = $input->query;
#	$modinfo{npane} = ((ref $modinfo{ctrl_panel}) eq "ARRAY" && ! exists $q->{_bare}) ? 2 : 1;
	return %modinfo;
    }
    return undef;
}

sub get_module_headers {
    my %mod = @_;
    my $module = $mod{module};
    my $out;

    # stylesheet

    if (-e "$mod{path}/$module.css") {
	# add a custom stylesheet
	$out .= $ml->link(undef,{rel=>"stylesheet",type=>"text/css",href=>"$mod{httppath}/$module.css"});
    }

    # Javascript

    my $js .= &insert_js("jquery","jqueryui");
    if (-e "$config{server}{HTMLroot}$config{server}{HTMLpath}/_Modules/$module/$module.js") {
	# add a custom JS file	
	$js .= &insert_js("$config{server}{HTMLpath}/_Modules/$module/$module.js");
    };
    $out .= $js;
    return $out;
}

sub module_icon {
    my (%mod) = @_;
    if ($mod{ctrl_panel}) {
	my $url = ((ref $mod{ctrl_panel}) =~ /CODE|ARRAY/) ?
	    "$config{server}{CGIpath}/$config{prog}{admin}/$mod{module}" : 
	    $mod{ctrl_panel};
	my %iconinfo = (
	    label => $msg{$mod{name}},
	    img => $mod{icon},
	    img_size => 64,
	    );
	if ($config{webtop}{popup_style} eq "tab") {
	    # open in tabs
	    $iconinfo{target} = "_blank";
	    $iconinfo{url} = $url;
	}
	if ($config{webtop}{popup_style} eq "pane") {
	    # open in panes
	    $iconinfo{url} = "javascript:openModule('$url','$mod{module}','$mod{name}')";
	}
	else {
	    ### FIXME: use Modules::launcher_link

	    # open in popups
	    my $size = $mod{mod}->ioctl("Size") || "large";
	    $iconinfo{url} = (ref $size eq "ARRAY") ?
		"javascript:popup_custom($size->[0],$size->[1],'$url')" :
		"javascript:popup_$size('$url')";
	}
	return $ui->Icon(%iconinfo);
    }
    return undef;
}

#===============================================================================
# goto - "execute" a URL
# Use this when one command "redirects" to another, but you don't want to 
# force another request (eg. to use the same %share data)

# seems useful... but is it being used anymore?

sub goto {
    my $url = shift;

    delete $share{input};
    delete $share{ENV};

    # parse the new URL
    $url =~ /^(([^:\/?\#]+):)?(\/\/([^\/?\#]*))?([^?\#]*)(\?([^\#]*))?(\#(.*))?/;
    my %urldata = (
	scheme    => $2,
	authority => $4,
	path      => $5,
	query     => $7,
	fragment  => $9,
	);
    my $hostname = $urldata{authority};
    my $querystring = $urldata{query};
    $urldata{path} =~ /\/cgi(-bin)?(\/.+?)?\/([\w-]+\.(cgi|pl))((\/.+?)*)?$/;
    my $cgisub = $2;
    my $scriptname = $3;
    my $pathinfo = $5;

    # rewrite the environment
    my $myname = $ENV{LOGNAME};
    my $cwd = `pwd`;
    chomp $cwd;
    my @cwd = split(/\//,$cwd);
    my $project = $cwd[-2];
    $ENV{SCRIPT_NAME} = "/cgi$cgisub/$scriptname";
    $ENV{SCRIPT_FILENAME} = "$cwd/$scriptname";
    $ENV{HTTP_HOST} = $hostname;
    $ENV{QUERY_STRING} = $querystring;
    $ENV{PATH_INFO} = $pathinfo;
    $ENV{SERVER_NAME} = $hostname;
    $ENV{REQUEST_URI} = $ENV{SCRIPT_NAME}."?$querystring";
    $ENV{REQUEST_METHOD} = "GET";

    my $path_info = $ENV{PATH_INFO};
    my @path = split /\//, $ENV{PATH_INFO};
    shift @path;
    $action = shift @path;
    $OKAY = 1;
    $access = 0;

    if (exists $action{$action}) {
	# reconfig
	if ($config{server}{auto}) {
	    &ExSite::Config::server_autoconf;
	}

	# reload inputs
	$input = new ExSite::Input;
	$input->path_info;
	$input->path("ExSiteAction",$action);

	# no reauthentication

	# run the action
	&run_action();
    }
    else {
	&Error("Unknown command: $action");
    }
}

#===============================================================================
# action methods

# admin : adminstrator control panels

sub admin {
    my @path = $input->path();
    my $q = $input->query();
    my ($mod,$module);
    if (scalar @path > 0) {
	$module = $path[0];
	if ($module) {
	    $mod = &get_module($module);
	    if (! $mod) {
		&Error("Failed to start module $module:\n".$@);
		return;
	    }
	}
    }

    my %content = (
	charset => $config{charset},
	base => $config{server}{HTMLpath},
	title => $config{site}{name},
	);

    if ($mod) {

	# show a particular plug-in control panel

	my %mod = &module_info($module,$mod);
	$content{title} = "$mod{name} &bull; $config{site}{name}";
	$content{html_title} = "$mod{name} ".$ml->span(" &bull; ".$config{site}{name},{class=>"website"});
	my $headers = &get_module_headers(%mod);
	my $out = &ctrl_panel(%mod);
	if ($out) {
	    # module has output we need to display
	    if ($out =~ /^<(!doctype|html)/i) { #/^((<!doctype[^>]+>\s*)?<html)/i) {
		
		# module has returned a complete HTML document

		print "Content-type: text/html\n\n".$out;
		return;
	    }
	    else {

		# module has returned an HTML snippet

		if ($q->{_bare}) {
		    # return the snippet alone
		    # _bare = 1 means this is a popup window
		    # _bare = 2 means this is an AJAX insert
		    # _bare = 3 means this is in an iframe
		    if ($q->{_bare} == 2) {
			print "Content-type: text/html\n\n".$out;
			return;
		    }
		    elsif ($q->{_bare} == 3) {
			$out = $headers . $out . $share{page_footer};
		    }
		    &simple_page($out, $content{title}, "ctrlpanel", ($q->{_bare} == 1));
		    return;
		}
		else {
		    # use the admin template, setup our various merge fields

		    $content{button_left} = $ml->td($ml->img(undef,{src=>$mod{icon},height=>32,width=>32,border=>0,alt=>$mod{name}}));
		    my $links = $ml->td(
			$ml->a($msg{"restart"},{ href=>"$config{server}{server}$config{server}{CGIpath}/$config{prog}{admin}/$module" })
			);
		    if (-e "$mod{path}/help.html") {

			### FIXME: use jquery load and put this into a popup

			$links = $ml->td(
			    $ml->a($msg{help},{ href=>"javascript:popup_medium('$mod{httppath}/help.html')" }),
			    );
		    }
		    $content{button_right} = $links;
		    $content{body} = $out;
#		    $content{bodyhead} = $ml->h1($content{title},{class=>"titlebar"});

		    my @tool = ( { label=>"home", url=>"$config{server}{CGIpath}/$config{prog}{ctrlpanel}/$module", faicon=>"home" } );
		    if (-e "$mod{path}/help.html") {
			$share{page_footer} .= &insert_js("misc");
			push @tool, { label=>"help", url=>"javascript:popup_medium('$config{server}{CGIpath}/$config{prog}{help}/$module')", faicon=>"help" };
		    } 
		    $content{bodyhead} = $ui->TitleBar(
			icon=>$mod{icon},
			title=>$mod{name},
			tools=>\@tool,
			#links=>[{label=>"help",url=>"#"}]
			);
		    $content{head} = $headers;
		    $content{head} .= &insert_js("ctrlpanel");
		}
	    }
	}
	else {
	    # no output - assume ctrlpanel has handled its own i/o
	    return;
	}
    }
    else {
	&admin_launcher(\%content);
    }
    # append any delayed output
    $content{bodyhead} .= $share{page_header};
    $content{bodyfoot} .= $share{page_footer};

###    my $template = &get_file("$config{server}{HTMLroot}$config{server}{HTMLpath}/_ExSite/templates/admin.html");
    my $template;
    while (<DATA>) { $template .= $_; }
    return &Error("No admin template.") if (! $template);
    print "Content-type: text/html\n\n";
    print &substitute($template,\%content);
}

sub admin_launcher {
    my $content = shift;
    $content->{title} = $config{site}{name};

    my $head = $ml->div(
	$ml->div(
	    $ml->h1($config{site}{name}),
	    {id=>"sysinfo",class=>"ctrlblock"}
	).
	$ml->div(
	    $ml->div(
		$ml->a($ui->FAIcon("user").$db->my_login,{class=>"dropdown-toggle",'data-toggle'=>"dropdown",'aria-haspopup'=>"true",'aria-expanded'=>"false"})."&nbsp;".$ml->span(undef,{class=>"caret"}).
		$ml->ul(
		    $ml->li(
			$ml->a($ui->FAIcon("exit").$msg{logout},{href=>"$config{server}{CGIpath}/$config{prog}{logout}"})
		    ),
		    {class=>"dropdown-menu"}
		),
		{class=>"btn-group"}
	    ),
	    {class=>"ctrlblock",id=>"userinfo"}
	).
	$ml->div(
	    $ml->div($ml->span(undef,{class=>"fa fa-fw fa-plus"})."new pane",{class=>"appTab thisApp",id=>"newapp"}),
	    {class=>"ctrlblock",id=>"appinfo"}
	),
	{id=>"control"}
	);

### master section selector

    my @modules = ($access < 8 && $config{webtop}{whitelist}) ? 
	@{$config{webtop}{whitelist}} :
	&ExSite::Module::module_list;
	
    my $errors;
    my (%group,@App);
    my %category = map { $_=>1 } @{$config{webtop}{categories}};
    my $ctrlpanel_panes;

    foreach my $modname (@modules) {
	# skip certain modules
	next if (exists $config{webtop}{module_name}{$modname} && 
		 ! $config{webtop}{module_name}{$modname});
	my $mod = &ExSite::Module::get_module($modname);
	if ($mod) {
	    my $ctrlpanel = $mod->ioctl("ControlPanel");
	    if ($ctrlpanel) { 
		my $url = ((ref $ctrlpanel) =~ /CODE|ARRAY/) ?
		    "$config{server}{CGIpath}/$config{prog}{admin}/$modname" : 
		    $ctrlpanel;
		my $icon = &ExSite::Module::icon($modname,$config{iconset});
		my $label = $config{webtop}{module_name}{$modname} || $mod->ioctl('ModuleName') || $modname;
		my $descr = $mod->ioctl('ModuleInfo');
		$descr =~ s/\n/ /g;
		my $size = $mod->ioctl('Size');
		my $category = $mod->ioctl('Category') || "Applications";
		if (ref $category eq "ARRAY") {
		    # multiple categories; use first one that already exists
		    foreach my $cat (@$category) {
			if (exists $category{$cat}) {
			    $category = $cat;
			    last;
			}
		    }
		    if (ref $category) {
			# no category selected, take first one
			$category = $category->[0];
		    }
		}
		my $color = $config{webtop}{color}{$category};
		push @App, "$modname:{title:'$label',count:0,size:'$size',url:'$url',bgcolor:'$color'}";
		my $launcher = 
		    $ml->div(
			$ml->a(
			    $ml->img(undef,{width=>16,height=>16,src=>$icon,border=>0}).$label,
			    {href=>"javascript:launchApp('$modname')",
			     title=>$descr}
			),
			{class=>"appLaunchApp"}
		    );
		$group{$category} .= $launcher;
	    }
	}
	elsif ($@) {
	    $errors .= $ml->div($@,{class=>"error"});
	}
    }

#    # add a support link to the Overview category
#
#    $group{Overview} .= 
#	$ml->div(
#	    $ml->a(
#		$ml->img(undef,{width=>16,height=>16,src=>"$config{server}{HTMLpath}/_ExSite/images/icons/help.png",border=>0})."Help / Support",
#		{href=>"$config{server}{CGIpath}/$config{prog}{help}"}
#	    ),
#	    {class=>"appLaunchApp"}
#	);

    # add root section and any standalone sections to Overview
    my $c = new ExSite::Content();
    my $tree = $c->get_content_tree();
    foreach my $sdata ($tree->find({type=>$c->isubtype("section")})) {
	my $s = new ExSite::Section(data=>$sdata);
	if (!$s->getdata("parent") || $s->is_standalone) {
	    $group{Overview} .= 
		$ml->div(
		    $ml->a(
			$ml->img(undef,{width=>16,height=>16,src=>"$config{server}{HTMLpath}/_ExSite/images/icons/home.png",border=>0}).$s->title,
			{href=>$s->get_url(),target=>"_blank"}
		    ),
		    {class=>"appLaunchApp"}
		);
	}
    }

    # add our App lancher defs
    $head .= $ml->script("var Apps = {\n".join(",\n",@App)."\n};\n");

    # output our various application categories

    my $out;
    foreach my $category (@{$config{webtop}{categories}}) {
	my $title = $config{webtop}{headings}{$category} || $category;
	$out .= $ml->div(
	    $ml->h2($msg{$title}).$group{$category},
	    { class=>"appLaunchCategory" }
	    );
	delete $group{$category};
    }
    # append any irregular categories
    foreach my $category (keys %group) {
	$out .= $ml->div(
	    $ml->h2($msg{$category}).$group{$category},
	    { class=>"appLaunchCategory" }
	    );
    }
    if ($errors && $config{debug}) {
	$out .= $ml->div($ui->BasicBox(title=>$msg{"Errors"},pane=>$errors),{style=>"padding:20px;" });
    }
    $content->{head} .= &insert_js("jquery","jqueryui","bootstrap.min.js","misc.js","launcher.js");
    $content->{bodyhead} = $head;
    $content->{body} = 
	$ml->div(
	    $ml->div($out,{class=>"app",id=>"app_new"}
	    ),
	    {id=>"ExSiteAdmin"}
	);
    return;
}

# app : call a plugin directly

sub app {
    my ($dcdname, $page_id, $stat, $dcd, $license_ok, $script, $path, 
	$input, $output, $ref, $query, $prevquery);
    
    my (undef,$dcdname) = split(/\//,$ENV{PATH_INFO});

    if ($dcdname) { 
	my $in = new ExSite::Input;
	my $q = $in->query;
	# httpRequest tools do not set the HTTP_REFERER, so we have to 
	# manually insert referer data into our URL
	my $ref = $q->{_ref};
	my $prog_re = join('|',values %{$config{prog}});
	my $uri = &get_obj("URI");
	$uri->setup($ref);
	$uri->get('script_name') =~ /\/?(.*)/;
	$script = $1;
	$path = $uri->get('path_info');
	$prevquery = $uri->get('query');
	$page_id = $uri->get('query_data')->{_id};
	$db = new ExSite::Form;
	my $page;
	if ($page_id) {
	    $page = new ExSite::Page(id=>$page_id);
	}
	else {
	    $page = new ExSite::Page();
	    $page->setup(path=>$path);
	    $page_id = $page->id;
	}
	
	# should we use AJAX for re-links, too?
	if ($q->{_ajax}) {
	    $share{ajax_target} = $q->{_ajax};
	}

	# set another language?
	my $version = $page->get_my("version");
	if ($version) {
	    (tied %msg)->version($version);
	}

	if ($ref) {
	    # change environment to make it look like we are at the reference URL
	    $uri->use_input;
	    $ENV{SCRIPT_NAME} =~ s/$config{prog}{app}$/$script/;
	    $ENV{SCRIPT_FILENAME} =~ s/$config{prog}{app}$/$script/;
	    $ENV{QUERY_STRING} = $prevquery;
	    $ENV{PATH_INFO} = $path;
	    # reload the input buffers
	    delete $share{input};
	    my $in2 = new ExSite::Input;
	    $in2->query();
	    $in2->path_info();
	    # now add in any extra parameters that were passed to us
	    foreach my $param (keys %$q) {
		next if ($param =~ /^_/);   # skip dcd control parameters
		$in2->set($param,$q->{$param},"get");
	    }
	}

	# instantiate the reference page so that our module runs in proper context
	my $section;
	if ($page_id) {
	    my $page = new ExSite::Page(id=>$page_id);
	    $page->set_context("parent");
	    $page->fix_path();
	    $section = $page->get("section");
	    $share{Page} = $page;
	}
	
	# instantiate the module itself
	my $dcd = &ExSite::Module::get_module($dcdname,0,$section);
	if ($dcd) {
	    # execute the DCD method
	    my $options = &url_unescape($q->{_opt});
	    $output = $dcd->write($options) || $@;
	}
	else {
	    $output = $@ ? "$dcdname: $@" : "$dcdname: permission denied";
	}
    }
    else {
	$output = "app: no module!";
    }

    if ($share{Page}) {
	# this gives us our content-type header, plus assorted
	# other headers (such as cookies)
	$share{Page}->show_headers();
	# do not show any other page output, however
	$share{Page}->cancel;
    }
    elsif (! $share{noContentHeader}) {
	# this situation (calling app with no page object) is most likely
	# to occur in some special AJAX applications.  In these cases, the 
	# plug-in can inform us that they've already issued their content-type
	# header by setting $share{noContentHeader}
	print "Content-type: text/html\n\n";
    }
    print $output;
}

# captcha : form security widget

sub captcha {
    if ($ENV{HTTP_USER_AGENT} =~ /msnbot|Googlebot|Yahoo/i) {
	# looks like a robot - don't even bother
	print "content-type:text/plain\n\n";
	print "Silly robot.";
    }
    my $q = $input->query();
    if ($q->{postkey}) {
	# AJAX-generated passive captcha
	my $c = new ExSite::Captcha;
	my $postkey = $c->get_post_key($q->{postkey});
	print "Content-type: text/plain\n\n";
	print "$postkey";
    }
    elsif (exists $q->{key}) {
	# AJAX-generated interactive (image) captcha
	# disallow text mode switing in AJAX mode
	my $c = new ExSite::Captcha(mode=>$q->{captchamode});
	my $captcha = $c->make($q->{key});
	print "content-type: text/html\n\n";
	print $captcha;
    }
    else {
	# generate the captcha image itself
	if ($config{token}{captcha} && $config{token}{type} eq "db") {
	    # need DB access
	    require ExSite::DB;
	    my $db = new ExSite::DB;
	}
	my $c = new ExSite::Captcha;
	my $imgdata = $c->make_captcha_image($ENV{QUERY_STRING});
	print "content-type:image/png\n\n";
	print $imgdata;
    }
}

# debug : display information about the request

sub debug {
    # make sure our input buffers are loaded for reporting
    $input->query;
    $input->post;
    &simple_page($ml->div(&debug_status,{class=>"body"}),"Debug");
}

# dialog : used by HTML editors

sub dialog {
    print ExSite::Dialog->new()->run();
}

# dispatch: call multiple plugins in a single call

sub dispatch {
    my $in = $input->combine();
    if ($in->{_cookie}) { 
	# load ajax cookies
	(tied %cookie)->load_cookies($in->{_cookie});
	$db->clear_authentication();
    }
    my (%out,%json);
    my $page = $in->{_id} ?
	new ExSite::Page(id=>$in->{_id}) : new ExSite::Page();
    $share{Page} = $page;

    # set another language?
    my $version = $page->get_my("version");
    if ($version) {
	(tied %msg)->version($version);
    }
    
    if ($page->defined) {
	# change environment to make it look like we are at the reference URL
	$ENV{SCRIPT_NAME} =~ s/$config{prog}{dispatch}$/$config{prog}{page}/;
	$ENV{SCRIPT_FILENAME} =~ s/$config{prog}{dispatch}$/$config{prog}{page}/;
	$ENV{QUERY_STRING} = "_id=$in->{_id}";
	$ENV{PATH_INFO} = "";
	# reload the input buffers
	delete $share{input};
	my $in2 = new ExSite::Input;
	$in2->query();
	$in2->path_info();
    }

    foreach my $item (keys %$in) {
	if ($item =~ /^([A-Z][a-z]+)(:(\w+))?$/) {
	    my $module = $1;
	    my $target = $3 | $1;
	    my $mod = &ExSite::Module::get_module($module);
	    if ($mod) {
		$out{$target} = $mod->write($in->{$item});
	    }
	    else {
		$out{$target} = "dispatch: invalid module: $module";
	    }
	}
    }
    $page->cancel;
    print "Content-type: application/json\n\n";
    print &encode_json(\%out);
}

# doform : process a generic form

sub doform {
    $db->{map}->load_submaps(); # load the entire DBmap
    my $output = $db->do || 
	$ml->p("No response was received when this form was submitted.");
    &simple_page($ml->div($output,{class=>"body"}),"Form results");
}

# file : return a file from the data repository

sub file {
    my $path = $input->path();
    if ($db->level >= $config{auth}{file_access}) {
	if (-e "$config{server}{fileroot}$path") {
	    my $mime = &MimeType($path);
	    print "Content-type: $mime\n\n";
	    print &get_file("$config{server}{fileroot}$path");
	    $ml->cancel;
	}
	else {
	    &Error("$path: file not found");
	}
    }
    else {
	&Error("$path: permission denied");
    }
}

# help : administrator help

sub help {
    my $mod = &get_module();
    if ($mod) { 
	my %modinfo = &module_info(undef,$mod);
	if (-e "$modinfo{path}/help.html") {
	    my $out = &get_file("$modinfo{path}/help.html");
	    return &simple_page($out,"$modinfo{name} Help");
	}
    }
    elsif ($ENV{HTTP_REFERER} =~ /$config{prog}{help}\/(\w+)/) {
	# not a help file, but an auxilliary asset requested by the help file
	my $modname = $1;
	my @path = split(/\//,$ENV{PATH_INFO});
	my $file = $path[-1];
	if (-e "$config{server}{HTMLroot}$config{server}{HTMLpath}/_Modules/$modname/$file") {
	    my $fdata = &get_file("$config{server}{HTMLroot}$config{server}{HTMLpath}/_Modules/$modname/$file");
	    my $mime = &MimeType($file);
	    print "Content-type: $mime\n\n";
	    print $fdata;
	    return;
	}
	else {
	    print "Location: /file.not.found\n\n";
	}
    }
    else {
	my $ml = &get_obj("ML");
	my $out = &insert_js("misc");
	$out .= $ml->h1("Help Topics");
	my $base = "$config{server}{HTMLroot}$config{server}{HTMLpath}/_Modules";
	opendir my $dir, $base;
	my @helptopic;
	while (readdir $dir) { push @helptopic, $_; }

	$out .= $ml->h2("Installed Modules");
	foreach my $topic (sort @helptopic) {
	    if (-e "$base/$topic/help.html") {
		my $icon = &ExSite::Module::icon($topic);
		$out .= $ml->p(
		    $ml->a(
			$ml->img(undef,{src=>$icon,height=>16,width=>16}).$topic,
			{href=>"javascript:popup_medium('$config{server}{CGIpath}/$config{prog}{help}/$topic')"}
		    )
		    );
	    }
	}

	$out .= $ml->h2("General Help");
	$out .= $ml->p(
	    $ml->a(
		$ml->img(undef,{width=>16,height=>16,src=>"$config{server}{HTMLpath}/_ExSite/images/icons/help.png",border=>0})."http://support.exsitewebware.com",
		{href=>"http://support.exsitewebware.com",target=>"_blank"}
	    )
	    );

	return &simple_page($out,"$config{site}{name} Help");
    }
}

# home : send user to most appropriate place

sub home {
#    print "Content-type: text/html\n\n";
#    print "Access = $access\n";
    if ($config{auth}{login_destination}[$access]) {
	print "Location: $config{auth}{login_destination}[$access]\n\n";
    }
    else {
	print "Location: $config{server}{server}\n\n";
    }
}

# login, logout

sub login {
    my %data = %{$input->combine()};
    if (exists $data{login}) {
	my $db = new ExSite::DB;
	if ($data{login_action} eq "forgot") {
	    &simple_page($ml->div($db->login_recover_form(),{class=>"body"}),"Forgot Password");
	}
	else {
	    if ($config{throttle}{user}{rate} || $config{throttle}{system}{rate}) {
		my $rate = &throttle();
		if ($rate > 0) {
		    # someone is hammering us; delay the login attempt
		    sleep($rate * 10);
		}
	    }
	    if (my $access = $db->login($data{login},$data{password},$data{goto},$data{remember})) {
		my $destination = $data{goto} || $config{auth}{login_destination}[$access];
		&redirect_page($destination);
	    }
	    else {
		my $contents = 
		    $ml->h1("Login Denied").
		    $db->show_diagnostics("warn","HTML").
		    $ml->p(
			$ml->a("Try again",{href=>"javascript:history.back()"})
		    );
		&simple_page($ml->div($contents,{class=>"body"}),"Login Denied");
	    }
	}
    }
    else {
	if ($access) {
	    # user already logged in
	    my $destination = $data{goto} || $config{auth}{login_destination}[$access];
	    $ml->location($destination);
	}
	else {
	    my $login_form = $db->login_form(undef,$data{goto},$config{site}{logo}.$ml->h1($config{site}{name}));
	    &simple_page($ml->div($login_form,{class=>"body"}),
			 "$config{site}{name} Login");
	}
    }
}

sub logout {
    $db->logout;
    # that was easy, but now we have to figure out where to send them
    my $goto;
    my $uri = new ExSite::URI();
    my $uriinfo = $uri->info();
    if ($uriinfo->{path} =~ /$config{prog}{page}/) {
	my $p = new ExSite::Content();
	my @path = $p->path_to_obj();
	while (my $p = pop @path) {
	    last if ($p->subtype eq "section");
	}
	if ($p) {
	    $goto = $p->get_url;
	}
	else {
	    $goto = $uriinfo->{scheme}."://".$uriinfo->{authority};
	}
    }
    elsif ($uriinfo->{path} =~ /$config{prog}{admin}/) {
	$goto = $uriinfo->{scheme}."://".$uriinfo->{authority};
    }
    elsif ($uriinfo->{path} =~ /$config{prog}{logout}/) {
	$goto = $uriinfo->{scheme}."://".$uriinfo->{authority};
    }
    else {
	# send them back to whereever they came from
	$goto = $uri->write_full();
    }
    print "Location: $goto\n\n";
}

sub null {
    my $out = $ui->MenuBar(links=>[
	$ml->a("Admin",{href=>"$config{server}{CGIpath}/$config{prog}{admin}"}),
	$ml->a("Debug",{href=>"$config{server}{CGIpath}/$config{prog}{debug}"}),
	$ml->a("Test",{href=>"$config{server}{CGIpath}/$config{prog}{test}"}),
	$ml->a("Logout",{href=>"$config{server}{CGIpath}/$config{prog}{logout}"}),
	]);
    $out .= $ml->p("Please select from the options above to get started.");
    &simple_page($out);
#    &simple_page($ml->div($ml->p($error,{class=>"error"}),{class=>"body"}),"Error");
}

# op : operate on an object

sub op {
    my @path = $input->path();
    my ($type,$op,$id) = @path;
    my $out;
    if (! $type) {
	$out .= "invalid operation: no object type specified";
    }
    elsif (! $op) {
	$out .= "invalid operation: no operator specified";
    }
    else {
	my $class = $share{DB}{map}->get_table_attr($type,"class") || "ExSite::Object";
	$class =~ /^((ExSite|Modules)::.*)$/;
	my $safe_class = $1;
	if (eval "require $safe_class") {
	    my $obj = eval "new $safe_class(type=>'$type',id=>'$id')";
	    if ($obj) {
		my $query = $input->query;
		$out .= eval { $obj->$op($query); };
		if ($@) {
		    $out .= $obj->error($@);
		}
	    }
	    else {
		$out .= &diagnostic("$class: $@");
	    }
	}
	else {
	    $out .= &diagnostic("$class: $@");
	}
    }
    print "Content-type: text/html\n\n";
    print $out;
}

sub page {
    my $q = $input->query;

    my $cmsflag = $access >= 2 && exists $q->{_cms};
    my $got_page_id = 0;

    my $p = new ExSite::Page();
    my @path = $p->path_to_obj();
    if (@path > 0) {
	# path corresponds to actual content
	my @name = map { $_->getdata("name") } @path;
	$input->new_path("content",@name);

	# what is the final object in the path?
	$p = $path[-1];
	$share{Content} = $p;
	if ($p->displaytype eq "template") {
	    # $p already displays in a page-like way
	    $share{Page} = $p;
	    if ($p->allow()) {
		# insert all the content
		#$p->expand(cms=>$cmsflag);
		$p->output(cms=>$cmsflag);
	    }
	    else {
		# permission denied!  Require user to log in before proceeding.
		my $goto = $config{server}{server}.$ENV{REQUEST_URI};
		my $login_form = $share{DB}->login_form("",$goto);
		### FIXME use templated error pages
		&simple_page($login_form);
	    }
	}
	else {
	    # last object is NOT a page; display within a page
	    if ($p->allow()) {
		$share{Page} = $p->my_page;
		$p->show_templated(cms=>$cmsflag);
		# manually set the content type, since we are not displaying
		# the raw content
		$p->set("content_type","text/html");
		$p->output();
	    }
	    else {
		&simple_page($p->error("Permission denied."));
	    }
	}
    }
    else {
	# no content specified
	&simple_page($ml->h3("Error").$p->error("No page to display!"));
    }
    print &debug_footer();
}

# peek : retrieve a value from the database

# Usage:
#    /peek?tab=TABLE&id=RECORD&col=COLUMN[&type=MIMETYPE]
#    /peek/TABLE/RECORD/COLUMN[?type=MIMETYPE]
# The 2nd format might have better caching performance.

sub peek {
    my (%data, $outdata);
    my ($tab,$rec,$col,$q,$path,$approved,$readcol_ok);
    $q = $input->query();
    $path = $input->path();
    $tab = $q->{tab} || $path->[0];
    $rec = $q->{id} || $path->[1];
    $col = $q->{col} || $path->[2];
  
    # check permissions:
    my ($approved,$readcol_ok);

    # ignore unreferred calls
    if (($config{auth}{referer_check} && $ENV{HTTP_REFERER}) || 
	!$config{auth}{referer_check}) {
	# see if we have permission to read this table/record/column
	$approved = $db->approve("read",$tab,$rec);
	$readcol_ok = $db->{map}->get($tab,$col,"read") <= $db->authorize;
    }
  
    if ($approved && $readcol_ok) {
    
	# fetch the requested record
	if ($tab && $rec && $col) {
	    %data = $db->fetch($tab,$rec);
	}
	# determine the mime type
	if ($q->{type} =~ /.+\/.+/) {
	    # type has been passed in the QUERY_STRING
	    print "Content-type: $q->{type}\n\n";
	    $outdata = $data{$col};
	}
	elsif ($db->{map}->get_column_attr($tab,$col,"datatype") =~ /file$/) {
	    # type should be guessable from the filename
	    my ($filename, $content) = split /$config{form}{sepchar}/, $data{$col}, 2;
	    my $mimetype = &MimeType($filename);
	    print "Content-type: $mimetype\n\n";
	    $outdata = decode_base64($content);
	}
	else {
	    # unknown type; display the raw datum as text/plain
	    print "Content-type: text/plain\n\n";
	    $outdata = $data{$col};
	}
    }
    else {
	print "Content-type: text/plain\n\n";
	$outdata = "Permission denied.\n";
    }

    # display the data
    if ($outdata) {
	print $outdata;
    }
}

# post

sub post {
    my $q = $input->query();
    if ($q->{_cookie}) { 
	# load ajax cookies
	(tied %cookie)->load_cookies($q->{_cookie});
	$db->clear_authentication();
    }
    my $c = new ExSite::Content(id=>$q->{_id});
    if (! $c->exists) {
	# passed by path
	$c = $c->path_to_obj(); # set path to $ENV{PATH_INTO}
    }
    if ($c->exists) {
	# found the requested content
	$c = $c->get_content_obj();  # change type if necessary
	my $out = $c->post();
	if ($q->{_bare}) {
	    # return the post result directly
	    print "Content-type: text/html\n\n";
	    print $out;
	}
	else {

############# FIXME: is this still necessary?

#	    my $from = $ENV{HTTP_REFERER};
#	    my $prog = $config{prog};
#	    if ($from =~ /$prog->{page}|$prog->{view}|$prog->{post}/) {
#		# posting from a regular content view; return a regular view
		if ($c->allow_view()) {
		    $share{Page} = $c->my_page;
		    $c->show_templated(content=>{body=>$out});
		    $c->set("content_type","text/html");
		    $c->output();
		}
		else {
		    &simple_page($out,"Post");
		}
#	    }
#	    else {
#		# posting from an indirect view, such as a control panel
#		$share{post_result} = $out;
#		# go back to the referrer view
#		return &goto($from);
#	    }
	}
    }
    else {
	my $out = $msg{"Invalid post."};
	if ($q->{_bare}) {
	    print "Content-type: text/html\n\n";
	    print $out;
	}
	else {
	    &simple_page($out,"Post");
	}
    }
    print &debug_footer();
}

# publish : write files to disk

sub publish {
    my $q = $input->query;
    my $quiet = $q->{silent};
    # publisher runs as a separate program so it can get setuid privileges
    my $bin = $config{server}{bin};
    # un-taint the publisher
#    "$bin/publish" =~ /^((\/\w[\w\-\.]+)+)$/;
#    my $publisher = $1;
    my $publisher = "./publish.cgi";
    if ($publisher && -e $publisher) {
	open PUB, "$publisher|";
	while (<PUB>) { print if (! $quiet); }
	close PUB;
    }
    else {
	&Error("Unable to find publisher (not in $bin)");
    }
}

sub test {
    my ($db, @dat, $dat, $nfail);
    my %required_mods = (
	'CGI' => "for uploading files",
	'Digest::MD5' => "for various security functions",
	'Devel::Size' => "for caching",
	'MIME::Base64' => "for uploading files",
	'Net::SMTP' => "for sending emails",
	'Image::Info' => "for impage processing",
	'IO::String' => "for image processing",
	'Cwd' => "for caching",
	'IPC::Open2' => "for cryptography",
	'IPC::Open3' => "for image processing",
	'Time::Local' => "for time/date management");
    my %suggested_mods = (
	'GDBM_File' => "for caching",
	'MIME::Entity' => "for sending emails",
	'Storable' => "for caching",
	'Fcntl' => "for caching",
	'MIME::Words' => "for multilingual emails",
	'CGI::Carp' => "for error trapping",
	'LWP::Simple' => "for some advanced web services and distributed applications",
	'LWP::UserAgent' => "for some advanced web services and distributed applications",
	'Spreadsheet::WriteExcel' => "for data exports",
	'XML::RSS' => "for reading 3rd-party RSS feeds",
	'String::Diff' => "for viewing changes to content",
	);

    my $out = $ml->h1("Testing ExSite install...");
    my $br = $ml->br;
    $out .= $ml->h2("Looking for static files...");
    if (! -e "$config{server}{HTMLroot}$config{server}{HTMLpath}/_ExSite/css") {
	$out .= $ml->p("FAILED: _ExSite files not found (did you copy all of the html files into your htdocs area?)",{class=>"error"});
	$nfail++;
    }
    elsif (! -e "$config{server}{HTMLroot}$config{server}{HTMLpath}/_Modules/icon.gif") {
	$out .= $ml->p("FAILED: _Modules files not found (did you copy all of the html files into your htdocs area?)",{class=>"error"});
	$nfail++;
    }
    else {
	$out .= $ml->p("PASSED.");
    }

    $out .= $ml->h2("Looking for ExSite plugin modules...");
    my $tmpfail = $nfail;
    if (! -e "$config{server}{CGIroot}/Modules/BaseDCD.pm") {
	$out .= $ml->p("FAILED: BaseDCD.pm not found (did you copy all of the CGI files and folders into your cgi-bin area?)",{class=>"error"});
	$nfail++;
    }
    if (opendir D, "$config{server}{CGIroot}/Modules") {
	my @plugins = readdir D;
	closedir D;
	my $nplug;
	foreach my $plug (@plugins) { 
	    if ($plug =~ /\.pm$/) { $nplug++; }
	}
	if ($nplug < 2) {
	    $out .= $ml->p("WARNING: No plug-ins were found (have you installed any plug-ins?)",{class=>"error"});
	    $nfail++;
	}
    }
    else {
	$out .= $ml->p("FAILED: plug-in area is missing (did you installed the cgi-bin area?)",{class=>"error"});
	$nfail++;
    }
    if ($tmpfail == $nfail) {
	$out .= $ml->p("PASSED.");
    }

    $out .= $ml->h2("Connect to Database...");
    eval '$db = new ExSite::Report';
    if ($@ || (ref $db !~ /Report/)) {
	$out .= $ml->p("FAILED (reported error: <i>$@</i>)",{class=>"error"});
	$out .= $ml->p($ml->strong("Double-check your database connection parameters:"));
	$out .= $ml->pre("
server.db.name
server.db.type
server.db.user
server.db.pass
server.db.server\n");
	$nfail++;
	&simple_page($out,"Test");
	return;
    }
    else {
	$out .= $ml->p("PASSED.");
    }

    $out .= $ml->h3("Looking for tables...");
    eval '@dat = $db->get_tables()';
    if ($@ || (scalar @dat <= 0)) {
	$out .= $ml->p("FAILED (reported error: <i>$@</i>)",{class=>"error"});
	$out .= $ml->p($ml->strong("No database tables found.  Are you connecting to the right database?  Did you initialize the database?"));
	$nfail++;
	&simple_page($out,"Test");
	return;
    }
    elsif (scalar grep /^user$/,@dat > 0) {
	$out .= $ml->p("FAILED",{class=>"error"});
	$out .= $ml->p($ml->strong("No user table found - you will not be able to log in.  Are you connecting to the right database?  Did you initialize the database?"));
	$nfail++;
	&simple_page($out,"Test");
	return;
    }
    elsif (scalar @dat < 6) {
	$out .= $ml->p("WARNING",{class=>"error"});
	$out .= $ml->p($ml->strong("Insufficient number of tables found.  Are you connecting to the right database?  Did you initialize the database?"));
	$nfail++;
    }
    else {
	$out .= $ml->p("PASSED.");
    }

    $out .= $ml->h2("Looking for database map...");

    if (ref $db->{map} !~ /DBmap/) {
	$out .= $ml->p("FAILED",{class=>"error"});
	$out .= $ml->p($ml->strong("No database map found. Double-check your database map parameters, eg.:"));
	$out .= $ml-pre("
server.db.map = map
server.map.name = dbmap
server.map.type = text\n");
	$nfail++;
	&simple_page($out,"Test");
	return;
    }
    
    eval '$dat = $db->{map}->get_table_title("content",1)';
    if ($dat !~ /Content/) {
	$out .= $ml->p("FAILED",{class=>"error"});
	$out .= $ml->p($ml->strong("Unexpected result from map query.  Is your <tt>dbmap</tt> directory installed under the cgi-bin area?"));
	$nfail++;
	&simple_page($out,"Test");
	return;
    }
    eval '$dat = $db->{map}->get_ncol("user")';
    if ($dat < 4) {  # should be at least 6 columns in this table
	$out .= $ml->p("FAILED",{class=>"error"});
	$out .= $ml->p($ml->strong("Unexpected result from map query.  Is your <tt>dbmap</tt> directory installed under the cgi-bin area?"));
	$nfail++;
	&simple_page($out,"Test");
	return;
    }
    $out .= $ml->p("PASSED.");

    $out .= $ml->h2("Looking for users...");
    eval '@dat = $db->fetch_all("user")';
    if ($@ || (scalar @dat <= 0)) {
	$out .= $ml->p("FAILED (reported error: ".$ml->em($@).")",{class=>"error"});
	$out .= $ml->p($ml->strong("No users found.  Did you initialize the database?  Did you create an admin user?"));
	$nfail++;
	&simple_page($out,"Test");
	return;
    }
    else {
	eval '@dat = $db->fetch_match("user",{login=>"admin",password=>"password"})';
	if (@dat > 0) {
	    $out .= $ml->p("WARNING: you did not set a new login/password for the default user.  This installation is not secure!",{class=>"error"});
	}
	else {
	    $out .= $ml->p("PASSED.");
	}
    }

    $out .= $ml->h2("Checking publisher...");
    if (-e 'publish.cgi') {
	if (-u 'publish.cgi') {
	    $out .= $ml->p("PASSED.");
	}
	else {
	    $out .= $ml->p("FAILED",{class=>"error"});
	    $out .= $ml->p($ml->strong("Publish program does not have permission to write files.  Did you set the permissions on publish.cgi?"));
	    $nfail++;
	}
    }
    else {
	$out .= $ml->p("FAILED",{class=>"error"});
	$out .= $ml->p($ml->strong("Publish program not found.  Did you compile publish.cgi?"));
	$nfail++;
    }

    # check Perl modules installation

    my $nmodfail = 0;
    $out .= $ml->h2("Looking for required perl modules...");
    my $test;
    foreach my $mod (keys %required_mods) {
	$test .= "-- $mod: ";
	if (eval "require $mod") {
	    $test .= "passed$br";
	}
	else {
	    $test .= $ml->span("FAILED: $@",{class=>"error"}).$br;
	    $nmodfail++;
	}
    }
    $out .= $ml->p($test);
    $ml->h3("Looking for suggested perl modules...");
    $test = "";
    foreach my $mod (keys %suggested_mods) {
	$test .= "-- $mod: ";
	if (eval "require $mod") {
	    $test .= "passed$br";
	}
	else {
	    $test .= $ml->p("FAILED: $@",{class=>"error"}) . $br;
	    $nmodfail++;
	}
    }
    $out .= $ml->p($test);
    if ($nmodfail > 0) {
	$out .= $ml->p("Failed modules may have to be (re-) installed to get full
functionality.");
    }
    else {
	$out .= $ml->p("All modules found.");
    }

    $out .= $ml->h1("Exsite System Configuration");
    $out .= $ml->ul([
	"ExSite WebWare Version: ${ExSite::Config::VERSION}",
	"Installation name: $config{site}{name}",
	"Server: $config{server}{server}",
	"Base HTdocs Directory: $config{server}{HTMLroot}",
	"Base CGI Directory: $config{server}{CGIroot}",
	"Base HTML URL: $config{server}{HTMLpath}",
	"Base CGI URL: $config{server}{CGIpath}",
	"Administrator: $config{site}{administrator}",
	"Configuration: ".($config{server}{auto} ? "automatic" : "manual")
		    ]);

    my $status = ($nfail + $nmodfail) > 0 ? "performed" : "passed";
    $out .= $ml->h1("Done!").
	$ml->p("All basic connectivity tests $status.");
    if ($nfail > 0) {
	$out .= $ml->p("Some tests failed.  Consult the messages above for tips
on solving the problems indicated.");
    }  
    if ($nmodfail > 0) {
	$out .= $ml->p("Some Perl modules are missing;  you can proceed, but 
certain features may not be available.");
    }  
    $out .= $ml->p("If there are no serious problems, you can now try to ".
		   $ml->a("log in",{href=>"$config{server}{CGIpath}/$config{prog}{login}"}).".");
    &simple_page($out,"Test");
}

# view : show a bare content object
# view/path/to/content?revision=N&view=X

sub view {
    my $mime = "text/plain";
    my $out = "Unknown content.";  # default error
    my @path;
    my $q = $input->query();
    my $c = new ExSite::Content(id=>$q->{_id});
    if ($c->defined) {
	# passed by id
	my $path = $c->content_path(); # ObjectList, convert to array
	while (my $item = $path->shift) {
	    push @path, $c->get_content_obj($item->get());
	}
    }
    else {
	# passed by path
	@path = $c->path_to_obj(); # set path to $ENV{PATH_INTO}
    }
    if (@path > 0) {
	# found the requested content
	my @name = map { $_->getdata("name") } @path;
	$input->new_path("content",@name);
	$c = $path[-1];
	$share{Content} = $c;
	# set view, revision
	my $q = $input->query();
	$c->set_view($q->{view}) if ($q->{view});
	if ($q->{revision} && $access > 4) {
	    $c->load_revision($q->{revision});
	}
	my $view = $c->revision()->view();
	$mime = $view->mime_type;
	if ($c->allow()) {
	    # display the content
	    if ($q->{display} eq "raw" || $c->displaytype eq "raw") {
		$out = $view->get_raw();
	    }
	    else {
		# formatted content - must display as HTML
		if ($mime eq "text/html") {
		    # try to expand any embedded CMS tags
		    $out = $c->expand(html=>$c->show);
		}
		else {
		    $mime = "text/html";
		    $out = $c->show;
		}
	    }
	}
	# permission denied

	### FIXME: assumes this is a members-only issue, but it could be
	### unmoderated or disabled content

	elsif ($mime =~ /image/) {
	    my $img = "$config{server}{HTMLroot}$config{server}{HTMLpath}/_ExSite/images/forbidden.png";
	    $mime = "image/png";
	    $out = &get_file($img);
	}
	elsif ($q->{ref}) {
	    # members-only, but we have a login target URL
	    my $loginuri = new ExSite::URI(uri=>"$config{server}{server}$config{server}{CGIpath}/$config{prog}{login}");
	    $loginuri->path("action","login");
	    $loginuri->parameter("goto",$q->{ref});
	    $mime = "text/html";
	    $out = $ml->p(&substitute($msg{"Permission denied. Please ".$ml->a("log in",{href=>"[[url]]"})." first."},{url=>$loginuri->write_full()}),{class=>"error"});
	}
	else {
	    $mime = "text/html";
	    $out = $ml->p($msg{"Permission denied. Please log in first."},{class=>"error"});
	}
    }
    print "Content-type: $mime\n\n";
    print $out;
    return;
}

# admin template
#<link rel="stylesheet" href="[[base]]/_ExSite/css/jquery-ui.css" type="text/css">
#<link rel="stylesheet" href="[[base]]/_ExSite/css/jquery-ui.theme.css" type="text/css">

__DATA__
<!DOCTYPE html>
<html lang="en">
<head>
<title>[[title]]</title>
<meta http-equiv="Content-Type" content="text/html; charset=[[charset]]">
<link rel="shortcut icon" href="[[base]]/_ExSite/images/exsite.ico">
<link rel="stylesheet" href="[[base]]/_ExSite/css/ExSite.css" type="text/css">
[[head]]</head>
<body class="admin">
[[bodyhead]]
[[body]]
[[bodyfoot]]
</body>
</html>
