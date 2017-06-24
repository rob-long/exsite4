#!/usr/bin/perl
#----------------------------------------------------------------------------
#
#   Copyright 2001-2006 Exware Solutions, Inc.  http://www.exware.com
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

package ExSite::Section;

use strict;
use ExSite::Config;
use ExSite::ML;
use ExSite::Misc;
use ExSite::Page;
use ExSite::Module;
use MIME::Base64;

use vars qw(@ISA);
@ISA = qw(ExSite::Page);

sub my_subtype { return "section"; }

sub setup {
    my ($this,%opt) = @_;
    $this->{type} = "content";
    if (exists $opt{id}) {
	if ($opt{id}) {
	    $this->{id} = $opt{id};
	}
	else {
	    # no id means setup the system root section
	    # we must preload in this case
	    my @data = $share{DB}->fetch_match("content",{type=>"section",parent=>0,name=>""},"content_id");
	    if (@data > 0) {
		$this->{data} = $data[0];
		$this->{id} = $data[0]{content_id};
	    }
	}
    }
    else {
	$this->{data} = $opt{data};
    }
    if ($this->{data} && ! $this->{id}) {
	$this->{id} = $this->{data}{content_id};
    }
    delete $this->{children};
    # flag whether we need to save data - assumes data is a clean record,
    # otherwise you should manually set the dirty flag
    $this->{dirty} = 0;
    # context
#    $this->set_context("none");
    $this->setup_querylib();
    return;
}

# get_host : return only the machine name part of the section URL

sub get_host {
    my $this = shift;
    my $url = $this->get_url;
    $url =~ /^https?:\/\/([^\/]*)/;
    return $1 if $1;
    my $host = $config{server}{host};
    $host .= $host ? "/".$config{server}{domain} : $config{server}{domain};
}

# get_server : return the scheme+authority part of the section URL

sub get_server {
    my $this = shift;
    my $url = $this->get_url;
    if ($url =~ /^(https?:\/\/[^\/]*)/) {
	return $1
    }
    return $config{server}{server};
}

sub service_page {
    my ($this,$module) = @_;
    return &ExSite::Module::service_page($module,$this);
}

sub get_url_same_as_base {
    my $this = shift;
    my $url = $this->getdata("url");
    if ($url) {
	# content has a fixed URL
	return $url;
    }
    elsif ($this->revision->view->getdata("format") eq "url") {
	# revision points to remote content
	return $this->revision()->get_url();
    }
    my $diskpath = $this->diskpath;
    my $httppath = $this->httppath;
    if (! $this->is_subdir) {
	my $file = $this->revision->filename;
	$diskpath .= "/$file";
	$httppath .= "/$file";
    }
    return -e $diskpath ? $httppath : $this->get_url_dynamic();
}

# root section has no parent, and no name
sub is_root {
    my $this = shift;
    if ($this->exists) {
	return (! ($this->getdata("parent") || $this->getdata("name")));
    }
    return undef;
}

# native sections are published under the system domain
sub is_native {
    my $this = shift;
    my $path = $this->content_path();
    my $s = $path->last;
    while ($s) {
	next if ($s->subtype ne "section");
	if ($s->getdata("url")) {
	    $path->reset;
	    return 0;
	}
	$s = $path->previous();
    }
    return 1;
}

# standalone sections are published under their own domain names
sub is_standalone {
    my $this = shift;
    return ! $this->is_native;
}

=pod

=head1 Content Management

=head2 get_all_pages()

Returns an array of page objects for all of the active pages in the
section.

=head2 get_mapped_pages()

Returns an C<ExSite::Tree> object containing all of the section's
pages organized into a site map.  The site map ignores the page
visibility attribute that determines whether to include the pages in
displayed site maps and menus, so code that constructs such menus
should consider the page's visibility when deciding whether to show
each page.

=head2 fetch_libraries()

Returns an array of library records (not objects) that are accessible
to the current section.  This includes libraries in the current
section, shared libraries in the the sectionpath, and public libraries
anywhere in the system.

=head2 get_services()

Returns an array of services running on this section.  A service is 
a special record connecting a section to a DCD (plug-in).  It is used
for authorizing access to restricted-access DCDs, and finding special
service pages that should be used to handle all requests to a DCD.

