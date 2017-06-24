#!/usr/bin/perl
#-----------------------------------------------------------------------
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

### TODO
# clean up get_url functions
# clean up _old functions 
# clean up deprecated functions

package ExSite::Content;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Util;
use ExSite::Tree;
use ExSite::Date;
use ExSite::ObjectMeta;
use ExSite::Workflow;
use ExSite::Revision;
use ExSite::Module qw(&get_module &launcher_link);
use ExSite::Metadata;
use ExSite::RSS;
use MIME::Base64;
#use Devel::Size qw(size total_size);

use vars qw(@ISA %publish_priority);
@ISA = qw(ExSite::ObjectMeta ExSite::Workflow);

%publish_priority = ( dynamic=>1, hourly=>2, daily=>3, weekly=>4, static=>5, never=>6 );

sub my_type { return "content"; }

sub name {
    my $this = shift;
    if ($this->exists) {
	return $this->getdata("name") || $this->getdata("label") || $this->getdata("title");
    }
    return "n/a";
}

sub title {
    my $this = shift;
    if ($this->exists) {
	return $this->getdata("title") || $this->dcmeta("title") || $this->getdata("label") || $this->getdata("name");
    }
    return "n/a";
}

sub label {
    my $this = shift;
    if ($this->exists) {
	return $this->getdata("label") || $this->getdata("name") || $this->getdata("title");
    }
    return "n/a";
}

sub setup {
    my ($this,%opt) = @_;
    my $save = 0;

    if (! $opt{id} && ! $opt{data}) {
	if ($opt{name} && $opt{parent}) {
	    my %match = ( parent=>$opt{parent}, name=>$opt{name} );
	    my $subtype = $this->my_subtype;
	    if ($subtype) { $match{type} = $subtype; }
	    my @cnode = $share{DB}->fetch_match("content",\%match,"content_id");
	    # should be only 1, but in case there are more, we'll take the
	    # most recently added one
	    if (scalar @cnode > 0) { $opt{data} = $cnode[-1]; }
	}
	elsif ($opt{path}) {
	    # hmm, no specific object requested, search for object using path
	    my $path;
	    my $in;
	    if ($opt{path} == 1) {
		# use PATH_INFO
		$in = new ExSite::Input();
		$path = $in->path();
	    }
	    else {
		$path = $opt{path};
	    }
	    my @path = $this->path_to_content($path);
	    if (@path > 0) {
		# found something - setup using this datahash
		$opt{data} = $path[-1];
		if ($opt{path} == 1) {
		    # note that we used this part of the PATH_INFO
		    $in->new_path("content", map { $_->{name} } @path );
		    $save = 1;
		}
	    }
	}
    }
    if (exists $opt{data} && $this->subtype($opt{data}{type}) eq "alias") {
	# just a pointer to the real cnode
	$opt{id} = $opt{data}{master};
	$this->{alias} = $opt{data}; # keep track that we're an alias
	delete $opt{data};
    }
    $this->SUPER::setup(%opt);

    if (! $this->{data} && $this->{id} && $share{content}{tree}) {
	# No content data, but we've preloaded the whole tree. 
	# See if we can find some of the content's data in the tree, 
	# and save ourselves an unnecessary DB query later.
	my $data = $this->get_content_tree()->getnode_data($this->{id});
	$this->{data} = $data if ($data);
    }

    $this->{Revision} = undef;
    $this->set_view($opt{view} || "normal");
    $share{Content} = $this if $save;
    $this->setup_querylib();
    return;
}

# get_content_obj: return a content object of the appropriate subclass
# You can pass an ID or datahash, or even use $this. This code determines
# the appropriate type and datahash to use.

sub get_content_obj {
    my ($this,$cnode) = @_;
    my $type;
    if ($cnode && (ref $cnode) ne "HASH") {
	# cnode is an ID
	if ($cnode != $this->id) {
	    # different from current object
	    $cnode = $this->fetch($cnode);
	    $type = $this->subtype($cnode->{type});
	}
	# get ourself
	elsif ($this->my_type ne $this->subtype()) {
	    # wrong class
	    $cnode = $this->{data} ? $this->{data} : $this->fetch($cnode);
	    $type = $this->subtype();
	}
	else {
	    # nothing to do
	    return $this;
	}
    }
    elsif (ref $cnode eq "HASH") {
	$type = $this->subtype($cnode->{type});
    }
    elsif (! defined $cnode && $this->{data}) {
	# get ourself using data
	$cnode = $this->{data};
	$type = $this->subtype();
    }
    elsif (! defined $cnode && $this->id) {
	# get ourself using id
	$cnode = $this->fetch($this->id);
	$type = $this->subtype($cnode->{type});
    }
    else {
	# doesn't appear to be any object to get
	return new ExSite::Content(); # dummy
    }
    # $cnode should now be a whole or partial datahash
    return $this->make_content_obj($type,data=>$cnode);
}

# make_content_obj: given a type and datahash, instantiate an
# object of the appropriate class.

sub make_content_obj {
    my ($this,$type,%opt) = @_;
    $type = $this->subtype($type) if ($type =~ /^\d+$/);
    if ($type eq "alias") {
	my $cdata = $this->fetch($opt{data}{master});
	$opt{data} = $cdata;
	$type = $this->subtype($cdata->{type});
    }
    my $class = $share{content}{subtype}{$type}{class} || "ExSite::Content";
    $class =~ /^((ExSite|Modules)::(\w+::)?\w+)$/;
    my $safeclass = $1;
    if ($safeclass) {
	if (eval "require $safeclass") {
	    my $obj = eval "new $safeclass(%opt)";
	    if ($obj) {
		return $obj;
	    }
	}
    }
    else {
	$this->error("Invalid content class: $class");
    }
    if ($@) {
	$this->error($@);
    }
    return new ExSite::Content(%opt);
}

sub load {
    my ($this,$data) = @_;
    if ($this->SUPER::load($data)) {
	if ($this->subtype($this->{data}{type}) eq "alias") {
	    # just a pointer to the real cnode
	    $this->{id} = $this->{data}{master};
	    $this->{alias} = $this->{data}; # keep track that we're an alias
	    delete $this->{data};
	    $this->SUPER::load();
	}
	if ((ref $this->{data}) eq "HASH") {
	    if (! $this->validate_subtype) {
		# ERROR: subtype mismatch - we setup a different CNode
		# than our module class expects
		$this->{status} = "subtype mismatch: ".$this->subtype()." trying to be a ".$this->my_subtype;
		delete $this->{id};
		delete $this->{data};
		return undef;
	    }
	}
	return $this->{data};
    }
    return $this->{data};
}

sub unload {
    my $this = shift;
    my @unload = qw(Revision revision revid view meta flags content_path path
                    contents html expanded noexpand htmlsub expand_redo done
                    dcd URI publish allowed_prices redirect http_header errorpage);
    foreach my $attr (@unload) {
	delete $this->{$attr};
    }
    $this->SUPER::unload();
}

sub getdata {
    my ($this,$key) = @_;
    if (defined $this->{data}) {
	if (exists $this->{data}{$key}) {
	    # sometimes we have the desired column from the tree
	    # without needing to load it from the DB
	    return $this->{data}{$key};
	}
    }
    return $this->SUPER::getdata($key);
}

sub loaded {
    my $this = shift;
    # content_id,parent,master,type,name,language may be partially loaded
    if ($this->ok) {
	if (exists $this->{data}{mtime}) {
	    # ctime is not preloaded, so if it exists, we can assume we 
	    # have loaded the whole record
	    return 1;
	}
	else {
	    return 1 if ($this->id && $this->load());
	}
    }
    return undef;
}

sub validate_subtype {
    my $this = shift;
    my $subtype = $this->my_subtype;
    return (! $subtype ||                  # no subtype match required
	    $subtype eq $this->subtype()); # subtype matches
}

sub validate {
    my $this = shift;
    my @err;

    # name should be URL-friendly
    my $name = $this->getdata("name");
    if ($name) {
	if ($name !~ /^[\w\-\.]+$/) {
	    push @err, "name should consist of URL-friendly characters only, with no spaces";
	}
    }
    elsif ($this->getdata("parent")) {
	push @err, "unnamed content can only exist at the top level";
    }

    # name should be unique
    my @match = $share{DB}->fetch_match("content",{name=>$name,
						   parent=>$this->getdata("parent")});
    foreach my $m (@match) {
	if ($m->{content_id} != $this->id) {
	    push @err, "name '".&html_escape($name)."' already in use here";
	    last;
	}
    }

    # validate type nesting
    my $parent = $this->parent;
    if ($parent->id) {
	my $type = $this->isubtype();
	my $ptype = $parent->isubtype();
	my @re = $share{DB}->fetch_match("content_rel",{type=>$type,under=>$ptype});
	if (@re == 0) {
	    # no relation records!
	    push @err, $this->subtype."s cannot be placed under a ".$parent->subtype;
	}
    }

    push @err, $this->SUPER::validate();
    return @err;
}

sub set_view {
    my ($this,$view) = @_;
    $this->{view} = $view;
    if ($this->{Revision}) {
	# reload revision
	delete $this->{Revision};
	$this->revision();
    }
}

sub parent {
    my $this = shift;
    return $this->get_content_obj($this->getdata("parent"));
}

sub template {
    my $this = shift;
    my $tid = $this->getdata("template");
    if (! $tid) {
	# hm, we don't have a template; 
	# pick template of nearest templated ancestor
	my $path = $this->content_path();
	my $prev = $path->last;
	while (! $tid && $prev) {
	    $tid = $prev->getdata("template");
	    $prev = $path->previous;
	}
    }
    return $this->get_content_obj($tid);
}

sub master {
    my $this = shift;
    return $this->get_content_obj($this->getdata("master"));
}

sub has_content {
    my $this = shift;
    return $this->revision->view->defined;
}

# is_page : should this node be treated as primary navigation?

sub is_page { 
    my $this = shift; 
    return $this->navtype eq "page"; 
}

# is_static : does this content publish to a static file?
# not the same as is_publishable()!
sub is_static {
    my $this = shift;
    my $access = $this->access();
    return (!$access && ($this->publish_rule !~ /never|dynamic/));
}

sub is_public { 
    my $this = shift;
    return $this->is_active() && $this->getdata("access")==0;
}

sub alias {
    my $this = shift;
    if ($this->{alias}) {
	return $this->{alias}{content_id};
    }
    return undef;
}

sub is_subdir {
    my $this = shift;
    if ($this->defined) {
	$this->get_subtypes();
	my $isubtype = $this->getdata("type");
	if ($isubtype) {
	    my $publish_as = $share{content}{isubtype}{$isubtype}{publish_as};
	    return $publish_as eq "directory";
	}
    }
    return undef;
}

# url_is_me: true if this content object is the content targeted by the URL 
sub url_is_me {
    my ($this,$c) = @_;
    $c or $c = $share{Content};
    return ($c && $c->id == $this->id);
}

# navtype:
# page => primary navigation point, answers to my_page
# item => secondary navigation point, shown in indexes
# none => not shown in navigation

sub navtype {
    my $this = shift;
    return $this->subtype_attr("navtype");
}

# displaytype:
# raw => content is displayed in its raw mimetype
# formatted => content is displayed with HTML formatting
# none => content is not displayed

sub displaytype {
    my $this = shift;
    return $this->subtype_attr("displaytype");
}

sub content_role {
    my $this = shift;
    my $role = $this->getdata("content_role");
    if (! $role) {
	$role = $this->subtype_attr("role") || "editorial";
    }
    return $role;
}

# langauge

sub language {
    my $this = shift;
    my $lang = $this->getdata("language");
    if (! $lang) {
	# language is inherited from page, if not explicitly defined
	$lang = $this->my_page()->getdata("language");
    }
    return $lang;
}

# === SUBTYPES

# my_subtype - the subtype of this object/class

sub my_subtype { return undef; }

# get_subtypes - load subtypes for quick reference

sub get_subtypes {
    my $this = shift;
    if (! exists $share{content}{subtype}) {
	my @subtype = $share{DB}->fetch_all("content_type");
	$share{content}{subtype} = &keywise("name",\@subtype);
	$share{content}{isubtype} = &keywise("content_type_id",\@subtype);
    }
}

# subtype - converts numeric subtypes to text names

sub subtype {
    my ($this,$isubtype) = @_;
    $isubtype or $isubtype = $this->getdata("type");
    $this->get_subtypes;
    return $share{content}{isubtype}{$isubtype}{name};
}

# isubtype - converts text subtypes to numeric indexes

sub isubtype {
    my ($this,$subtype) = @_;
    return $this->getdata("type") if (! $subtype);
    $this->get_subtypes;
    return $share{content}{subtype}{$subtype}{content_type_id};
}

sub subtype_attr {
    my ($this,$attr,$isubtype) = @_;
    $this->get_subtypes;
    $isubtype or $isubtype = $this->getdata("type");
    return $share{content}{isubtype}{$isubtype}{$attr}
}

#=== METADATA

# metadata object
sub meta {
    my $this = shift;
    if (! $this->{meta}) { # && $this->defined) {
	$this->{meta} = new ExSite::Metadata($this->{id});
    }
    return $this->{meta};
}

# get_metadata: fetch content record + metadata, merged into one hash
# This is so that things like title, lable, name are included in the
# metadata, regardless of whether they are defined formally as metadata.

sub get_metadata {
    my $this = shift;
    if ($this->loaded()) {
	my %meta = ( %{$this->{data}}, $this->meta->get_all );
	return wantarray ? %meta : \%meta;
    }
    return undef;
}

# set_metadata does a temporary set (not saved to database).
# Use this to temporarily change titles, for instance.
# Use $this->meta->set() to permanently change the setting.
 
#### redundant - use meta_set()
sub set_metadata {
    my ($this,$name,$value) = @_;
    $this->meta->set_nosave($name,$value);
}

# editmeta: edit record and its metadata

sub editmeta { 
    my ($this,%opt) = @_;
    if ($this->ok) {
	$this->load();
	$this->meta()->load();
	$this->DB()->set_action($this->action());  # insert/update
	$this->DB()->form(%opt);
	$opt{show} or $opt{show} = $this->editmeta_fields;
	$this->DB()->input_record({table=>$this->{type},
				   record=>$this->{id},
				   hide=>$opt{hide},
				   show=>$opt{show},
				   data=>$this->get(),
				   simplename=>1,
				  });

	my @metafields = $this->meta()->get_allowed();
	if (@metafields == 0) {
	    my %meta = $this->meta()->get_all();
	    @metafields = keys %meta;
	}
	my $subtype = $this->subtype();
	foreach my $key ($this->meta->get_allowed_sorted()) { #sort @metafields) {
	    next if ($key =~ /^DC./);  # skip dublin core 
	    my $writeaccess = $this->meta->get_map_info($key,"write");
	    next if ($writeaccess && $writeaccess > $share{DB}->level());
	    # this metadata is specific to this content type
	    $this->meta()->input("_meta_".$key,$key);
	}

	my $flags = $config{content}{flags}{$subtype};
	if (ref $flags eq "ARRAY") {
	    my $form = $this->DB()->form();
	    my %flagset = $this->flags();
	    foreach my $flag (@$flags) {
		my $flagname = &safetext($flag);
		$form->input(type=>"checkbox",name=>"_flag_$flagname",prompt=>$flag,checked=>$flagset{$flag});
	    }
	}

	my $template = $this->editmeta_template();
	$this->DB()->form()->template($template) if ($template);

	return $this->DB()->form()->make;
    }
    return $this->show_diagnostics("error","html");
}

sub do_editmeta { 
    my $this = shift; 
    if ($this->allow("edit")) {
	my $errcnt = &AtError();
	my $input = new ExSite::Input();
	my $post = $input->post();
	if (keys %$post > 0) {
	    my $metamap = $config{content}{metadata}{$this->subtype()};
	    my %in = $share{DB}->parse_parts(%$post);
	    my %oldflag = $this->flags();
	    my %flag;
	    while (my ($key,$val) = each %in) {
		if ($key =~ /^_meta_/) {
		    my $metakey = $key;
		    $metakey =~ s/^_meta_//;
		    if (exists $metamap->{$metakey}) {
			my $writeaccess = $metamap->{$metakey}{write};
			next if ($writeaccess && $writeaccess > $share{DB}->level());
		    }
		    $this->meta_set($metakey,$val);
		}
		elsif ($key =~ /^_flag_/) {
		    my $flagkey = $key;
		    $flagkey =~ s/^_flag_//;
		    $flag{&unsafetext($flagkey)} = 1;
		}
		elsif ($key !~ /^_flag_/) {
		    $this->setdata($key,$val);
		}
	    }
	    # save object and metadata
	    $this->save();
	    # save flags
	    # turn off flags
	    foreach my $flag (keys %oldflag) {
		if (! $flag{$flag}) {
		    $this->unset_flag($flag);
		}
	    }
	    # turn on flags
	    foreach my $flag (keys %flag) {
		if (! $oldflag{$flag}) {
		    $this->set_flag($flag);
		}
	    }
	    if (&AtError($errcnt)) {
		# new errors have happened
		return &ExSite::Config::show_diagnostics();
	    }
	    else {
		my $type = $this->subtype();
		return $this->info(ucfirst($type)." reconfigured.");
	    }
	}
    }
    else {
	return $this->error("Configure ".$this->label.": permission denied");
    }
    return undef;
}

# editmeta - form used for configuring content objects

sub editmeta_template { 
    my ($this,%opt) = @_;
    # only need to template the form if there are flags
    my $subtype = $this->subtype();
    return undef if (! exists $config{content}{flags}{$subtype});
    my $ml = &get_obj("ML");
    my $br = $ml->br;

    # 1) standard content fields
    my $template;
    $opt{show} or $opt{show} = $this->editmeta_fields;
    foreach my $fld (@{$opt{show}}) {
	$template .= $ml->p("[[$fld:prompt]]${br}[[$fld:input]]");
    }

    # 2) metadata fields
    my @metafields = $this->meta()->get_allowed();
    if (@metafields == 0) {
	my %meta = $this->meta()->get_all();
	@metafields = keys %meta;
    }
    foreach my $key (sort @metafields) {
	if ($config{content}{metadata}{$subtype}{$key}) {
	    my $fld = "_meta_".$key;
	    $template .= $ml->p("[[$fld:prompt]]${br}[[$fld:input]]");
	}
    }

    # 3) flags - reformat to be input, prompt 
    my $flags = $config{content}{flags}{$subtype};
    if (ref $flags eq "ARRAY") {
	my $flagout;
	foreach my $flag (@$flags) {
	    my $flagname = "_flag_" . &safetext($flag);
	    $flagout .= "[[$flagname:input]] [[$flagname:prompt]]$br";
	}
	$template .= $ml->p($flagout) if $flagout;
    }

    return $template;
}

sub editmeta_fields {
    my $this = shift;
    return ["title","label","name","publish","access","hide","language","status"];
}

sub makemeta {
    my ($this,%opt) = @_;
    my $parent = $opt{parent} || $this->id;
    $this->DB()->set_action("insert");
    $this->DB()->form(%opt);
    $opt{show} or $opt{show} = $this->editmeta_fields;
    $this->DB()->input_record({table=>$this->{type},
			       hide=>$opt{hide},
			       show=>$opt{show},
			       data=>$opt{data},
			       simplename=>1,
			      });
    my @metafields = $this->meta()->get_allowed();
    if (@metafields == 0) {
	my %meta = $this->meta()->get_all();
	@metafields = keys %meta;
    }
    my $subtype = $this->subtype();
    foreach my $key (sort @metafields) {
	if ($config{content}{metadata}{$subtype}{$key}) {
	    my $writeaccess = $config{content}{metadata}{$subtype}{$key}{write};
	    next if ($writeaccess && $writeaccess > $share{DB}->level());
	    # this metadata is specific to this content type
	    $this->meta()->input("_meta_".$key,$key);
	}
    }

    my $flags = $config{content}{flags}{$subtype};
    if (ref $flags eq "ARRAY") {
	my $form = $this->DB()->form();
	my %flagset = $this->flags();
	foreach my $flag (@$flags) {
	    my $flagname = &safetext($flag);
	    $form->input(type=>"checkbox",name=>"_flag_$flagname",prompt=>$flag,checked=>$flagset{$flag});
	}
    }

    my $template = $this->editmeta_template();
    $this->DB()->form()->template($template) if ($template);

    return $this->DB()->form()->make;
}

sub do_makemeta {


}

# standard metadata requests

# dcmeta("name") returns a metadata value for "name"
# Preference is given to Dublin Core metadata, "DC.Name", then just 
# "Name", and finally "name". The 15 standard DC metadata names are:
# DC.Title
# DC.Creator
# DC.Subject
# DC.Description
# DC.Publisher
# DC.Contributor
# DC.Date
# DC.Type
# DC.Format
# DC.Identifier
# DC.Source
# DC.Language
# DC.Relation
# DC.Coverage
# DC.Rights
# Thus, dcmeta("title") looks for metadata named "DC.Title", 
# "Title", and "title", in that order.

sub dcmeta {
    my ($this,$metaname) = @_;
    my %meta = $this->meta->get_all;
    my $ucmeta = ucfirst $metaname;
    my $dcmeta = "DC.$ucmeta";
    return $meta{$dcmeta} || $meta{$ucmeta} || $meta{$metaname};
}

sub author { my $this = shift; return $this->dcmeta("author") || $this->dcmeta("creator"); }

sub description { 
    my $this = shift; 
    my $out = $this->dcmeta("description");
    if (! $out) {
	# see if there is an abstract
	$out = $this->meta->get("abstract");
	if (! $out) {
	    # pick best content object to extract a teaser from
#	    my $c = $this->subtype_attr("revtype") eq "template" ?
	    my $c = $this->displaytype eq "template" ?
		$this->my_content("body") :  # for page-like objects, use body
		$this;                       # otherwise, use ourself
	    if ($c && $c->has_content && $c->revision()->is_text) {
		my $html = $c->revision()->view()->get_html();
		$out = &make_teaser_text($html);
	    }
	    elsif ($this->revision->is_file) {
		$out = $this->caption() || $this->content_info;
	    }
	}
    }
    return $out;
}

# keywords: metadata consisting of a list of keywords that describe the content
# can be explictly defined using the keywords metadata, or implicitly by looking
# up any keyword tags

sub keywords { 
    my $this = shift; 
    my $out = $this->meta->get("keywords");
    if (! $out && $config{content}{keywords_from_tags}) {
	# see if we can invent a set of keywords from index tags
	# fixme? use tagged_keywords below
	my $ikw = $this->isubtype("keyword");
	my $iin = $this->isubtype("index");
	my $ial = $this->isubtype("alias");
	return undef if (! $ikw || ! $iin || ! $ial); # not supported
	$out = join ",",$share{DB}->get_query("names of keyword tags",$iin,$ikw,$ial,$this->id);
    }
    return $out;
}

# tags : return a list of keyword objects that are linked to this content

sub tags { 
    my $this = shift; 
    my $ikw = $this->isubtype("keyword");
    my $iin = $this->isubtype("index");
    my $ial = $this->isubtype("alias");
    return undef if (! $ikw || ! $iin || ! $ial); # not supported
    my @kw = $share{DB}->get_query("keyword tags",$iin,$ikw,$ial,$this->id);
    my $tags = new ExSite::ObjectList(type=>"content",list=>\@kw);
    return $tags;
}

sub show_tags {
    my $this = shift;
    my $ml = &get_obj("ML");
    my $tags = $this->tags();
    if ($tags->count > 0) {
	my @tag;
	while (my $t = $tags->next) {
	    push @tag, $ml->a($t->label,{href=>$t->get_url(),class=>"tagLink"});
	}
	return $ml->div($msg{"Tagged as:"}." ".join(", ",@tag),{class=>"Tags"});
    }
    return undef;
}

# see top for title()

# caption: returns a suitable caption for a piece of content
# if $force is false/undef, may return blank if there is no good caption;
# if $force is true, it will always return something, even just a filename
sub caption {
    my ($this,$force) = @_; # set force=1 to get a caption even if none is defined
    my $caption = $this->dcmeta("caption") || $this->dcmeta("description") || $this->dcmeta("subject");
    if (! $caption && $force) {
	$caption = $this->title();
    }
    return $caption;
}

# descriptive info about the content

sub content_info { 
    my $this = shift;
    return $this->revision->description;
}

sub height {
    my $this = shift;
    my @dim = $this->revision->view->dim();
    return $dim[1];
}

sub width {
    my $this = shift;
    my @dim = $this->revision->view->dim();
    return $dim[0];
}

sub dim {
    my $this = shift;
    return $this->revision->view->dim();
}

#=== FLAGS
# Flags are metadata-like booleans; rather than name/value pairs, they are
# simply names. If the flag exists, the boolean value is true, otherwise
# it is false.

# flag: test a particular flag value 
sub flag {
    my ($this,$flag) = @_;
    my $flags = $this->flags();
    return $flags->{$flag};
}

# flags: return all set flags for this content
sub flags {
    my ($this,$reload) = @_;
    if ($reload || ! $share{content}{flags}) {
	my %flag;
	my @flag = $share{DB}->fetch_all("content_flag");
	foreach my $flag (@flag) {
	    $flag{$flag->{content_id}}{$flag->{flag}} = 1;
	}
	$share{content}{flags} = \%flag;
    }
    if ($reload || ! $this->{flags}) {
	$this->{flags} = $share{content}{flags}{$this->id} || {};
    }
    return wantarray ? %{$this->{flags}} : $this->{flags};
}

# set_flag: turn on a flag

