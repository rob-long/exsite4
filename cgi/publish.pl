#!/usr/bin/perl
#-----------------------------------------------------------------------
# publish.pl - write public content to disk
#
# Typically run via the publish.c[gi] setuid wrapper, to obtain the 
# necessary write permissions.
#
# USAGE:
#    publish.cgi?id=xxx - publishes content id XXX
#    publish.cgi?-id=xxx - unpublishes content id XXX
#    publish.cgi?module=xxx - publishes plug-in module XXX
#    publish.cgi?-module=xxx - unpublishes plug-in module XXX
#    publish.cgi?install=xxx - install file xxx
#    publish.cgi?-install=xxx - removes files xxx
#
#    The parameter silent=1 causes publish.pl to run silently.
#    This is useful when invoking publish.cgi indirectly to write
#    files to disk.  Otherwise it ends up writing to the top of
#    the current page.
#
# "publish" creates files
# "unpublish" removes files (presumably ones that were previously published)
#
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

# KLUDGE!  Include local dir in path to get ExSite libraries.
# This makes the path insecure for setuid execution of other programs.
my ($utime1,$stime1,$cutime1,$cstime1,$rtime);
BEGIN { 
    if (grep ( /^\.$/, @INC ) == 0) { push @INC,"."; } 
    ($utime1,$stime1,$cutime1,$cstime1) = times;
    $rtime = time;
}

use strict;
use ExSite::Config;
use ExSite::Form;
use ExSite::Content;
use ExSite::Input;
use ExSite::Auth;
use ExSite::Misc;
use ExSite::ML;
use ExSite::Module qw(&get_module);
use ExSite::Search;

&exsite_init;
my $db = new ExSite::Form;
&diagnostic({level=>1,type=>"cms",message=>"running publisher"});
my $in = new ExSite::Input;
my $auth = new ExSite::Auth;
if ($config{search}{reindex_on_publish}) {
    $share{Search} = new ExSite::Search;
}
my $ml = new ExSite::ML;
my %query = %{$in->query};
my $delay = 3;                           # seconds to refresh
my $obj;                                 # cms object
my ($redirect_url,$type,$name);

if ($query{silent}) {
    # run silently, so we don't contaminate another page's output

    # save old streams
    open(OLDOUT, ">&STDOUT");
    open(OLDERR, ">&STDERR");
    # redirct streams to /dev/null
    open(STDOUT, '>', "/dev/null") || die "Can't redirect stdout";
    open(STDERR, ">&STDOUT")       || die "Can't dup stdout";
    # make unbuffered
    select(STDERR); $| = 1;
    select(STDOUT); $| = 1;
}
else {
    $| = 1;
}

# disable cookies in published pages
tied (%cookie)->publish_mode();

if ($db->is_visitor) {
    &print_head;
    &diagnostic({level=>2,type=>"cms",message=>"Unpublish $query{id} - permission denied"});
    print "\n",$ml->p("Permission denied.");
}
elsif ($query{id}) {
    # publish a cnode
    &diagnostic({level=>1,type=>"cms",message=>"publishing content $query{id}"});
    my $cnodedata = $share{DB}->fetch("content",$query{id});
    if ($cnodedata) {
	my $cnode = new ExSite::Content();
	my $obj = $cnode->get_content_obj($cnodedata);
	if ($obj->allow("publish")) {
	    $share{publish} = $query{id};
	    $obj->set("revision","newest");
	    
	    # redirect to published page when done
	    $redirect_url = $obj->get_url_canonical();
	    #print "Refresh: ${delay}; URL=$url\n";
	    &print_head;

	    # authenticate/authorize

	    $share{DB}->set_level(0);
	    $type = $obj->my_subtype || "Content";
	    $name = $obj->name;
	    print $ml->h2("Publishing ".$ml->em($name));
	    $share{Page} = $obj;
	    $obj->info("Publishing $type $name");
	    print "<ul>\n";
	    my %popt;
	    foreach my $method (qw(child parent self force)) {
		$popt{$method} = $query{$method} if (exists $query{$method});
	    }
	    eval { $obj->publish(%popt); };
	    if ($@) { 
		print $obj->error($@); 
		&diagnostic({level=>2,type=>"cms",message=>"publish failed: $@"});
	    }
	    print "</ul>\n";
	}
	else {
	    print $ml->p("Permission denied.");
	}
    }
    else {
	&diagnostic({level=>3,type=>"cms",message=>"content $query{id} not found"});
    }
}
elsif ($query{'-id'}) {
    # unpublish a cnode
    &print_head;
    my $id = $query{'-id'};
    &diagnostic({level=>1,type=>"cms",message=>"unpublishing content $id"});
    my $cnodedata = $share{DB}->fetch("content",$id);
    if ($cnodedata) {
	my $cnode = new ExSite::Content();
	my $obj = $cnode->get_content_obj($cnodedata);
	if ($obj->allow("publish")) {
	    my $type = $obj->my_subtype || "Content";
	    print $ml->h2("Removing $type $id");
	    $obj->info("Unpublishing $type $id");
	    print "<ul>\n";
	    my %popt;
	    foreach my $method (qw(child parent self)) {
		$popt{$method} = $query{$method} if (exists $query{$method});
	    }
	    eval { $obj->unpublish(%popt); };
	    if ($@) {
		print $obj->error($@); 
		&diagnostic({level=>2,type=>"cms",message=>"publish failed: $@"});
	    }
	    print "</ul>\n";
	}
	else {
	    &diagnostic({level=>2,type=>"cms",message=>"Unpublish $query{id} - your keys do not allow publishing"});
	}
    }
    else {
	&diagnostic({level=>3,type=>"cms",message=>"unpublish content $id not found"});
    }
}
elsif ($query{module}) {
    # publish plug-in
    &print_head; 
    $query{module} =~ /^(\w+)$/;
    my $mod = $1;

    $obj = &get_module($mod);
    if ($obj) { 
	my $publisher = $obj->ioctl("Publish");
	if (ref $publisher eq "CODE") {
	    $obj->info("Publishing Module $mod");
	    print $obj->$publisher || $@;
	}
	else {
	    print "$mod: this module does not publish";
	}
    }
    else {
	my $reason = $@ || "no license";
	print "$mod: permission denied ($reason)";
    }
    ### FIXME: reindex if $config{search}{reindex_on_publish}
}
elsif ($query{'-module'}) {
    # publish plug-in
    &print_head; 
    $query{module} =~ /^(\w+)$/;
    my $mod = $1;

    $obj = &get_module($mod);
    if ($obj) { 
	my $publisher = $obj->ioctl("Unpublish");
	if (ref $publisher eq "CODE") {
	    $obj->info("Unpublishing Module $mod");
	    print $obj->$publisher || $@;
	}
	else {
	    print "$mod: this module does not unpublish";
	}
    }
    else {
	my $reason = $@ || "no license";
	print "$mod: permission denied ($reason)";
    }
}
elsif ($query{install}) {
    # install file into file repository
    &print_head;
    my $crypt = new ExSite::Crypt();
    my $filename = $crypt->decrypt($query{install});
    if ($filename) {
	print $ml->h2("Installing file $filename");
	my $file = "$config{server}{temppath}/exsite-$filename";
	if (-e $file) {
	    my $df = new ExSite::Diskfile(tmpfile=>$file,
					  filename=>$filename);
	    $df->audit("Installing $file");
	    print $df->install();
	}
	else {
	    print $ml->p("$filename not found");
	}
    }
    else {
	print $ml->p("$filename not found");
    }
}
elsif ($query{'-install'}) {
    # remove file from file repository
    &print_head;
    my $crypt = new ExSite::Crypt();
    my $filename = $crypt->decrypt($query{'-install'});
    if ($filename) {
	print $ml->h2("Removing file $filename");
	my $file = "$config{server}{fileroot}$filename";
	if (-e $file) {
	    unlink $file;
	}
	else {
	    print $ml->p("$filename not found");
	}
    }
    else {
	print $ml->p("$filename not found");
    }
}
else {
    print $ml->h2("Error: nothing to publish! $ENV{QUERY_STRING}");
}