=head2 find_dcd()

Finds pages using a particular DCD (plug-in).

    my @pages = $section->find_dcd($module);

Returns an array of page records representing those pages that contain
a tag invoking the DCD C<$module> in the newest revision of their content.

=cut

sub get_page {
    my ($this,$name) = @_;
    if (!$name || $name eq $this->getdata("name")) {
	# the request page is the section itself
	return $this;
    }
    my $map = $this->get_mapped_pages();
    my $page_id = $this->id;
    # look for matching pages in child pages
    my %page = &keywise("name",scalar $map->get_child_data($page_id));
    if ($page{$name}) {
	my $p = new ExSite::Page(id=>$page{$name}{content_id});
	return $p;
    }
    # nothing; look in whole map
    %page = &keywise("name",scalar $map->collapse($this->id));
    if ($page{$name}) {
	my $p = new ExSite::Page(id=>$page{$name}{content_id});
	return $p;
    }
    my $p = new ExSite::Page();
    return $p;
}

# get all pages for the section
#
# options are:
# language => alternate language
#
# Note: we return all pages, regardless of visibility or status.

sub get_all_pages {
    my ($this,%opt) = @_;
    if ($this->defined) {
	my $tree = $this->get_page_tree();
	# get all page-like objects in this section
	my $id = $this->id;
	my @plist = ( $tree->getnode_data($id) );  # the collapsed array of pages
	my $itype_section = $this->isubtype("section");
	my @node = $tree->get_child_nodes($id);
	my $inode = 0;
	my %done;
	while ($inode < $#node) {
	    my $n = $node[$inode]{data};
	    $inode++;
	    next if ($n->{type} == $itype_section); # do not descend into subsections
	    next if ($done{$n->{content_id}});
	    $done{$n->{content_id}} = 1; # infinite loop trap, just in case
	    push @plist, $n;
	    push @node, $tree->get_child_nodes($n->{content_id});
	}
	return wantarray ? @plist : \@plist;
    }
}

# return all pages as a tree
# NB: NOT all pages in this section, but all pages in the system!
# Q: should we extract this section's subtree?

sub get_page_tree {
    my ($this,%opt) = @_;
    if (! $share{content}{pagetree}) {
	# use a different tree than content_tree, because we don't want
	# to have to instantiate every object to decide if it is page-like
	# and we don't want to have to to a DB query to know if it is hidden
# query now installed in Content::setup_querylib
#	if (! exists $share{querylib}{"page tree"}) {
#	    $share{DB}->set_query("page tree",
#				  sql=>"select c.content_id,c.parent,c.master,c.type,c.name,c.language,c.status,c.hide from content c,content_type t where c.type=t.content_type_id and t.navtype='page' order by $config{content}{tree_order}" ,
#				  nparam=>0,
#				  mode=>"r",
#				  keys=>"content");
#	}
	my @page = $share{DB}->get_query("page tree");
	$share{content}{pagetree} = new ExSite::Tree("content_id","parent",@page);
	$share{content}{pagetree}->set("name_key","name"); # for paths
    }
    return $share{content}{pagetree};
}

# get all pages for the section, organized into a map (ExSite::Tree)
#
# options are:
# language => alternate language
#
# Note: the map includes pages with reduced visibility.  Applications
# that honour page visibility (eg. menu builders) should test the 
# visibility attribute themselves.

sub get_mapped_pages {
    my ($this,$parent_id,$opt) = @_;
    if (! $this->{sitemap}) {
#	my $tree = $share{content}{pagetree};
	my $tree = $this->get_page_tree();
	# get all page-like objects in this section
	my @allpage = $tree->collapse($this->id);

	# make list of primary/master pages
	$this->load(); # make sure we have a datahash to add to the list
	my @pdata = ($this->get());
	foreach my $p (@allpage) {
	    push @pdata, $p if ($p->{master} == 0);
	}
	my $map = new ExSite::Tree("content_id","parent",@pdata);

	# do we need to consider alterate pages?
	my $lang = $opt->{language};
	if (! $lang && $parent_id) {
	    # no language explicitly specified, but we should check the language
	    # of the parent page, just to be sure
	    my $parent = $tree->get_parent_data($parent_id);
	    $lang = $parent->{language};
	}
    
	# overlay the alternate pages
	if ($lang) {
	    my @alt;
	    foreach my $d (@allpage) {
		if ($d->{master} && $d->{language} eq $lang) {
		    push @alt, $d;
		}
	    }
	    # clone the list, because we modify it in replacenode, 
	    # and don't want to modify the version in cache
	    my $clonedpages = &clone(\@alt);
	    foreach my $alt (@$clonedpages) {
		$map->replacenode($alt->{master},$alt);
	    }
	}
	$this->{sitemap} = $map;
    }
    return $this->{sitemap};
}