##### permission check: can a non-admin set flags?

sub set_flag {
    my ($this,$flag) = @_;
    my $flags = $this->flags();
    if (! $flags->{$flag}) {
	if ($this->allow_flag($flag)) {
	    my $id = $this->id;
	    $share{DB}->insert("content_flag",{content_id=>$id,
					       flag=>$flag});
	    $share{content}{flags}{$id}{$flag} = 1;
	}
    }
}

# unset_flag: turn off a flag
sub unset_flag {
    my ($this,$flag) = @_;
    my $flags = $this->flags();
    if ($flags->{$flag}) {
	if ($this->allow_flag($flag)) {
	    my $id = $this->id;
	    my @flag = $share{DB}->fetch_match("content_flag",{content_id=>$id,
							       flag=>$flag});
	    foreach my $fl (@flag) {
		$share{DB}->trash_key("content_flag",$fl->{content_flag_id});
	    }
	    $share{content}{flags}{$id}{$flag} = 0;
	}
    }
}

# allow_flag: can the user change the flag setting?
sub allow_flag {
    my ($this,$flag) = @_;
    if (exists $config{flags}{$this->subtype()}) {
	# if this is a recognized flag, any user with a key/role can 
	# set the flag
	return 
	    $share{DB}->has_role($share{DB}->my_uid) ||  
	    $share{DB}->is_admin();
    }
    # unknown flag type - level 8 admins can force other flags into the DB
    return $share{DB}->is_admin();
}

#=== LIKES
# Likes are tags that join users to content; they have a numeric value,
# which is understood as a strength of the join. +ve values mean the user
# likes the content; -ve values mean they dislike it. The overall 
# popularity of the content is calculated by summing the likes.

sub popularity {
    my ($this) = @_;
    if ($this->ok) {
	my @pop = $share{DB}->get_query("popular content");
	my $rank = 0;
	my $id = $this->id;
	foreach my $p (@pop) {
	    $rank++;
	    if ($p->{content_id} == $id) {
		if (wantarray) {
		    return ( 
			rank=>$rank, 
			total=>(scalar @pop),
			popularity => $p->{popularity},
			);
		    # todo: bin the likes into 5 bins -> star rating
		}
		else {
		    return $p->{popularity};
		}
	    }
	}
    }
    return undef;
}

# like: record approval (or disapproval) of this content
# options:
# weight = (default 1) increase for greater significance, set to -ve for dislikes
# uid = likes are logged against this uid
# account = likes are logged against this account_id (for non-users)

sub like {
    my ($this,%opt) = @_;
    if ($this->ok) {
	my $status = $this->run_handler("content_like",%opt);
	return $status if (defined $status);
	my $db = $share{DB};
	my $uid = $opt{uid} || $db->my_uid;
	if ($uid || $opt{account}) {
	    my $weight = $opt{weight} || 1;
	    my @like = $uid ?
		$db->fetch_match("content_like",{uid=>$uid}) :
		$db->fetch_match("content_like",{account=>$opt{account}});
	    my %like = &keywise("content_id",\@like);
	    my $id = $this->id;
	    if (exists $like{$id}) {
		if ($like{$id}{value} == -$weight) {
		    # cancel previous like
		    $share{DB}->trash_key("content_like",$like{$id}{content_like_id});
		    return 0;
		}
		elsif ($like{$id}{value} != $weight) {
		    # update like
		    $like{$id}{value} = $weight;
		    $share{DB}->update("content_like",$like{$id});
		    return $weight;
		}
		# else: ignore - cannot vote twice
		return undef;
	    }
	    else {
		$share{DB}->insert("content_like",{content_id=>$this->id,uid=>$uid,value=>$weight});
		return $weight;
	    }
	}
    }
    return undef; # nothing done
}

#=== Settings
# Settings are configuration parameters that can be set for either specific
# content items, or general subtypes. Settings can be specified in these 
# formats:
#
# 1) general, eg. setting.subtype.parameter
# 3) specific, eg. setting.subtype:ID.parameter
# 2) semi-specific, eg. setting.subtype:name.parameter
#
# We look for settings in the following places, taking the first one we find:
#
# 1) specific setting in %config
# 2) semi-specific setting in %config
# 3) general setting on the content object itself, in preferences
# 4) general setting on the section, in preferences
# 5) general setting in %config

sub setting {
    my ($this,$param) = @_;
    my $type = $this->subtype();
    my $name = $this->name;
    my $id = $this->id;
    if (exists $config{setting}{"$type:$id"}{$param}) {
	return $config{setting}{"$type:$id"}{$param};
    }
    elsif (exists $config{setting}{"$type:$name"}{$param}) {
	return $config{setting}{"$type:$name"}{$param};
    }
    my $setting = &preference("setting.$type.$param","content",$this->id);
    return $setting if (defined $setting);
    $setting = &preference("setting.$type.$param");
    return $setting if (defined $setting);
    return $config{setting}{$type}{$param};
}

#=== DATES

sub date {
    my $this = shift;
    my $time = $this->getdata("ctime");
    if (! $time || $time =~ /^0/) {
	$time = $this->getdata("mtime");
	if (! $time || $time =~ /^0/) {
	    $time = $this->getdata("ptime");
	    if (! $time || $time =~ /^0/) {
		$time = $this->getdata("ptime");
	    }
	}
    }
    my $date = new ExSite::Time($time,"sql_timestamp");
    return $date->write("date");
}

sub posting_date {
    my $this = shift;
    my $t = new ExSite::Time($this->getdata("ctime"),"sql_timestamp");
    ### FIXME: configurable dates, eg. mtime, configurable formats
    return $t->write("date");
}

# return content age, in days

sub age {
    my $this = shift;
    my $today = new ExSite::Time($this->getdata("ctime"),"sql_timestamp");
    my $age_s = $today->diff(); # diff to today
    my $age = int($age_s / 86400);
    return $age;
}

# last_update: last time content went live

sub last_update {
    my $this = shift;
    my $ptime = $this->revision->getdata("ptime");
    foreach my $c ($this->get_contents()) {
	my $ptime2 = $c->last_update();
	if ($ptime2 cmp $ptime > 0) { $ptime = $ptime2; }
    }
    return $ptime;
}

# last_modified: last time content was changed

sub last_modified {
    my $this = shift;
    my $ctime = $this->revision->getdata("ctime");
    foreach my $c ($this->get_contents()) {
	my $ctime2 = $c->last_modified();
	if ($ctime2 cmp $ctime > 0) { $ctime = $ctime2; }
    }
    return $ctime;
}

#===========================================================================
# date service - allows user to tag content with dates other than timestamps
# Dates are used by calendars, cron, logging functions.
# They should instantiate as ExSite::Date objects, which allow for other
# formatting/display functions.
# dates have a type, which allows them to support numerous functions:
# * task - scheduled jobs
# * todo - scheduled reminders
# * calendar - public date announcement
# * log - logbook entry
# * other - custom (use description field)

sub get_dates {
    my ($this,$type) = @_;
    if ($this->loaded() && $this->child_loaded("content_date")) {
	my $dates;
	if ($this->{children}{content_date}) {
	    $dates = $this->{children}{content_date};
	    if ($type) {
		my $typedates = new ExSite::ObjectList(type=>"content_date");
		$dates->reset;
		while (my $date = $dates->next) {
		    if (! $type || $date->getdata("type") eq $type) {
			$typedates->push($date->get());
		    }
		}
		return $typedates;
	    }
	    return $dates;
	}
    }
    return undef;
}

# log: uses the date service to record timestamped messages on the content

sub log {
    my ($this,$message) = @_;
    my $t = new ExSite::Time();
    my $d = new ExSite::Date(data=>{
	content_id=>$this->id,
	type=>"log",
	description=>$message,
	start=>$t->write("sql_timestamp"),
	status=>"active"}
	);
    return $d->save();
}

# todo: uses the date service to add to-do list items for the content

sub todo {
    my ($this,$message,$date) = @_;
    my $d = new ExSite::Date(data=>{
	content_id=>$this->id,
	type=>"todo",
	description=>$message,
	start=>$date,
	status=>"active"}
	);
    return $d->save();
}

# TASKS
# Tasks are invoked by cron to perform timed or scheduled actions on the 
# object. Default content supports
#  * publish
#  * unpublish
#  * archive
# Other content types can overload this to support other scheduled tasks.

sub task {
    my $this = shift;
    $_ = shift; # this is the task command
    if (/^publish/) {
	if ($this->wf_status() ne "published") {
	    $this->wf_publish();
	}
	else {
	    # republish
	    $this->publish(approve=>1);
	}
    }
    elsif (/^unpublish/) {
	$this->unpublish(approve=>1);
    }
    elsif (/^archive/) {
	$this->wf_archive();
    }
}

sub allowed_tasks {
    my $this = shift;
    my @tasks = qw(publish archive unpublish);
    return wantarray ? @tasks : \@tasks;
}

#=== PATH
# Path queries

# content_path - complete array of content objects related by parent
# path - text representation of content_path
# basedir - root directory - must pre-exist on server - we do not write outside of this
# subdir - location relative to basedir - we can create/delete these folders
# diskpath - basedir + subdir
# httpbase - $config{server}{HTMLpath}
# httpdir - URL path relative to httpbase
# httppath - location relative to HT doc root = httpbase + httpdir
#
# is_subdir determines whether we publish into own subdirectory; if not, we 
# publish into our parent's directory

# my_subdir : publish into a subdirectory of this name
#             if blank, publish into parent's subdir
sub my_subdir { 
    my $this = shift;
    return ($this->subtype_attr("publish_as") eq "directory") ?
	return $this->getdata("name") :
	undef;  # regular content objects publish as files, not dirs
}

sub filename {
    my $this = shift;
    my $rev = $this->revision;
    if ($rev->defined) {
	my $mime = $rev->view->mime_type();
	if ($rev->is_file) {
	    # uploaded file
	    return &clean_filename($this->revision->view->filename);
	}
	elsif ($this->is_subdir) {
	    if ($this->revision->view->format eq "url") {
		# remote content has no filename
		return undef;
	    }
	    elsif ($mime && $mime ne "text/html") {
		# some other file type
		my $name = $this->name();
		my $suffix = &MimeToFile($mime);
		return ($name =~ /\.$suffix$/) ? $name : "$name.$suffix";
	    }
	    else { #if ($mime eq "text/html") {
		# we are an index page
		return $config{index_filename} || "index.html";
	    }
	}
	elsif ($mime !~ /^text\/html$/) {
	    my $name = $this->name();
	    my $suffix = &MimeToFile($mime);
	    return ($name =~ /\.$suffix$/) ? $name : "$name.$suffix";
	}
    }
    else {
	if ($this->is_subdir) {
	    return $config{index_filename} || "index.html";
	}
	else {
	    # unknown mime-type; defaul to HTML
	    return $this->name().".html";
	}
    }
    return undef;
}

# content_path is an ObjectList of content objects related through parent

sub content_path {
    my $this = shift;
    if (! $this->{content_path}) {
	my $p = new ExSite::ObjectList(type=>"content");
	if ($this->defined) { $p->push($this->get()); };
	my %done = ($this->id()=>1);
	# don't use parent() because aliases can create infinite loops
	my $pid = $this->getdata("parent");
	if ($pid) {
	    if ($done{$pid}) {
		$this->error("infinite loop in path to content ".$this->id());
		return undef;
	    }
	    $done{$pid} = 1;
	    my $pdata = $this->fetch($pid);
	    while ($pdata) {
		$p->unshift($pdata);
		$pid = $pdata->{parent};
		$pdata = $this->fetch($pid);
	    }
	}
	$this->{content_path} = $p;
    }
    return $this->{content_path};
}

# path is the simple text representation of content_path()

sub path {
    my $this = shift;
    my $p = $this->content_path();
    my @path = $p->array_by_key("name");   ### FIXME: should this be httppath ?
    if (! $path[0]) { shift @path; } # do not include anonymous root nodes
    return wantarray ? @path : "/".join("/",@path);
}

#### EXPERIMENTAL
# datapath() is the path to the content object's files in the 
# data repository

sub datapath {
    my $this = shift;
    my @path;
    my $p = $this->content_path();
    $p->reset();
    while (my $pel = $p->next) {
	push @path, "c".$pel->id;
    }
    push @path, "r".$this->revision->id;
    return wantarray ? @path : join("/",@path);
}

# navpath() is an array of hyperlinks representing content_path.
# These can be used to construct a cookie-crumb.
# Options:
# span_sections => true if path should extend back to other sections
# separator => the string to separate the links, default is ' > '

sub navpath {
    my ($this,%opt) = @_;
    my $p = $this->content_path();
    my $ml = &get_obj("ML");
    my @path;
    my $pathel = $p->last;
    while ($pathel) {
	my $cobj = $pathel->get_content_obj();
	my $type = $cobj->subtype;
	unshift @path, $ml->a($cobj->label(),
			      {href=>$cobj->get_url_canonical()});
	last if ($type eq "section" && ! $opt{span_sections});
	$pathel = $p->previous;
    }
    return @path if (wantarray);
    my $sep = $opt{separator} || "&nbsp;&gt;&nbsp;";
    return join $sep, @path;
}

sub setup_path {
    my $this = shift;
    return $this->{path} if $this->{path};
    if ($this->defined) {
	my $p = $this->content_path();
	my $c = $p->last->get_content_obj();
	my ( @path,    # array of path attributes
	     %path );  # this is what we are setting up

	# build array of path attributes in reverse order
	while ($c && $c->defined) {
	    push @path, {
		type => $c->subtype,
		subdir => $c->my_subdir,
		url => $c->getdata("url")
	    };
	    $c = $p->previous;
	    $c = $c->get_content_obj() if $c;
	}

	# basedir = top-level dir in which we can publish files
	$path{basedir} = "$config{server}{HTMLroot}$config{server}{HTMLpath}";

	my ($base,$section);
	my $subdir = "";
	foreach my $item (@path) {
	    my $pathel = $item->{subdir};

	    # correct basedir for current section/site
	    if (! $base && $item->{subdir} && $item->{url} && $item->{type} eq "section") {
		# different virtual host - move base here
		$base = $pathel;
		$section = $item;
	    }
	    elsif ($base) {
		$base = "$pathel/$base";
	    }

	    # build up path
	    if ($pathel =~ /^\//) {
		# httpbase is outside the normal system base
		$path{httpbase} = $pathel;
		last;
	    }
	    elsif ($pathel && ! $section) {
		$subdir = "/$pathel".$subdir; 
	    }
	    if ($item->{type} eq "section" && $item->{url}) {
		$path{httpbase} = "";
	    }
	}
	$path{basedir} .= "/$base" if $base;
	$path{subdir} = $subdir;

	# diskpath = basedir + subdir
	$path{diskpath} = $path{basedir}.$path{subdir};

	# httpbase = basedir, relative to HTDOCS_ROOT 
	if (! defined $path{httpbase}) {
	    $path{httpbase} = $config{server}{HTMLpath};
	}

	# httpdir = our workding directory, relative to httpbase
	my $httpdir = "";
	foreach my $item (@path) {
	    last if ($item->{type} eq "section" && $item->{url});
	    my $pathel = $item->{subdir};
	    if ($pathel) { $httpdir = "/$pathel".$httpdir; }
	}
	$path{httpdir} = $httpdir;

	# httppath = httpbase + httpdir
	$path{httppath} = $path{httpbase}.$path{httpdir};

	$this->{path} = \%path;
	return $this->{path};
    }
    return {}; #undef;
}

sub basedir  { my $this = shift; return $this->setup_path()->{basedir}; }
sub subdir   { my $this = shift; return $this->setup_path()->{subdir}; }
sub diskpath { my $this = shift; return $this->setup_path()->{diskpath}; }
sub httpbase { my $this = shift; return $this->setup_path()->{httpbase}; }
sub httpdir  { my $this = shift; return $this->setup_path()->{httpdir}; }
sub httppath { my $this = shift; return $this->setup_path()->{httppath}; }

# test if we are contained within another content object
### FIXME: dupe of is_descendant_of() ??
sub is_in {
    my ($this,$content) = @_;
    if ($this->defined) {
	my $container_id;
	if (ref $content) {
	    if ((ref $content) eq "HASH") {
		$container_id = $content->{content_id};
	    }
	    else {
		$container_id = $content->id;
	    }
	}
	else {
	    $container_id = $content;
	}
	my $path = $this->content_path();
	my $node = $path->last;
	do {
	    return 1 if ($node && $node->id == $container_id);
	    $node = $path->previous;
	} until (! $node);
    }
    return 0;
}

#=== DISPLAY

### FIXME: pass a date?
sub load_revision {
    my ($this,$revision) = @_;
    if ($this->{Revision} && $revision) {
	# clear revision, in case this is a change
	delete $this->{Revision};
    }
    if (! $this->{Revision} && $this->ok) {
	# revision can be "newest", "active", "draft", or numeric
	if (! $revision) { $revision = $this->{revision} || "active"; }
	$this->{revid} = $revision;

	if (exists $share{Cache_revision}) {
	    # when publishing sections, we preload latest revisions
	    my $newest = $share{Cache_revision}{$this->id};
	    if ($newest) {
		# there is a revision in the cache
		if ($revision eq "newest" || ($revision eq "active" && $newest->{ptime} !~ /^0/)) {
		    $this->{Revision} = new ExSite::Revision(content=>$this,data=>$newest);
		}
	    }
	    else {
		# no revisions, setup dummy
		$this->{Revision} = new ExSite::Revision();
	    }
	}

	# no cache, or cached revision not appropriate
	$this->{Revision} = $this->find_revision($revision,$this->{view}) 
	    if ! $this->{Revision};
    }
    return $this->{Revision};
}

sub find_revision {
    my ($this,$revision,$view) = @_;
    my $rev;
    # revision can be "newest", "active", "draft", or numeric
    if (! $revision) { $revision = $this->{revision} || "active"; }
    if ($revision =~ /^\d+$/) {
	$rev = new ExSite::Revision(id=>$revision);
    }
    else {
	my @rev = $this->get_revisions();
	if (@rev > 0) {
	    if ($revision eq "draft") {
		$rev = new ExSite::Revision(content=>$this,data=>$rev[-1]);
		last;
	    }
	    else {
		my $revdata;
		while (my $r = pop @rev) {
		    if ($revision eq "newest" && ! $r->{status}) {
			# pick last one with status 0
			if (! $r->{status}) {
			    $revdata = $r;
			    last;
			}
		    }
		    elsif ($r->{ptime} !~ /^0/) {
			# this rev was published/approved at some point
			$revdata = $r;
			last;
		    }
		    elsif (! $revdata) {
			# just take the most recent revision if there are no matches
			$revdata = $r;
		    }
		}
		$rev = new ExSite::Revision(content=>$this,data=>$revdata);
	    }
	}
	else {
	    # nothing available
	    $rev = new ExSite::Revision(content=>$this);  # dummy revision
	}
    }
    $rev->view($view) if $view;
    return $rev;
}

sub find_revision_old {
    my ($this,$revision,$view) = @_;
    my $rev;
    # revision can be "newest", "active", "draft", or numeric
    if (! $revision) { $revision = $this->{revision} || "active"; }
    if ($revision =~ /^\d+$/) {
	$rev = new ExSite::Revision(id=>$revision);
    }
    else {
	my @rev = $this->get_revisions();
	if (@rev > 0) {
	    my $newest = $rev[-1];
	    if ($revision !~ /newest/) {
		while (my $r = pop @rev) {
		    if ($r->{ptime} !~ /^0/) {
			# this rev was published/approved at some point
			$rev = new ExSite::Revision(content=>$this,data=>$r);
			last;
		    }
		}
	    }
	    if (! $rev) {
		$rev = new ExSite::Revision(content=>$this,data=>$newest);
	    }
	}
	else {
	    # nothing available
	    $rev = new ExSite::Revision(content=>$this);  # dummy revision
	}
    }
    return $rev;
}

sub get_revisions {
    my $this = shift;
    return $this->DB->fetch_child("revision","content",$this->id,"revision_id");
}

sub count_revisions {
    my $this = shift;
    my $rev = $this->get_revisions();
    return (ref $rev) eq "ARRAY" ? scalar @$rev : 0;
}

# has_revisions : tests for our own revisions

sub has_revisions {
    my ($this,$revision) = @_;
    $this->load_revision();
    if ($this->{Revision}) {
	# confirm that the revision exists and belongs to us
	my $rcid = $this->{Revision}->getdata("content_id");
	return ($rcid && $rcid == $this->id);
	# otherwise, it probably belongs to our template
    }
    return undef;
}

sub revision {
    my ($this) = @_;
    if (! $this->{Revision}) {
	if ($this->ok) {
	    my $rev = $this->{cms} ? "draft" : undef;
	    $this->{Revision} = $this->load_revision($rev);
	    if ($this->{view}) {
		# we have an explicitly set view - pass it through
		$this->{Revision}->view($this->{view});
	    }
	}
    }
    return $this->{Revision} ? $this->{Revision} : new ExSite::Revision();
}

# rollback : go back to an older revision
# todo: 
# - rollback to a specific rev #, or simply deactivate last rev?
# - republish?

sub rollback {
    my ($this) = @_;
    if ($this->{Revision}) {
	# we have a loaded revision
	my $currid = $this->{Revision}->id;
	my @rev = $this->get_revisions();
	my $lastrev = new ExSite::Revision(data=>$rev[-1]);
	my $lastrevid = $lastrev->id;
	$lastrev->delete;
	if ($currid == $lastrevid) {
	    # deleted our revision; reload
	    $this->load_revision("draft");
	}
    }
    else {
	# no revision set
	my $newrev = $this->find_revision("draft");
	$newrev->delete() if ($newrev->ok);
	delete $this->{Revision};
    }
}

# show methods ----------------------------------------------------------------
# show - default display of the content
# show_templated - display the content within a template, as a complete page
# show_formatted - display the content in a custom layout
# show_summary - display an abbreviated version of the content, such as for an index
# preview - show the content to an administrator
# show_view - used by preview
# show_icon - 

# show(%opt) - display the content to an end-user
#
# options are:
# view - select the view
# other options will be passed to expand, show_formatted, show_revision

sub show {
    my ($this,%opt) = @_;
    my $out;
    if ($this->allow_view()) {

	my $postout;
	if ($ENV{REQUEST_METHOD} eq "POST" &&   # form posting
	    $this->url_is_me() &&               # aimed as this content
	    $this->allow_post()) {              # and we are expecting form input
	    $postout = $this->post();
	}

	my $disptype = $this->displaytype;
	if ($disptype eq "none") {
	    return undef;
	}
	elsif ($disptype eq "template") {
	    return $this->expand(%opt);
	}
	elsif ($disptype eq "formatted") {
	    my $fmt = $config{content}{format}{$this->subtype()} ||
		$config{content}{format}{content};
	    $out = $this->show_formatted($fmt,%opt);
	}
	else {
	    # raw content, show revision only
	    $out = $this->show_revision(%opt);
	}
	# append any post results;
	$out .= $postout if $postout;
    }
    else {
	$out = "Permission denied.";
    }
    return $out;
}

sub show_revision {
    my ($this,%opt) = @_;
    my $viewtype = $opt{view} || $this->{view} || "normal";
    if ($this->has_revisions) {
	my $rev = $this->revision();
	if (! $rev->has_view($viewtype)) {
	    $this->warn("No $viewtype view of this revision, using best substitute.");
	}
	return $rev->show(%opt);
    }
}

# show_templated - like show, but try to wrap the content in a template

sub show_templated {
    my ($this,%opt) = @_;
    # warning: %opt is sent to both show() and expand()
    if ($this->displaytype ne "template" &&  # not already templated
	! exists $opt{content}{body}) {      # body not explicitly def'd
	# spoof normal page structure by using this content as the body
	$opt{content}{body} = $this->show(%opt);
    }
    return $this->expand(%opt);
}

# show_formatted - display content in a custom format
# allow for the following substitution fields:
# title, url, author, name, label, date, html
# url_VIEWNAME, html_VIEWNAME (url, html for alternate views)
# meta_METANAME (dcmeta values)

# FIXME: what if user inserts merge codes into their content, could
# we get into an infinite loop?
# -- no, there is only a single substitution pass

sub show_formatted {
    my ($this,$format,%data) = @_;

    # get our format/template

    my $template = exists $config{content}{format}{$format} ?
	$config{content}{format}{$format} :  # predefined format
	$format;                             # format was passed to us

    # make a list of all substitution parameters

    my %param;
    my $temp = $template;
    while ($temp =~ /\[\[(\w+?)\]\]/) { 
	$param{$1} = 1;
	$temp =~ s/\[\[$1\]\]//g;
    }
    while ($temp =~ /\[\[(\w+:(\w+?))\]\]/) { 
	$param{$1} = 1;
	$temp =~ s/\[\[$1\]\]//g;
    }

    # obtain the substitution data

    foreach my $p (keys %param) {
	next if ($data{$p}); # manual override
	$data{$p} = $this->get_param($p);
    }

    # substitute the data into the template

    return $this->merge($template,\%data);
}

# based on ExSite::Misc::substitute, with additional features for
# inserting other templates and sources
# [[foo]] - insert value of foo from the substitution hash
# [[?foo]]...[[/?foo]] - insert contents if foo is defined in the subhash
# [[!foo]]...[[/!foo]] - insert contents if foo is NOT defined in the subhash
# [[>foo]] - find/insert content object "foo" (eg. find foo in a library)
# [[>>foo]] - find_in_path content object "foo" (eg. inherit foo from parent)
# [[.foo]] - insert $config{content}{format}{foo}

