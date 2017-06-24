#!/usr/bin/perl
#----------------------------------------------------------------------------
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

package ExSite::Util;

use strict;
use ExSite::Misc;
use ExSite::Config;
use POSIX "setsid";
use Cwd;

#========================================================================

=pod

=head1 ExSite::Util --  miscellaneous utility functions needed by ExSite::

Miscellaneous routines and functions that depend on ExSite::Config only

=cut

#========================================================================

BEGIN {
    use Exporter   ();
    use vars       qw($VERSION @ISA @EXPORT);
    $VERSION     = 1.00;
    @ISA         = qw(Exporter);
    @EXPORT = qw(   &replace_tag &restore_cms_tags 
		    &restore_cms_tag_img &restore_cms_tag_dcd
		    &redirect &redirect_http &redirect_html
                    &make_name
		    &make_pdf
		    &run &spawn
		    &run_publisher
		    &parse_url
		    &sysload &throttle
		    &debug_status
		    );
}

=pod

=head2 redirect($goto) - change to a different URL.

This is presently an alias for C<redirect_http()>, which switches URLs 
using a C<Location:> header.  Partial (relative) URLs may leave the
address bar indicating the previous URLs, although the content will
reflect the new URL.

As an alternative, you can use C<redirect_html()>, which switches URLs
using a meta-refresh HTML tag.  This should update the address bar no matter
what URL you pass.  It also outputs a brief redirection message, which 
also allows the user to click a link to redirect in case the redirection
fails or is not supported by the browser.  However, it results in two 
distinct pages being served, which is slower.

=cut

sub redirect {
    &redirect_http(@_);
}

sub redirect_http {
    my $goto = shift;

    # look for page management objects that will handle redirection 
    # gracefully, even if we have already generated output.

    my $p = $share{Page} || $share{ML};
    if ($p) { 
	$p->location($goto);
    }
    else {
	# no page management objects found
	# try printing the location header directly
	print "Location: $goto\n";
    }
    return;
}

sub redirect_html {
    my ($goto,$message) = @_;
    my $ml = &get_obj("ML");
    $message or $message = "Redirecting to ".$ml->a($goto,{href=>$goto})."...";

    # look for page management objects that may contain buffered output;
    # cancel this output

    my $p = $share{Page} || $share{ML};
    if ($p) { 
	$p->cancel();
    }

    # now output a dummy page that contains a meta-refresh header

    print "Content-type:text/html\n\n";
    print $ml->html(
	$ml->head(
	    $ml->meta(undef,{'HTTP-EQUIV'=>"Refresh",CONTENT=>"0;URL=$goto"})
	).
	$ml->body($message)
	);
    return;
}

# make_name: generate a single "word-like" name from a block of text

sub make_name {
    my ($text, $allow_nonascii, $join_char) = @_;
    $join_char or $join_char = "_";
    if ($text =~ /<\w+( [^>]*)?>/) {
	$text = &make_plaintext($text,1);
    }
    $text = &utf8_to_ascii($text) unless $allow_nonascii;
    $text =~ s/[^\w]/ /g; # strip punctuation, linebreaks
    # remove small skipwords
    my $remove = $store{make_name_remove};
    if (! $remove) {
	$remove = {};
	foreach my $word (split /\s/, &get_file("$config{server}{CGIroot}/conf/stopwords.txt")) {
	    $remove->{$word} = 1 if (length $word < 5);
	}
	$store{make_name_remove} = $remove;
    }
    my @oldword = split(/\s/,$text);
    my $newtext;
    my $neg;
    foreach my $word (split(/\s/,$text)) {
	# string together significant words; negatives no, not, non are significant
	$neg = $neg || $word =~ /^no[tn]$/;
	next if ! $neg && $remove->{$word};
	$newtext .= $newtext ? $join_char.$word : $word;
	$neg = $word =~ /^no[tn]$/;
	last if (length $newtext > 60);
    }
    $newtext =~ s/$join_char{2,}/$join_char/g;
    if ($join_char eq "_") {
	$newtext =~ s/_-_/-/g;
    }
    return lc $newtext;
}

=pod

=head1 CMS tag utilities

=head2 replace_tag($html)