### UPDATE
sub get_mapped_subsections {
    my ($this,$opt) = @_;
    my @site = $this->fetch_all("section","section_id");

    # make a global Tree/map
    require ExSite::Tree;
    my $allmap = new ExSite::Tree("section_id","parent_id",@site);

    # extract the subtree corresponding to us
    my $submap = $allmap->subtree($this->get_my("section_id"));

    # drop ourselves from the subtree, so we only get our children
    $submap->splice($this->get_my("section_id"));

    return $submap;
}

# find all content of a type in the section

sub fetch_content {
    my ($this,$itype) = @_;
    my $tree = $this->get_content_tree();
    return $tree->find({type=>$itype},$this->id);
}

# fetch_libraries : fetches all libraries in the site path.

### FIXME: finds only libraries in this section; should be enhanced to
### include shareable libraries in ancestral sections
### FIXME: doesn't find albums

sub fetch_libraries {
    my $this = shift;
    return $this->fetch_content($this->isubtype("library"));
}

# get_services : fetches all web application services running on this site

sub get_services {
    my $this = shift;
    my @service = $share{DB}->fetch_child("service","content",$this->id);
    return wantarray ? @service : \@service;
}

# find_dcd : find all active oysters for a particular module

sub find_dcd {
    my ($this,$module) = @_;
    my $sid = $this->id();
    my @moddata;
    if ($sid && $module =~ /^\w+$/) {
    
	### WARNING: elaborate custom query - may be mysql-specific

	# We must search for all page-specific content (ie. not template 
	# content) that contains an oyster for the given module.
	#
	# Note: this query selects the "newest" revision, not the active 
	# revision.

	my $regexp = '<!--&+'.$module.'\\\(';
	@moddata = $share{DB}->get_query("oysters",$sid,$regexp);

#	my $query = "select page.*,content.content_id from page,content,content_data where page.page_id=content.page_id and content.content_id=content_data.content_id and page.section_id=$sid and content_data.mime_type=\"text/html\" and page.type=\"page\" and content_data.data rlike \"$regexp\" order by content_data.content_data_id desc;";
#	@moddata = $share{DB}->custom_query($query);
    }

    my (@page,%found);
    foreach my $dat (@moddata) {
	next if ($found{$dat->{content_id}});
	$found{$dat->{content_id}} = 1;
	delete $dat->{content_id};
	push @page, $dat;
    }
    return wantarray ? @page : \@page;
}

# sitemap tool
#
# DEPRECATED - use get_mapped_pages() instead

sub map {
    my ($this,$options,$pageoptions) = @_;
    my $out;
    my $db = $share{DB};
    my $ml = new ExSite::ML;
    my %match = (section_id=>$this->id,
		 type=>"page",
		 status=>"active",
		 parent_id=>0,);
    if (! $options->{show_hidden}) {
	$match{visibility} = "visible";
    }
    my @pages = $db->fetch_match("page",\%match,"rank");
    my $map;
    foreach my $page (@pages) {
	$map .= $this->map_r($page,$options,$pageoptions);
    }
    $out = $ml->p($ml->ul($map,{class=>"sitemap"}));
    if (! $options->{show_hidden} && $options->{footnote}) {
	$out .= $ml->p("NOTE: hidden pages do not appear in the site map.");
    }
    return $out;
}