sub merge {
    my ($this,$text,$subhash,$startmark,$endmark) = @_;
    if (! $startmark) { $startmark = '\[\['; }
    if (! $endmark)   { $endmark = '\]\]'; }
    if ($text !~ /$startmark/ && $text =~ /^\w[\w\-\.]+$/) {
	# $text is probably a content object name
	my $c = $this->find($text);
	if ($c && $c->defined) {
	    $text = $c->get_html();
	}
	elsif (defined $config{content}{format}{$text}) {
	    $text = $config{content}{format}{$text};
	}
    }

    # any include objects from the path?
    if ($text =~ /$startmark(>>(.+?))$endmark/) {
	$text =~ s/$startmark(>>(.+?))$endmark/$this->find_in_path($2,1)->get_html()/sge;
    }

    # any include objects?
    if ($text =~ /$startmark(>(.+?))$endmark/) {
	$text =~ s/$startmark(>(.+?))$endmark/$this->find($2)->get_html()/sge;
    }

    # any include conf formats?
    if ($text =~ /$startmark(\.(.+?))$endmark/) {
	$text =~ s/$startmark(\.(.+?))$endmark/$config{content}{format}{$2}/sge;
    }

    # any include blocks?
    if ($text =~ /$startmark(\?(.+?))$endmark(.+?)$startmark(\/\?(.+?))$endmark/s) {
	# remove include blocks that we don't have data for
	$text =~ s/$startmark(\?(.+?))$endmark(.+?)$startmark(\/\?(.+?))$endmark/defined $subhash->{$2} ? $3 : ""/sge;
    }
    if ($text =~ /$startmark(\!(.+?))$endmark(.+?)$startmark(\/\!(.+?))$endmark/s) {
	# include anti-include blocks that we don't have data for
	$text =~ s/$startmark(\!(.+?))$endmark(.+?)$startmark(\/\!(.+?))$endmark/defined $subhash->{$2} ? "" : $3/sge;
    }
    # substitute
    $text =~ s/$startmark(.+?)$endmark/$subhash->{$1}/g;
    return $text;
}

# get_param: return a value associated with one of the following
# named parameters: id, type, title, label, name, language, date, 
# author, caption, summary, index, meta_NAME, url, html, navpath,
# description, info, attachments, tags
# url_VIEW, html_VIEW
# You can also prefix any of these parameters with CONTENT:, where
# "CONTENT" is a named content object, or one of:
# _FIRST, _LAST - the top or bottom subcontent item
# _IMG - first image of the subcontent items
# Your class can also define custom parameters, eg. "xxx" by including
# methods like param_xxx().

sub get_param {
    my ($this,$p) = @_;
    if ($p =~ /^(title|label|name|language)$/) {
	return $this->getdata($p);
    }
    elsif ($p =~ /^(id|about|author|caption|description|icon|index|link|navpath|summary|tools|height|width)$/) {
	return $this->$p();
    }
    elsif ($p eq "info") {
	return $this->content_info();
    }
    elsif ($p eq "type") {
	return $this->subtype();
    }
    elsif ($p eq "date") {
	return $this->posting_date();
    }
    elsif ($p eq "curl") {
	return $this->get_url_canonical();
    }
    elsif ($p eq "url") {
	return $this->get_url();
    }
    elsif ($p eq "purl") {
	return $this->permalink();
    }
    elsif ($p eq "html") {
	return $this->get_html();
    }
    elsif ($p eq "navpath") {
	return $this->navpath();
    }
    elsif ($p eq "attachments") {
	return $this->attachments();
    }
    elsif ($p eq "gallery") {
	return $this->gallery();
    }
    elsif ($p eq "secondary_gallery") {
	return $this->gallery(secondary=>1);
    }
    elsif ($p eq "price") {
	return $this->show_price();
    }
    elsif ($p eq "tags") {
	return $this->show_tags();
    }
    elsif ($p eq "image") {
	return $this->insert_image(undef,view=>"small",caption=>1);
    }
    elsif ($p =~ /^mime_/) {
	my $mime = $this->revision->mime_type();
	if ($p eq "mime_type") {
	    return $mime;
	}
	elsif ($p eq "mime_descr") {
	    return &MimeDescr($mime);
	}
	elsif ($p eq "mime_category") {
	    my ($category,$type) = split /\//,$mime;
	    return $category;
	}
    }
    elsif ($p =~ /^meta_(.*)$/) {
	# metadata value
	my $meta = $1;
	return $this->meta->get($meta);
    }
    elsif ($p =~ /^url_(.*)$/) {
	# URL of a particular view
	my $view = $1;
	my $v = $this->revision->select_view($view);
	return $v->get_url;
    }
    elsif ($p =~ /^html_(.*)$/) {
	# HTML for a particular view
	my $view = $1;
	my $v = $this->revision->select_view($view);
	return $v->get_html();
    }
    elsif ($p =~ /^(index|contents)_(.*)$/) {
	# index of particular subcontent type
	my $index = $1;
	my $type = $2;
	my @c = $this->get_contents($type);
	if (@c > 0) {
	    my $index;
	    foreach my $item (@c) {
		$index .= ($index eq "index") ? $item->summary() : $item->show();
	    }
	    return $index;
	}
    }
    elsif ($p =~ /^([\w\-\.]+):(.*)$/) {
	# subcontent reference
	my $name = $1;
	my $param = $2;
	my $cobj;
	if ($name =~ /^_/) {
	    # meta content name
	    my $contents = $this->get_contents();
	    if ($name eq "_FIRST") {
		$cobj = $contents->[0];
	    }
	    elsif ($name eq "_LAST") {
		$cobj = $contents->[-1];
	    }
	    elsif ($name eq "_IMG") {
		# look for first image content
		foreach my $c (@$contents) {
		    if ($c->revision->mime_type =~ /^image/) {
			$cobj = $c;
			last;
		    }
		}
	    }
	}
	else {
	    # actual content name
	    $cobj = $this->find($name);
	}
	if ($cobj) {
	    return $cobj->get_param($param);
	}
    }
    else {
	# unknown parameter
	my $custom = "param_$p";
	if ($this->can($custom)) {
	    # custom parameter supported by this class only
	    return eval { $this->$custom() } || $@;
	}
    }
    return undef;
}

# specially-formatted views of the content:
# summary - hotlink title + description
# about - hotlink title + info
# thumb - hotlink thumbnail + caption
# preview - administrator 

# summary - an abbreviated view that links through to the main view, used for indexes

sub show_summary { return &summary(@_); }
sub summary {
    my ($this,%opt) = @_;
#    my $ptype = $this->my_page->subtype();
    my $descr;
    my $fmt = 
	$config{content}{format}{$opt{format}} || 
#	$this->find_format($ptype."_".$this->subtype()."_summary") ||
	$this->find_format($this->subtype()."_summary") ||
	$config{content}{format}{summary};
    if ($fmt =~ /\[\[description\]\]/) {
	# descriptions are common in summary views, but are not necessarily defined
	$descr = $this->description();
	if (! $descr) {
	    # no description; make something up
	    ### is this redundant? description() has its own fallback logic
	    if ($this->revision->is_file) {
		my $caption = $this->caption();
		if ($caption) {
		    $descr = $caption;
		}
		else {
		    # describe the file
		    $descr = $this->revision->description;
		}
	    }
	    else {
		my $view = $this->revision()->view();
		my $mime = $view->mime_type;
		if ($mime !~ /html/) {
		    $descr = &MimeDescr($mime);
		}
		my $t = new ExSite::Time($this->getdata("ctime"),"sql_timestamp");
		$descr .= ", ".&substitute("posted on [[date]]",{date=>$t->write("date")});
	    }
	}
    }
    return $this->show_formatted($fmt,(description=>$descr));
}

sub find_format {
    my ($this,$name) = @_;
    my $c = $this->find_in_path($name);
    if ($c && $c->defined) {
	my $format = $c->get_html();
	return $format;
    }
    # not found in cms; fall back on config settings
    if ($config{content}{format}{$name}) {
	return $config{content}{format}{$name};
    }
    return undef;
}

# show_index : show summaries of all contents
### FIXME: duplicates index()
sub show_index {
    my ($this,%opt) = @_;
    my $out;
    my @child = scalar @_ ? @_ : reverse $this->get_contents();
    foreach my $c (@child) {
	$out .= $c->summary(%opt);
    }
    return $out;
}

# preview - like show, but for admins

sub preview {
    my ($this,%opt) = @_;
    if ($this->allow()) {
	my $out;
	my $html;
	my $viewtype = $opt{view} || "normal";
	if ($viewtype eq "all") { $viewtype = "large,normal,small,thumbnail,icon"; }
	my $format = $opt{format} || "both";

	my %view;
	if ($viewtype =~ /,/) {
	    # multiple views requested
	    my @view = split /,\s*/,$viewtype;
	    foreach my $v (@view) {
		if ($this->revision()->has_view($v)) {
		    $view{$v} = $this->revision()->select_view($v);
		}
	    }
	    my (@tabs,@panes);
	    my $itab = 0;
	    my $thistab;
	    foreach my $v (qw(large normal small thumbnail icon)) {
		next if (! exists ($view{$v}));
		if ($v eq "normal") { $thistab = $itab; }
		push @tabs, $v;
		push @panes, $this->show_view($view{$v},$format);
		$itab++;
	    }
	    my $ui = new ExSite::UI;
	    $out .= $ui->DynTabBox(
		tabs=>\@tabs,
		panes=>\@panes,
		thistab=>$thistab,
		);
	}
	else {
	    # one view requested
	    if (! $this->revision()->has_view($viewtype)) {
		$out .= $this->warn("No $viewtype view of this revision, using best substitute.");
	    }
	    my $view = $this->revision()->view($viewtype);
	    $out .= $this->show_view($view,$format);
	}
	$out .= $this->check_publish_rule();
	return $out;
    }
    else {
	return "Permission denied.";
    }
}

sub show_view {
    my ($this,$view,$format) = @_;  # format is raw, html, both
    my $ml = &get_obj("ML");
    my $mimetype = $view->mime_type;
    if ($mimetype =~ /^text/ && $mimetype !~ /^text\/html/) {
	return $ml->pre($view->get_raw());
    }

    my $raw = $view->get_html();
    return $raw if ($format eq "raw");

    my $html = $raw;
    $html =~ s/\&/&amp;/ig;
    $html =~ s/</&lt;/ig;
    $html =~ s/>/&gt;/ig;
    $html =~ s/(\&lt;.+?\&gt;)/<span class="htmltag">$1<\/span>/g;
    $html =~ s/\[\[(.+?)\]\]/<span class="urltag">\[\[$1\]\]<\/span>/g;
    $html =~ s/{{(.+?)}}/<span class="purltag">{{$1}}<\/span>/g;
    $html =~ s/(\&lt;!--content\(.+?\)--\&gt;)/<span class="contenttag">$1<\/span>/g;
    $html =~ s/(\&lt;!--\$.+?--\&gt;)/<span class="metatag">$1<\/span>/g;
    $html =~ s/(\&lt;!--\&.+?--\&gt;)/<span class="dcdtag">$1<\/span>/g;
    $html =~ s/\n/<br>\n/g;
    return $html if ($format eq "html");

    my $raw = $ml->div($raw,{style=>"width:100%;overflow:auto"});
    my $ui = new ExSite::UI;
    return $ui->AccordionBox(
	titles=>["Formatted","Raw HTML"],
	states=>[1,0],
	panes=>[$raw,$html],
	width=>"100%",
	);
}

# show_icon : display a graphical icon for the object

#### FIXME: is icon() deprecated?
sub icon {
    my $this = shift;
    return $this->revision->get_icon_html();
}

sub show_icon {
    my ($this,%opt) = @_;
    my $rev = $this->revision();
    if ($rev) {
	my $view = $rev->select_view("icon");
	if ($view) {
	    return $view->show_icon($opt{size});
	}
    }
    # no revision/view, show a blank icon
    my $ml = &get_obj("ML");
    return $ml->img(undef,{src=>"$config{server}{HTMLpath}/_ExSite/images/mime/blank.png",alt=>$this->name,title=>$this->name});
}

###FIXME: is this used?
sub content_type {
    my ($this) = @_;
    if ($this->{content_type}) {
	# content type has been set manually
	return $this->{content_type};
    }
    else {
	# choose content type automatically
	return $this->revision()->content_type();
    }
}

# tools : optional controls for managing/manipulating the content

sub tools {
    my ($this,%opt) = @_;
    return undef;
}

#------------------------------------------------------------------
# finding related content

sub get_content_tree {
    my ($this) = @_;
    if (! $share{content}{tree}) {
	my @content = $share{DB}->get_query("content tree");
	$share{content}{tree} = new ExSite::Tree("content_id","parent",@content);
	$share{content}{tree}->set("name_key","name"); # for paths
    }
    return $share{content}{tree};
}

# my_ancestor : returns the nearest ancestor node of a given type
# NB: if the current node is of the requested type, we return ourself

sub my_ancestor {
    my ($this,$type) = @_;
    if ($this->loaded) {
	my $tree = $this->get_content_tree;
	my $cnode = $this->get();
	my $itype = $this->isubtype($type);
	do {
	    if ($cnode->{type} == $itype) {
		#return $cnode->{content_id}==$this->id ? $this : $this->get_content_obj($cnode->{content_id});
		return $cnode->{content_id}==$this->id ? $this : $this->get_content_obj($cnode);
	    }
	    $cnode = $tree->getnode_data($cnode->{parent});
	} until (! $cnode);
    }
    # nothing found
    exists $share{content}{isubtype} or $this->get_subtypes;
    my $module = $share{content}{subtype}{$type}{class};
    my $dummy = eval "new $module";
    $dummy or $dummy = new ExSite::Content;
    return $dummy;
}

sub my_page {
    my $this = shift;
    return $this if $this->is_page;
    my $path = $this->content_path();
    my $node = $path->last(); # already checked $this
    while ($node = $path->previous) {
	my $content = $node->get_content_obj();
	return $content if ($content->is_page);
    }
    # no ancestral page
    my $dummy = new ExSite::Content();
    return $dummy;
}

sub my_section {
    my $this = shift;
    if ($this->loaded()) {
	return $this->my_ancestor("section");
    }
    return undef;
}

sub my_root {
    my $this = shift;
    my $path = $this->content_path();
    return $path->first();
}

# is_descendent_of(X) : return true if we are on X's branch of the content tree
### FIXME: dupe of is_in() ??

sub is_descendant_of {
    my ($this,$c) = @_;
    my $cid;
    if (ref $c eq "HASH") { $cid = $c->{content_id}; }
    elsif (ref $c) { $cid = $c->id; }
    else { $cid = $c; }
    my $tree = $this->get_content_tree();
    my $cdata = $this->get();
    while (my $parent = $tree->get_parent($cdata->{content_id})) {
	return 1 if ($parent->{content_id} == $cid);
	$cdata = $parent;
    }
    return 0;
}

sub is_ancestor_of {
    my ($this,$c) = @_;
    my ($cdata,$cid);
    if (ref $c eq "HASH") { $cdata = $c; $cid = $c->{content_id}; }
    elsif (ref $c) { $cdata = $c->get(); $cid = $c->id; }
    else { $cdata = {content_id=>$c}; $cid = $c; }
    my $tree = $this->get_content_tree();
    while (my $parent = $tree->get_parent($cdata->{content_id})) {
	return 1 if ($parent->{content_id} == $this->id);
	$cdata = $parent;
    }
    return 0;
}

# my_type - find best node of a certain type relative to this node
# performs a more extensive search than my_page, etc, above
# because it also looks in our descendant nodes, so that you can do 
# something like $section->my_content_by_type("blog")

sub my_content_by_type {
    my ($this,$type) = @_;
    if ($type) {
	return $this if ($this->subtype() eq $type); # it's us!

	# look in ancestral nodes
	my $p = $this->content_path();
	my $ctype;
	while (my $c = $p->next) {
	    if ($c->subtype eq $type) {
		$ctype = $c;
	    }
	}
	return $this->get_content_obj($ctype) if $ctype;

	my $tree = $this->get_content_tree;
	if ($tree) {
	    # look under our page
	    my $page = $this->my_page();
	    if ($page->is_page) {
		foreach my $c ($tree->get_child($page->id)) {
		    return $this->get_content_obj($c) if ($c->subtype eq $type);
		}
	    }

	    # look through all descendant nodes
	    foreach my $c ($tree->collapse($this->id)) {
		return $this->get_content_obj($c) if ($c->subtype eq $type);
	    }
	}
    }
    # nothing found...
    return new ExSite::Content();  # empty object
}

# contents consist of all child objects
# get_contents - returns an array of objects
# get_contents_as_list - returns an ObjectList

sub get_contents {
    my ($this,$type) = @_;
    if (! exists $this->{contents}) {
	my $tree = $this->get_content_tree;
	my @child = $tree->get_child_data($this->id);
	#my @list = map { $this->get_content_obj($_->{content_id}) } @child;
	my @list = map { $this->get_content_obj($_) } @child;
	my $sortrule = $config{content}{$this->subtype}{sort};
	if ($sortrule) {
	    @list = $this->sort($sortrule,@list);
	}
	$this->{contents} = \@list;
    }
    if ($type) {
	my @typelist;
	my $itype = ($type =~ /^\d+$/) ? $type : $this->isubtype($type);
	foreach my $c (@{$this->{contents}}) {
	    if ($c->isubtype == $itype) {
		push @typelist, $c;
	    }
	}
	return wantarray ? @typelist : \@typelist;
    }
    return wantarray ? @{$this->{contents}} : $this->{contents};
}

sub get_contents_as_list {
    my ($this,$type) = @_;
    my @list;
    my $sorted;
    if (exists $this->{contents}) {
	$sorted = 1; # already sorted in previous call
	if ($type) {
	    my $itype = ($type =~ /^\d+$/) ? $type : $this->isubtype($type);
	    foreach my $c (@{$this->{contents}}) {
		push @list, $c->get() if ($c->isubtype == $itype);
	    }
	}
	else {
	    foreach my $c (@{$this->{contents}}) {
		push @list, $c->get();
	    }
	}
    }
    else {
	my $tree = $this->get_content_tree;
	my @child = $tree->get_child_data($this->id);
	if ($type) {
	    my $itype = ($type =~ /^\d+$/) ? $type : $this->isubtype($type);
	    foreach my $c (@child) {
		push @list, $c if ($c->{type} == $itype);
	    }
	}
	else {
	    foreach my $c (@child) {
		push @list, $c;
	    }
	}
    }
    if (! $sorted) {
	my $sortrule = $config{content}{$this->subtype}{sort};
	if ($sortrule) {
	    @list = $this->sort($sortrule,@list);
	}
    }
    my $list = new ExSite::ObjectList(type=>"content",list=>\@list);
    return $list;
}

sub get_contents_as_hash {
    my ($this,$type) = @_;
    my %contents;
    foreach my $c ($this->get_contents($type)) {
	$contents{$c->name} = $c;
    }
    return wantarray ? %contents : \%contents;
}

# my_content : return named sub-content item

sub my_content {
    my ($this,$name) = @_;
    my @children = $share{content}{tree} ?
	$share{content}{tree}->get_child_data($this->id) :
	$share{DB}->fetch_match("content",{parent=>$this->id});
    foreach my $child (@children) {
	if ($child->{name} eq $name) {
	    return $this->get_content_obj($child);
	}
    }
    return undef;

    # this code fails to find aliases because it resolves aliases before
    # name comparison
    my $contents = $this->get_contents();
    foreach my $c (@$contents) {
	return $c if ($c->name eq $name);
    }
    return undef;
}

sub count_contents {
    my ($this,$type,$match) = @_;
    my ($count,@content);
    $match->{type} = $this->isubtype($type || "content");
    my $tree = $this->get_content_tree;
    return $tree->count($match,$this->id);
}

# attachments : format contents for display

sub attachments {
    my $this = shift;
    my $out;
    my $ml = &get_obj("ML");
    foreach my $c ($this->get_contents()) {
	next if ($c->subtype ne "content"); # only show images, docs, etc.
	my $icon = $c->show_icon();
	$out .= $ml->div(
	    $ml->a($icon.$c->name,{href=>$c->get_url()})." ".
	    $c->description(),
	    {class=>"attachmentLink"});
    }
    if ($out) {
	return $ml->div($out,{class=>"Attachments"});
    }
    return undef;
}

# gallery: thumbnail gallery of images
# options:
# secondary - show a gallery of secondary images only (first image is excluded)

sub gallery {
    my ($this,%opt) = @_;
    my $out;
    my $first = 1;
    foreach my $c ($this->get_contents()) {
	if ($c->revision->is_image) {
	    if (! $opt{secondary} || ! $first) {
		$out .= $this->insert_image($c,
					    view=>"thumbnail",
					    caption=>1,
					    css_prefix=>"gallery");
	    }
	    $first = 0;
	}
    }
    if ($out) {
	my $ml = &get_obj("ML");
	return $ml->div($out,{class=>"Gallery"});
    }
    return undef;
}

# format a sub-image for embedded display
# img is automatically selected if not passed
# options:
# view => which view to display; if a larger view is on file, show it in a popup
# caption => caption for the image; 1 to use the stored caption 
# css_prefix => used for CSS classes

### inserts dupe view images and useless captions==filename

sub insert_image {
    my ($this,$img,%opt) = @_;
    if (! $img) {
	# find top-ranked sub-image
	my $contents = $this->get_contents();
	foreach my $c (@$contents) {
	    if ($c->revision->mime_type =~ /^image/) {
		$img = $c;
		last;
	    }
	}
    }
    if ($img) {
	my $ml = &get_obj("ML");
	my $view = $opt{view} || "normal";
	my $cview = $img->revision->select_view($view);
	return undef if (! $cview || $cview->mime_type !~ /^image/);
	my ($imgurl,@imgdim,$imghtml,$largeurl,@largedim,$largehtml);
	$imghtml = $cview->get_html();
	$imgurl = $cview->get_url();
	my $large_view = $view eq "normal" ? "large" : "normal";
	if ($img->revision->has_view($large_view)) {
	    $cview = $img->revision->select_view($large_view);
	    my $lgurl = $cview->get_url();
	    if ($lgurl ne $imgurl && $cview->mime_type =~ /^image/) {
		# different image
		$largehtml = $cview->get_html();
	    }
	}
	my $caption = $opt{caption}==1 ? $img->caption() : $opt{caption};
	my $out;
	if ($largehtml) {
	    my $ui = &get_obj("UI");
	    $out = $ui->Overlay(
		label=>$imghtml,
		title=>$caption,
		pane=>$largehtml
		);
	    $caption or $caption = $msg{"click to zoom"};
	}
	else {
	    $out = $imghtml;
	}
	if ($caption) {
	    $out .= $ml->div($caption,{class=>"$opt{css_prefix}ImageCaption"});
	}
	return $ml->div($out,{class=>"$opt{css_prefix}Image"});
    }
    return undef; # no image to insert
}

# sort a list of content objects
# can pass a list of objects or datahashes
# method can be:
# - date (publication time)
# - alpha (by title)
# - any content column or list of columns, including sortkey
#   Caution: not all columns may be loaded.
# - null (sorts in order of creation, newest first)

sub sort {
    my ($this,$method,@list) = @_;
    # @list could be objects or datahashes
    my @sortkey;
    if ($method =~ /date/) {
	@sortkey = ("ptime");
    }
    elsif ($method =~ /alpha/) {
	@sortkey = ("title","sortkey");
    }
    elsif (ref $method eq "ARRAY") {
	@sortkey = @$method;
    }
    elsif ($method) {
	@sortkey = ($method,"sortkey");
    }
    else {
	@sortkey = ("content_id");
    }
    my $objects;
    if (ref $list[0] ne "HASH") {
	# objects were passed
	$objects = 1;
	@list = map { $_->get() } @list;
    }
    my $save = $config{report}{case_insensitive_sort};
    $config{report}{case_insensitive_sort} = 1;
    my @sorted = $share{DB}->sort_rows("content",\@list,@sortkey);
    $config{report}{case_insensitive_sort} = $save;
    if ($objects) {
	@sorted = map { $this->get_content_obj($_) } @sorted;
    }
    return wantarray ? @sorted : \@sorted;
}

# sort a list of content objects
# can pass a list of objects or datahashes
# if datahashes, $method is the hashkey to sort on
# if objects, sort method can be:
# - date (most recent items first)
# - alpha (by title)
# - sortkey (manual sort)
# - id (order of creation, newest first)
##### deprecated

sub sort_old {
    my ($this,$method,@list) = @_;
    # @list could be objects or datahashes
    if (ref $list[0] eq "HASH") {
	return $share{DB}->sort_rows("content",\@list,$method);
    }
    else {
	if ($method =~ /date/) {
	    return sort { $b->getdata("ptime") cmp $a->getdata("ptime") } @list;
	}
	elsif ($method =~ /alpha/) {
	    return sort { $a->title cmp $b->title } @list;
	}
	elsif ($method =~ /sortkey/) {
	    return sort { $a->getdata("sortkey") cmp $b->getdata("sortkey") } @list;
	}
	else {
	    # note reverse order (newest first)
	    return sort { $b->id <=> $a->id } @list;
	}
    }
}

# submenu consists of the child pages of this node