replaces the CMS tags in $html with IMG tags that serve as
placeholders, and allow the HTML to be displayed out of context.
DEPRECATED: ExSite::ContentBase::expand() dummy modes now do this
task.

=head2 restore_cms_tags($html)

convert masked CMS tags (see replace_tag) back to the original CMS
tags.

This routine contains a lot of ugly kludges to clean up after some 
browsers that alter our HTML for reasons that probably seemed like a good
idea to the browser authors, but which have obligated us to call down a 
plague of locusts upon them for messing with our stuff.

For example:

=over 4

=item IE randomly rearranges the attributes in our IMG tags, making it hard 
to find the ones we just inserted into the code.

=item IE rewrites our HREF URLs to add hostname info, thereby trashing our
page pointer tags.

=item several browsers like to convert '&' in URLs to '&amp;' and then 
convert it back again so that scripts etc. don't notice.  But *we* notice...

=back

=cut


sub replace_tag {
    my ($html) = @_;

    # replace <img src=[[...]]> tags

    $html =~ s/\<img src=(\'|\")?\[\[(\w+\.\w+)\]\](\'|\")?[^>]*\>/\<img alt=\"\[\[$2\]\]\" name=\"$2\" src=\"$config{server}->{HTMLpath}\/_ExSite\/images\/checker.png\" title=\"$2\" width=\"100\" height=\"50\"\>/gi;

    # replace <!--content(...)--> tags

    $html =~ s/\<!--content\((\w*)\)--\>/\<img alt=\"content($1)\" name=\"$1\" src=\"$config{server}->{HTMLpath}\/_ExSite\/images\/checker.png\" title=\"$1\" width=\"100\" height=\"50\"\>/gi;

    # replace DCD tags <!--&XYZ(...)-->

    $html =~ s/\<!--\&(\w+)\((.*?)\)--\>/\<img alt=\"$1($2)\" name=\"$1\" src=\"$config{server}->{HTMLpath}\/_ExSite\/images\/checker.png\" title=\"$1\" width=\"100\" height=\"50\"\>/gi;

    return $html;
}

sub restore_cms_tags {
    my ($data) = @_;

    # convert img tags back to CMS tags
    $data =~ s/(<img .+?>)/&restore_cms_tag_img($1)/gei;

    # convert content.cgi links back to CMS tags
    $data =~ s/(<(a|link|script) .+?>)/&restore_cms_tag_url($1)/gei;

    # restore masked URL substitutions - [|[name]|]
    $data =~ s/\[\|\[(.*?)\]\|\]/[[$1]]/g;
    $data =~ s/\{\|\{(.*?)\}\|\}/{{$1}}/g;

    # KLUDGE: unescape URL-substitution tags that are mysteriously escaped 
    # by some browsers
    $data =~ s/%7B%7B/{{/g;
    $data =~ s/%7D%7D/}}/g;
    $data =~ s/%5B%5B/\[\[/g;
    $data =~ s/%5D%5D/\]\]/g;

    # KLUDGE: fix page-URL substitutions that get trashed by IE
    # IE wants to convert '<a href={{x}}>' 
    #                  to '<a href="http://whatever.com/cgi/{{x}}>'
    # so we have to strip out the gak that it has so helpfully inserted
    # for us.
    $data =~ s/href=\"[^{>]+({{[^}]+}})\"/href=\"$1\"/g;
    $data =~ s/href=\"[^\[>]+(\[\[[^\]]+\]\])\"/href=\"$1\"/g;

    return $data;
}

sub restore_cms_tag_img {
    my ($tag) = @_;
    $tag =~ /^<\w+\s(.*)>$/;
    my %tagdata = &DecodeAttributes($1);
    my $ml = &get_obj("ML");
    if ($tagdata{src} =~ /$config{prog}{view}/) {
	# view URLs need to be converted back to CMS tags
	if ($tagdata{src} =~ /$config{prog}{view}(.*?)$/) {
	    my @name = split /\//, $1;
	    my $name = @name[-1];
	    if ($tagdata{alt} =~ /^\[\[.+\]\]$/) {
		# URL-substituted img
		$tagdata{src} = "[[$name]]";
		$tagdata{alt} = $tagdata{title};
		return $ml->img(undef,\%tagdata);
	    }
	    elsif ($tagdata{alt} =~ /^content(.+)$/) {
		# html-substituted img
		return "<!--content($name)-->";
	    }
	    else {
		# assume this should be a URL-substitution
		$tagdata{src} = "[[$name]]";
		return $ml->img(undef,\%tagdata);
	    }
	}
    }
    elsif ($tagdata{src} =~ /\/_ExSite\/images\/checker.png$/) {
	# content checker placeholder
	return "<!--$tagdata{alt}-->";
    }
    elsif ($tagdata{src} =~ /_Modules\/(([\w-]+)\/)?icon.(gif|png)$/) {
	# plugin icon
	$tagdata{title} =~ s/\&amp;/\&/g;
	$tagdata{alt} =~ s/\&amp;/\&/g;
	# name and params might be together or separated in title and alt
	return $tagdata{alt} =~ /^\&*\w+\(.*?\)$/ ?
	    "<!--&$tagdata{alt}-->" :
	    "<!--&$tagdata{title}$tagdata{alt}-->";
    }
    # not a CMS img tag
    return $tag;
}

# restore CMS URL refs in non-IMG tags

sub restore_cms_tag_url {
    my ($tag) = @_;
    $tag =~ /^<(\w+)\s(.*)>$/;
    my $el = lc $1;
    my %srcattr = ( a=>"href", script=>"src", link=>"href" );
    if ($srcattr{$el}) {
	my %tagdata = &DecodeAttributes($2);
	my $url = $tagdata{$srcattr{$el}};
	if ($url =~ /$config{prog}{view}(.*?)$/) {
	    my @name = split /\//, $1;
	    my $name = @name[-1];
	    $tagdata{$srcattr{$el}} = "[[$name]]";
	    my $ml = &get_obj("ML");
	    my $newtag = $ml->Element($el,undef,\%tagdata);
	    $newtag =~ s/<\/$el>$//; # we only want the opening tag
	    return $newtag;
	}
    }
    # not a CMS tag
    return $tag;
}

# DCD tags get the parameter separator '&' munged by browsers. We should
# switch to using ';' instead, but in the meantime, this kludge un-munges 
# the '&' characters in the tags.

sub restore_cms_tag_dcd {
    my ($dcd,$param) = @_;
    $dcd =~ s/\&amp\;/\&/g; # dcd name can have embedded & chars, if using Ajax
    $param =~ s/\&amp\;/\&/g;
    return "<!--\&$dcd($param)-->";
}

#------------------------------------------------------------------------
# Unpriveleged publishing - if we need to publish files from a URL other
# than publish.cgi, we have to do so by running publish.cgi, since no other
# programs have sufficient priveleges.
#
# Admin privileges are still required to do this.  To run this as an 
# unprivileged user, you must pass an authtoken in the %$other args.
#
# Options:
# id => the content id to publish
# module => the module to publish
# install => the file to install
# unpublish => run unpublish instead of publish, if true
# args => hash of other arguments to publish command
# self => publish only this item (default true)
# child => publish sub-items (default true)
# parent => publish container (default true)
# uid => uid to run as
# exec_method => run or spawn

sub run_publisher {
    my (%opt) = @_;

    my %args = (ref $opt{args} eq "HASH") ? %{$opt{args}} : ();
    if ($opt{id}) {
	if ($opt{unpublish}) {
	    $args{'-id'} = $opt{id};
	}
	else {
	    $args{id} = $opt{id};
	}
    }
    elsif ($opt{module}) {
	if ($opt{unpublish}) {
	    $args{'-module'} = $opt{module};
	}
	else {
	    $args{module} = $opt{module};
	}
    }
    elsif ($opt{install}) {
	my $c = new ExSite::Crypt;
	my $cryptfile = $c->encrypt($opt{install});
	if ($opt{unpublish}) {
	    $args{'-install'} = $cryptfile;
	}
	else {
	    $args{install} = $cryptfile;
	}
    }
    foreach my $method (qw(self parent child)) {
	$args{$method} = $opt{$method} if (exists $opt{$method});
    }
    my $script = "$config{server}{CGIpath}/$config{prog}{publish}";
    my $query = &EncodeHash(%args);
    if ($opt{uid}) {
	my $publish_url = "$script?$query";
	my $authtoken = $share{DB}->make_authtoken($opt{uid},0,$publish_url);
	$query .= "&_auth=$authtoken";
    }

    # overload environment
    $ENV{QUERY_STRING} = $query;
    $ENV{SCRIPT_NAME} = $script;
    $ENV{REQUEST_METHOD} = "GET";
    $ENV{PATH_INFO} = "";

    my $cmd = "$config{server}{CGIroot}/$config{prog}{publish}";
    $cmd =~ /^((\/\w[\w\-\.]+)+)$/;
    my $secure_cmd = $1;
    &diagnostic({message=>"spawning $script?$query",type=>"cms",level=>1});
    #my $out = &run($secure_cmd);
    my $time = time;
    $opt{exec_method} eq "run" ? &run($secure_cmd) : &spawn($secure_cmd);
    &diagnostic({message=>(time - $time)." seconds elapsed during exec",type=>"cms",level=>1});
    # restore the environment of the current request, just to be safe
    $ENV{QUERY_STRING} = $share{ENV}{QUERY_STRING};
    $ENV{SCRIPT_NAME} = $share{ENV}{SCRIPT_NAME};
    $ENV{REQUEST_METHOD} = $share{ENV}{REQUEST_METHOD};
    $ENV{PATH_INFO} = $share{ENV}{PATH_INFO};

    #return $out || $?;
    return $?;
}

# $what - section|page|content|module
# $id - numeric id, or module name
# $unpublish - true (1) if we are removing, rather than creating, files
# $other - hash ref to other publish args

sub run_publisher_old {
    my ($id,$unpublish,$other,$exec_method) = @_;

    my %args = (ref $other eq "HASH") ? %$other : ();
    if ($unpublish) {
	$args{'-id'} = $id;
    }
    else {
	$args{id} = $id;
    }

    # overload environment
    $ENV{QUERY_STRING} = &EncodeHash(%args);
    $ENV{SCRIPT_NAME} = "$config{server}{CGIpath}/$config{prog}{publish}";
    $ENV{REQUEST_METHOD} = "GET";
    $ENV{PATH_INFO} = "";

    my $cmd = "$config{server}{CGIroot}/$config{prog}{publish}";
    $cmd =~ /^((\/\w[\w\-\.]+)+)$/;
    my $secure_cmd = $1;
    &diagnostic({message=>"spawning $ENV{SCRIPT_NAME}?$ENV{QUERY_STRING}",type=>"cms",level=>1});
    #my $out = &run($secure_cmd);
    my $time = time;
    $exec_method eq "run" ? &run($secure_cmd) : &spawn($secure_cmd);
    &diagnostic({message=>(time - $time)." seconds elapsed during spawn",type=>"cms",level=>1});
    # restore the environment of the current request, just to be safe
    $ENV{QUERY_STRING} = $share{ENV}{QUERY_STRING};
    $ENV{SCRIPT_NAME} = $share{ENV}{SCRIPT_NAME};
    $ENV{REQUEST_METHOD} = $share{ENV}{REQUEST_METHOD};
    $ENV{PATH_INFO} = $share{ENV}{PATH_INFO};

    #return $out || $?;
    return $?;
}

# parse a URL into its component parts
# $protocol://$host$scriptpath/$scriptfile$pathinfo?$query
#
# can optionally pass in a regexp to identify scripts;
# by default, we use $config{prog} to recognize scripts.
#
# DEPRECATED:  use ExSite::URI instead

sub parse_url {
    my $url = shift;
    my $scriptre = shift || join "|",values %{$config{prog}};
    my ($script,$query) = split /\?/, $url, 2;
    my ($protocol,$hostpath) = split /\:\/\//, $script;
    my (@path,$host);
    if ($hostpath) { 
	@path = split /\//,$hostpath;
	$host = shift @path;
    }
    else {
	# missing protocol - partial url?  All our data is probably in protocol
	@path = split /\//,$protocol;
	$protocol = $config{server}{protocol};
	$host = "$config{server}{host}.$config{server}{domain}";
    }
    my $scriptfile = undef;
    my (@scriptpath,@pathinfo);
    while (@path) {
	my $pathel = shift @path;
	if ($pathel =~ /$scriptre/) { $scriptfile = $pathel; }
	elsif ($scriptfile) { push @pathinfo,$pathel; }
	else { push @scriptpath,$pathel; }
    }
    my $scriptpath = join("/",@scriptpath);
    my $pathinfo = join("/",undef,@pathinfo);
    return ($protocol,$host,$scriptpath,$scriptfile,$pathinfo,$query);
}

=pod

Here is an alternative URL-parsing approach from the W3C docs:

Berners-Lee, et al.         Standards Track                    [Page 50]
RFC 3986                   URI Generic Syntax               January 2005

   As the "first-match-wins" algorithm is identical to the "greedy"
   disambiguation method used by POSIX regular expressions, it is
   natural and commonplace to use a regular expression for parsing the
   potential five components of a URI reference.

   The following line is the regular expression for breaking-down a
   well-formed URI reference into its components.

      ^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?
       12            3  4          5       6  7        8 9

   The numbers in the second line above are only to assist readability;
   they indicate the reference points for each subexpression (i.e., each
   paired parenthesis).  We refer to the value matched for subexpression
   <n> as $<n>.  For example, matching the above expression to

      http://www.ics.uci.edu/pub/ietf/uri/#Related

   results in the following subexpression matches:

      $1 = http:
      $2 = http
      $3 = //www.ics.uci.edu
      $4 = www.ics.uci.edu
      $5 = /pub/ietf/uri/
      $6 = <undefined>
      $7 = <undefined>
      $8 = #Related
      $9 = Related

   where <undefined> indicates that the component is not present, as is
   the case for the query component in the above example.  Therefore, we
   can determine the value of the five components as

      scheme    = $2
      authority = $4
      path      = $5
      query     = $7
      fragment  = $9

=cut

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

#------------------------------------------------------------------------
# make_pdf : generate a PDF file from a PS template
#
# $template = postscript template filename/path
# $subst = a substitution hash
#
# The PS template is plain text and can contain substitution tags
# of the form [[TAG]].  We make the substitutions in the PS (source)
# file, and then use ps2pdf to compile the PDF.  The PDF is returned
# as a data blob;  undef is returned if there was an error.  (Check
# $? or $! for possible reasons.)
#------------------------------------------------------------------------

sub make_pdf($$) {
    my ($template,$subst) = @_;
    my $pdfdata;
    my $cwd = cwd;

    # open the template and source file
    open TEMPLATE, "<$template";
    if (chdir $config{server}{temppath}) {
	open PS, ">makepdf$$.ps";
	while (<TEMPLATE>) {
	    # make substitutions and write to the source file
	    if (keys %$subst) {
	    s/\[\[(.+?)\]\]/$subst->{$1}/ge;
	    }
	    print PS;
	}
	close PS;

	# generate a PDF from the source file
	my $errcnt = &AtError();
	my $scratch = &run("ps2pdf $config{server}{temppath}/makepdf$$.ps");
	if (! &AtError($errcnt)) {
	    # no errors
	    if (open PDF, "<$config{server}{temppath}/makepdf$$.pdf") {
		# read the pdf into memory
		my $size;
		my $pos = 0;
		do {
		    $size = read(PDF,$pdfdata,1024,$pos);
		    $pos += $size;
		} until (!$size);
		close PDF;
		# PDF now loaded in memory; discard the file
		unlink "$config{server}{temppath}/makepdf$$.pdf";
	    }
	}
	# discard the source file
	unlink "$config{server}{temppath}/makepdf$$.ps";
    }
    close TEMPLATE;
    chdir $cwd;
    return $pdfdata;
}

#------------------------------------------------------------------------
# run : run an external command and capture its output
#
# Usage: ($out,$err) = run($cmd,$in);
#
# Implementation depends on which streams are used.  If there is no $in
# data, no STDIN is provided to the remote process.  If wantarray is false,
# no STDERR is returned from the remote process:
#
# $out = run($cmd);            # return STDOUT
# $out = run($cmd,$in);        # send STDIN, return STDOUT
# ($out,$err) = run($cmd);     # return STDOUT & STDERR
# ($out,$err) = run($cmd,$in); # send STDIN, return STDOUT & STDERR
#
# $cmd may fail to run if you do not taint-check it.
# $ENV{PATH} is automatically un-tainted, by being set to the securepath.
#------------------------------------------------------------------------

sub run {
    my ($cmd,$in) = @_;
    my ($out,$err);
    if (&is_tainted($ENV{PATH})) { 
	$ENV{PATH} = $config{server}{securepath};
    }
    if (&is_tainted($cmd)) {
	&diagnostic("Unsafe command: $cmd");
	return undef;
    }
    if (wantarray) {
	# require STDERR
	if (require IPC::Open3) {
	    # STDIN and STDERR both needed - use 3-stream spawn
	    my $pid = open3(*W, *R, *E, $cmd);
	    # send input
	    print W $in; 
	    close W;
	    # get output
	    while (<R>) { $out .= $_; } 
	    close R;
	    # get error
	    while (<E>) { $err .= $_; } 
	    close E; 
	    # anti-zombie incantation
	    waitpid $pid, 0;
	}
	else {
	    my $err = "IPC::Open3 failed: $!";
	    &diagnostic($err);
	    return ($err, "");
	}
    }
    elsif ($in) {
	# STDIN and STDOUT only
	if (require IPC::Open2) {
	    my $pid = open2(*W, *R, $cmd);
	    # send input
	    print W $in; 
	    close W;
	    # get output
	    while (<R>) { $out .= $_; } 
	    close R;
	    # anti-zombie incantation
	    waitpid $pid, 0;
	}
	else {
	    my $err = "IPC::Open2 failed: $!";
	    &diagnostic($err);
	    return ($err, "");
	}
    }
    else {
	# STDOUT only
	$out = `$cmd`;
    }
    if ($?) {
	# exec'd command had a problem
	&diagnostic("$cmd failed, error code $?");
    }
    return wantarray ? ($out,$err) : $out;
}

#------------------------------------------------------------------------
# spawn : fork/exec an external command so it runs detached from the 
#         current process. All output is discarded.
#
# Usage: &spawn($cmd);
#
# $cmd may fail to run if you do not taint-check it.
# $ENV{PATH} is automatically un-tainted, by being set to the securepath.
#------------------------------------------------------------------------

sub spawn {
    my $cmd = shift;
    if (&is_tainted($ENV{PATH})) { 
	$ENV{PATH} = $config{server}{securepath};
    }
    if (&is_tainted($cmd)) {
	&diagnostic("Unsafe command: $cmd");
	return undef;
    }
    else {
	#$SIG{CHLD} = "IGNORE";
	if (fork) {
	    # resume regular Apache request
	    return;
	}
	else {
	    # we are in the forked process
	    &diagnostic({message=>"forked $cmd",level=>1,type=>"general"});
	    &exsite_close();
	    # shutdown all our I/O streams
	    open STDIN, '</dev/null';
	    open STDOUT, '>/dev/null';
	    open STDERR, '>&STDOUT';
	    # now run new command
	    #exec $cmd ;  ### for some reason Apache holds on to this one
	    system("$cmd >/dev/null 2>&1 &");
	    #system("$cmd > publish.log 2>&1 &"); # debug
	    exit;
	}
    }
}

#------------------------------------------------------------------------
# debug_status : report debugging information about the current request
# Can optionally pass the output of time to get benchmarking info.
#------------------------------------------------------------------------
# deprecated? see ex.cgi::debug_status

sub debug_status {
    return if (! $config{debug});
    #return if ($ENV{REMOTE_ADDR} =~ /$config{auth}{trusted_hosts}/);
    my $ml = &get_obj("ML");
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
    if ($share{input}{get}{raw}) {
	$out .= $ml->h2("GET data");
	$out .= $ml->pre($share{input}{get}{raw});
    }
    if ($share{input}{post}{raw}) {
	$out .= $ml->h2("POST data");
	$out .= $ml->pre($share{input}{post}{raw});
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
	$out .= $ml->h2("Cookies");
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
	$out .= $ml->pre($cmd1);
    }
    else {
	$out .= $ml->h3("Automatic login");
	$out .= $ml->pre($cmd1);
	$out .= $ml->h3("Manual login");
	$out .= $ml->pre($cmd2);
    }
    return $ml->div($out,{class=>"ExSiteDebug"});
}

1;