if ($config{search}{reindex_on_publish}) {
    $share{Search}->update($config{search}{threshold});
}

my $buttons = $query{back} ?
    $ml->a("&lt; Back",{href=>"javascript:history.back()",class=>"button"}) :
    $ml->a("Close Window",{href=>"javascript:window.close()",class=>"button"});
if ($redirect_url) {
    $buttons .= $ml->a("Go to $type $name",{href=>$redirect_url,class=>"button"});
}

print $ml->div($buttons,{align=>"center",style=>"padding:10px;"});

my @err = $db->fetch_diagnostics("error");
my @warn = $db->fetch_diagnostics("warn");
if (ref $obj) { 
    push @err, $obj->fetch_diagnostics("error") if ($obj->errorcheck("error"));
    push @warn, $obj->fetch_diagnostics("warn") if ($obj->errorcheck("warn"));
}
#print $db->show_diagnostics("info","html");

if (scalar @err + scalar @warn > 0) {
    print $ml->h3("Diagnostic Information:");
}
if (scalar @err > 0) {
    print $ml->p("Errors:"), $ml->ol(\@err);
}
if (scalar @warn > 0) {
    print $ml->p("Warnings:"), $ml->ol(\@warn);
}

&print_foot;
if ($query{silent}) {
    # restore normal I/O streams
    close(STDOUT);
    close(STDERR);
    open(STDOUT, ">&OLDOUT");
    open(STDERR, ">&OLDERR");
}
&exsite_close;
if ($ENV{EXSITE_BENCHMARK}) {
    my ($utime2,$stime2,$cutime2,$cstime2) = times;
    print "\nUser time:         ".($utime2-$utime1).
	"\nSystem time:       ".($stime2-$stime1).
	"\nChild User time:   ".($cutime2-$cutime1).
	"\nChild System time: ".($cstime2-$cstime1).
	"\nTotal Real Time:   ".(time - $^T)."\n";
}

sub print_head {
    print "Content-type: text/html\n\n";

    # we print incomplete html and body tags because we want to ouput the page
    # in real time, and cannot close these tags until all output has bee flushed.
    print $config{doctype},"\n";
    print "<html>\n";
    print $ml->head(
		    $ml->title("$config{site}{name} Publisher").
		    $ml->link(undef,
			      {rel=>"stylesheet",
			       href=>"$config{server}{HTMLpath}/_ExSite/css/ExSite.css",
			       type=>"text/css"})
		    );
    print "<body>\n";
    print $ml->div(
		   $config{site}{logo}.
		   $ml->br.
		   $ml->h1("ExSite Publisher"),
		   {align=>"center"}
		   );
    #print $ml->p($ENV{QUERY_STRING});  # debug
}

sub print_foot {
    print &ExSite::Config::show_diagnostics("html",1);
    print "</body>\n</html>\n";
}