sub my_submenu_items {
    my ($this) = @_;
    my $tree = $this->get_content_tree;
    my @child = $tree->get_child_data($this->id);
    my @menu;
    foreach my $cnode (@child) {
	my $c = new ExSite::Content(id=>$cnode->{content_id});
	my $p = $c->get_content_obj();
	if ($p->is_page()) {
	    push @menu, $p->{data};
	}
    }
    my $submenu = new ExSite::ObjectList(type=>"content",list=>\@menu);
    return $submenu;
}

# menu consists of this node, plus its child pages

sub my_menu_items {
    my ($this) = @_;
    my $menu = $this->my_submenu_items();
    $menu->unshift($this->{data}) if ($this->is_page());
    return $menu;
}

# find descendant nodes of selected type(s)
# like get_contents(), but performs a deep search, skipping nodes
# of undesired types.

sub get_descendants {
    my ($this,@type) = @_;
    my $tree = $this->get_content_tree();
    my $id = $this->id;
    my $data = $tree->getnode_data($id);
    # alld is a list of all descendant nodes
    my @all_d = ( $data );
    push @all_d, $tree->collapse($id);
    if (scalar @type == 0) { 
	# no special subtypes requested; return everything
	return wantarray ? @all_d : \@all_d;
    }
    # good_d is a list of descendant nodes of the correct type
    my (@good_d,@itype);
    # make a list of desired itypes
    foreach my $t (@type) { push @itype, $this->isubtype($t); }
    # select matching items from all_d
    foreach $data (@all_d) {
	foreach my $itype (@itype) {
	    if ($data->{type} == $itype) {
		push @good_d, $data;
	    }
	}
    }
    return wantarray ? @good_d : \@good_d;
}

# index - display an HTML listing of contents

sub index {
    my ($this,%opt) = @_;
    my $out;
    my $ml = &get_obj("ML");

    # look for pagination instructions
    my $input = new ExSite::Input;
    my $in = $input->query_or_post();
    my $start = $in->{_st};
    my $pagelen = $in->{_pl};
    my $show = $start ? 0 : 1;
    my $n = 0;
    my $nshow = 0;
    my $more;

    my $contents = $this->get_contents_as_list();
    while (my $c = $contents->next()) {
	next if ($c->navtype ne "item");
	$n++;
	if ($start) {
	    next if ($n < $start);
	    $show = 1;
	}
	$out .= $c->summary(%opt);
	$nshow++;
	if ($pagelen && $nshow >= $pagelen) {
	    $more = ($n < $contents->count) ? $n+1 : undef;
	    last;
	}
    }
    # pagination links
    my $prev_st = $start - $pagelen;
    if ($prev_st <= 0) { $prev_st = undef; }
    if ($prev_st || $more) {
	my $uri = $this->get_uri();
	my $links;
	if ($prev_st) {
	    $uri->parameter("_st",$prev_st);
	    $links = $ml->a("&lt; $msg{previous}",{href=>$uri->write()});
	}
	if ($more) {
	    $uri->parameter("_st",$more);
	    $links = $ml->a("&lt; $msg{next}",{href=>$uri->write()});
	}
	$out .= $ml->div($links,{class=>"indexLinks"});
    }
    return $ml->div($out,{class=>"Index"});
}

# rss - generate an RSS listing of contents

sub rss {
    my ($this,%opt) = @_;
    my $clist = $this->get_contents_as_list();
    $clist->reset();
    if ($clist->count > 0) {
	my $nitem;
	my $rss = new ExSite::RSS(xml=>1);
	$rss->title($this->title);
	$rss->description($this->description);
	$rss->link($this->get_url);
	while (my $c = $clist->next) {
	    #next if ($c->getdata("status") ne "active");
	    next if ($c->wf_status() ne "published");
	    if ($c->navtype eq "item") {
		$nitem++;
		$rss->item($c->title,$c->description,$c->get_url,$c->posting_date);
	    }
	}
	return $rss->write() if $nitem;
    }
    return undef;
}

# fetch, fetch_obj: try fetching from the tree cache to save a DB hit

sub fetch {
    my ($this,$id) = @_;
    return $this->get_content_tree->getnode_data($id) || 
	$share{DB}->fetch("content",$id);
}

sub fetch_obj {
    my ($this,$id) = @_;
    my $data = $this->fetch($id);
    if ($data) {
	return $this->get_content_obj($data);
    }
    else {
	return ExSite::Content->new();
    }
}

# return the types of content allowed under this node
# - types are content_type records

sub get_allowed_types {
    my ($this,$cnode) = @_;
    $cnode or $cnode = $this;
    my $subtype = $cnode->subtype();
    # only sections are allowed if there is no current subtype
    return $subtype ?
	$share{DB}->get_query("allowed content types",$subtype) :
	$share{DB}->fetch_match("content_type",{name=>"section"});
}

# posts are content additions/updates made by regular website users,
# eg. comments, reviews, profile changes
# posts are not supported by low-level content objects, should be
# overloaded by higher-level objects that support them.
#
# About linking from post output: post() can be called implicitly
# from show(), in which case regular link() calls should work as expected.
# post() can also be called directly, ie. /cgi/ex.cgi/post/content...
# This mode simplifies AJAX posts, but link() will not work as expected
# (it will link back to /cgi/ex.cgi/post/...). If you want to support direct
# AJAX calls, then use get_url-type calls instead of link() for linking.

sub post {
    my ($this,%opt) = @_;
    return undef;

# stub code:

#    # get post data
#    my $input = new ExSite::Input;
#    $this->{post_data} = $input->{post};
#    # do something...
}

sub allow_post {
    my ($this) = @_;
    return undef;
}

sub report {
    my ($this,%opt) = @_;
    if ($this->defined()) {
	$this->load();

	# metadata

	my %meta;
	my @meta = sort $this->meta->get_allowed();
	my $nmeta = 0;
	my @metahead;
	foreach my $m (@meta) {
	    my $val = $this->meta->get($m);
	    if ($val) {
		push @metahead, $m;
		$meta{$m} = $val; 
		$nmeta++;
	    }
	}
	my $metareport = new ExSite::ReportBuilder(title=>"Metadata");
	$metareport->headers(@metahead);
	$metareport->data( map { $meta{$_} } @metahead );
	my $foot = $metareport->make() if $nmeta;

	# other info

	my %other;
	if ($this->revision->is_file) {
	    my %fileinfo = $this->revision->get_fileinfo;
	    $other{'Original filename'} = $this->revision->view->original_filename;
	    $other{'File location'} = $fileinfo{diskpath};
	    $other{'File size'} = $fileinfo{size};
	}
	$other{"MIME type"} = $this->revision->view->mime_type;
	$other{"Path (logical)"} = scalar $this->path();
	$other{"Path (disk)"} = $this->diskpath();
	$other{"Path (url)"} = $this->httppath();
	$other{"Filename"} = $this->filename || "n/a";
	$other{Published} = $this->revision->is_published ? $this->revision->showdata("ptime") : "not yet";
	$other{"Publish Heuristic"} = $this->publish_rule_heuristic();

	my $otherreport = new ExSite::ReportBuilder(title=>"Other Information");
	$otherreport->headers(sort keys %other);
	$otherreport->data( map { $other{$_} } sort keys %other );
	$foot .= $otherreport->make();

	# contents

	my $contentreport = new ExSite::ReportBuilder(title=>"Contents");
	$contentreport->headers("Name","Type","Language","MIME-Type");
	my $tree = $this->get_content_tree();
	my @child = $tree->get_child_data($this->id);
	if (scalar @child > 0) {
	    foreach my $n (@child) {
		my $cnode = new ExSite::Content(id=>$n->{content_id});
		$contentreport->push(
		    $cnode->name,
		    $this->subtype($cnode->getdata("type")),
		    $cnode->getdata("language"),
		    $cnode->revision->mime_type);
	    }
	    $foot .= $contentreport->make();
	}

	# revisions

	my %rev;
	my @rev = $this->get_revisions();
	my $revreport = new ExSite::ReportBuilder(title=>"Revisions");
	$revreport->headers("Revision","Note","Updated on","Published on");
	foreach my $rev (reverse @rev) {
	    next if ($rev->{content_id} != $this->id);
	    my @rdata;
	    my $r = new ExSite::Revision(data=>$rev);
	    my $id = $r->id;
	    if ($id == $this->revision->id) { $id .= "*"; }
	    push @rdata,$id;
	    push @rdata,$r->showdata("note");
	    push @rdata,$r->showdata("ctime");
	    my $ptime = $r->getdata("ptime");
	    push @rdata, $ptime =~ /^0/ ? "n/a" : $r->showdata("ptime");
	    $revreport->push(@rdata);
	}
	$revreport->foot("* The revision currently being shown.");
	$foot .= $revreport->make() if ($revreport->nrow > 0);
	
	# views

	my $viewreport = new ExSite::ReportBuilder(title=>"Views of revision ".$this->revision->id);
	$viewreport->headers("View","Format","MIME Type","Attributes");
	foreach my $vtype (qw(large normal small thumbnail icon)) {
	    if ($this->revision->has_view($vtype)) {
		my $v = $this->revision->select_view($vtype);
		$viewreport->push($vtype,
				  $v->showdata("format"),
				  $v->showdata("mime_type"),
				  $v->showdata("attributes"));
	    }
	}
	$foot .= $viewreport->make() if ($viewreport->nrow > 0);
	
	# keys

	my @keys = $this->keys();
	if (scalar @keys > 0) {
	    my $keyreport = new ExSite::ReportBuilder(title=>"Administrator Keys");
	    $keyreport->headers("User","Role");
	    foreach my $key (@keys) {
		my $user = $share{DB}->fetch("member",$key->{uid});
		$keyreport->push($share{DB}->user_name($user),$key->{role});
	    }
	    $foot .= $keyreport->make();
	}

	return $this->DB()->report({ table=>$this->{type},
				     data=>[$this->{data}], 
				     columns=>"full|brief",
				     type=>"full", 
				     title=>$this->name,
				     foot=>$foot,
				     %opt });
    }
    return undef;
}

# find_subtypes - locate related content by type

#### DEPRECATED ??

sub find_subtypes {
    my ($this,@subtype) = @_;
    my $sql;
    if (@subtype > 1) {
	$sql = "select content.* from content,content_type where content.type=content_type.content_type_id and content_type.name in ('" . join("','",@subtype) . "') ";
    }
    elsif (@subtype > 0) {
	$sql = "select content.* from content,content_type where content.type=content_type.content_type_id and content_type.name='$subtype[0]'";
    }
    else {
	return undef;
    }
    return $share{DB}->custom_query($sql);
}

# find - locate related content by name
# We search in:
# - the current content node
# - the nearest ancestral page, if we are not a page
# - our templates
# - our nearest ancestral page's templates
# - our descendant pages
# - our sections' libraries

### FIXME: are we finding nodes of any type, or only content nodes?
### get_child returns pages, libraries, templates, etc.

sub find {
    my ($this,$name) = @_;
    return undef if (! $name);

    my $tree = $this->get_content_tree;
    if (! $tree) {
	$this->error("Failed to get content tree");
	return undef;
    }

    # look under current cnode
    my %child = &keywise("name", scalar $tree->get_child($this->id));
    if ($child{$name}) {
#	if ($this->subtype_attr("navtype",$child{$name}{type}) eq "other") {
	    # ignore pages, items
	    return $this->get_content_obj($child{$name});
#	}
    }

    # look under our page
    my ($page_id,$pnode);
    my $page = $this;
    while ($page->defined && ! $page->is_page) {
	$page = $page->parent();
    }
    if ($page->is_page) {
	$pnode = $page->get();
	$page_id = $page->id;
	%child = &keywise("name", scalar $tree->get_child($page_id));
	if ($child{$name}) {
	    return $this->get_content_obj($child{$name});
	}
    }

    # look through our templates
    my $node = $this->find_in_template($name);
    return $node if $node;

    ### FIXME: look through our parents' templates?
    ### eg. a photo in a library; could the library specify a template?

    # look through our page's templates
    my $node = $this->find_in_template($name,$pnode->{template});
    return $node if $node;

    if ($name ne "body") { 
	# only pick up body from page or template
	# for other content, look through all descendant nodes
	%child = &keywise("name", scalar $tree->collapse($this->id));
	if ($child{$name}) {
	    return $this->get_content_obj($child{$name});
	}

	# find our section   ### FIXME: use my_section ?
	my ($section_id,$snode);
	my $parent = $this->{data};
	while ($parent && $this->subtype($parent->{type}) ne "section") {
	    $parent = $tree->getnode_data($parent->{parent});
	}
	if ($parent && $this->subtype($parent->{type}) eq "section") {
	    # found our section
	    $section_id = $parent->{content_id};

	    # look in the section template(s)
	    my $s = new ExSite::Section(id=>$section_id);
	    my $node = $this->find_in_template($name,$s->getdata("template"));
	    return $node if $node;

	    # look in this section's libraries ### FIXME: use $s->fetch_libraries
	    while ($section_id) {
		my @child = $tree->get_child_data($section_id);
		foreach my $lib (@child) {
		    if ($this->subtype($lib->{type}) eq "library") {
			%child = &keywise("name", scalar $tree->get_child($lib->{content_id}));
			if ($child{$name}) {
			    return $this->get_content_obj($child{$name});
			}
		    }
		    ### nested libraries?
		}
		# next section
		$parent = $tree->getnode_data($parent->{parent});
		#### can this section share content with us???
		$section_id = $this->subtype($parent->{type}) eq "section" ? $parent->{parent} : 0;
	    }
	}
    }

    # nothing found...

    return new ExSite::Content();  # empty object
}

# find_in_template: find a named content object in a template
# (also searches parent templates)

sub find_in_template {
    my ($this,$name,$template_id) = @_;
    my $tree = $this->get_content_tree;
    $template_id or $template_id = $this->{data}{template};
    while ($template_id) {
	my %child = &keywise("name", scalar $tree->get_child($template_id));
	if ($child{$name}) {
	    return $this->get_content_obj($child{$name});
	}
	my $t = new ExSite::Template(id=>$template_id);
	my $tnode = $tree->getnode_data($t->getdata("template"));
	$template_id = $tnode ? $tnode->{content_id} : undef;
    }
    return undef; # not found under this template
}

# find_in_path: find a named content object amongst the children of our path nodes
# - set $not_in_self to true to skip searching in the current object

sub find_in_path {
    my ($this, $name, $not_in_self) = @_;
    my $path = $this->content_path();
    my $c = $path->last;
    $c = $c->previous() if $not_in_self;
    while ($c && $c->defined) {
	my $c2 = $c->my_content($name);
	return $c2 if $c2;
	$c = $path->previous;
    }
    return new ExSite::Content(); # blank
}

# expand - perform CMS substitutions on HTML by finding related cnodes and 
# inserting their HTML or URLs

sub expand {
    my ($this,%option) = @_;
    return $this->{html} if ($this->{expanded} || $this->{noexpand});
    $this->info("expanding html");

    # monitor the content objects that we have expanded, to avoid infinite loops
    $this->{expanded} = {};

    # fetch raw template data
    # fetch prepublished template data, if possible; otherwise fetch raw data
    $this->{html} = $option{html} || $this->get_start_html($this);

    if (! exists $option{content}) { $option{content} = {}; }
    my $method = $option{method} || "data,url,content,page,module"; 

    do {

	# clear substitution counter
	$this->{htmlsub} = 0;

	# 1) content-URL substitutions, eg. SRC=[[content-object-name]]

	if ($method =~ /url/) {
	    $this->{html} =~ s/\[\[(.+?)\]\]/$this->get_content_url($1,\%option)/ges;
	}

	# 2) page-URL substitutions, eg. HREF={{page-name/id}}

	if ($method =~ /page/) { 
	    $this->{html} =~ s/\{\{([\w\.-]*)\}\}/$this->get_page_url($1,\%option)/ges;
	}

	# 3) HTML content substitutions, eg. <!--content(content-obj-name)-->

	if ($method =~ /content/) { 
	    # repeat until all substitutions are done
	    while ($this->{html} =~ /<\!--\&?content\((.+?)\)-->/) {
		$this->{html} =~ s/<\!--\&?content\((.+?)\)-->/$this->get_content($1,\%option)/ges;
	    }
	}

	# 4) Dynamic Content Driver substitutions, eg. <!--&module.method(args)-->

	if ($method =~ /module/) {
	    # insert DCD content
	    do {
		$this->{expand_redo} = 0;
		my $html = $this->{html};
		# direct substitution of dynamic content (same server request)
		$html =~ s/<\!--\&(\w+)\((.*?)\)-->/$this->get_dynamic_content($1,$2,\%option)/ges;
		# indirect substitution of dynamic content (separate request)
		$html =~ s/<\!--\&\&(\&)?(\w+)\((.*?)\)-->/$this->get_dynamic_content_indirect($2,$3,\%option,$1)/ges;
		if (! $this->{expand_redo} && ! $this->{noexpand}) {
		    $this->{html} = $html;
		}
	    } until (! $this->{expand_redo} || $this->{noexpand});

	    # Normally there is only one pass through above do...until loop.
	    # However, some DCDs may set flags to change the logic:
	    #    expand_redo - start over
            #    noexpand - abort

	}
    } until ($this->{htmlsub} == 0);

    # build a hash of meta data
    my $meta = $this->get_metadata();
    # page_header, page_footer substitutions are handled like metadata
    $meta->{page_header} = $share{page_header};
    $meta->{page_footer} = $share{page_footer};
    # perform meta data substitutions, eg. <!--$name-->
    # (we do this last, in case plug-ins want to change our metadata)
    if ($method =~ /data/) { 
	$this->{html} =~ s/<!--\$(\w+)-->/$meta->{$1}/gs;
    }

    if ($option{expand}) {
	# partial expansion was requested, which means we should now have
	# one or more masked CMS tags in our HTML.  Now we have to unmask them.
	$this->{html} = &restore_cms_tags($this->{html});
    }

    if ($share{page_footer} && $this->{html} =~ /^<(!doctype|html)/i) {
	# full page; append any deferred footer content
	$this->{html} .= $share{page_footer};
    }

    # flag expansion as done; also frees the hash we used to keep track
    # of expansions
    $this->{expanded} = 1;
    return $this->{html};
}

# special options to control expansion

sub cancel {
    my $this = shift;
    # do NOT show this page
    $this->{done} = 1;
    return;
}

sub halt {
    my $this = shift;
    # abort current pass of content generation, 
    # but leave content in its current state
    $this->{noexpand} = 1;
    return;
}

sub redo {
    my $this = shift;
    # abort current pass of content generation and start over
    $this->{expand_redo} = 1;
    return;
}

# unexpand: undo expand() so we can re-do it

sub unexpand {
    my $this = shift;
    delete $this->{expanded};
    delete $this->{html};
    return;
}

# get_page_url : return replacement text for a {{...}} CMS tag

sub get_page_url {
    my ($this,$id,$opt) = @_;
    my $stat = $this->run_handler("get_page_url",$id,$opt);
    return $stat if (defined $stat);
    my ($p,$Page,$query,$url,$static);
    if ($id =~ /\?/) {
	($id,$query) = split /\?/, $id;
    }

    if ($opt->{method} =~ /dummy-page/) {
	# change our brackets so they will be ignored by expand()
	return "{|{".$id."}|}";
    }

    # get the base URL for the page

    if (! $id) {
	# no id means a self-link
	$Page = $share{Page};
	$static = defined $query;
    }
    elsif ($id eq "!") {
	# ! means self-link to dynamic version
	$Page = $share{Page};
	$static = 0;
    }
    else {
	if ($id =~ /^\d+$/) {
	    # fetch by ID
	    $Page = $this->get_content_obj($id);
	    if (! $Page->is_in($this->my_section())) {
		$this->error($this->name." cannot link to ".$Page->name);
		return "";
	    }
	}
	else {
	    # fetch by name
	    $Page = $this->my_section->get_page($id,$this->my_page);
	}
	$static = ! defined $query;
    }

    # change language automatically
    my $new_lang = $Page->get_my("language");
    my $old_lang = $share{Page} ? $share{Page}->get_my("language") : undef;
    if ($old_lang && $new_lang ne $old_lang) {
	$Page->set_language($old_lang);
    }

    # modify the base URL with extra query params

    if ($query) {
	my $uri = $Page->get_uri_dynamic();
	my %qdata = &DecodeString($query);
	$uri->query(%qdata);
	$url = $uri->write();
    }
    else {
	$url = $static ? $Page->get_url() : $Page->get_url_dynamic();
    }
    return $url;
}

# get_content_url : return replacement text for a [[...]] CMS tag

sub get_content_url {
    my ($this,$id,$option) = @_;
    my $stat = $this->run_handler("get_content_url",$id,$option);
    return $stat if (defined $stat);
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
	$cnode = $this->get_content_obj($id); #new ExSite::Content(id=>$id);
	#### FIXME: validate permissions to view this cnode
    }
    else {
	$cnode = $this->find($id);
    }
#    $cnode = $cnode->get_content_obj();

    # change language automatically
    if ($cnode->is_page) {
	my $new_lang = $cnode->getdata("language");
	my $old_lang = $share{Page} ? $share{Page}->getdata("language") : undef;
	if ($old_lang && $new_lang ne $old_lang) {
	    $cnode->set_lanugage($old_lang);
	}
    }

    if ($cnode && $option->{cms}) { $cnode->load_revision("newest"); }
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

# get_content : return replacement text for a <!--&content(...)--> CMS tag

