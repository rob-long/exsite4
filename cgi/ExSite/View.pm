#!/usr/bin/perl
#-----------------------------------------------------------------------
#
#   Copyright 2011-2012 Exware Solutions, Inc.  http://www.exware.com
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

package ExSite::View;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Image;
use ExSite::ML;
use ExSite::Revision;
use ExSite::Diskfile;
use ExSite::Object;
use MIME::Base64;

use vars qw(@ISA @type);
@ISA = qw(ExSite::Object);

sub my_type { return "cview"; }

sub setup {
    my ($this,%opt) = @_;
    
    $this->SUPER::setup(%opt);
    if ($opt{revision}) {
	$this->{revision} = $opt{revision};
    }
    return;
}

sub loaded {
    my $this = shift;
    # loading of data column may be deferred in some cases
    if ($this->ok) {
	if (exists $this->{data}{data}) {
	    return 1;
	}
	else {
	    return 1 if ($this->id && $this->load());
	}
    }
    return undef;
}

sub format {
    my $this = shift;
    return $this->getdata("format");
}

sub diskfile { 
    my $this = shift;
    if (! exists $this->{diskfile}) {
	my $fmt = $this->format;
	my $vdata = $this->getdata("data");
	my ($base,$path,$filename,$data);
	if ($fmt eq "file") {
	    my $cnode = $this->content();
	    if ($cnode->defined) {
		$base = $cnode->basedir;
		$path = $cnode->subdir;
		my ($orig_filename,$contents) = split /#/, $vdata;
		$data = &decode_base64($contents);
		$filename = $this->filename;
	    }
	}
	elsif ($fmt eq "path") {
	    my $fullpath = $vdata;
	    if ($fullpath =~ /^$config{server}{fileroot}/) {
		$base = $config{server}{fileroot};
		$fullpath =~ s/^$config{server}{fileroot}//;
		my @path = split /\//, $fullpath;
		$filename = pop @path;
		$path = join "/",@path;
	    }
	    else {
		# not in fileroot
		my @path = split /\//, $fullpath;
		$filename = pop @path;
		$base = join "/",@path;
	    }
	}
	else { # $fmt eq "text"
	    $data = $vdata;
	    my $cnode = $this->content();
	    if ($cnode->defined) {
		$filename = $cnode->name();
		my $suffix = &MimeToFile($this->getdata("mime_type"));
		if ($filename !~ /\.$suffix$/) { $filename .= "." . $suffix; }
	    }
	}
	if ($base && $filename) {
	    $this->{diskfile} = new ExSite::Diskfile(
		base => $base,
		path => $path,
		filename => $filename,
		contents => $data,
		);
	    if ($this->{revision}) {
		# set time of last content change
		$this->{diskfile}->last_modified($this->{revision}->getdata("ctime"),"sql_datetime");
	    }
	}
	if (! $this->{diskfile}) {
	    # NB:  because we have a diskfile object doesn't mean we
	    # will have an actual file on disk
	    $this->{diskfile} = new ExSite::Diskfile(
		base => $this->content->basedir(),
		path => $this->content->subdir(),
		filename => $this->content->filename(),
		contents => $data,
		);
	}
    }
    return $this->{diskfile};
}

sub diskfile_old { 
    my $this = shift;
    if (! exists $this->{diskfile}) {
	if ($this->is_file) {
	    my $cnode = $this->content();
	    if ($cnode) {
		my $content = $cnode->get_content_obj();
		#my $path = $content->is_subdir ? 
		### do this give the same result
		my $path = $content->my_subdir ? 
		    scalar $content->subdir() : 
		    scalar $content->parent->subdir();
		my ($orig_filename,$contents) = split /#/, $this->{data}{data};
		my $base;
		my $s = $this->content->my_section;
		if ($s->defined && $s->getdata("url")) {
		    $base = $s->diskpath();
		}
		$this->{diskfile} = new ExSite::Diskfile(
		    base => $base,
		    path => $path,
		    filename => $this->filename,
		    contents => &decode_base64($contents),
		    );
		if ($this->{revision}) {
		    # set time of last content change
		    $this->{diskfile}->last_modified($this->{revision}->getdata("ctime"),"sql_datetime");
		}
	    }
	}
	if (! $this->{diskfile}) {
	    # NB:  because we have a diskfile object doesn't mean we
	    # will have an actual file on disk
	    $this->{diskfile} = new ExSite::Diskfile(
		path => $this->content->subdir(),
		filename => $this->content->filename(),
		contents => $this->{data}{data},
		);
	}
    }
    return $this->{diskfile};
}

