#!/usr/bin/perl
#-----------------------------------------------------------------------
#
#   Copyright 2001-2011 Exware Solutions, Inc.  http://www.exware.com
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

package ExSite::Template;

use strict;
use ExSite::Config;
use ExSite::Util;
use ExSite::Page;
use ExSite::Misc;

use vars qw(@ISA);
@ISA = qw(ExSite::Page);

sub my_subtype { return "template"; }

sub can_index {
    return undef; # no search on templates
}

# Templates have simplified expansion rules:
# - no WYSIWYG or inline editing features supported
# - no page URL expansion (since templates can be shared across sections)
# - no DCD expansion
# - no metadata expansion

sub expand {
    my ($this,%option) = @_;
    return $this->{html} if ($this->{expanded} || $this->{noexpand});
    $this->info("expanding template html");

    # monitor the content objects that we have expanded, to avoid infinite loops
    $this->{expanded} = {};

    # fetch raw template data
    # fetch prepublished template data, if possible; otherwise fetch raw data
    $this->{html} = $option{html} || $this->get_start_html($this);

    if (! exists $option{content}) { $option{content} = {}; }

    do {
	# clear substitution counter
	$this->{htmlsub} = 0;
	# content-URL substitutions, eg. SRC=[[content-object-name]]
	$this->{html} =~ s/\[\[(.+?)\]\]/$this->get_content_url($1,\%option)/ges;
	### we don't do page url substitions, because templates can be shared by
	### different sections
	# HTML content substitutions, eg. <!--content(content-obj-name)-->
	while ($this->{html} =~ /<\!--\&?content\((.+?)\)-->/) {
	    $this->{html} =~ s/<\!--\&?content\((.+?)\)-->/$this->get_content($1,\%option)/ges;
	}
    } until ($this->{htmlsub} == 0);

    # unmask any unexpanded tags
    $this->{html} = &restore_cms_tags($this->{html});

    # done
    $this->{expanded} = 1;
    return $this->{html};
}

# get_start_html: get the block of HTML used to seed the page

sub get_start_html {
    my ($this,$content) = @_;
    my $stat = $this->run_handler("template_get_start_html",$content);
    return $stat if (defined $stat);

    if ($this->ok) {

	if ($content && $content->subtype() ne "template") { # && $content->id != $this->id) {
	    # if displaying something other a template and other than ourself,
	    # look for a prepublished template
	    my $tpath = $this->diskpath();
	    if (-e "$tpath/index.html") {
		return &get_file("$tpath/index.html");
	    }
	}

	# see if template has its own revision
	if ($this->has_revisions()) {
	    my $rev = $this->revision();
	    if ($rev->defined && $rev->getdata("content_id") == $this->id) {
		return $rev->get_html();
	    }
	}

	my $t = $this->template;
	if ($t->ok) {
	    return $t->get_start_html($content);
	}
    }
    # shouldn't reach this point
    return $this->warn($this->label().": no template found");
}

# get_content : return replacement text for a <!--&content(...)--> CMS tag4