sub map_r {
    my ($this,$page,$options,$pageoptions) = @_;
    # recursive mapping routine
    my $ml = new ExSite::ML;
    my $db = $share{DB};
    my $pid = $page->{page_id};
    my $url;

    if ($options->{link_to} eq "cms") {
	$url = &relink(path=>"/$page->{section_id}/$pid",cmscmd=>undef);
    }
    elsif ($options->{link_to} eq "dynamic") {
	my $query;
	if (ref $pageoptions eq "HASH") {
	    $pageoptions->{_id} = $pid;
	    $query = &EncodeHash(%$pageoptions);
	}
	else {
	    $query = "_id=$pid";
	}
	#$url = "$config{server}{CGIpath}/page.cgi?$query";
	$url = "$config{server}{CGIpath}/$config{prog}{page}?$query";
    }
    else {
	my $p = new ExSite::Page(page=>$page);
	$url = $p->get_url;
    }
    
    my $linkopt = { href=>$url };
    if ($options->{target}) { $linkopt->{target} = $options->{target}; }
    my $pageitem = $ml->a($page->{label} || "(no label)", $linkopt);

    my @attr;
    if ($options->{show_filename}) { 
	$pageitem .= " ($page->{filename})"; 
    }
    if ($page->{access} ne "public") { 
	push @attr, "RESTRICTED ACCESS"; 
    }
    if ($page->{visibility} eq "hidden") { 
	push @attr, "HIDDEN";
    }
    if (@attr > 0) {
	$pageitem .= " [".join(", ",@attr)."]";
    }
    my $out = $ml->li($pageitem);
    my $subpage = $db->fetch_match("page",{parent_id=>$pid,
					   type=>"page",
					   visibility=>"visible"},
				   "rank");
    if (@$subpage > 0) {
	my $submap;
	foreach my $page (@$subpage) { 
	    $submap .= $this->map_r($page,$options,$pageoptions); 
	}
	$out .= $ml->ul($submap, { class=>"sitemap" });
    }
    return $out;
}

### PUBLISHING
# use ExSite::Page::publish()

sub publish_content {
    my ($this,%opt) = @_;
    my $name = $this->getdata("name");
    if ($name) {
	# must set up the section directory first
	my $parent = $this->parent();
	my $base;
	if ($parent->defined) {
	    # this section publishes into the parent's directory
	    $base = $parent->diskpath();
	}
	else {
	    $base = $config{server}{HTMLroot}.$config{server}{HTMLpath};
	}
	my $df = new ExSite::Diskfile( base => $base, path => "/$name" );
	print $df->mkdir();

	### also hook up _ExSite, _Modules
    }
    
    # caching optimizations, since we're going to do a LOT of lookups

    my $publish_all;
    if (! exists $opt{child} || $opt{child}) {
	# looks like we're publishing everything
	# disable general local DB caching, to reduce memory usage
	$share{Cache}->off if $share{Cache};
	$publish_all = 1;
    }

    # make some specialized caches for faster full-site lookups
    # latest non-draft revision for all content
    foreach my $rev ($share{DB}->get_query("all revisions")) {
	$share{Cache_revision}{$rev->{content_id}} = $rev->{status} ? undef : $rev;
    }
    # include content with no revisions, to prevent dud lookups
    foreach my $rev ($share{DB}->get_query("content with no revisions")) {
	$share{Cache_revision}{$rev->{content_id}} = undef;
    }

    my $allmeta = $share{DB}->fetch_all("metadata");
    foreach my $meta (@$allmeta) {
	if (! exists $share{Cache_metadata}{$meta->{id}}) {
	    $share{Cache_metadata}{$meta->{id}} = [];
	}
	push @{$share{Cache_metadata}{$meta->{id}}}, $meta;
    }

    $this->SUPER::publish_content(%opt);

    if ($publish_all && $share{Cache} && tied %store) {
	# since we disabled caching, and we may have done some writes to the DB,
	# we should clear the global cache to force a reload of everything
	$this->info("clearing cache and rebuilding store");
	(tied %store)->clear_prefix("cache:"); # $share{Cache}{cache_name}
	# might as well rebuild the store now, since we have write permission
	# and we've already taken the hit of a big job
	(tied %store)->rebuild();
    }
}

# publish contents in specific order