sub content {
    my $this = shift;
    if (! $this->{content}) {
	my $rev = $this->revision();
	if ($rev) {
	    $this->{content} = $rev->content();
	}
	else {
	    $this->{content} = new ExSite::Content();
	}
    }
    return $this->{content};
}

sub revision {
    my $this = shift;
    if (! $this->{revision}) {
	$this->{revision} = $this->defined ? 
	    new ExSite::Revision(id=>$this->getdata("revision_id")) :
	    undef;
    }
    return $this->{revision};
}

# CONTENT QUERIES

sub allow {
    my $this = shift;
    return $this->content->allow();
}

sub deny {
    my $this = shift;
    return $this->content->deny();
}

# return the content-type

sub mime_type {
    my $this = shift;
    return $this->getdata("mime_type") || $this->guess_mime_type();
}
sub content_type { return &mime_type; }

sub guess_mime_type {
    my ($this,$data,$fmt) = @_;
    $data or $data = $this->getdata("data");
    if ($data) {
	# guess the mime-type of content that was passed to us
	$fmt or $fmt = $this->getdata("format");
	if ($fmt eq "text") {
	    # look for suggestive patterns
	    if ($data =~ /<(!--|[\/a-zA-Z])/) {
		return "text/html";
	    }
	    elsif ($data =~ /\/\*|[\w-]+:\s*[\w\#]+\;|^\w*\.\w+\s*\{/) {
		return "text/css";
	    }
	    else {
		return "text/plain";
	    }
	}
	elsif ($fmt eq "file") {
	    my ($filename,$fdata) = split /$config{form}{sepchar}/, $data;
	    return &MimeType($filename);
	}
	else {
	    # look at file type
	    return &MimeType($data);
	}
    }
    return undef;
}

# determine whether content is in a virtual file

sub is_file {
    my $this = shift;
    my $format = $this->getdata("format");
    return ($format eq "file" || $format eq "path");
}

# determine whether content is an image

sub is_image {
    my $this = shift;
    return $this->mime_type =~ /^image\//;
}

# determine whether content is text

sub is_text {
    my $this = shift;
    return $this->mime_type =~ /^text\//;
}

# determine whether content is publishable to a file
# -> essentially true for all non-HTML mime types in static pages/libraries

sub is_publishable {
    my $this = shift;
    my $mimetype = $this->mime_type();
    if ($mimetype && $mimetype !~ /html/) {
	### the content is publishable, but what about its cnode?
	return 1;
    }
    return 0;
}

# length - size of data in bytes

sub length {
    my $this = shift;
    return length $this->get_raw();
}

sub showdata {
    my ($this,$key) = @_;
    if ($this->defined) {
	if ($key eq "data") {
	    my $fmt = $this->{data}{format};
	    if ($fmt eq "file") {
		return $this->get_html_dynamic();
	    }
	    elsif ($fmt eq "url") {
		my $ml = &get_obj("ML");
		my $url = $this->getdata("data");
		return $ml->a($url,{href=>$url});
	    }
	}
	return $this->SUPER::showdata($key);
    }
    return undef;
}

sub report {
    my ($this,%opt) = @_;
    if ($this->ok) {
	if ($this->defined()) {
	    my $ml = &get_obj("ML");
	    my $db = $share{DB};
	    my $out;
	    my $access = $db->authorize;
	    my $ncol = $db->{map}->get_ncol("cview");
	    for (my $icol = 0; $icol < $ncol; $icol++) {
		my %colmap = $db->{map}->get_column("cview",$icol);
		next if ($colmap{read} > $access);
		$out .= $ml->tr(
		    $ml->th($colmap{label},{class=>"label"}).
		    $ml->td($this->showdata($colmap{column}),{class=>"data"})
		    );
	    }
	    return $ml->table(
		{caption=>$this->name,
		 tbody=>$out,
		 tfoot=>$opt{tfoot}},
		{class=>"Report"});
	}
	else {
	    my $name = ucfirst $this->name;
	    return $this->error("$name does not exist.");
	}
    }
    return $this->error($this->{status});
}

# return the raw content

sub get_raw {
    my $this = shift;
    if ($this->exists) {
	my $fmt = $this->getdata("format");
	if ($fmt eq "file") {
	    return $this->diskfile->contents;
	}
	elsif ($fmt eq "path") {
	    return &get_file($this->getdata("data"));
	}
	elsif ($fmt eq "url") {
	    # get_raw is inappropriate in this case;  we will return 
	    # a hyperlink to fetch the content
	    my $ml = new ExSite::ML;
	    my $data = $this->getdata("data");
	    return $ml->a($data,{href=>$data});
	}
	else { #if ($fmt eq "text") {
	    return $this->getdata("data");
	}
    }
    return undef;
}

# return the HTML tags needed to inline the content into a page

sub get_html {
    my ($this,%opt) = @_;
    my $extra_attributes = $opt{attributes};
    my $url = $opt{url};
    if ($this->exists) {
	my $type = $this->mime_type();
	my $attributes = {};
	my $data = $this->get();
	if ($data->{attributes}) {
	    $attributes = &DecodeAttributes($data->{attributes});
	}
	if (ref $extra_attributes eq "HASH") {
	    $attributes =  { %$attributes, %$extra_attributes };
	}
	my $ml = new ExSite::ML(safe_attributes=>0);
	if ($type =~ /^text\/html$/) {
	    # html can be returned straight-up
	    return $this->get_raw;
	}
	elsif ($type =~ /^text\/css$/) {
	    #my $inline_css = $opt{inline_css} || $config{content}{inline_css};
	    if ($config{content}{inline_css}) {
		my $css = $this->get_raw;
		$attributes->{type} = "text/css";
		return $ml->style("\n$css",$attributes);
	    }
	    else {
		$url or $url = $this->get_url();
		$attributes->{rel} = "stylesheet";
		$attributes->{type} = "text/css";
		$attributes->{href} = $url;
		return $ml->link(undef,$attributes);
	    }
	}
	elsif ($type =~ /^text/) {
	    if ($config{content}{preformatted_plaintext}) {
		return $ml->pre($this->get_raw);
	    }
	    else {
		return $this->get_raw;
	    }
	}
	elsif ($type =~ /^image/) {
	    # images are rendered using IMG tags
	    $url or $url = $this->get_url();
	    if (! exists $attributes->{alt}) {
		# add an alt to make W3C happy
		$attributes->{alt} = $this->content->label;
	    }
	    my $title = $this->get("title");
	    if (! exists $attributes->{title} && $title) {
		# tooltip (using title attribute)
		$attributes->{title} = $title;
	    }
	    $attributes->{src} = $url;
	    return $ml->img(undef, $attributes);
	}
	elsif ($type =~ /^application\/x-shockwave-flash$/) {
	    # flash objects require some embedded object cruft
	    if (! $url) { $url = $this->get_url(); }
	    my $filename = $this->filename;
	    # attributes typically has dimensions for the movie
	    my $objattr = $attributes;
	    $objattr->{type} = "application/x-shockwave-flash";
	    $objattr->{data} = $url;
	    # return a flash object containing appropriate params
	    # followed by an IE Flash hack script
	    my $objcontents = 
		$ml->param(undef,{name=>"allowScriptAccess",value=>"sameDomain"}).
		$ml->param(undef,{name=>"quality",value=>"best"}).
		$ml->param(undef,{name=>"movie",value=>$url});
	    if ($attributes->{img}) {
		# optional img attribute specifies an image that will be used
		# if flash is not enabled
		$objcontents .= $ml->img(undef,$attributes->{img});
		delete $objattr->{img};
	    }
	    return $ml->object($objcontents,$objattr).
		$ml->script(undef,{ src=>"$config{server}{HTMLpath}/_ExSite/js/flashinsert.js" });
	}
	elsif (! $data->{data}) {
	    # empty revision
	    return "";
	}
	else {
	    # miscellaneous types are shown as hotlinks
	    if (! $url) { $url = $this->get_url(); }
	    my $filename = $this->filename() || "$msg{Download} $type";
	    $attributes->{href} = $url;
	    return $ml->a($filename,$attributes);
	}
    }
    return undef;
}

# return the HTML tags needed to inline the content into a page

sub get_html_dynamic {
    my ($this, %opt) = @_;
    $opt{url} = $this->get_url_dynamic();
    return $this->get_html(%opt);
}

# return a URL that fetches the content as a separate HTTP request
sub get_url {
    my $this = shift;
    my $format = $this->getdata("format");
    if ($format =~ /file|path/) {
#	return $this->diskfile->exists ?
	return $this->file_exists ?
	    $this->get_url_static : 
	    $this->get_url_dynamic;
    }
    elsif ($format eq "url") {
	return $this->getdata("data");
    }
    else {
	return $this->get_url_dynamic();
    }
}

sub get_url_static {
    my $this = shift;
    my $format = $this->getdata("format");
    if ($format eq "file") {
	my $content = $this->content();
	my $view = $this->getdata("type");
	if ($content->get("view") eq $view) {
	    return $content->get_url_static;
	}
	else {
	    # different view that our object is currently using
	    my $c = $content->get_content_obj($content->get());

	    ### preload rev and view into this content obj?

	    $c->set_view($view);
	    return $c->get_url_static;
	}
    }
    elsif ($format eq "path") {
	my $cnode = $this->content();
	if ($cnode) {
	    return $cnode->httpbase.$cnode->subdir."/".$this->filename;
	}
    }
    elsif ($format eq "url") {
	return $this->getdata("data");
    }
    # nothing suitable found
    return "$config{server}{HTMLpath}/_ExSite/images/checker.png";
}

sub get_url_dynamic {
    my $this = shift;
    my $format = $this->getdata("format");
    return $this->get_url() if ($this->getdata("format") eq "url");
    my $path = $this->content->path();
    my $url = "$config{server}{CGIpath}/$config{prog}{view}$path";
    my %query;
    my $vtype = $this->getdata("type");
    if ($vtype ne "normal") {
	$query{view} = $vtype;
    }
    my $revid = $this->content->get("revid");
    if ($revid && $revid ne $this->revision->id) {
	$query{revision} = $this->revision->id;
    }
    if (scalar keys %query > 0) {
	$url .= "?".&EncodeHash(%query);
    }
    return $url;
}

sub get_image {
    my $this = shift;
    if ($this->exists && 
	$this->is_image && 
	$this->format =~ /file|path/) {
	return new ExSite::Image($this->diskfile->filename,
				 $this->diskfile->contents);
    }
    $this->warn("cannot make Image object from revision");
    return undef;
}

sub set_image {
    my ($this,$img,$filename) = @_;
    if ($this->is_image && 
	$this->format eq "file") {
	my %opt;
	if ($filename) {
	    $opt{filename} = $filename;
	}
	$opt{contents} = $img->get("filedata");
	$this->diskfile->setup(%opt);                 ######### check
	$this->setdata("data",$img->encode);
	return 1;
    }
    else {
	$this->error("cannot convert view to image");
	return 0;
    }
}
		
sub height {
    my $this = shift;
    my @dim = $this->dim();
    return $dim[1];
}

sub width {
    my $this = shift;
    my @dim = $this->dim();
    return $dim[0];
}

sub dim {
    my $this = shift;
    if (! $this->{dim}) {
	my $mime = $this->mime_type;
	if ($mime =~ /^image/) {
	    my $img = $this->get_image();
	    my @dim = $img->dim();
	    $this->{dim} = \@dim;
	}
	else {
	    $this->{dim} = [0,0];
	}
    }
    return @{$this->{dim}};
}

# show: display the content

sub show {
    my ($this,%opt) = @_;
    my $mode = $opt{mode};
    if ($mode =~ /source/ && $this->content_type =~ /^text/) {
	# source view
	my $ml = new ExSite::ML(safe_content=>0);
	return $ml->pre($this->get_raw);
    }
    elsif ($mode =~ /preview/) {
	# administrator view (slow)
	return $this->get_html_dynamic(%opt);
    }
    else {
	# normal view
	return $this->get_html(%opt);
    }
}

# show the view as an icon
# - use image itself if the view is an image
# - otherwise, use a mime-type icon
# size = preferred/max icon size in pixels (eg. 64)

sub show_icon {
    my ($this,$size) = @_;
    $size or $size = $config{content}{viewdim}{icon};
    if ($this->is_image) {
	my $img = $this->get_image();
	if ($img) {
	    my ($w,$h) = $img->dim();
	    my $attr;
	    if ($w > $size || $h > $size) {
		# scale down
		my $max = $w > $h ? $w : $h;
		my $scale = $max > 0 ? $size / $max : 1.0;
		$attr = {
		    width => int($w * $scale),
		    height => int($h * $scale)
		};
	    }
	    return $this->show(attributes=>$attr);
	}
    }
    # show a mime-type icon
    my $mime = $this->mime_type();
    my $image;
    my ($class,$type) = split /\//,$mime;
    if (-e "$config{server}{HTMLroot}$config{server}{HTMLpath}/_ExSite/images/mime/${type}.png") {
	$image = "${type}.png";
    }
    elsif (-e "$config{server}{HTMLroot}$config{server}{HTMLpath}/_ExSite/images/mime/${class}.png") {
	$image = "${class}.png";
    }
    else {
	$image = "blank.png";
    }
    my $ml = &get_obj("ML");
    return $ml->img(undef,{src=>"$config{server}{HTMLpath}/_ExSite/images/mime/$image",height=>$size,width=>$size,alt=>$mime,title=>$mime});
}

# determine the published filename of a content datum "virtual file"
# NB: for path formats, this is not necessarily the same as the 
# installed filename

sub filename {
    my $this = shift;
    my $format = $this->getdata("format");
#    if ($format eq "file") {
#	return $this->diskfile->filename;
#    }
#    elsif ($format eq "path") {
#    if ($format eq "path") {
#	# strip path info
#	my @path = split /[:\\\/]/, $this->getdata("data");
#	return $path[-1];
#    }
#    elsif ($format eq "url") {
    if ($format eq "url") {
	# strip path info
	my @path = split /\//, $this->getdata("data");
	return $path[-1];
    }
    elsif ($this->defined) {
#	my $suffix = &MimeToFile($this->content_type);
#	return $this->content->id . "." . $suffix;
	my $suffix = &MimeToFile($this->content_type);
	my $prefix = $config{content}{viewprefix}{$this->getdata("type")};
	my $name = $this->content->name;
	return $name =~ /\.$suffix$/ ? 
	    "$prefix$name" :          # suffix already part of name
	    "$prefix$name.$suffix";   # append suffix for easier filetype id
    }
    return undef;
}

sub original_filename {
    my $this = shift;
    if ($this->defined) {
	my ($orig_filename,undef) = split /#/, $this->getdata("data");
	return $orig_filename;
    }
    return undef;
}

# determine the htdocs path to the file, if published

sub httppath {
    my $this = shift;
    my $format = $this->getdata("format");
    if ($format eq "file") {
	my $path = $this->content->path;
	my $file = $this->diskfile->filename;
	return "$path/$file";
    }
    elsif ($format eq "path") {
	my $path = $this->getdata("data");
	if ($path =~ /^$config{server}{HTMLroot}/) {
	    $path =~ s/^$config{server}{HTMLroot}//;
	    return $path;
	}
    }
    # else, not in the htdocs
    return undef;
}

# determine the path to the file, if published

sub diskpath {
    my $this = shift;
    $_ = $this->getdata("format");
    if (/file/) {
	return $this->diskfile->location;
    }
    elsif (/path/) {
	return $this->getdata("data");
    }
    return undef;
}

# return the timestamp from the last time the content was published

sub is_published {
    my $this = shift;
    if ($this->exists) {
	my $rev = $this->revision; 
	my $ptime = $rev->getdata("ptime");
	return ($ptime !~ /^0+/);
### only indicates that it was published at one time; should also check for
### existence of file on disk
    }
    return 0;
}

# see if file exists in htdocs

sub file_exists {
    my $this = shift;
    my $format = $this->getdata("format");
    my $location;
    if ($format eq "file") {
	$location = $this->diskfile->location;
    }
    elsif ($format eq "path") {
	my $data = $this->getdata("data");
	if ($data =~ /^$config{server}{fileroot}/) {
	    my $cnode = $this->content();
	    $location = $cnode->diskpath."/".$cnode->filename;
	}
	elsif ($data =~ /^$config{server}{HTMLroot}/) {
	    $location = $data;
	}
    }
    return $location ? -e $location : 0;
}

### FIXME: publish to file repository, link to HTdocs

sub publish {
    my ($this,%opt) = @_;
    if ($this->is_publishable) {
	my $fmt = $this->format();
	if ($fmt eq "path") {
	    my $cnode = $this->content();
	    if ($cnode) {
		$this->diskfile->link($cnode->basedir,$cnode->subdir,$this->filename);
		$this->diskfile->clear;
	    }
	}
	else {
	    $this->diskfile->publish($opt{force});
	    $this->diskfile->clear;
	}
    }
    return undef;
}

# remove the file associated with the content data

sub unpublish {
    my $this = shift;
    if ($this->is_publishable) {
	my $fmt = $this->format();
	if ($fmt eq "path") {
	    my $cnode = $this->content();
	    if ($cnode) {
		$this->diskfile->unlink($cnode->basedir,$cnode->subdir,$this->filename);
	    }
	}
	else {
	    return $this->diskfile->unpublish();  # unlink?
	}
    }
}

#===========================================================================
# install
#
# tries to put files in fileroot
# this should result in less DB traffic and faster performance
# if successful, rewrites the view record to use the path view type

sub install {
    my ($this,%opt) = @_;

    if ($this->is_file) {
	my $content = $this->content();
	if ($content->defined) {
	    my $name = $content->name;
	    my $subpath = $name."-".$content->id."-".$this->revision->id;
	    my $installed_file = $this->diskfile->install(
		filename=>$this->filename,
		name=>$name,
		subpath=>$subpath,
		);
	    if ($installed_file) {
		# looks like file installed correctly; rewrite the view to
		# use the installed version instead
		$this->setdata("format","path");
		$this->setdata("data",$installed_file->location);
		$this->save() if ($opt{save});
		return $installed_file;
	    }
	}
    }
    return undef;
}

#===========================================================================
# DB functions

sub validate {
    my $this = shift;
    my @err = $this->SUPER::validate();
    my @view = $share{DB}->fetch_child("cview","revision",$this->revision->id);
    my $action = $this->action;
    if ($action eq "insert") {
	my %view = &keywise("type",\@view);
	if (exists $view{$this->{data}{type}}) {
	    # trying to insert a view that already exists
	    push @err, $this->{data}{type}." view already exists for this revision";
	}
    }
    elsif ($action eq "update") {
	foreach my $v (@view) {
	    if ($v->{type} eq $this->{data}{type} && $v->{cview_id} != $this->id) {
		# changing to a view that already exists
		push @err, $this->{data}{type}." view already exists for this revision";
	    }
	}
    }
    return @err;
}

# unload: drop optionally loadable data to reduce memory usage

sub unload {
    my $this = shift;
    delete $this->{diskfile};
    delete $this->{revision};
    delete $this->{content};
    $this->SUPER::unload();
}

#===========================================================================
# DiskFile proxy calls

sub get_fileinfo {
    my $this = shift;
    return $this->diskfile->get_fileinfo();
}

#sub filename {
#    my $this = shift;
#    return $this->diskfile->filename();
#}

sub path {
    my $this = shift;
    return $this->diskfile->path();
}

sub diskpath {
    my $this = shift;
    return $this->diskfile->diskpath();
}

sub location {
    my $this = shift;
    return $this->diskfile->location();
}

sub contents {
    my $this = shift;
    return $this->diskfile->contents();
}

=pod

=head1 ExSite::View - Content Data Handling

Every revision of a content object can be broken down into one or more
views. The supported views are:

=over 4

=item normal

This is the default view of the content, intended for insertion into a
regular web page. If the content is an image, it is scaled to a
typical web page body width (by default 512 pixels).

=item large

If the original data is larger than the normal view, we can optionally
retain it in its original form as a large view. (The CMS may
nevertheless scale it down if it too large to save in the CMS.) Large
views are also suitable for HD video that is larger than what would be
served to viewers by default, large or uncompressed documents, and so
on.

=item small

A small view is intended to be used with content summaries, such as
are used in listings and indexes. Small views of text content include
abstracts, teasers, and summaries. Small views of images are typically
scalled down (by default to 256 pixels) so that they can be floated
left or right of the surrounding text. Small views of documents might
consist of simply the cover or introduction.

=item thumbnail

Thumbnails are normally used for images. A thumbnail view is scaled to
a good size for aggregating into thumbnail grids or "contact
sheets". If a thumbnail view is requested, we scale it down to the
system thumbnail size (typically 100 pixels). For other types of
content, we can install image thumbnails so that they can also be
presented this way.

=item icon

An icon view is an extra-small view that is typically used for listing
files or downloads. They are small enough to inline into text. Icon
views are not automatically generated. The system can be asked to
provide a generic icon (eg. suitable for the content's mime-type) if
no specific icon is installed.

=back

Setup/create your view object in one of these ways:

    my $view = $revision->select_view($viewtype);
    my $view = new ExSite::View(id=>$view_id);
    my $view = new ExSite::View(data=>\%viewdata);

Internally, the view is stored in one of 4 formats:

=over 4 

=item * as a file that was uploaded

=item * as text that was entered directly

=item * as apath to some other file on the server

=item * as an URL to a remote resource elsewhere on the web

=back

The latter two are less commonly used, as the content data is outside
the control of the CMS, but they can help in some unusual cases. You
can obtain the particular format used in a view using:

    $view->format();
    $view->is_file();  # true if file format

=head2 Disk Files

In cases where the view can publish as a file (such as images,
stylesheets, documents, and so on), you can obtain a Diskfile object
that represents this file:

    my $file = $view->diskfile();

This object is used for all publishing operations. See the
documentation for ExSite::Diskfile for more information.

The filename that will be used for the current view is given by:

    my $filename = $view->filename();

The original filename that was used to upload the file can be retrieved using:

    my $orig_filename = $view->original_filename();

The publication location of the file can be obtained using:

    $view->httppath();   # path in URL
    $view->diskpath();   # full path on server

=head2 MIME-type

Each view records its own mime-type, which can be retrieved using:

    my $mime = $view->getdata("mime_type");

If the mime-type is not recorded, we can make a guess based on the 
data or file extensions:

    my $mime = $view->guess_mime_type();

You can also use this to guess the mime type of other content, by
passing in the data directly in one of the 4 accepted formats:

    my $mime = $view->guess_mime_type($data,$format);

The simplified call:

    my $mime = $view->mime_type();

does all of the above, as needed, to come up with a suitable mime-type
for the content.

The following calls will also give you some more general MIME information:

    $view->is_image;
    $view->is_text;
    $view->is_publishable;  # true for all non-HTML MIME-types

=head3 Images

If the data is an image, you can fetch an ExSite::Image object for it:

    my $img = $view->get_image();

You can also do the reverse, and pass an ExSite::Image object in as the data:

    $view->set_image($img,$filename);

The following calls will work for images:

    my $w = $view->width;
    my $h = $view->height;
    my ($w,$h) = $view->dim;

=head2 Retrieving/Displaying Data

Views can be output/displayed in 3 ways:

=over 4

=item HTML

The system will generate the necessary HTML to display the content.

=item URL

The system will return an appropriate URL to retrieve the content,
suitable for use in hyperlinks or as SRC= attributes in img tags.

=item raw

The system will return the raw content directly. This is suitable for
delivering the content direct to the user's browser, or writing it to
a disk file.

=back

Use the following methods:

    $view->get_html();
    $view->get_html_dynamic();
    $view->get_url();
    $view->get_url_dynamic();
    $view->get_url_static();
    $view->get_raw();

    $view->show(mode=>"source"); # outputs displayable HTML source code
    $view->show(mode=>"preview"); # displays from the database, not published files

=cut

1;