sub get_content {
    my ($this,$id,$option) = @_;
    my $view;
    if ($id =~ /^(.+)(:(\w+))?/) {
	# specific view requested
	$id = $1;
	$view = $3;
    }
    $this->{htmlsub}++;
    my ($start,$end,$cobj,$cobjname,$csub,$newtext,@cobjname);
    @cobjname = split(/,/,$id);
    # first content object in list is substituted directly
    $cobjname = shift @cobjname;
    $this->{expanded}{$cobjname} = 1;

    if ($option->{content}{$cobjname}) {
	# predefined content object
	$newtext = $option->{content}{$cobjname};
    }
    else {
	# look for matching content object in DB
	$cobj = $this->find($cobjname);
	if ($cobj->parent->subtype ne "template") {
	    # defer substitution of non-template content 
	    $newtext = $this->placeholder_image($id);
	}
	elsif ($cobj->getdata("content_role") eq "editorial") {
	    # defer substitution of editorial content 
	    $newtext = $this->placeholder_image($id);
	}
	else {
	    # substitute now
	    my $in = new ExSite::Input;
	    my $q = $in->query;
	    $newtext = $cobj->get_html;
	}
    }
    
    # remaining content objects in list are content objects to 
    # insert into the first content object
    
    my $icobj = 1;
    foreach $cobjname (@cobjname) {
	if ($cobjname =~ /^\".+\"$/) {
	    # quoted string - plaintext substitution
	    # simple strings only - (no commas!)
	    $cobjname =~ s/^\"//;
	    $cobjname =~ s/\"$//;
	    $newtext =~ s/<!--\&?content\($icobj\)-->/$cobjname/g;
	}
	else {
	    # unquoted string - treat as a content object reference
	    $newtext =~ s/<!--\&?content\($icobj\)-->/<!--content($cobjname)-->/g;
	}
	$icobj++;
    }
    return $newtext;
}

sub get_content_url {
    my ($this,$id,$option) = @_;
    # clean up id in case the browser has mangled it with escape codes
    $id =~ s/\&amp;/\&/g;
    my $view;
    # check for query string
    my $query;
    if ($id =~ /\?/) {
	($id,$query) = split /\?/, $id;
    }
    # check for view request
    if ($id =~ /^(.+)(:(\w+))?/) {
	# specific view requested
	$id = $1;
	$view = $3;
    }
    my ($cnode, $vfile);
    if ($id =~ /^\d+$/) {
	$cnode = new ExSite::Content(id=>$id);
	#### FIXME: validate permissions to view this cnode
    }
    else {
	$cnode = $this->find($id);
    }
    $cnode = $cnode->get_content_obj();
    if ($cnode->getdata("content_role") ne "design") {
	# we only resolve design content in templates
	return "[|[$id]|]";
    }

    #if ($cnode && $option->{cms}) { $cnode->load_revision("newest"); }
    $cnode->load_revision("newest");

    if ((! $cnode || ! $cnode->defined) && $id =~/\%/) {
	# no matching content - try unescaping any escape chars embedded in the id
	$id =~  s/%(..)/pack("c",hex($1))/ge;
	$cnode = $this->find($id);
    }
    if (! $cnode || ! $cnode->defined) {
	# no matching content - escape the tag chars in case this is not a CMS tag
	$vfile = &html_escape("[[$id]]","[]");
    }
    else {
	# regular content
	$cnode->set_view($view) if $view;
	$vfile = $cnode->get_url($option->{mode});

	if ($query) {
	    # alter the URL using the query info given to us
	    my $uri = $cnode->get_uri();
	    $uri->parameters(&DecodeString($query));
	    $vfile = $uri->write();
	}
    }
    return $vfile;
}

# FIXME: this function is never called. Delete?
sub publish_content {
    my ($this,%opt) = @_;

    # do not publish if we came from an alias
    return undef if ($this->alias);

    my $ml = &get_obj("ML");
    $this->{publish} = 1;

    # set the language
    (tied %msg)->language($this->getdata("language"));
    # rebuild environment as if we were viewing this page
    $this->update_env();

    my $name = $this->getdata("name");
    my $type = $this->my_subtype || "page";
    print $ml->li("Publishing template " . $ml->em($this->name));
    print "<ul>\n";

    $this->publish_contents(%opt);

    # publish our own data

    my $page_prev = $share{Page};
    $share{Page} = $this;
    my $format = $this->revision->view->getdata("format");
    
    # regular web page or other text file
    my $diskfile = new ExSite::Diskfile( base => $this->basedir,
					 path => $this->subdir,
					 filename => $this->filename,
					 contents => $this->expand(expand=>"template"),
	);
    $diskfile->publish($opt{force});
    $share{Page} = $page_prev;

    ### republish pages using this template??

    print "</ul>\n";
}

1;