sub subpublish {
    my ($this,%opt) = @_;
    my $clist = $this->get_contents_as_list();
    my %done;
    # publish templates first
    while (my $c = $clist->next) {
	if ($c->subtype eq "template") {
	    $c->publish_down(%opt);
	}
    }
    # publish libraries second
    $clist->reset;
    while (my $c = $clist->next) {
	if ($c && $c->subtype eq "library") {
	    $c->publish_down(%opt);
	}
    }
    # publish everything else
    $clist->reset;
    while (my $c = $clist->next) {
	if ($c->subtype !~ /^template|library$/) {
	    $c->publish_down(%opt);
	    $done{$c->id} = 1;
	}
    }
#    $clist->setlist();
#    # also publish any deeper page objects
#    foreach my $pdata ($this->get_all_pages()) {
#	next if ($pdata->{content_id} == $this->id);
#	if (! $done{$pdata->{content_id}}) {
#	    my $p = $this->get_content_obj($pdata);
#	    $p->publish_content(%opt);
#	    $done{$p->id} = 1;
#	}
#    }
}

### get_contents puts a high memory load on the system
sub subpublish_old {
    my ($this,%opt) = @_;
    my @contents = $this->get_contents();
    my %done;
    # publish templates first
    foreach my $c (@contents) {
	if ($c->subtype eq "template") {
	    $c->publish_down(%opt);
#	    $done{$c->id} = 1;
	    undef $c;
	}
    }
    # publish libraries second
    foreach my $c (@contents) {
	if ($c && $c->subtype eq "library") {
	    $c->publish_down(%opt);
#	    $done{$c->id} = 1;
	    undef $c;
	}
    }
    # publish everything else
    foreach my $c (@contents) {
	if ($c) { # && $c->subtype !~ /^(template|library)$/) {
	    $c->publish_down(%opt);
	    $done{$c->id} = 1;
	    undef $c;
	}
    }
    delete $this->{contents};
    # also publish any deeper page objects
    foreach my $pdata ($this->get_all_pages()) {
	next if ($pdata->{content_id} == $this->id);
	if (! $done{$pdata->{content_id}}) {
	    my $p = $this->get_content_obj($pdata);
	    $p->publish_content(%opt);
	    $done{$p->id} = 1;
	}
    }
}

# remove the published section files from disk

sub unpublish {
    my ($this) = @_;
    if ($this->defined) {
	# remove subsections
	foreach my $sec ($this->get_contents("section")) {
	    $sec->unpublish();
	}
	# remove ourself
	$this->SUPER::unpublish();
	# remove plugin content
	foreach my $serv ($this->get_services()) {
	    my $mod = &ExSite::Module::get_module($serv->{name},1,$this);
	    if ($mod) { 
		my $publisher = $mod->ioctl("Unpublish");
		if (ref $publisher eq "CODE") {
		    $mod->info("Unpublishing Module $mod");
		    print eval { $mod->$publisher } || $this->error($@);
		}
	    }
	}
    }
    return;
}

sub can_index {
    my $this = shift;
    return undef if (! $this->is_active());
    return 0 if (! $this->allow("publish")); # perm denied
    return (! $this->hide_from("search"));
}

sub search_index {
    my ($this,$search) = @_;
    return undef if (! $this->can_index());

    # preload a search index summary so we can detect stale entries better
    my @counts = $share{DB}->get_query("searchterm counts");
    $share{searchterm_counts} = scalar &keywise("content_id",\@counts);

    # index home page
    my $out .= $this->SUPER::search_index($search);

    # index all section content
    foreach my $cdata ($this->get_descendants()) {
	next if ($cdata->{content_id} == $this->id); # already done
	my $c = $this->get_content_obj($cdata);
	$out .= $c->search_index($search);
    }

    # index plugins
    foreach my $service ($this->get_services) {
	if ($service->{page_id}) {
	    my $p = new ExSite::Page(id=>$service->{page_id});
	    my $modname = $service->{name};
	    my $dcd = &get_module($modname,0,$this->id);
	    if ($dcd) {
		$out .= $search->index_plugin($dcd,$this,$p);
	    }
	}
    }

    $search->add_section($this->id());
    return $out;
}

1;