sub get_content {
    my ($this,$id,$option) = @_;
    my $stat = $this->run_handler("get_content",$id,$option);
    return $stat if (defined $stat);
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

    if ($option->{method} =~ /dummy-content/) {
	# we're not really substituting content, 
	# so use a placeholder graphic instead
	$newtext = $this->placeholder_image($id);
    }
    elsif (exists $option->{content}{$cobjname}) {
	# predefined content object
	$newtext = $option->{content}{$cobjname};
    }
    else {
	# look for matching content object in DB
	$cobj = $this->find($cobjname);
	# has_content only checks for revisions, not sub-objects
	#return undef if (! $cobj->has_content);
	if ($option->{cms}) { $cobj->load_revision("newest"); }
	my $in = new ExSite::Input;
	my $q = $in->query;

	if (! $cobj->has_content) {
	    return undef;
	}
	elsif ($share{Page} && 
	       $share{Page}->is_publishing && 
	       $share{Page}->is_static && 
	       ! $cobj->is_static) {
	    # dynamic content in a static page
	    my $id = $cobj->id;
	    my $v = $view ? "/$view" : undef;
	    my $uri = new ExSite::URI(uri=>"$config{server}{CGIpath}/$config{prog}{view}");
	    $uri->path("action","view");
	    $uri->path("content",scalar $cobj->path);
	    if ($share{Page} && $cobj->getdata("access")) {
		# add some referer info to help with authentication/redirection
		$uri->parameter("ref",$share{Page}->get_url());
		#$url .= "?ref=".&url_escape($share{Page}->get_url());
	    }
	    my $mime = $cobj->revision->view->mime_type();
	    if ($mime !~ /html/) {
		$uri->parameter("fmt","html");
	    }
	    $uri->plaintext;
	    my $url = $uri->write();
	    my $ml = &get_obj("ML");
	    if (! $share{httprequest_included}) {
		$newtext = $ml->script(undef,{src=>"$config{server}{HTMLpath}/_ExSite/js/httprequest.js"});
		$share{httprequest_included} = 1;
	    }
	    $newtext .= $ml->script("document.write(getRequestData(\"$url\"))");
	    $newtext .= $ml->noscript($msg{"Please enable Javascript to view this content."});
	}
	elsif ($share{Page} && 
	       $cobj->deny()) {
	    # restricted content in a dynamic page
	    my $mime = $cobj->revision->view->mime_type();
	    my $ml = &get_obj("ML");
	    if ($mime =~ /image/) {
		my $url = "$config{server}{HTMLpath}/_ExSite/images/forbidden.png";
		return $ml->img(undef,{src=>$url,class=>"AccessDenied"});
	    }
	    else {
		return $ml->p("Access denied. Please log in to view this content.",{class=>"error"});
	    }
	}
	else {
	    # regular content, same access and publish rule as its page
	    $newtext = $cobj->show();
	}
	if ($option->{cms} && 
	    $cobj->context("content")->{content_id} == 
	    $this->context("page")->{content_id}) {
	    ###### should allow hotlinks to undefined content
	    ###### objects that are being inherited from template
	    # can only manage content tied directly to this page
	    # to manage templates, view the template in cms mode
	    
	    # inline editing links
	    if ($share{DB}->owns() && 
		(($config{page}{editmode} ne "MySite") || $id eq "body")) {
		$newtext .= $this->edit_content_link($cobj);
		# highlight editable content sections
		my $ml = new ExSite::ML;
		if ($option->{cms} > 1 && $config{page}{editmode} eq "MySite") {
		    # for the noobs
		    $newtext .= 
			$ml->br().
			$ml->a("Return to website control panel",{href=>"javascript:window.close()"});
		}
		$newtext = $ml->div($newtext,{style=>"border-width:1px; border-color:red; border-style:dashed; padding:0px;"});
	    }
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

sub placeholder_image {
    my ($this,$id) = @_;
    ### FIXME: use html_escape();
    $id =~ s/\"/%22/g;
    $id =~ s/</%3C/g;
    $id =~ s/>/%3E/g;
    my $ml = new ExSite::ML;
    return $ml->img(undef,{alt=>"content($id)", 
			   src=>"$config{server}{HTMLpath}/_ExSite/images/checker.png",
			   title=>$id,
			   name=>"_".$id,
			   height=>50,
			   width=>100,});
}

sub get_dynamic_content {
    my ($this,$module,$modargs,$option) = @_;
    my $stat = $this->run_handler("get_dynamic_content",$module,$modargs,$option);
    return $stat if (defined $stat);
    my ($dcd,$endname,$modname,$modmethod,$newtext);

    # flag a substitution as having occured, so we can expand these results
    $this->{htmlsub}++;

    ($modname,$modmethod) = split(/\./,$module,2);
    if (!$modmethod) { $modmethod = "write"; }

    my $ml = new ExSite::ML;
    
    # run the DCD
    
    if ($option->{method} =~ /dummy-module/ || $option->{expand}) {
	my $icon = "$config{server}{HTMLpath}/_Modules/$modname/icon.gif";
	if (! -e "$config{server}{HTMLroot}$icon") {
	    $icon =~ s/\.gif$/\.png/;
	}
	if (! -e "$config{server}{HTMLroot}$icon") {
	    # no icon; use default ExSite app icon
	    $icon = "$config{server}{HTMLpath}/_Modules/icon.gif";
	}
	$newtext = $ml->img(undef,{alt=>"$module($modargs)",
				   src=>$icon,
				   title=>"$module($modargs)",
				   name=>"$module($modargs)",
				   border=>3,
				   style=>"border-style:outset;"});
    }
    elsif ($modmethod =~ /^(read|write|ioctl)$/) {
	# find the module
	my $section = $this->my_section();
	$dcd = &get_module($modname,0,$section->get());
	if ($dcd) {
	    if ($option->{method} =~ /static-module/) {

### FIXME: use isDynamic instead

		# only expand modules whose output is constant on a given page
		if ($dcd->ioctl('isStatic')) {
		    # execute the DCD method
		    $newtext = eval {
			# try to trap fatal errors
			$dcd->$modmethod($modargs);
		    };
		    if ($@) {
			$newtext = $this->error($@);
		    }
		}
		else {
		    # pass the tag through - mask the tag by adding '*'; 
		    # we'll unmask it after expansion is complete
		    $newtext = "<!--*&${module}(${modargs})-->";
		}
	    }
	    else {
		# execute the DCD method
		$newtext = eval {
		    # try to trap fatal errors
		    $dcd->$modmethod($modargs);
		};
		if ($@) {
		    $newtext = $this->error($@);
		}
	    }
	    # disable substitution for read and ioctl methods
	    if ($modmethod ne "write") {
		$newtext = $ml->Comment("$modname.$modmethod executed");
	    }
	}
	else {
	    $newtext = $ml->Comment("$modname failed");
	    $newtext .= &ExSite::Config::show_diagnostics();
	}
    }
    else {
	$newtext = $ml->Comment("Error: invalid dynamic content driver method: $modmethod");
	$this->error("invalid DCD method: $modmethod");
    }
    return $newtext;
}

# AJAX version
#
# FIXME: in principle, we don't have to display a warning message in
# <noscript>...</noscript>.  We could actually display the the real
# content, as in a direct substitution.  Unfortunately, that would involve
# running the DCD twice, once for the <noscript> direct sub, and again for
# the JS indirect sub.  If we cached this data (in the %session?) we could
# spare ourselves that extra hit, and give ourselves some robustness to
# non-JS clients (eg. GoogleBot).
#
# Actually, there's no need to put it in the <noscript> section;  you could
# put it in the regular DIV, in which case, all clients see it and use it.
# Javascript-enabled clients then overwrite it with the most current 
# dynamic version, if there is one.  The double-hit is a reasonable price
# to pay if we are publishing, since the 1st hit only occurs once for the
# lifetime of the file.

sub get_dynamic_content_indirect {
    my ($this,$module,$modargs,$option,$indlink) = @_;
    my $stat = $this->run_handler("get_dynamic_content_indirect",$module,$modargs,$option,$indlink);
    return $stat if (defined $stat);
    my $newtext;
    my $ml = new ExSite::ML;
    if ($option->{method} =~ /dummy-module/ || $option->{expand}) {
	my $icon = "$config{server}{HTMLpath}/_Modules/$module/icon.gif";
	if (! -e "$config{server}{HTMLroot}$icon") {
	    $icon =~ s/\.gif$/\.png/;
	}
	if (! -e "$config{server}{HTMLroot}$icon") {
	    # no icon; use default ExSite app icon
	    $icon = "$config{server}{HTMLpath}/_Modules/icon.gif";
	}
	$newtext = $ml->img(undef,{alt=>"&${indlink}$module($modargs)",
				   src=>$icon,
				   title=>"&${indlink}$module($modargs)",
				   name=>"&${indlink}$module($modargs)",
				   border=>3,
				   style=>"border-style:outset;"});
    }
    else {
	if (! $this->can("is_page") || ! $this->is_page) {
	    # we're probably in some special mode such as a preview or
	    # search index routine, in which case AJAX is not appropriate
	    return $ml->Comment("AJAX call to $module ignored");
	}
	my $ref;
	if ($this->is_publishing) {
	    # referrer isn't really publish.cgi; should probably be page.cgi
	    my $pid = $this->id("page");
	    # note escaped ?
	    $ref = "$config{server}{CGIpath}/$config{prog}{page}%3f_id=$pid";
	}
	else {
	    $ref = &url_escape($ENV{REQUEST_URI});
	}
	my $il = $indlink ? "_ajax=$module&" : "";
	$modargs = &url_escape($modargs);
	if ($config{content}{ajax_method} eq "dispatch") {
	    # dispatch script will be appended at end of page
	    $modargs =~ s/=/%3D/g;
	    my $target = $module . "_dispatch" . &randname();
	    $share{dispatch}{"$module:$target"} = $modargs;
	    $newtext .= $ml->div(
		$ml->noscript("(You must have javascript enabled to view $module.)"),
		{ id=>$target }
		);
	}
	else {
	    $newtext = $ml->script(undef,{type=>"text/javascript",
				      src=>"$config{server}{server}$config{server}{HTMLpath}/_ExSite/js/httprequest.js"});
	    $newtext .= $ml->div(
		$ml->script("<!--//
document.write(
getRequestDataAsync('$config{server}{CGIpath}/$config{prog}{app}/$module?_opt=$modargs&${il}_ref=$ref','$module'));
//-->", { type=>"text/javascript" }).
		$ml->noscript("(You must have javascript enabled to view $module.)"),
		{ id=>$module }
		);
	}
    }
    return $newtext;
}

sub get_dynamic_content_indirect_old {
    my ($this,$module,$modargs,$option,$indlink) = @_;
    my $newtext;
    my $ml = new ExSite::ML;
    if ($option->{method} =~ /dummy-module/ || $option->{expand}) {
	my $icon = "$config{server}{HTMLpath}/_Modules/$module/icon.gif";
	if (! -e "$config{server}{HTMLroot}$icon") {
	    $icon =~ s/\.gif$/\.png/;
	}
	if (! -e "$config{server}{HTMLroot}$icon") {
	    # no icon; use default ExSite app icon
	    $icon = "$config{server}{HTMLpath}/_Modules/icon.gif";
	}
	$newtext = $ml->img(undef,{alt=>"&${indlink}$module($modargs)",
				   src=>$icon,
				   title=>"&${indlink}$module($modargs)",
				   name=>"&${indlink}$module($modargs)",
				   border=>3,
				   style=>"border-style:outset;"});
    }
    else {
	if ((ref $this) !~ /Page/) {
	    # we're probably in some special mode such as a preview or
	    # search index routine, in which case AJAX is not appropriate
	    return $ml->Comment("AJAX call to $module ignored");
	}
	my $ref;
	if ($this->is_publishing) {
	    # referrer isn't really publish.cgi; should probably be page.cgi
	    my $pid = $this->id("page");
	    # note escaped ?
	    $ref = "$config{server}{CGIpath}/$config{prog}{page}%3f_id=$pid";
	}
	else {
	    $ref = &url_escape($ENV{REQUEST_URI});
	}
	my $il = $indlink ? "_ajax=$module&" : "";
	$modargs = &url_escape($modargs);	
	$newtext = $ml->script(undef,{type=>"text/javascript",
				      src=>"$config{server}{server}$config{server}{HTMLpath}/_ExSite/js/httprequest.js"});
	$newtext .= $ml->div(
			$ml->script("<!--//
document.write(
getRequestDataAsync('$config{server}{CGIpath}/$config{prog}{app}/$module?_opt=$modargs&${il}_ref=$ref','$module'));
//-->", { type=>"text/javascript" }).
			     $ml->noscript("(You must have javascript enabled to view $module.)"),
			     { id=>$module }
			     );
    }
    return $newtext;
}

# get_start_html: get the block of HTML used to seed the page

sub get_start_html {
    my ($this,$content) = @_;
    my $stat = $this->run_handler("get_start_html",$content);
    return $stat if (defined $stat);
    my $p = $this->my_page;
#    if ($this->subtype_attr("revtype") eq "template") {
    if ($this->displaytype eq "template") {
	# our revision serves as a custom template
	my $prev = $p->revision();
	if ($prev->defined && $prev->getdata("content_id") == $p->id) {
	    return $prev->get_html();
	}
    }
    my $t = $this->template();
    return $t->defined ? 
	$t->get_start_html($content) : 
	$this->warn($this->label().": no template found.");
}

# get_html : return html for current revision, view
# use show() for user-facing functions

sub get_html {
    my $this = shift;
    return $this->has_revisions() ? $this->revision->get_html : undef;
}

# get_raw : return raw content, regardless of mime-type

sub get_raw {
    my $this = shift;
    return $this->has_revisions() ? $this->revision->get_raw : undef;
}

#------------------------------------------------------------------------------
# get_url : gets the current best URL for the object

sub get_url {
    my $this = shift;
    my $url = $this->get_hardcoded_url();
    return $url if ($url);
    return $this->was_published ?
	$this->get_url_static() :
	$this->get_url_dynamic();
}

# get_url_dynamic : recommended dynamic content view for this content type

sub get_url_dynamic {
    my ($this,$method) = @_;
    if (! $method) { 
	$this->get_subtypes();
	$method = $share{content}{isubtype}{$this->getdata("type")}{displaytype} eq "formatted" ? "page" : "view";
    }
    return $method eq "view" ? 
	$this->get_view_url_dynamic() : 
	$this->get_page_url_dynamic();
}

# get_view_url_dynamic : dynamic URL to view the raw/bare content

sub get_view_url_dynamic {
    my $this = shift;
    my $url = $this->getdata("url");
    return $url if ($url); # content has a fixed URL
    return "$config{server}{CGIpath}/$config{prog}{view}".$this->path;
}

# same as above, but tries to wrap the content up in a complete page

sub get_page_url_dynamic {
    my $this = shift;
    my $url = $this->getdata("url");
    return $url if ($url); # content has a fixed URL
    return "$config{server}{CGIpath}/$config{prog}{page}".$this->path();
}

# get_url_static : always return a static URL 
# (even if content is not static - url may not work in this case!)

sub get_url_static {
    my $this = shift;
    my $url = $this->get_hardcoded_url();
    return $url if ($url);
    $url = $this->httppath();
    my $filename = $this->filename();
    if ($filename && $filename !~ /^index\.html$/) {
	$url .= "/$filename";
    }
    my $section = $this->my_section();
    if ($section && $section->is_standalone) {
	# use full urls for standalone sites
	$url = $section->get_server().$url;
    }
    return $url ? $url : "/";
}

# permalink : the permalink is the best user-friendly navigation URL to use
# Permalinks can be relative, and can redirect.

sub permalink { 
    my $this = shift;
    my $url = $this->get_hardcoded_url();
    return $url if ($url);
    # always return a relative static URL; 
    # meta-redirects will take care of dynamic content
    $url = $this->httppath();
    my $filename = $this->filename();
    if ($filename && $filename !~ /^index\.html$/) {
	$url .= "/$filename";
    }
    return $url;
}

# get_url_canonical : the canonical URL is the permanent direct URL
# Canonical links must be absolute and direct.

### FIXME: canonical urls can point off site; but they are used by search, navpath, link

sub get_url_canonical {
    my $this = shift;
    return $this->{canonical_url} if ($this->{canonical_url});

    my $url = $this->get_hardcoded_url();
    return $url if ($url);

    # manual override (useful if the url points off-site)
    if (exists $config{content}{metadata}{$this->subtype()}{canonical}) {
	# manual canonical override is supported for this content type
	my $metacanonical = $this->dcmeta("canonical");
	$this->{canonical_url} = $metacanonical;
	return $metacanonical if $metacanonical;
    }

    $url = $this->is_static ? $this->get_url_static : $this->get_url_dynamic;
    # canonical URLs should be complete
    if ($url =~ /^\w+:\/\//) {
	$this->{canonical_url} = $url;
	return $url;
    }
    my $s = $this->my_section();
    if ($s && $s->defined) {
	$url = $s->get_server() . $url;
    }
    else {
	$url = "$config{server}{server}$url";
    }
    $this->{canonical_url} = $url;
    return $url;
}

sub get_hardcoded_url {
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
    return undef;
}

# get_uri : get a URI object for the dynamic URL
# you can override the default, using $c->set("URI",$uri);

sub get_uri {
    my $this = shift;
    if (! $this->{URI}) {
	my $url = $this->get_url_dynamic(@_);
	$this->{URI} = new ExSite::URI();
	$this->{URI}->setup($url);
    }
    return $this->{URI};
}

# get_page_uri : get a page-like URI object for the dynamic URL

sub get_page_uri {
    my $this = shift;
    my $url = $this->get_page_url_dynamic(@_);
    my $uri = new ExSite::URI();
    $uri->setup($url);
    return $uri;
}

# link : like get_url, but allow for passing additional dynamic 
# parameters; if there are no alterations to the url, use the 
# canonical url.
#
# On admin views, set $this->{content_link_type} to "id" to get
# ctrl-panel type links. Use the __page=>1 parameter to override this
# (eg. if generating a page link from a control panel).

sub link {
    my ($this,%args) = @_;
    my $canonical;
    my $url;
    if ($args{__uri}) {
	# custom context passed to us
	$url = $args{__uri};
    }
    elsif ($this->{URI}) {
	# custom context in object
	$url = $this->{URI};
    }
    elsif ($share{Page} || $args{__page}) {
	# viewing from within a page
	$canonical = ! $args{__dynamic};
	if ($this->revision->view->mime_type =~ /^text\/(html|plain)/) {
	    # try to inline the content into a page-like presentation
	    $url = $this->get_page_uri();
	}
	else {
	    $url = $this->get_uri();
	}
    }
    else {
	# other context (admin or dynamic view) - use current dynamic URL
	$url = new ExSite::URI();
	if ($this->{content_link_type} eq "id") {
	    $url->parameter("id",$this->id);
	}
    }
    if ($args{__plaintext}) {
	$url->plaintext();
    }
    if ($args{__path}) {
	foreach my $key (keys %{$args{__path}}) {
	    $url->path($key,$args{__path}{$key});
	    $canonical = 0;
	}
    }
    if ($args{__clear}) {
	my $query_data = $url->get("query_data");
	if ($query_data) {
	    foreach my $key (keys %$query_data) {
		$url->parameter($key,undef);
	    }
	}
    }
    foreach my $param (keys %args) {
	# __* are not actual url parameters
	delete $args{$param} if ($param =~ /^__/);
    }
    if (scalar keys %args) {
	$url->query(%args);
	$canonical = 0;
    }
    ## FIXME: what if canonical points to an external url?
    return $canonical ? $this->get_url_canonical : $url->write;
}

# admin_url: try to find an appropriate plug-in app that can manage this 
# content, and return its URL

sub admin_url {
    my $this = shift;
    my $plugin = $this->subtype_attr("plugin");
    my $id = $this->id;
    if ($plugin) {
	$plugin =~ /(\w+)$/;
	my $modname = $1;
	return &launcher_link($modname,"id=$id");
    }
    elsif ($this->defined) {
	return &launcher_link("CMS","_bare=3&id=$id");
    }	
    return undef;
}

#-------------------------------------------------------------------------------
# revise: add a revision to the content
#
# Options:
# data [required] = the revision data
# format [required] = text, file, url, path
# mime_type 
# note
# view.NAME = flag to generate that view (if an image), or view record
# status (defaults to approved)
# force = add the revision, even if blank

sub revise {
    my ($this,%opt) = @_; #$rev,$data,$view) = @_;
#    $this->info("in Content::revise");
    if (! $opt{data} && ! $opt{force}) {
	$this->error("cannot make revision without any content");
	return undef;
    }
    if (! $opt{format}) {
	$this->error("unspecified revision format");
	return undef;
    }
#    if ($this->subtype_attr("revtype") eq "none") {
#	$this->error("you cannot revise/update a(n) ".$this->subtype);
#	return undef;
#    }
    $opt{status} or $opt{status} = 0; # default to published, can set to draft

    # make revision object
    my $rev = {
	content_id => $this->id,
	mime_type => $opt{mime_type},
	uid => $share{DB}->my_uid || "0",
	note => $opt{note},
	status => $opt{status},
    };
    my $r = new ExSite::Revision(data=>$rev);
#    $this->info("revision object made");

    # make normal view object
    my %attr = $opt{attributes} ? %{$opt{attributes}} : ();
    my $cview = {
	data => $opt{data},
	mime_type => $opt{mime_type},
	'format' => $opt{format},
	attributes => &EncodeAttributes(%attr),
    };

    # fill in missing revision data
    if (! $cview->{mime_type}) {
	my $mime_type = $rev->{mime_type} || &guess_MimeType($opt{data},$opt{format});
	$cview->{mime_type} = $mime_type;
	if (! $rev->{mime_type}) {
	    $r->setdata("mime_type",$mime_type);
	}
    }
    if (! $rev->{note}) {
	$rev->{note} = "inserted by " . $share{DB}->my_name . " using " . ref $this;
    }

    # save revision
#    $this->info("saving revision");
    my $revision_id = $r->save;
    if (! $revision_id) {
#	$this->info("failed to save revision");
	$this->error("failed to add new revision: ".
		     $share{DB}->show_diagnostics("error"));
	return undef;
    }
    $cview->{revision_id} = $revision_id;
    return $revision_id if (! $opt{data}); # no actual content to install

    # make views

    my $view = $opt{view};
    my ($img,$imgdim,$imgsize,$filename);
    if ($cview->{mime_type} =~ /^image/) {
	$img = new ExSite::Image($cview->{data});
	$filename = $img->get("filename");
	$imgsize = $img->size;
	if ($imgsize > $config{form}{bigfile_maxsize}) {
	    # filesize too large for storing as a revision
	    # make web-friendly optimizations
	    $img->jpeg;
	    $imgsize = $img->size;
	}
	if ($imgsize > $config{form}{bigfile_maxsize} && ! $config{content}{install_files}) {
	    # filesize still too large for storing as a revision
	    # shrink it
	    $img->shrink(size=>$config{form}{bigfile_maxsize},
			 dim=>$config{content}{viewdim}{large});
	    # redo dimensions
	    $imgsize = $img->size;
	    my ($x,$y) = $img->dim;
	    $imgdim = $x > $y ? $x : $y;
	    $attr{height} = $y;
	    $attr{width} = $x;
	}
	else {
	    my ($x,$y);
	    if ($attr{width} && $attr{height}) {
		$x = $attr{width};
		$y = $attr{height};
	    }
	    else {
		($x,$y) = $img->dim();
	    }
	    $imgdim = $x > $y ? $x : $y;
	}
    }
    my %install_view;

    # large view

    if ($view->{large} == 1) {
	if ($img) {
	    if ($imgdim > $config{content}{viewdim}{normal} * 1.2) {
		# proceed with large view if at least 20% larger than 
		# ideal normal size
		if ($imgdim > $config{content}{viewdim}{large}) {
		    # oversize; auto-scale to large size
		    $img->scale($config{content}{viewdim}{large},$config{content}{viewdim}{large},-1);
		    $imgsize = $img->size;
		    my ($x,$y) = $img->dim;
		    $imgdim = $x > $y ? $x : $y;
		    $attr{height} = $y;
		    $attr{width} = $x;
		}
		$img->set("filename",$config{content}{viewprefix}{large}.$filename);
		$cview->{data} = $img->encode();
		$cview->{attributes} = &EncodeAttributes(%attr);
		$cview->{type} = "large";
		$install_view{large} = &clone($cview);
	    }
	}
    }
    elsif (ref $view->{large} eq "HASH") {
	$install_view{large} = $view->{large};
    }

    # normal view

    if ($view->{normal} == 1 && # do not rescale if explicit view was passed to us
	$img && $imgdim > $config{content}{viewdim}{normal}) {
	# oversize; auto-scale to normal size
	$img->scale($config{content}{viewdim}{normal},$config{content}{viewdim}{normal},-1);
	$imgsize = $img->size;
	my ($x,$y) = $img->dim;
	$imgdim = $x > $y ? $x : $y;
	$img->set("filename",$config{content}{viewprefix}{normal}.$filename);
	$cview->{data} = $img->encode();
	$attr{height} = $y;
	$attr{width} = $x;
	$cview->{attributes} = &EncodeAttributes(%attr);
    }
    $cview->{type} = "normal";
    $install_view{normal} = &clone($cview);
    my $normaldim = $imgdim;

    # small view

    if ($img && $view->{small} == 1) {
	if ($imgdim > $config{content}{viewdim}{small}) {
	    $img->scale($config{content}{viewdim}{small},$config{content}{viewdim}{small},-1);
	    $imgsize = $img->size;
	    my ($x,$y) = $img->dim;
	    $imgdim = $x > $y ? $x : $y;
	    $attr{height} = $y;
	    $attr{width} = $x;
	    $img->set("filename",$config{content}{viewprefix}{small}.$filename);
	    $cview->{data} = $img->encode();
	    $cview->{attributes} = &EncodeAttributes(%attr);
	    $cview->{type} = "small";
	}
	if ($imgdim < $normaldim) {
	    # only install small view if different in size from normal view
	    $install_view{small} = &clone($cview);
	}
    }
    elsif (ref $view->{small} eq "HASH") {
	$install_view{small} = $view->{small};
    }
    # thumbnail view 

    if ($img && $view->{thumbnail} == 1) {
	if ($imgdim > $config{content}{viewdim}{thumbnail}) {
	    $config{thumbnail_type} eq "square" ? $img->square_thumb : $img->thumb;
	    $imgsize = $img->size;
	    my ($x,$y) = $img->dim;
	    $imgdim = $x > $y ? $x : $y;
	    $img->set("filename",$config{content}{viewprefix}{thumbnail}.$filename);
	    $cview->{data} = $img->encode();
	    $attr{height} = $y;
	    $attr{width} = $x;
	    $cview->{attributes} = &EncodeAttributes(%attr);
	    $cview->{type} = "thumbnail";
	}
	$install_view{thumbnail} = &clone($cview);
    }
    elsif (ref $view->{thumbnail} eq "HASH") {
	$install_view{thumbnail} = $view->{thumbnail};
    }

    # icon view

    if (ref $view->{icon} eq "HASH") {
	$install_view{icon} = $view->{icon};
    }
    elsif ($view->{icon} == 1) {
	if ($img) {
	    if ($imgdim > $config{content}{viewdim}{icon}) {
		$img->scale_crop($config{content}{viewdim}{icon},$config{content}{viewdim}{icon});
		$img->set("filename",$config{content}{viewprefix}{icon}.$filename);
		$cview->{data} = $img->encode();
		$attr{height} = $config{content}{viewdim}{icon};
		$attr{width} = $config{content}{viewdim}{icon};
		$cview->{attributes} = &EncodeAttributes(%attr);
		$cview->{type} = "icon";
	    }
	    $install_view{icon} = &clone($cview);
	}
    }

    # now install all views

    foreach my $vtype (qw(large normal small thumbnail icon)) {
	if ($install_view{$vtype}) {
	    my $data = $install_view{$vtype};
	    if (! $data->{revision_id}) {
		$data->{revision_id} = $revision_id;
	    }
	    if (! $data->{type}) {
		$data->{type} = $vtype;
	    }
	    my $v = new ExSite::View(data=>$data);
	    $v->install() if ($config{content}{install_files});
	    if (! $v->save()) {
		$this->error("failed to add $vtype view: ".
			     $share{DB}->show_diagnostics("error"));
	    }
	}
    }
    # Note: you might need to call load_revision() to see the new rev

    return $revision_id;
}

sub new_content_obj {
    my ($this,%opt) = @_;
    my $title = $opt{title} || $opt{label} || $opt{name};
    my $label = $opt{label} || $opt{title} || $opt{name};
    my $type;
    if ($opt{type}) {
	$type = $opt{type} =~ /^\d+$/ ? $opt{type} : $this->isubtype($opt{type});
    }
    else {
	$type = $this->isubtype("content");
    }
    my $parent = $opt{parent};
    if (! $parent) {
	if ($this->exists) {
	    # new content is child of current object
	    $parent = $this->id;
	}
	else {
	    # new content is child of our site
	    my $site = $share{DB}->this_site();
	    if (ref $site) {
		$parent = $site->{content_id};
	    }
	}
    }
    my %cnode = (
	type=>$type,
	title=>$title,
	label=>$label,
	name=>$opt{name} || &make_name($label),
	parent=>$parent,
	template=>$opt{template} || 0,
	access=>$opt{access} || 0,
	content_role=>$opt{content_role} || "editorial",
	publish=>$opt{publish}, # || "static",
	status=>$opt{status} || 0,
	hide=>$opt{hide},
	sortkey=>$opt{sortkey},
	ctime=>undef
	);
    my $c = new ExSite::Content(data=>\%cnode);
    $c->{content_id} = $c->insert();
    #my $tree = $this->get_content_tree();
    #$tree->addnode(\%cnode);
    return $c;
}

sub new_content {
    my ($this,%opt) = @_;
    my $c = $this->new_content_obj(%opt);
    return wantarray ? %{$c->get()} : $c->id;
}

sub new_feature {
	return undef;
}

# install - place files in the fileroot

sub install {
    my ($this,$file,$mime,$view) = @_;
    $view or $view = "normal";
    #$file or $file = %ENV{EXSITE_INSTALL_FILE};
    return 0 if !$file;
    if ($file !~ /\//) {
	$file .= $config{server}{temppath}."/".$file;
    }
    return 0 if (! -e $file);
    #### untaint $file

    # load file to mem
    my $data;
    open F, "<$file";
    my $size = 0;
    my $continue = 1;
    while ($continue) {
	$continue = read(F,$data,1024,$size);
	$size += $continue;
    }
    $ENV{CONTENT_LENGTH} = $size;
    close F;

    my $path = $this->datapath();
    my $filename = $view . "." . &MimeToFile($mime);

    my $f = new ExSite::Diskfile(base=>$config{server}{dataroot},
				 path=>$path,
				 filename=>$filename,
				 contents=>$data,
				 mimetype=>$mime);
    $f->publish();
    # errorcheck?

    # remove tmp file
    unlink($file);

    return "$path/$filename";
}

# install2 - install a file from /tmp

sub install2 {
    my ($this,$file,$mime,$view) = @_;
    $view or $view = "normal";
    return 0 if !$file;
    if ($file !~ /\//) {
	$file .= $config{server}{temppath}."/".$file;
    }
    return 0 if (! -e $file);
    #### untaint $file

    # load file to mem
    my $data;
    open F, "<$file";
    my $size = 0;
    my $continue = 1;
    while ($continue) {
	$continue = read(F,$data,1024,$size);
	$size += $continue;
    }
    $ENV{CONTENT_LENGTH} = $size;
    close F;

    my $path = $this->datapath();
    my $filename = $view . "." . &MimeToFile($mime);

    my $f = new ExSite::Diskfile(base=>$config{server}{dataroot},
				 path=>$path,
				 filename=>$filename,
				 contents=>$data,
				 mimetype=>$mime);
    $f->publish();
    # errorcheck?

    # remove tmp file
    unlink($file);

    return "$path/$filename";
}

# publish: write content to fast static files
# options:
# uid => publish as this UID (will fail if UID does not have permission)
# approve => publish as a UID that has publish permission

sub publish {
    my ($this,%opt) = @_;
    # do not publish if we came from an alias
    return undef if ($this->alias);

    # publishing can have a lot of recursive effects, so let's
    # remember which object we started from
    if (! exists $share{publish_content}) {
	$share{publish_content} = $this->id;
    }

    my $status = $this->wf_status;
    if ($status eq "approved" || 
	($status eq "draft" && $share{publish_content} == $this->id)) {
	# content has been approved for publishing, or 
	# we are explicitly publishing a draft item - update status
	$this->setdata("status",$this->wf_istatus("published"));
	$this->save();
    }
    elsif ($status !~ /published|archived/) {
	# do not publish
	return;
    }

    if (-w $config{server}{HTMLroot}) {
	# this is the true publisher process
	# in debug mode, we can sometimes have post data lying around that will confuse
	# the publisher
	delete $ENV{CONTENT_LENGTH};
	delete $ENV{CONTENT_TYPE};
	# proceed to write files
	$this->publish_content(%opt);
    }
    elsif ($ENV{SCRIPT_NAME} =~ /publish/) {
	# this is the publisher process, but we still don't have permission to write
	print $this->fatal("Publish: publish tool does not have permission to write to your documents area.");
	return;
    }
    else {
	# no write permissions - spawn a setuid publisher process
#	my $other;
	my $uid = $opt{uid};
	if (! $uid) {
	    if ($opt{approve}) {
		# preapproved operation - select an admin to publish as
		my $authority = $this->authority("administrator");
		if ($authority) {
		    $uid = $authority->{uid};
		}
	    }
	}
# this makes an authtoken, but use existing cookie
#	if (! $uid) {
#	    $uid = $share{DB}->my_uid;
#	}
	my %popt = (id=>$this->id,uid=>$uid,exec_method=>$opt{exec_method});
	foreach my $method (qw(self parent child)) {
	    $popt{$method} = $opt{$method} if (exists $opt{$method});
	}
	
#	my $id = $this->id;
#	my $publish_url = "$config{server}{CGIpath}/$config{prog}{publish}?id=$id";
#	my $authtoken = $share{DB}->make_authtoken($uid,0,$publish_url);
#	$other = {_auth=>$authtoken};
	&ExSite::Util::run_publisher(%popt);
    }
}

# publish_content: publish the selected content object, 
# plus contents, plus container

sub publish_content {
    my ($this,%opt) = @_;
    # do not publish if we came from an alias
    return undef if ($this->alias);

    $this->{publish} = 1;
    my $type = $this->my_subtype || "Content";
    my $ml = &get_obj("ML");
    print $ml->li("Publishing $type " . $ml->em($this->name));
    print "<ul>\n";

    # publish our contents
    if (! exists $opt{child} || $opt{child}) {
	$this->subpublish(%opt);
    }

    # publish our self
    if (! exists $opt{self} || $opt{self}) {
	$this->publish_self(%opt);
    }

    # publish our container
#    if ($opt{parent} || $this->navtype eq "item") {   ### is this better?
    if ($opt{parent} || $this->navtype ne "page") {
	$this->superpublish(%opt);
    }
    print "</ul>\n";

}

# publish_down: publish self and contents, not container
# use this for recursive publishing, so that we don't accidentally republish
# containers over and over

sub publish_down {
    my ($this,%opt) = @_;
    return undef if ($this->alias);
    $this->{publish} = 1;
    my $type = $this->my_subtype || "Content";
    my $ml = &get_obj("ML");
    print $ml->li("Publishing $type " . $ml->em($this->name));
    print "<ul>\n";
    # publish subnodes
    $this->subpublish(%opt);
    # publish this node
    $this->publish_self(%opt);
    print "</ul>\n";
}

# publish_self: publish this node only

sub publish_self {
    my ($this,%opt) = @_;
    # do not publish if we came from an alias
    return undef if ($this->alias);

    $this->{publish} = 1;

    # publish self
    if ($this->is_publishable) {
	$_ = $this->displaytype;
	if (/raw/) {
	    $this->publish_raw(%opt);
	}
	elsif (/formatted/) {
	    $this->publish_formatted(%opt);
	}
    }

    if ($this->publish_rule ne "never") {
	if ($this->getdata("ptime") =~ /^0/) {
	    # first time - set the ptime
	    $share{DB}->update("content",
			       {ptime=>undef},
			       {content_id=>$this->id()});
	}
    }

    if ($share{publish_content} != $this->id) {
	# publishing related files; we're probably done with the object data
	# try to unload to save memory
	$this->unload();
	$share{DB}{diagnostics}{info} = [];
    }
}

# publish_raw: publish revision directly

sub publish_raw {
    my ($this,%opt) = @_;
    $this->load_revision("newest");

    ### FIXME set basedir???

    $this->revision->publish(%opt);
    $this->revision->unload();
}

sub unpublish_raw {
    my ($this,%opt) = @_;
    $this->revision->unpublish(%opt);
    $this->revision->unload();
}

# publish_formatted: publish the content within a template

sub publish_formatted {
    my ($this,%opt) = @_;
    #my $ml = &get_obj("ML");

    # set the version/language
    (tied %msg)->language($this->getdata("language"));
    # rebuild environment as if we were viewing this page
    $this->update_env();  # resets share, among other things

    #print $ml->li("Publishing ".$this->subtype()." ".$ml->em($this->name));
    #print "<ul>\n";

    # we are not a page, but we need a page context to get certain features
    # (such as menus).
    my $orig_page = $share{Page};
    $share{Page} = $this->my_page();
    my $diskfile = new ExSite::Diskfile( base => $this->basedir,
					 path => $this->subdir,
					 filename => $this->filename,
					 contents => $this->show_templated() );
    $diskfile->last_modified($this->last_modified());
    $diskfile->publish($opt{force});
    $diskfile->clear;
    #print "</ul>\n";
    $share{Page} = $orig_page if $orig_page;
}

sub unpublish_formatted {
    my ($this,%opt) = @_;
    my $diskfile = new ExSite::Diskfile( base => $this->basedir,
					 path => $this->subdir,
					 filename => $this->filename );
    $diskfile->unpublish();
}

# publish_contents: publish child content nodes

sub publish_contents { &subpublish(@_); }
sub subpublish {
    my ($this,%opt) = @_;
    #return if (exists $opt{contents} && ! $opt{contents}); # turned off on this call
#    my $subpubrule = $share{content}{isubtype}{$this->getdata("type")}{subpublish};
#    return if ($subpubrule eq "none"); # turned off for this type
    my $clist = $this->get_contents_as_list();
    while (my $node = $clist->next) {
#	# only follow content if it matches the subpublish rule
#	if ($subpubrule ne "all") {
#	    my $navtype = $node->navtype;
#	    next if ($subpubrule eq "page" && $navtype eq "item");
#	    next if ($subpubrule eq "item" && $navtype eq "page");
#	    next if ($subpubrule eq "other" && $navtype =~ /item|page/);
	    next if ($node->type eq "section");
#	}
	# check wf status
	my $status = $node->wf_status;
	if ($status eq "approved") {
	    # content has been approved for publishing
	    $node->setdata("status",$node->wf_istatus("published"));
	    $node->save();
	}
	#elsif ($status !~ /published/) {   # don't republish archived content
	elsif ($status !~ /published|archived/) {
	    # do not publish (FIXME: what about force?)
	    next;
	}
	$node->publish_down(%opt);
    }
    # RSS - lists all contents with "item" navtype
    if ($this->is_publishable && $this->is_subdir) {
	my $rssdata = $this->rss;
	if ($rssdata) {
	    my $ml = &get_obj("ML");
	    my $diskfile = new ExSite::Diskfile( base => $this->basedir,
						 path => $this->subdir,
						 filename => "index.rss",
						 contents => $rssdata );
	    print $ml->li("Publishing RSS");
	    $diskfile->publish($opt{force});
	    $diskfile->clear;
	}
    }
}

# superpublish: publish parent object

sub superpublish {
    my ($this,%opt) = @_;
    #return if ($this->navtype eq "page"); # superpublish items, content only
    #return if ($this->subtype eq "section"); # redundant
    $this->parent->publish_self();
    return;
}

# publish_up : publish self and ancestors up to the current section

sub publish_up {
    my ($this,%opt) = @_;
    my $c = $this;
    while ($c) {
	$c->publish_self();
	$c = $c->subtype eq "section" ? undef : $c->parent;
    }
    return;
}

# publish_redirect : publish a file that redirects to the dynamic object

sub publish_redirect {
    my $this = shift;
    if (! $this->is_publishable) {
	my $diskfile = new ExSite::Diskfile( base => $this->basedir,
					     path => $this->subdir,
					     filename => $this->filename,
					     contents => $this->redirect_to_dynamic() );
	$diskfile->publish();
	$diskfile->clear;
    }
}

sub unpublish {
    my ($this,%opt) = @_;
    # do not publish if we came from an alias
    return undef if ($this->alias);
    my $ml = &get_obj("ML");

    # publishing can have a lot of recursive effects, so let's
    # remember which object we started from
    if (! exists $share{publish_content}) {
	$share{publish_content} = $this->id;
    }

    if (-w $config{server}{HTMLroot}) {
	# we have authorization to write into the HTMLdocs area
	$this->unpublish_content(%opt);
    }
    elsif ($ENV{SCRIPT_NAME} =~ /publish/) {
	# oops, fork bomb!
	# we're already running the publisher process, but we still don't 
	# have permission to write
	print $this->fatal("Publish: publish tool does not have permission to write to your documents area.");
	return;
    }
    else {
	# no write permissions - spawn a publisher process
	my $uid = $opt{uid};
	if (! $uid) {
	    if ($opt{approve}) {
		# preapproved operation - select an admin to publish as
		my $authority = $this->authority("administrator");
		if ($authority) {
		    $uid = $authority->{uid};
		}
	    }
	}
	if (! $uid) {
	    $uid = $share{DB}->my_uid;
	}
	my %popt = (unpublish=>1,id=>$this->id,uid=>$uid,exec_method=>$opt{exec_method});
	foreach my $method (qw(self parent child)) {
	    $popt{$method} = $opt{$method} if (exists $opt{$method});
	}
	&ExSite::Util::run_publisher(%popt);
    }
    return;
}

sub unpublish_content {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");

    # authorize/authenticate ??

    if (! exists $opt{child} || $opt{child}) {
	# remove all subnodes
	my $start;
	foreach my $node ($this->get_contents()) {
	    if (! $start) { 
		print "<ul>\n";
		$start = 1;
	    }
	    $node->unpublish_content();
	}
	if ($start) { print "</ul>\n"; }
    }

    if (! exists $opt{self} || $opt{self}) {
	# unpublish self
	my $type = $this->my_subtype || "Content";
	print $ml->li("Removing $type " . $ml->em($this->name));

	$_ = $this->displaytype;
	if (/raw/) {
	    $this->unpublish_raw();
	}
	elsif (/formatted/) {
	    $this->unpublish_formatted();
	}

	# remove our own directory

	if ($this->is_subdir) {
	    my $subdir = $this->my_subdir();
	    if ($subdir) {  # will ignore anonymous root
		my $df = new ExSite::Diskfile(base=>$this->basedir,path=>$this->subdir); # has rmdir()
		my $dir = $this->diskpath();
		if ($dir =~ /^(.+)\/$subdir/) {
		    $dir = $1;
		    # $dir is now the path up to the parent - remove everything
		    # below this
		    my @subdir = split /\//, $subdir;
		    while (my $sdir = pop @subdir) {
			my $rmdir = (scalar @subdir) ?
			    "$dir/" . join("/",@subdir) . "/$sdir" :
			    "$dir/$sdir";
			my $rm = $df->rmdir($rmdir);
			print $rm ? $rm : $df->show_diagnostics("error","html");
		    }
		}
		else {
		    print $this->warn("cannot remove $subdir - not part of $dir");
		}
	    }
	}
    }

# FIXME: should we do this?
#	# republish parent?
#	if ($opt{parent} || $this->navtype ne "page") {
#	    # print a message?
#	    $this->superpublish();
#	}

}

# has the latest revision of this page's content been published?

### warning: this only gives accurate results for normal pages
### warning: as a check to see if we need to publish, this may be
###          costlier than just publishing

sub is_published { 
    my $this = shift;
    if ($this->is_static) {
    
	# the page timestamp is a MySQL timestamp
	my $time = $this->timestamp;
	$time =~ /^(....)(..)(..)(..)(..)(..)$/;
	my ($y1,$M1,$d1,$h1,$m1,$s1) = ($1,$2,$3,$4,$5,$6);

	# the published file has a Unix timestamp
	my @stat = stat($this->diskpath);
	my ($s2,$m2,$h2,$d2,$M2,$y2,undef,undef,undef) = 
	    localtime $stat[9]; # ie. mtime
	$M2 += 1;
	$y2 += 1900;
    
	# compare the two timestamps;  return TRUE if the published
	# file is older than the page data

	if    ($y2 < $y1) { return 0; }
	elsif ($y2 > $y1) { return 1; }

	elsif ($M2 < $M1) { return 0; }
	elsif ($M2 > $M1) { return 1; }

	elsif ($d2 < $d1) { return 0; }
	elsif ($d2 > $d1) { return 1; }

	elsif ($h2 < $h1) { return 0; }
	elsif ($h2 > $h1) { return 1; }

	elsif ($m2 < $m1) { return 0; }
	elsif ($m2 > $m1) { return 1; }

	elsif ($s2 < $s1) { return 0; }
	elsif ($s2 > $s1) { return 1; }

    }
    return 0;
}

# was_published: is the object's file present on the disk?

sub was_published { 
    my $this = shift;
    if ($this->is_static) {
	return (-e $this->diskpath."/".$this->filename);
    }
    return undef;
}

# does this content ever get published?
# static - content publishes to static file
# dynamic - content is always rendered dynamically
# hourly, daily, weekly - content republishes itself on intervals
# never - content is not published

sub publish_rule {
    my $this = shift;
    my $typerule = $this->subtype_attr("publish");
    return $typerule if ($typerule eq "never"); # cannot override never
    my $publish_rule = $this->getdata("publish");
    return $publish_rule if ($publish_rule);
    # if we get here, there is no explicit publish rule; 
    # use heuristics to figure out something appropriate
    return $this->publish_rule_heuristic();
}

# use heuristics to guess an appropriate publish rule
sub publish_rule_heuristic {
    my $this = shift;
    # restricted-access content should be dynamic
    return "dynamic" if (! $this->is_public());
    my $publish_rule;
    if ($this->has_revisions()) {
	if ($this->revision->mime_type() eq "text/html") {
	    # html content might contain plugins
	    my $html = $this->revision->get_html();
	    while ($html =~ /<\!--\&{1,3}(\w+)\((.*?)\)-->/) {
		# contains plug-in content - see if plug-in declares a publish rule
		my $mod = &get_module($1);
		if ($mod) {
		    my $modpubrule = $mod->ioctl("PublishRule") || "daily";
		    if ($modpubrule eq "dynamic") {
			return $modpubrule; # contains dynamic plugin module content
		    }
		    elsif ($modpubrule =~ /ly$/) {
			# interval
			$publish_rule = $modpubrule if ($publish_priority{$modpubrule} < $publish_priority{$publish_rule});
		    }
		    elsif (! defined $modpubrule) {
			# module does not declare whether it is dynamic
			# default to interval publishing to be safe
			if ($publish_rule ne "hourly") {
			    $publish_rule = "daily";
			}
		    }
		}
		$html =~ s/<\!--\&{1,3}\w+\(.*?\)-->//g; # remove module
	    }
	}
    }
    return $publish_rule || $this->subtype_attr("publish") || "static";
}

# check for publish rule mismatches (not necessarily a problem, but might be 
# worth warning the admin about)
sub check_publish_rule {
    my ($this) = @_;
    my $publish = $this->getdata("publish");
    if ($publish) {
	my $hpublish = $this->publish_rule_heuristic();
	if ($publish ne $hpublish) {
	    my $type = $this->subtype();
	    if ($publish_priority{$publish} > $publish_priority{$hpublish}) {
		# we've overriden the heuristic with a LESS urgent publish rule
		return $this->warn("This $type is set for $publish publishing, but that means that visitors may not see changes when they occur. Consider using $hpublish publishing for more timely output.");
	    }
	    elsif ($publish_priority{$publish} < $publish_priority{$hpublish}) {
		# our publish rule could be less urgent
		return $this->warn("This $type is set for $publish publishing, but $hpublish publishing may give better perfomance and security.");
	    }
	}
    }
    return undef;
}

# not the same as is_static: is_publishable depends on workflow status
# (ie. it answers the question: can I publish this object NOW?)
sub is_publishable { 
    my $this = shift;
    return undef if ($this->access());
    return ($this->is_viewable && ($this->publish_rule !~ /never|dynamic/));
}

sub is_publishing { 
    my $this = shift;
    return $this->{publish};
}

sub is_publishing_this { # publish request was to publish this item specifically
    my $this = shift;
    return $this->{publish} && $share{publish_content} == $this->id;
}

# redirect_html - static pseudo-page that redirects to dynamic version of this content
sub redirect_to_dynamic {
    my ($this,$message) = @_;
    my $goto = $this->is_page ? $this->get_page_url_dynamic() : $this->get_url_dynamic();
    my $ml = &get_obj("ML");
    my $out = $ml->html(
	$ml->head(
	    $ml->meta(undef,{'HTTP-EQUIV'=>"Refresh",CONTENT=>"0;URL=$goto"})
	).
	$ml->body($message)
	);
    return $out;
}

# update the environment to so that it looks like Apache is serving a request for 
# this object (displayed as a page).
# We do this when generating complete pages for view, so that their 
# input bufs, self-referential links, etc. are appropriate to the page.

sub update_env {
    my $this = shift;

    # doctor the URI to spoof normal page generation
    my $uri = &get_obj("URI");
    $uri->setup($this->get_page_url_dynamic());
    $uri->use_input();
    
    # WARNING: tampering with environment to spoof normal 
    # page generation context;  this should make the input
    # buffers look like a normal page call.
    $ENV{SCRIPT_NAME} = $uri->get("script_name");
    $ENV{QUERY_STRING} = $uri->get("query");
    $ENV{PATH_INFO} = $uri->get("path_info");

    # save our input buffer state in case we need to restore it later
    $this->{input_save} = &clone($share{input});

    # clear and regenerate input buffers to force a 
    # reload from our spoofed environment
    &ExSite::Config::reset_share();
    my $in = new ExSite::Input;
    $in->query;
    $in->path_info;
    #$this->fix_path();

    return;
}

# undo the above changes

sub restore_env {
    my $this = shift;
    # restore original environment
    $ENV{SCRIPT_NAME} = $share{ENV}{SCRIPT_NAME};
    $ENV{QUERY_STRING} = $share{ENV}{QUERY_STRING};
    $ENV{PATH_INFO} = $share{ENV}{PATH_INFO};
    $ENV{REQUEST_METHOD} = $share{ENV}{REQUEST_METHOD};
    # restore original input buffers
    $share{input} = $this->{input_save};
    delete $this->{input_save};
    # clear any URI object that might be persisting with our old ENV
    delete $share{URI};
    return;
}

# the timestamp is the timestamp of the youngest revision in the 
# cnode or its descendants

sub timestamp {
    my $this = shift;
    my $timestamp;
    my $rev = $this->revision;
    if ($rev->getdata("content_id") == $this->id) {
	# this revision belongs to us (it might not in some cases,
	# eg. pages using a different template, untranslated content)
	$timestamp = $rev->getdata("ctime");
    }
    my $tree = $this->get_content_tree();
    my $cnode = new ExSite::Content();
    foreach my $child ($tree->get_child_data($this->id)) {
	my $childnode = $cnode->get_content_obj($child);
	if ($childnode->getdata("parent") == $this->id) {
	    # this revision belongs to us (it might not in some cases,
	    # eg. pages using a different template, untranslated content)
	    my $chtime = $childnode->timestamp;
	    $timestamp = $chtime if (! $timestamp || $chtime lt $timestamp);
	}
    }
    # WARNING: if timestamp is still undefined, that means the object
    # has no contents; but if you pass that "timestamp" to a Time 
    # object, it will initialize to the current time.
    return $timestamp;
}

# can_index: 
# undef for do not search
# 0 for permission denied
# -1 for searchable, but already done
# 1 for indexing should be done now

sub can_index {
    my $this = shift;

    # only index complete html docs by default
    my $disptype = $this->displaytype();
    return undef if ($disptype =~ /none|raw/);

    # do we index this subtype?
    my $type = $this->subtype();
    # FIXME: just overload can_index in that type
    return undef if ($config{search}{skip}{$type});

    # skip if user is not authorized to index
    return 0 if (! $this->allow("publish"));

    my $db = $share{DB};
    my $url = $this->get_url_canonical;
    my @searchurl = $db->fetch_match("searchurl",{url=>$url,section_id=>$this->my_section->id});
    if (! $this->is_active() || $this->hide_from("search")) {
	# should not be indexed
	if (@searchurl > 0) {
	    $this->audit("clearing defunct searchurl");
	    # looks like there is search data - remove it
	    $db->get_query("clear url from search index",$url);
	    # shouldn't be necessary, but there might be cruft:
	    $db->get_query("clear content from search index",$this->id);
	}
	return undef;
    }

    # skip if there have been no updates since last indexing
    my $last_update = $this->last_update;
    if (@searchurl == 1 && ($searchurl[0]{mtime} cmp $last_update) > 0) {
	if (exists $share{searchterm_counts}) {
	    return ($share{searchterm_counts}{$this->id} > 0) ? -1 : 1;
	}
	return -1;  # assume there is really a search index there
    }
    return 1;
}

sub search_index {
    my ($this,$search) = @_;
    my $ml = &get_obj("ML");
    my $br = $ml->br;
    my $name = $this->subtype." ".$ml->em($this->name);
    my $stat = $this->can_index();
    return "$name already indexed - skipping...$br" if ($stat < 0);
    if (! $stat) {
	return "$name - permission denied$br" if (defined $stat);
	return undef;
    }
    my $status = $this->getdata("status");

    my %content = (
	#name => $this->name, # usually just dupes the title
	title => $this->title,
	keywords => $this->keywords(),
	description => $this->dcmeta("description"), # not description(), since that may just dupe the body
	body => $this->get_html(),
	);
    my %weight = ( # weights are halved for non-active (eg. archived) content
	#name => 2,
	title => $status ? 5 : 10,
	keywords => $status ? 1 : 2,
	description => $status ? 1 : 2,
	body => 1,
	);
    $search->index_url(
	content => \%content,
	weight => \%weight,
	language => $this->language(),
	url => $this->get_url_canonical(),
	access => $this->getdata("access"),
	section_id => $this->my_section->id,
	content_id => $this->navtype =~ /page|item/ ? $this->id : $this->parent->id,
	type => $this->subtype(),
	);
    # $search->update() must be called by the caller
    return "indexed $name...$br\n";
}

# allow - test for permissions for various operations
# ops are:
# view - display the content (default)
# update - add a revision
# edit - configure the content
# insert - create new content
# copy - create new content by copying exsiting content
# delete
# publish, unpublish
# approve, reject, moderate
# post - post to the content

sub allow {
    my ($this,$op,$user) = @_;
    my $stat = $this->run_handler("content_allow",$op);
    return $stat if (defined $stat);
    if ($this->ok) {
	$op or $op = "view";
	$user or $user = $share{DB}->my_user;
    
	if ($op eq "view") {
	    return $this->allow_view($user);
	}
	elsif ($op eq "post") {
	    return $this->allow_post($user);
	}

	my $path = $this->content_path;
	my @key = $this->my_keyring();
	my $content_role = $this->content_role();
	if ($op eq "update") {
	    # adding a revision
	    if ($content_role eq "editorial") {
		foreach my $key (@key) {
		    return 1 if ($key->{role} =~ /editor/);
		}
	    }
	    elsif ($content_role eq "design") {
		foreach my $key (@key) {
		    return 1 if ($key->{role} =~ /designer/);
		}
	    }
	    elsif ($content_role eq "user") {
		my $home = $user->home();
		my $path = $this->content_path;
		$path->reset;
		while (my $node = $path->next) {
		    # we are a user if this our home area
		    return 1 if ($home->id == $node->id);
		    # or if we have a key of any type to the node
		    foreach my $key (@key) {
			return 1 if ($key->{content_id} == $node->id);
		    }
		}
	    }
	}
	elsif ($op eq "edit") {
	    # configuring content
	    foreach my $key (@key) {
		return 1 if ($key->{role} =~ /admin/);
	    }
	    if ($content_role eq "editorial") {
		foreach my $key (@key) {
		    return 1 if ($key->{role} =~ /editor/);
		}
	    }
	    elsif ($content_role eq "design") {
		foreach my $key (@key) {
		    return 1 if ($key->{role} =~ /designer/);
		}
	    }
	}
	elsif ($op =~ /^(insert|copy)$/) {
	    # creating content
	    foreach my $key (@key) {
		return 1 if ($key->{role} =~ /editor|designer|admin/);
	    }
	}
	elsif ($op eq "delete") {
	    foreach my $key (@key) {
		return 1 if ($key->{role} =~ /admin/);
	    }
	}
	elsif ($op =~ /publish/) {
	    # includes unpublish
	    foreach my $key (@key) {
		return 1 if ($key->{role} =~ /admin/);
	    }
	}
	elsif ($op =~ /^(approve|reject|moderate)$/) {
	    # moderation
	    foreach my $key (@key) {
		return 1 if ($key->{role} =~ /reviewer/);
	    }
	}
	else {
	    # unknown operation - allow for admins only
	    foreach my $key (@key) {
		return 1 if ($key->{role} =~ /admin/);
	    }
	}
    }
    return 0; 
}

sub allow_view {
    my ($this,$user) = @_;
    my $stat = $this->run_handler("content_allow_view");
    return $stat if (defined $stat);
    return 1 if ($this->is_publishing);
    $user or $user = $share{DB}->my_user;
    if ($this->is_viewable) {
	my $level = $user->level;
	return 1 if ($this->access <= $level);
	if ($level) {
	    # content is level-restriced, but we are not of a sufficient level
	    # - check for special keys that authorize us
	    if ($config{auth}{view_keys}) {
		# optional security feature - causes extra DB lookups
		my $allow = 0;
		foreach my $key ($this->my_keys($user->id)) {
		    return 0 if ($key->{type} eq "revoke");
		    $allow = 1;
		}
		return $allow;
	    }
	}
    }
    # if we get here, the content is not viewable by regular visitors
    if ($share{Page}) {
	# regular page view - allow only if CMS preview mode is enabled
	my $in = new ExSite::Input;
	my $q = $in->query();
	if ($q->{_cms}) {
	    # CMS preview enabled - check for appropriate role
	    my @key = $this->my_keyring();
	    foreach my $key (@key) {
		return 1 if ($key->{role}); # any role will do
	    }
	}
    }
    else {
	# admin preview
	if (! $user->is_visitor) {
	    # administrator	
	    my @key = $this->my_keyring();
	    foreach my $key (@key) {
		return 1 if ($key->{role}); # any role will do
	    }
	}
    }
    return undef;
}

sub deny {
    my ($this,$op) = @_;
    return ! $this->allow($op);
}

# is_member: is the current user part of our family?

sub is_member {
    my ($this,$uid) = @_;
    $uid or $uid = $share{DB}->my_uid;
    my %user = $share{DB}->my_user_record();
    my $home = $user{$config{auth}{user_group_column}};
    return 1 if ($home == $this->id);
    my @key = $this->my_keyring();
    my $path = $this->content_path();
    my $node = $path->last();
    do {
	return 1 if ($home == $node->id);
	foreach my $key (@key) { return 1 if ($node->id == $key->{content_id}); }
    } while ($node = $path->previous);
    return 0;
}

#----- keys

sub all_keys {
    my $this = shift;
    if (! exists $share{content_keys}) {
	$share{content_keys} = { content_id => {}, uid => {} };
	foreach my $key ($share{DB}->fetch_all("content_key")) {
	    my $cid = $key->{content_id};
	    my $uid = $key->{uid};
	    my $gid = $key->{gid};
	    if (! $share{content_keys}{content_id}{$cid}) {
		$share{content_keys}{content_id}{$cid} = [];
	    }
	    push @{$share{content_keys}{content_id}{$cid}}, $key;
	    if ($uid) {
		if (! $share{content_keys}{uid}{$uid}) {
		    $share{content_keys}{uid}{$uid} = [];
		}
		push @{$share{content_keys}{uid}{$uid}}, $key;
	    }
	    if ($gid) {
		if (! $share{content_keys}{gid}{$gid}) {
		    $share{content_keys}{gid}{$gid} = [];
		}
		push @{$share{content_keys}{gid}{$gid}}, $key;
	    }
	}
    }
    return $share{content_keys};
}

# keys - keys for this node only
# keyring - keys for this path

sub keys {
    my ($this) = @_;
    my $all_keys = $this->all_keys();
    my $keys = $all_keys->{content_id}{$this->id};
    if ($keys) {
	return wantarray ? @$keys : $keys;
    }
    return wantarray ? () : [];
}

sub keyring {
    my ($this) = @_;
    my @key;
    my $clist = $this->content_path();
    my $cnode = $clist->last();
    do {
	my @nodekeys = $cnode->keys();
	push @key, @nodekeys if (scalar @nodekeys > 0);
    } while ($cnode = $clist->previous);
    return @key;
}

sub my_keys {
    my ($this,$uid) = @_;
    my $user = new ExSite::User(id=>$uid);
    
    my @key = $this->my_group_keys($uid);
    push @key, $this->my_private_keys($uid);
    return wantarray ? @key : \@key;
}

sub my_private_keys {
    my ($this,$uid) = @_;
    $uid or $uid = $share{DB}->my_uid;
    my $all_keys = $this->all_keys;
    my $all_my_keys = $all_keys->{uid}{$uid};
    my @key;
    if ($all_my_keys) {
	my $id = $this->id;
	foreach my $k (@$all_my_keys) {
	    push @key, $k if ($k->{content_id} == $id);
	}
    }
    return wantarray ? @key : \@key;
}

sub my_group_keys {
    my ($this,$uid) = @_;
    my @key;
    my $all_keys = $this->all_keys;
    if (exists $all_keys->{gid}) {
	my @my_groups = $share{DB}->get_query("user groups",$uid);
	my $id = $this->id;
	foreach my $gr (@my_groups) {
	    my $all_my_keys = $all_keys->{gid}{$gr->{gid}};
	    if ($all_my_keys) {
		foreach my $k (@$all_my_keys) {
		    push @key, $k if ($k->{content_id} == $id);
		}
	    }
	}
    }
    return wantarray ? @key : \@key;
}

sub my_keyring {
    my ($this,$uid) = @_;
    $uid or $uid = $share{DB}->my_uid;
    my @key;
    my $cpath = $this->content_path();
    my $cnode = $cpath->last();
    do {
	push @key, $cnode->my_keys($uid);
    } while ($cnode = $cpath->previous);
    return @key;
}

sub add_key {
    my ($this,%opt) = @_;
    $opt{content_id} or $opt{content_id} = $this->id;
    $opt{uid} or $opt{uid} = $share{DB}->my_uid;
    return undef if (! $opt{content_id} || ! $opt{uid});
    $opt{type} or $opt{type} = "grant";
    $opt{role} or $opt{role} = "owner";
    $opt{content_key_id} = $share{DB}->insert("content_key",\%opt);
    if ($share{content_keys}) {
	$share{content_keys}{content_id}{$opt{content_id}} = \%opt;
	$share{content_keys}{uid}{$opt{uid}} = \%opt;
    }
    return $opt{content_key_id};
}

# role : return hash of role=>key for a particular user at this node

sub roles {
    my ($this,$uid) = @_;
    $uid or $uid = $share{DB}->my_uid;
    my %role;
    my @key = $this->my_keyring($uid);
    while (my $key = pop @key) {
	foreach my $role (split /; /, $key->{role}) {
	    if ($key->{type} eq "revoke") {
		delete $role{$role};
	    }
	    else {
		$role{$role} = $key;
	    }
	}
    }
    return wantarray ? %role : \%role;
}

sub has_role {
    my ($this,$uid,$role) = @_;
    my %roles = $this->roles($uid);
    if ($role) {
	return $roles{$role};
    }
    else {
	return (keys %roles > 0);  # any role will do
    }
}

# all_roles : return hash of role => uid => key for a node

sub all_roles {
    my ($this) = @_;
    my %role;
    my @key = $this->keyring();
    my %role;
    while (my $key = pop @key) {
	foreach my $role (split /; /, $key->{role}) {
	    if ($key->{type} eq "revoke") {
		delete $role{$role}{$key->{uid}};
	    }
	    else {
		$role{$role}{$key->{uid}} = $key;
	    }
	}
    }
    return wantarray ? %role : \%role;
}

# authority: list of authorities (user records) over this content
# (authorities are admin-level users with keys)
# scalar mode - returns most authoritative user
# list mode - returns all authorities, ranked from most to least authoritative

sub authority {
    my ($this,$role) = shift;
    $role or $role = "administrator";
    my $roles = $this->all_roles()->{$role};
    if (scalar keys %$roles > 0) {
	my $auth = $this->all_authorities();
	my @user;
	foreach my $uid (keys %$roles) {
	    if (exists $auth->{$uid}) {
		push @user, $auth->{$uid};
	    }
	}
	if (@user > 0) {
	    @user = $share{DB}->sort_rows("user",\@user,"access","uid");
	}
	return wantarray ? @user : $user[0];
    }
    return undef;
}

sub all_authorities {
    my $this = shift;
    if (! exists $share{authorities}) {
	my @auth = $share{DB}->get_query("all authorities");
	$share{authorities} = &keywise("uid",\@auth);
    }
    return wantarray ? %{$share{authorities}} : $share{authorities};
}

# access - the access level for this node; if not defined, use the 
# access level for the parent

sub access {
    my $this = shift;
    my $access = $this->getdata('access');
    if (! defined $access) {
	my $parent = $this->parent();
	if ($parent->defined) {
	    $access = $parent->getdata('access');
	}
    }
    return $access || 0;
}

sub hide_from {
    my ($this,$target) = @_;
    my $hide = $this->getdata("hide");
    return $target ?
	$hide =~ /$target/ :
	$hide;
}

#--------------------------------------------------------------------------
# path_to_content -  converts a path string /a/b/c to content datahash
# path_to_obj - converts path string to object

sub path_to_content {
    my ($this,$path,$start) = @_;
    my ($input,$urlpath);
    if (! $path) {
	$input = new ExSite::Input;
	$path = $input->path();
	$urlpath = 1; # we are parsing the current URL
    }
    if (! $start) {
	$start = ($path =~ /^\//) ? undef : $this->id;
    }
    my $tree = $this->get_content_tree();
    my @path;
    if ($start) {
	@path = $tree->path_is($path,"name",$start);
    }
    else {
	# no explicit start node; try anonymous root node first
	my $anonroot;
	foreach my $root ($tree->get_topnodes_data()) {
	    if (! $root->{name}) {
		$anonroot = $root;
		last;
	    }
	}
	if ($anonroot) {
	    @path = $tree->path_is($path,"name",$anonroot->{content_id});
	}
	if (scalar @path == 0 || ! defined $path[0]) {
	    # nothing under the anonymous root, try named root nodes
	    @path = $tree->path_is($path,"name");
	}
    }
    if (! defined $path[-1]) {
	# additional non-CMS path elements, not found in tree - ignore
	pop @path;
    }
    if ($urlpath) {
	# update input bufs to say what we found
	my @urlpath = map { $_->{name} } @path;
	$input->new_path("content",join("/",@urlpath));
    }
    return wantarray ? @path : $path[-1];  # datahashes
}

sub path_to_obj {
    my ($this,$path,$start) = @_;
    my @path = $this->path_to_content($path,$start);
    my @cpath = map { $this->get_content_obj($_) } @path;
    return wantarray ? @cpath : $cpath[-1];
}

# find_path : walk the tree based on a text path
# options:
# %opt =>
#   path = arrayref or text representation of path, eg. '/a/b/c'
#   start = begin search from this node ID
#   type = search for this node type
# returns (last element's datahash, path elements used) in list mode,
# last element's datahash otherwise

#### DEPRECATED ??

sub find_path {
    my ($this,%opt) = @_;
    my $path = $opt{path};
    if ($path == 1) {
	my $input = new ExSite::Input;
	$path = $input->path();
    }
    my $type = $opt{type};
    my $start = $opt{start};
    if (! defined $start) {
	$start = ($path =~ /^\//) ? undef : $this->id;
    }
    my $tree = $this->get_content_tree();
    my @path = $tree->path_is($path,"name",$start);
    if ($type) {
	# we don't want the whole path, only the path to the 
	# last instance of $type
	my $itype = $this->isubtype($type);
	while (my $last = pop @path) {
	    if ($last && $last->{type} == $itype) {
		if (wantarray) {
		    my $path = "/".join("/", map { $_->{name} } @path, $last);
		    return ($last,$path);
		}
		else {
		    return $last;
		}
	    }
	}
	# nothing in the path of the requested type
	return undef;
    }
    my $last = $path[-1];
    if (! defined $last) {
	$this->warn("Could not find $path");
	pop @path;
	$last = $path[-1];
    }
    if (wantarray) {
	my $path = "/".join("/", map { $_->{name} } @path);
	return ($last,$path);
    }
    else {
	return $last;
    }
}

sub find_path_obj {
    my ($this,%opt) = @_;
    my ($data,$path) = $this->find_path(%opt);
    if ($data) {
	my $cobj = $this->get_content_obj($data);
	return wantarray ? ($cobj,$path) : $cobj;
    }
    return new ExSite::Content(); # dummy
}

# add_child : add a child content node, with optional revision data

sub add_child {
    my ($this,$content,%revision);
    if (ref $content eq "HASH") {
	delete $content->{content_id};
	$content->{parent} = $this->id;
	my $child = $this->get_content_obj($content);
	if ($child->save) {
	    if (scalar keys %revision) {
		$child->revise(%revision);
	    }
	}
	return $child->id;
    }
    return undef;
}

# delete the content
### FIXME - unpublish, delete children, delete self
### delete metadata??
### delete search index

sub delete {
    my $this = shift;
    my $id = $this->id;
    if ($id && $this->allow("delete")) {
	$this->unpublish();
	$share{DB}->trash_r("content",$id);
	return 1;
    }
    return 0;
}

# copy content

sub copy {
    my ($this,%data) = @_;
    if ($this->loaded) {
	if (! $data{name}) {
	    if (! exists $data{parent} || $data{parent} == $this->getdata("parent")) {
		# copying under same parent; rename
		$data{name} = $this->getdata("name") . "_copy";
	    }
	}
	my $newid = $this->SUPER::copy(%data); # also copies metadata
	if ($newid) {
	    # copy current revision
	    if ($this->has_revisions) {
		my $newrevid = $this->revision->copy(content_id=>$newid);
	    }
	}
	# copy flags
	my %flag = $this->flags();
	if (keys %flag) {
	    my $c = $this->get_content_obj($newid);
	    foreach my $key (keys %flag) {
		$c->set_flag($key);
	    }
	}
	# copy prices
	my @prices = $this->get_prices();
	if (@prices > 0) {
	    foreach my $price (@prices) {
		delete $price->{price_id};
		$price->{content_id} = $newid;
		$share{DB}->insert("price",$price);
	    }
	}
	# FIXME: copy dates???

	# do not copy keys, likes
	return $newid;
    }
    return undef;
}

#===========================================================================
# pricing

## TODO: multiple currencies
## many issues here: conversion, gateway support, financial reports, 
## mixing currencies on same invoice, paying in different currencies than
## the original purchase

# price: return the best allowed price

sub price {
    my $this = shift;
    my $price = $this->run_handler("Content_price");
    return $price if (defined $price);
    my @prices = $this->get_allowed_prices();
    foreach my $p (@prices) {
	if (! $price || $p->{cost} < $price->{cost}) {
	    $price = $p;
	}
    }
    return $price;
}

sub price_value {
    my $this = shift;
    my $price = $this->price();
    return $price ? $price->{cost} : undef;
}

sub show_price {
    my ($this,$pricedata) = @_;
    $pricedata or $pricedata = $this->price();
    my $price = new ExSite::Object(data=>$pricedata,type=>"price");
    if ($price->defined) {
	my $ml = &get_obj("ML");
	my $descr = $price->getdata("description");
	my $out;
	if ($descr) {
	    $out .= $ml->span($msg{$descr}.": ",{class=>"priceDescription"});
	}
	# don't use showdata, because pricing has to be shown to public
	$out .= $ml->span($config{report}{currency_char}.$price->getdata("cost"),{class=>"priceCost"});
	return $out;
    }
    return undef;
}

# get_allowed_prices: return all prices that match the current date and
# user's access level

sub get_allowed_prices {
    my $this = shift;
    if (! $this->{allowed_prices}) {
	$this->{allowed_prices} = [];
	my $prices = $this->get_prices();
	if ($prices) {
	    my $level = $share{DB}->level;
	    foreach my $p (@$prices) {
		next if ($p->{access} && $p->{access} > $level);
		if ($p->{start} !~ /^0/) {
		    # price has a start date
		    my $t = new ExSite::Time($p->{start},"sql_datetime");
		    next if ($t->in_future);
		}
		if ($p->{end} !~ /^0/) {
		    # price has an end date
		    my $t = new ExSite::Time($p->{end},"sql_datetime");
		    next if ($t->in_past);
		}
		# this price is allowed
		push @{$this->{allowed_prices}}, $p;
	    }
	}
    }
    return @{$this->{allowed_prices}};
}

# get_prices: return all defined prices

sub get_prices {
    my $this = shift;
    if ($this->ok) {
	if ($share{DB}{map}->is_mapped("price")) {
	    return $share{DB}->fetch_child("price","content",$this->id,"price_id");
	}
    }
    return undef;
}

sub has_prices {
    my $this = shift;
    my @price = $this->get_prices;
    return @price > 0;
}

#===========================================================================
# serving content to end viewer

# output - like show, but write to stdout with headers

sub output {
    my ($this,%opt) = @_;
    if (! $this->{done}) { # only output once
	# get ouput
	my $out = $this->expand(%opt);
	# dump headers
	$this->show_headers();
	# dump page
	print $out if (! $this->{redirect});
	$this->{done} = 1;
    }
    return;
}

# some HTTP header functions

sub header {
    my $this = shift;
    my $hdr = shift;
    if ($hdr !~ /\n$/) { $hdr .= "\n"; }
    $this->{http_header} .= $hdr;
    return;
}

sub show_headers {
    my $this = shift;
    my $content_type = $this->content_type || "text/html";
    print $this->{http_header};
    if ($this->{http_header} !~ /content-type:/i) {
	print "Content-type: $content_type\n";
    }
    print "\n";
    return;
}

# redirect using a location: header (address bar does not change)

sub redirect {
    return &location(@_);
}

sub location {
    my ($this,$url) = @_;
    $this->header("Location: $url");
    $this->{redirect} = 1;
    return;
}

# redirect using a location: header (address bar does not change)

sub redirect {
    return &location(@_);
}

sub location {
    my ($this,$url) = @_;
    $this->header("Location: $url");
    $this->{redirect} = 1;
    return;
}

# error pages, to be used when content cannot be displayed

sub errorpage {  ############################################### FIXME
    my ($this,$html) = @_;

    # flag this as an error page
    $this->{errorpage} = 1;

    # see if the section has defined a special template for exceptions

    ### FIXME: this only finds error templates in the current site;
    ### Would be nice to inherit error templates from parent sites.
    ### Also: does this fail to identify the section, if the URL has our
    ### domain, but no page identifier info?
    my @t = $share{DB}->fetch_match("page",{type=>"template",
					    section_id=>$this->id("section"),
					    filename=>"_ERROR"});

    if (@t > 0) {
	# reset the page template
	$this->{data}{template_id} = $t[-1]{page_id};
	$this->reset_context;
	$this->{expanded} = 0;
	$this->expand(content=>{body=>$html});
	return;
    }
    else {
	# no error-handler page;
	# just output the bare html
	$this->{html} = $html;
	$this->{noexpand} = 1;
	return;
    }
}

sub is_errorpage {
    my $this = shift;
    return $this->{errorpage};
}

# exception_page : change the template to handle irregular occurences
#
# Special templates can be defined to handle exceptional conditions
# (errors, permission denied, login screens, etc.).  When the code calls
# exception_page($html,"ABC"), then the system will attempt to replace
# the correct template for the page with a template named '_ABC' (always
# upper case), and then substitute $html into the body of this template.
#
# ExSite knows about and will try to use the following exception templates:
#
# _LOGIN : authentication failures, requiring login to proceed
# _ERROR : errors in building or displaying the page
#
# Note that '_ERROR' is the default exception template, and will be used
# if no explicit exception template is named, or in cases where another 
# exception template was requested but not found.  For example, if the
# "LOGIN" template is requested, but not defined, but an "ERROR" template
# _is_ defined, the _ERROR template will be used instead.
#
# Any other exception templates may be defined, and invoked by plug-in
# modules or other custom code.

sub exception_page {
    my ($this,$html,$exception) = @_;

    $exception = $exception ? uc($exception) : "ERROR";

    # see if the section has defined a special template for exceptions

    ### FIXME: this only finds error templates in the current site;
    ### Would be nice to inherit error templates from parent sites.
    ### Also: does this fail to identify the section, if the URL has our
    ### domain, but no page identifier info?
    my @t = $share{DB}->fetch_match("page",{type=>"template",
					    section_id=>$this->id("section"),
					    filename=>"_$exception"});
    if (@t == 0 && $exception ne "ERROR") { 
	# requested exception page not found;
	# try _ERROR instead.
	@t = $share{DB}->fetch_match("page",{type=>"template",
					     section_id=>$this->id("section"),
					     filename=>"_ERROR"});
    }

    if (@t > 0) {
	# reset the page template
	$this->{data}{template_id} = $t[-1]{page_id};
	$this->reset_context;
	$this->{expanded} = 0;
	$this->expand(content=>{body=>$html});
	return;
    }
    else {
	# no error-handler page;
	# just output the bare html
	$this->{html} = $html;
	$this->{noexpand} = 1;
	return;
    }
}

sub setup_querylib {
    my $this = shift;
    return if (exists $share{querylib}{"content tree"}); # already done

    my $db = $share{DB};
    # content tree lookups
    # all content - for resolving content references
    $db->set_query("content tree",
		   sql=>"select $config{content}{tree_columns} from content order by $config{content}{tree_order}",
		   nparam=>0,
		   keys=>"content");
    # pages only - for building sitemaps, menus
    $db->set_query("page tree",
		   sql=>"select c.content_id,c.parent,c.master,c.type,c.name,c.language,c.status,c.hide from content c,content_type t where c.type=t.content_type_id and t.navtype='page' order by $config{content}{tree_order}" ,
		   nparam=>0,
		   mode=>"r",
		   keys=>"content");

    # keyword indexes
    $db->set_query("names of keyword tags",
		   sql=>"select kw.name from content ind,content kw,content tag where kw.parent=ind.content_id and tag.parent=kw.content_id and ind.type=? and kw.type=? and tag.type=? and tag.master=? order by kw.sortkey, kw.title",
		   nparam=>4,
		   keys=>"content");
    $db->set_query("keyword tags",
		   sql=>"select kw.* from content ind,content kw,content tag where kw.parent=ind.content_id and tag.parent=kw.content_id and ind.type=? and kw.type=? and tag.type=? and tag.master=? order by kw.sortkey, kw.title",
		   nparam=>4,
		   keys=>"content");

    # allowed content types under a node
    $db->set_query("allowed content types",
		   sql=>"select t.content_type_id,t.name from content_type t,content_type u,content_rel r where u.content_type_id=r.under and t.content_type_id=r.type and u.name=?",
		   nparam=>1,
		   keys=>["content_type","content_rel"]);

    # all revisions
    $db->set_query("all revisions",
		   sql=>"select revision_id,content_id,mime_type,ptime from revision order by revision_id",
		   nparam=>0,
		   mode=>"r",
		   keys=>["revision"]);
    $db->set_query("content with no revisions",
		   sql=>"select content.content_id from content left join revision on revision.content_id=content.content_id where revision.revision_id is null",
		   nparam=>0,
		   mode=>"r",
		   keys=>["content","revision"]);

    # popular content
    $db->set_query("popular content",
		   sql=>"select content_id,sum(value) popularity from content_like group by content_id order by popularity desc",
		   nparam=>0,
		   mode=>"r",
		   keys=>["content_like"]);
    # allowed types to post under (where the passed type may be placed)
    $db->set_query("allowed types to post under",
		   sql=>"select t2.name,t2.content_type_id from content_type t1, content_type t2, content_rel r where r.type=t1.content_type_id and t1.name=? and r.under=t2.content_type_id",
		   nparam=>1,
		   mode=>"r",
		   keys=>["content_type","content_rel"]);
    # clear search indexes
    $db->set_query("clear search index",
		   sql=>"delete searchurl, searchterm from searchurl, searchterm where searchurl.section_id=? and searchurl.searchurl_id=searchterm.searchurl_id",
		   nparam=>1,
		   mode=>"w",
		   keys=>["searchurl","searchterm"]);
    $db->set_query("clear url from search index",
		   sql=>"delete searchurl, searchterm from searchurl, searchterm where searchurl.url=? and searchurl.searchurl_id=searchterm.searchurl_id",
		   nparam=>1,
		   mode=>"w",
		   keys=>["searchurl","searchterm"]);
    $db->set_query("clear content from search index",
		   sql=>"delete searchurl, searchterm from searchurl, searchterm where searchurl.content_id=? and searchurl.searchurl_id=searchterm.searchurl_id",
		   nparam=>1,
		   mode=>"w",
		   keys=>["searchurl","searchterm"]);
    $db->set_query("searchterm counts",
		   sql=>"select searchurl.content_id,count(searchterm.searchurl_id) from searchurl,searchterm where searchurl.searchurl_id=searchterm.searchurl_id group by searchterm.searchurl_id",
		   nparam=>0,
		   mode=>"r",
		   keys=>["searchurl","searchterm"]);
}

#===========================================================================
# ExSite 3 backwards-compatibility methods

sub publishing { return &is_publishing(@_); } # deprecated

sub section { return &my_section(@_); }

sub get_my { my $this = shift; $this->getdata(@_); }

sub set_context { return; } # deprecated

sub id {
    my ($this,$subtype) = @_;
    if ($subtype) {
	if ($subtype eq "section") {
	    return $this->my_section->id;
	}
	elsif ($subtype eq "page") {
	    return $this->my_page->id;
	}
	elsif ($subtype eq "content") {
	    return $this->revision->getdata("parent");
	}
	elsif ($subtype eq "content_data") {
	    return $this->revision->id;
	}
    }
    return $this->SUPER::id();
}

sub context {
    my ($this,$type) = @_;
    if ($this->loaded()) {
	if ($type eq "section") {
	    return $this->my_section->get();
	}
	elsif ($type eq "page") {
	    return $this->my_page->get();
	}
	elsif ($type eq "content") {
	    return $this->get();
	}
	elsif ($type eq "content_data") {
	    return $this->revision->get();
	}
    }
    return {};
}

1;

=pod

=head1 ExSite::Content - CMS Base Class

The Content class provides all of the basic CMS services required
by various different subsystems, including:

=over 4

=item * revision control, archiving

=item * alternate views (eg. thumbnails)

=item * level-based access controls (public, member-only, administrator-only)

=item * role-based access controls (editorial, design, user)

=item * publishing

=item * scheduling, queuing

=item * workflows, moderation, approvals

=item * hiding content from navigation, search, robots

=item * metadata management

=item * pricing

=item * URL management

=item * tagging

=item * translation, multilingual services

=item * search

=back

Different classes of content will inherit from this class to get the
basic CMS behaviours, which they can then overload to define their
specific class behaviours.

Content objects are organized hierarchically. Every content object has
a name, and a path to its node in the overall tree, which is the list
of names that have to be traversed to get to the node. For example

    /foo/bar

There can be one "anonymous" node with no name; it must be at the root
of the tree. So the above path could refer to either one of

    foo -> bar
    [anonymous] -> foo -> bar

Content names must be unique under each parent. Additionally, they
must be unique at the root and under the anonymous root node, to avoid
the above ambiguity.

Content objects typically publish to directories that match their
path, and can be viewed at an URL like:

    http://foo.com/foo/bar

However, different content classes can alter their publication rules
to vary this location. For example, events can publish to dated
directories like C</calendar/2012/11/event.html>.

Content objects can also be viewed dynamically as bare content:

    http://foo.com/cgi/ex.cgi/view/foo/bar

or formatted like a full web page:

    http://foo.com/cgi/ex.cgi/page/foo/bar

=head2 Setup

Create your content object in one of the following ways:

By its content ID:

    my $c = new ExSite::Content(id=>99);

By its whole or partial data record:

    my $c = new ExSite::Content(data=>\%content);

By its name (you must provide a parent ID):

    my $c = new ExSite::Content(name=>"foo",parent=>99);

By its path:

    my $c = new ExSite::Content(path=>"/foo/bar");

By the path requested in C<$ENV{PATH_INFO}>:

    my $c = new ExSite::Content(path=>1);

=head3 Converting Content Type

This will create an object of class C<ExSite::Content>. If you have
actually specified an object of a different class (for example, a
page), you will not get the correct object behaviour. Convert your
object to the correct class using:

    $c = $c->get_content_obj();

If you already have a content object handy, you can often do this in
one step. For example, to make an object from a content ID:

    my $newc = $c->get_content_obj($id);

For example, to make an object from a content record:

    my $newc = $c->get_content_obj(\%content);

=head2 Basic Object Queries

The Content class inherits from the ObjectMeta class, and has all of
the behaviours of a standard ExSite object with metadata. For example:

    my $val = $c->getdata($column);  # fetch a raw data value
    my $val = $c->showdata($column); # safely display a data value
    my @err = $c->validate();        # validate the record contents

...and so on. See the documentation for C<Object.pm> and
C<ObjectMeta.pm> for more information.

In addition to the basic Object methods, there are also the following
Content-specific methods for obtaining information about the object.

Content names:

    $c->name()  # used in URLs
    $c->title() # used in page titles, headings
    $c->label() # used in hyperlinks to the content

Relationships to other content objects:

    $c->parent()    # returns the parent object
    $c->template()  # returns this object's template
    $c->master()    # returns this object's original reference content object
    $c->alias()     # whether or not we were redirected to this content from an alias
    $c->is_in($c2)  # whether $c is contained within $c2
    $c->my_ancestor($type) # nearest ancestor of a certain type
    $c->my_page()   # nearest page-like object that contains us
    $c->my_section() # the section that contains us
    $c->my_root()   # the highest-level object that contains us

Status of this content object:

    $c->has_content(); # true if this object contains its own revisions
    $c->is_static();   # true if this object publishes
    $c->is_active();   # true if this object is okay for regular viewing
    $c->is_public();   # true if this object can be shown to the public

The type/behaviour of this content:

    $c->subtype();     # for example content, library, article, page, etc.
    $c->isubtype();    # the numeric type that corresponds to the above
    $c->is_page();     # does this content behave in a page-like way?
    $c->is_subdir();   # dies this content publish to its own directory?
    $c->my_subdir();   # the actual subdirectory name we publish to
    $c->filename();    # the filename we publish to

C<is_page()> determines whether the content is page-like. A "page" is
a primary navigation destination on your site, and will determine
certain default behaviours, such as whether to include links in
menus. For the base Content class, C<is_page()> returns FALSE. You
should overload this if your content object is page-like. (You may
also want to inherit from the Page class to get other page
behaviours.)

C<is_subdir()> determines whether this content is published as
directory or as a file. If as a directory, it will have a static URL
like C</foo/bar>, whereas if as a file, it will have a static URL like
C</foo/bar.html> (and will publish into the parent's directory). The
base Content class publishes as files, but higher-level classes can
override this.

C<my_subdir()> is the actual subdirectory name we publish to (which
may be blank for the anonymous root node). C<my_filename()> is the
filename we publish to, which will typically be C<NAME.EXT> where NAME
is C<$c-E<gt>name()> and EXT is the appropriate MIME-type suffix. For
page-like objects that publish into their own directory and are HTML,
the filename defaults to C<index.html>.

Use the C<info()> method to obtain a bunch of technical info about the
current revision of the content, such as filenames, mime-types, sizes,
and image dimensions.

    my $info_string = $c->info();  # returns descriptive string
    my %info = $c->info();         # returns all info in a hash

=head3 Content Dates

The following calls will return date information about the content:

    $c->getdata("ctime"); # creation time of the content record, as a timestamp
    $c->getdata("mtime"); # last modification time of the content record, as a timestamp
    $c->getdata("ptime"); # original publication of this content, as a timestamp
    $c->posting_date();   # ctime, but as an ExSite::Time object
    $c->age();            # time since creation, in days

    $c->revision->timetamp();        # creation time of the current revision
    $c->revision->getdata("ptime");  # publication time of the current revision

=head3 Metadata

Object metadata is stored separately from the core data, and can be
accessed using the following methods:

    $c->meta();         # returns metadata object, for metadata manipulation
    $c->get_metadata(); # returns all metadata, as a hash

To find the "best" metadata under a given name, use something like

    my $val = $c->dcmeta("description");

This will look for an appropriate metadata item under
C<DC.Description>, C<Description>, and C<description>, in that
order. The first one (C<DC.Description>) is the industry-standard
"Dublin Core" metadata format, which defines the following metadata names:

    DC.Title
    DC.Creator
    DC.Subject
    DC.Description
    DC.Publisher
    DC.Contributor
    DC.Date
    DC.Type
    DC.Format
    DC.Identifier
    DC.Source
    DC.Language
    DC.Relation
    DC.Coverage
    DC.Rights

Because of their industry-standard nature, these will be preferred
over other, similar metadata, if they are defined.

Additionally, you can use the following methods to obtain
metadata-like values, even if no metadata is actually defined. The
object will find something appropriate to use regardless:

    $c->title();
    $c->author();      # checks both author and creator
    $c->description(); # checks description, abstract, and summarizes content, otherwise
    $c->caption();     # checks caption, description, subject
    $c->caption(1);    # same, but returns title if no caption defined

=head3 Flags

Flags are boolean metadata; ie. just a name, not a value. The flag returns
true if that name is set, false (undef) otherwise.

    $c->flags();          # returns a hash of all flags on this content
    $c->flag($flag);      # returns the flag setting (true/false)
    $c->set_flag($flag)   # turns on the flag for this content
    $c->unset_flag($flag) # turns off the flag for this content

Define which flags are used for different content types using config
settings like:

    content.flags.TYPE += flag name/description

=head3 Likes

Likes are tags that join users to content; they have a numeric value
that can be positive (like) or negative (dislike). A value of +/- 1 is 
the default, but other weights can be provided.

To record that the user likes a piece of content:

    $c->like($weight);

C<$weight> defaults to 1; use a -ve value to dislike. To fetch all
liked content, ordered by popularity (most popular first, least popular
last):

    $share{DB}->get_query("popular content");

This query excludes content that has not been rated either way. To see
the popularity of a particular piece of content:

    $c->popularity();

In scalar mode, this returns it's total like score (sum of all
likes). In list mode, it returns a hash of popularity metrics so you
can see how the content relates to other content on the site: C<total> 
number of rated items, C<rank> of this item in that list, C<popularity> 
score of this item.

=head3 Pricing

Content can have various prices associated with it. Prices can have
access controls (eg. member pricing), and time limits (eg. specials, sales).

    $c->get_prices();     # return all prices associated with this content
    $c->get_allowed_prices();   # return valid prices only
                          # (those that match the date and user access level)
    $c->price();          # returns the best valid price record
    $c->show_price();     # displays the best price

=head2 Content Paths

There are numerous ways to describe the path to the content. Use the
following methods:

    $c->content_path();   # returns an object list of the nodes traversed to get to this content object
    $c->path();           # a simple text representation of this path, eg. "/foo/bar"
    $c->navpath();        # a cookie-crumb style formatted list of links representing this path

When publishing to disk, we use the logical path to the content to
build an actual diskpath.

    $c->my_subdir();      # the subdirectory name that this content publishes to, if it publishes as a directory
    $c->filename();       # the filename that this content publishes to
    $c->basedir();        # our HTdocs directory; the root of our published files
    $c->subdir();         # our subdirectory relative to basedir()
    $c->diskpath();       # basedir + subdir
    $c->httpbase();       # our base path element in the URL, $config{server}{HTMLpath}
    $c->httpdir();        # our URL path relative to httpbase();
    $c->httppath();       # our URL path relative to the docroot, httpbase + httpdir

=head1 Displaying the Content

To fetch and display your content, you have 3 general approaches:

=over 4

=item * get HTML to render the content

=item * get an URL to visit the content

=item * get the raw content data (for example, the JPG data)

=back

The following methods can be used:

=head2 Getting HTML

=head3 C<show(%opt)>

This returns HTML to render the content in a web browser. It should
return an HTML snippet that can be inlined into another document.

Use C<$c-E<gt>show(view=E<gt>$viewname)> to explicitly display a different
view than the default.

=head3 C<show_templated(%opt)>

This call always returns a complete web document; the content will be
wrapped up in HTML to give it the same appearance as a full web page on
this site.

It will use the C<template> setting for the content object to
determine which template HTML to use to wrap up the object. If
C<template> is not defined, it will find something appropriate based
on the pages or sections we are nesting under.

For page-like objects, C<show()> and C<show_templated()> should give
the same results.

=head3 C<show_formatted($format,%data)>

This allows for on-the-fly custom formats to display the
content. C<$format> is either the name of a predefined format (kept in
C<$config{content}{format}{...}>, or a fully-specified template with
merge fields. C<ExSite::Misc::substitute> is used to merge the data,
so you can use codes like:

    [[foo]]                - insert foo here
    [[?foo]]TEXT[[/?foo]]  - insert TEXT if foo is defined
    [[!foo]]TEXT[[/!foo]]  - insert TEXT if foo is not defined

The allowed substitution parameters include:

     about        # posting info, such as author, date
     author       # author name
     attachments  # display sub-content
     caption      # caption
     curl         # canonical URL
     date         # posting date
     description  # description, or summarized content
     height       # image height
     html         # content HTML
     icon         # an icon to represent the content
     id           # the content ID
     image        # display a formatted image for this content
     index        # an HTML listing of sub-contents
     info         # description of the file, such as mime type, size
     label        # hyperlink anchor for the content
     language     # the langauge, if not the default
     name         # the content name, as used in URLs
     navpath      # HTML to show a cookie crumb to this content
     price        # display the best price for this content
     summary      # description, or file information
     tools        # links to operate on the content
     title        # title
     type         # content type, such as library, page, article, etc
     url          # current URL to the content
     width        # image width

You can also substitute any metadata, using:

     meta_FOO     # metadata "FOO"

You can also substitute views other than the one you are working
with. Replace C<VIEW> in the following with the view you want, such as
C<small> or C<thumbnail>:

     url_VIEW     # URL to this view
     html_VIEW    # HTML to render this view

You can also subsitute other content objects into the display of this
one. (For example, inlining images into an article.) In the following
parameters, replace C<...> with any of the above to get the
appropriate parameter for the specified content:

    NAME:...      # any of the above parameters for content object NAME
    _FIRST:...    # any of the above parameters for the first subcontent item
    _LAST:...     # any of the above parameters for the last subcontent item
    _IMG:...      # any of the above parameters for the "best" image of the subcontent items

=head3 C<summary()>

This is just shorthand for

    $c->show_formatted("summary");

However, because the summary wants to display a description, and there
often is not a good description available, this call will attempt to
compose a useful description first.

=head3 C<preview()>

C<preview()> is a special display of the content, for
administrators. By default, it shows all existing views of the
content, in both normal and source form. This should be overloaded by
other content classes that have different content managment
requirements.

=head3 C<report()>

This displays technical information about the content.

=head3 C<get_html()>

This retrieves the raw HTML for the current revision. For simple
content objects, this should give the same results as C<show()>.

=head2 Getting URLs

There are numerous URLs you can use to obtain/view content:

    $c->get_url()              # current best URL to the content
    $c->get_url_dynamic()      # the dynamic URL to the content
    $c->get_view_url_dynamic() # the dynamic URL to view the bare content
    $c->get_page_url_dynamic() # the dynamic URL to view the content formatted as a page
    $c->get_url_static()       # the static URL to the content
    $c->get_url_canonical()    # the canonical URL to the content
    $c->permalink()            # the best human-friendly URL to the content
    $c->get_uri()              # a URI object representing get_url_dynamic()
    $c->get_page_uri()         # a URI object representing get_page_url_dynamic()
    $c->link(%args)            # modify the dynamic URL with other parameters

=head2 Sub-content and Indexes

Some content objects can contain other content. In the base content
class, this is not possible, but higher classes (for example,
libraries, blogs) may not actually have their own revisions, just
sub-content.

Use the following calls to obtain sub-content. You can optionally pass
a type if you want to restrict the listing to only that class of item.

    my @clist = $c->get_contents($type);   # returns an array of datahashes
    my $n = $c->count_contents($type);     # returns the number of sub-content items

For creating menus and submenus, you want the subcontents that are page-like.

    my @submenu = $c->my_submenu_items();  # children of this node
    my @menu = $c->my_menu_items();  # also includes this node as the top item

If you want to get all descendant nodes, not just the immediate children, use:

    my @all = $c->get_descendants(@type);   # you can pass multiple types

Indexes are HTML listings of sub-content items. Typically these are
hyperlinked so that the viewer can use the index to find and visit the
other content items.

    $out .= $this->index();   # display an index to the contents

Other content classes can overload this to provide their own
specialized indexes.

Attachments are content objects (images or downloads) that are attached
to the current content object. These can be displayed using

    $out .= $c->attachments();

An RSS fees is just a specialized index, formatted as an RSS XML
file. You can generate this XML using this call:

    $xml = $this->rss();

=head1 Interacting with the Content

=head2 C<tools()>

C<tools()> generates the links that are needed to work on the
content. For regular content objects, there are none. Other content
classes can overload this to provide additional functions.

=head2 C<post()>

C<post()> processes data that has been POSTed to the object. Regular 
content objects do not support POSTs, but specialized ones (eg. comments)
might. Overload this method to define those POST behaviours.

=head1 Finding Content

Starting from any given content object, we can find other content
given only a name. Because names are not unique system-wide, there is
a particular order we search in:

=over 4

=item * search the children of the current node

=item * search the children of the current page

=item * search the children of our template (and the template's parents)

=item * search the children of the current page's template (and parents)

=item * search our descendant nodes

=item * search the children of our section's template (and parents)

=item * search the libraries of this section (and parent sections)

=back

To perform such a search directly, use:

    my $best = $c->find($name);

C<$best> will be the best-match content object named C<$name>.

=head2 Content Expansion

HTML content can contain substitution tags like the following:

    <!--content(NAME)-->     # insert HTML for content NAME here
    [[NAME]]                 # insert URL to raw content for NAME here
    {{NAME}}                 # insert URL to templated (page-like) content NAME here
    <!--$META-->             # insert metadata META here
    <!--&MODULE(options)-->  # insert plug-in MODULE content here

If the content object contains HTML, you can automatically substitute
all of the tags by calling:

    my $html = $c->expand(%option);

C<%option> can contain the following options:

    html => $starting_html

Use this if you want to start from something different than the
current content object's HTML.

    method => "data,url,content,page,module"

Use this switch to control which substitutions will be performed. You
can pass a list of any of the above 5 substitution types.

    expand => "template"

Assume the content being expanded is a template, not actual
content. This will leave certain items unexpanded.

C<$c-E<gt>unexpand()> undoes the content expansion so that it can be restarted.

=head3 C<get_dynamic_content()>

    my $html = $this->get_dynamic_content($module,$args,$option);

Return replacement text for a C<< <!--&Module(...)--> >> CMS tag

Loads the C<$module> plug-in, and calls its C<write()> method, passing
the C<$args> to it.  Returns the output of the module.  If the module 
fails to load/compile, a Perl error string will be returned.

C<$option> is the same as is passed to C<expand()>.  If the "B<expand>" option
or "B<dummy-module>" methods are selected, a placeholder image will be
substutited instead of the module content.

If the "B<static-module>" method is selected, each module will be
queried to see if its output is static for this page; only if static
will the content will be substituted.  (This allows for precompiling 
certain modules' output, eg. menus, while rendering others at page 
view time.)

=head3 C<get_dynamic_content_indirect()>

    my $html = $this->C<get_dynamic_content_indirect($module,$args,$option);

This is an AJAX version of C<get_dynamic_content()>.

This method returns replacement text for CMS tags of the form:

    <!--&&Module(...)-->    # indirect substitution, direct re-links
    <!--&&&Module(...)-->   # indirect substitution, indirect re-links

This fetches the DCD content using a separate server request, instead 
of inlining it directly.

The main advantage is that you can publish the main page to a static 
HTML file, yet keep some page elements dynamic.  This is especially 
useful for index.html pages, which must be static, but may contain 
dynamic elements (eg. recent news, upcoming events, current specials,
etc.).  The solution is either continuous republishing of the index
page (which may still be a better solution for heavily loaded sites)
or using an indirect dynamic content fetch.

The disadvantage is that the full page is slower (although the base
page may be much faster), and that JavaScript must be enabled to 
perform the secondary content fetches.

The '&&' variant does direct re-links, ie. links from the dynamic content
point to full URLs that generate a new page.  The '&&&' variant does 
indirect re-links, ie. links back to the same module in the same page
only fetch the DCD content and inline it dynamically into the current
page without generating a whole new page.

=head1 Revision Control

The content itself gets updated in the form of revisions. Each update
creates a new revision record tied to its content record. The most
recent revision is the B<newest> revision, while the most recently
publish revision is the B<active> revision.

By default we load the active revision, since that is the one
approved for public viewing.  To use the newest revision instead (for
admins, for instance), add a C<cms> flag when creating your content
object, to tell the system that you are doing CMS work:

    my $c = new ExSite::Content(id=>99,cms=>1);

To obtain the revision that the content object is using, use;

    my $r = $c->revision();

To set the revision of the content object to a different revision, use:

    $c->load_revision($rev);

where C<$rev> is "newest", "active", or a numeric revision ID for some
other revision.

To fetch a different revision, without changing the current content
object, use:

    $c->find_revision($rev);

To make calls to the current revision, use calls like:

    $c->revision->mime_type();

The full list of calls is documented in the C<ExSite::Revision> class.

=head2 C<revise(%opt)>

Adds a new revision to this content object. Options are:

=over 4

=item data

The raw data for the view(s). For file uploads, should be an encoded file.

=item format

The format of the data, ie. text, file, path, url.

=item mime_type

The mime_type of the data. Optional - will be guessed if not provided.

=item attributes

A hash of attributes and values.

=item note

A revistion control comment.

=item view

A hashref with instructions for generating views. Each hash item is of the form

    viewname => 1

or

    viewname => \%cview_datahash

where C<viewname> is one of the recognized view names, ie. large,
normal, small, thumbnail, or icon. If the view is defined as a
datahash, it will be installed as defined. Otherwise, if the view is
defined as TRUE, the system will attempt to generate the view
automatically. This is normally only possible for images, which can be
rescaled for different views.

=back

The standard views are:

=over 4

=item normal

This is the default view of the content, intended for insertion into a
regular web page. If the content is an image, it is scaled to a
typical web page body width (normally 512 pixels).

=item large

If the original data is larger than the normal view, we can optionally
retain it in its original form as a large view. (The CMS may
nevertheless scale it down if it too large to save in the CMS.)

=item small

A small view is scaled so that it can be floated to the side of a body
of text, with text wrapping around it. If a small view is requested,
we scale it down to the optimal small size (usually 256 pixels wide),
and save it if this is a different size from the normal view.

=item thumbnail

A thumbnail view is scaled to a good size for aggregating into
thumbnail grids or "contact sheets". If a thumbnail view is requested,
we scale it down to the system thumbnail size (typically 100 pixels).

=item icon

An icon view is an extra-small view that is typically used for listing
files or downloads. Icon views are not automatically generated.

=back

=head2 Views

The revision itself serves mostly as an archival/record keeping
object.  Actual content is stored in the B<Views>. Any given revision
can be maintained in multiple views:

=over 4

=item normal

This is the default view of the content, and is how the content will
normally be displayed at its default/home location or URL.

=item large

This is a larger view of the content, which might be inappropriate
for regular web surfing due to its size. (For example, hi-res images,
or HD video.) Users can opt-in to viewing the large view if they
choose to.

=item small

This is an abbreviated or shrunken view of the content, which can be
useful as a teaser or summary in cases where you do not want to show
the complete content all at once, such as in indexes and listings.

=item thumbnail

This is a very reduced view of the content, suitable for very long
listings or thumbnail galleries.

=item icon

This is an extremely small representation of the content, suitable for
inlining into text.

=back

When a revision is selected, the normal view is preselected by
default. To request a different view, use something like:

    $c->revision->view("thumbnail");

There is no guarantee that the request view exists, however. To check
if it exists, use:

    my $view_exists = $c->revision->has_view("thumbnail");

If it does not exist, and you request it anyway, you will get the
closet matching view. For example, you will receive a thumbnail
instead of an icon, or a normal instead of a large.

The actual content is all contained in the view, so content-specific
queries are really view queries. For example:

    $c->revision->view->mime_type();
    $c->revision->view->is_image();
    $c->revision->view->get_html();

Full documentation of the available calls is in the C<ExSite::View> class.

=cut
