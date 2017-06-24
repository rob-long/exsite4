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

package ExSite::Revision;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Image;
use ExSite::ML;
use ExSite::Content;
use ExSite::View;
use ExSite::Diskfile;
use ExSite::Object;
use MIME::Base64;

use vars qw(@ISA);
@ISA = qw(ExSite::Object ExSite::Workflow);

sub my_type { return "revision"; }

sub setup {
    my ($this,%opt) = @_;
    $this->{content} = undef;
    $this->{cview} = undef;
    $this->SUPER::setup(%opt);
    if ($opt{content}) {
	$this->{content} = $opt{content};
    }
    return;
}

sub content {
    my $this = shift;
    if (! $this->{content}) {
	if ($this->defined) {
	    my $cnode = new ExSite::Content(id=>$this->getdata("content_id"));
	    $this->{content} = $cnode->get_content_obj();
	}
    }
    return $this->{content};
}

sub allow {
    my ($this,$op) = @_;
    return $this->content->allow($op);
}

# set the view

sub view_orig {
    my ($this,$requested_view) = @_;
    $this->{view} or $this->{view} = "normal";
    $requested_view or $requested_view = $this->{view};
    if (! $this->{cview}) {
	$this->{cview} = $this->select_view($requested_view);
    }
    return $this->{cview} || new ExSite::View;
}

sub view { ############################################################
    my ($this,$requested_view) = @_;
    $this->{view} or $this->{view} = "normal";
    $requested_view or $requested_view = $this->{view};
    if (! $this->{cview}) {
	$this->{cview} = $this->select_view($requested_view);
	if ($this->{cview}) {
	    $this->{view} = $this->{cview}->getdata("type");
	}
    }
    return $this->{cview} || new ExSite::View;
}

sub load {
    my ($this,$data) = shift;
    if (ref $data eq "HASH") {
	# we were given a complete datahash
	$this->{data} = $data;
	$this->{id} = $data->{content_id};
    }
    elsif ($data) {
	# we were given an object ID
	$this->{id} = $data || $this->id;
	$this->{data} = $share{DB}->fetch("revision",$this->{id});
    }
    elsif ($this->{id} && ! $this->{data}) {
	# we were given nothing - use our existing ID
	$this->{data} = $share{DB}->fetch("revision",$this->{id});
    }
    if (! $this->{id} && $this->{data}) { 
	# our data doesn't seem to match this object type
	$this->error("Mis-configured revision object."); 
	return undef;
    }
    elsif (! $this->{id} || ! $this->{data}) { 
	# failed to load anything
	if ($this->{content}) {
	    if (! $this->{content}{no_revisions}) {
		$this->warn("Content " . $this->{content}->name . " has no revisions.");
		$this->{content}{no_revisions} = 1; # issue 1 warning only
	    }
	}
	else {
	    $this->warn("Undefined revision."); 
	}
	return undef;
    }
    # load our views as well (abbreviated - leave off file data)
    $this->{views} = &keywise("type", scalar $share{DB}->select("cview",["cview_id","type","mime_type","format","attributes"],{revision_id=>$this->{id}}));
    #$share{DB}->fetch_child("cview","revision",$this->id));
    return $this->{data};
}

sub loaded {
    my ($this) = shift;
    if (! $this->{data} || ! defined $this->{views}) {
	$this->load;
    }
    return defined $this->{data} && defined $this->{views};
}

sub select_view {
    my ($this,$requested_view) = @_;
    if ($this->loaded) {
	my ($best_view,$viewtype);
	foreach $viewtype (@{$config{content}{altview}{$requested_view}}) {
	    next if (! $this->{views}{$viewtype});
	    if ($viewtype eq $requested_view) {
		$best_view = $this->{views}{$viewtype};
		last;
	    }
	    elsif (! $best_view) {
		$best_view = $this->{views}{$viewtype};
	    }
	}
	return new ExSite::View(revision=>$this,data=>$best_view);
    }
    return undef;
}

sub has_view {
    my ($this,$viewtype) = @_;
    if ($this->loaded) {
	return exists $this->{views}{$viewtype};
    }
    return undef;
}

sub has_views {
    my ($this) = @_;
    if ($this->loaded) {
	return keys %{$this->{views}};
    }
    return ();
}

# return the timestamp

sub timestamp {
    my $this = shift;
    my $type = shift || "ctime";
    return $this->getdata($type);
}

sub allow {
    my $this = shift;
    return $this->content->allow();
}

sub deny {
    my $this = shift;
    return $this->content->deny();
}

# VIEW QUERIES

# return the content-type

sub mime_type {
    my ($this,$data,$fmt) = @_;
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
    else {
	# warning: revision mime-type may not be the same as the mime-type of the 
	# current view. Eg. the icon view of a text revision will probably have an
	# image mime-type.
	return $this->getdata("mime_type");
    }
}
sub content_type { &mime_type; }

# determine whether content is in a virtual file

sub is_file {
    my $this = shift;
    return $this->view->is_file;
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

# in the event that the content data is an upload, return the file info
# (filename, size (K), mime-type)

sub get_fileinfo {
    my $this = shift;
    return $this->view->get_fileinfo;
}

sub description { 
    my $this = shift;
    my $info = $this->get_fileinfo();
    return $info ? $info->{description} : undef;
}

sub filename {
    my $this = shift;
    return $this->view->filename;
}

# content fetching functions 

sub get_raw {
    my $this = shift;
    return $this->view->get_raw;
}

sub get_html {
    my $this = shift;
    return $this->view->get_html;
}

sub get_html_dynamic {
    my $this = shift;
    return $this->view->get_html_dynamic;
}

sub get_url {
    my $this = shift;
    return $this->view->get_url;
}

sub get_url_static {
    my $this = shift;
    return $this->view->get_url_static;
}

sub get_url_dynamic {
    my $this = shift;
    return $this->view->get_url_dynamic;
}

# Thumbnails

sub get_thumb {
    my $this = shift;
    return ($this->view->getdata("type") eq "thumbnail") ?
	$this->view : $this->select_view("thumbnail");
}

sub get_thumb_html {
    my $this = shift;
    my $view = $this->get_thumb;
    my $type = $view->getdata("type");
    if ($type eq "thumbnail") {
	# our view is the real thumbnail
	return $view->get_html();
    }
    elsif ($config{content}{viewsize}{$type} > $config{content}{viewsize}{"thumbnail"}) {
	# our alternate view is larger than a thumbnail
	return $view->get_html(attributes=>{height=>$config{thumbnail_size},width=>$config{thumbnail_size}});
    }
    else {
	# our alternate view is smaller than a thumbnail
	return $view->get_html();
    }
    return undef;
}

sub get_thumb_url {
    my $this = shift;
    my $view = $this->get_thumb;
    return $view->get_url;
}

sub get_thumb_raw {
    my $this = shift;
    my $view = $this->get_thumb;
    return $view->get_raw;
}

# Icons

sub get_icon {
    my $this = shift;
    return ($this->view->getdata("type") eq "icon") ?
	$this->view : $this->select_view("icon");
}

sub get_icon_html {
    my $this = shift;
    my $view = $this->get_icon;
    my $type = $view->getdata("type");
    if ($type eq "icon") {
	# we have a custom icon
	return $view->get_html();
    }
    else {
	my $url = $this->get_icon_url();
	if ($url) {
	    return &get_obj("ML")->img(undef,{src=>$url,height=>$config{content}{viewdim}{icon},width=>$config{content}{viewdim}{icon},class=>"icon"});
	}
    }
    return undef;
}

sub get_icon_url {
    my $this = shift;
    my $view = $this->get_icon;
    my $type = $view->getdata("type");
    if ($type eq "icon") {
	# we have a custom icon
	return $view->get_url();
    }
    else {
	my $mime = $this->mime_type();
	if ($view->is_image && $config{content}{viewsize}{$type} < 3) {
	    # no icon, but we have a thumbnail; simply scale down to icon size
	    return $view->get_url();
	}
	else {
	    # no specific icon; use a generic icon
	    return $this->get_generic_icon_url();
	}
    }
    return undef;
}

sub get_icon_raw {
    my $this = shift;
    my $view = $this->get_icon;
    return $view->get_raw;
}

sub get_generic_icon_url {
    my $this = shift;
    my $mime = $this->mime_type();
    if (exists $config{icon}{$mime}) {
	# use a stock icon for this mimetype
	return "$config{server}{HTMLpath}/_ExSite/images/icons/$config{icon}{$mime}";
    }
    else {
	$mime =~ s/\/\w+$//;
	if (exists $config{icon}{$mime}) {
	    # use a stock icon for this generic mimetype (image, text, etc.)
	    return "$config{server}{HTMLpath}/_ExSite/images/icons/$config{icon}{$mime}";
	}
	elsif (exists $config{icon}{generic}) {
	    # use a generic icon
	    return "$config{server}{HTMLpath}/_ExSite/images/icons/$config{icon}{generic}";
	}
    }
    return undef;
}

sub get_image {
    my $this = shift;
    if ($this->loaded) {
	my $view;
	foreach my $viewtype (@{$config{content}{altview}{$this->{view}}}) {
	    if ($this->{views}{$viewtype}) {
		$view = new ExSite::View(revision=>$this,data=>$this->{views}{$viewtype});
		last if ($view->is_image);
	    }
	}
	return $view;
	### should this be $view->get_image() ??
    }
    return undef;
}

# show: display the content

sub show {
    my ($this,%opt) = @_;
    ### access control ?? eg. should public see archived revs?
    $this->view->show(%opt);
}

### deprecated; use description();

sub info_old {
    my $this = shift;
    my @info;
    if ($this->is_file || $this->view->getdata("format") eq "path") {
	my %info = $this->get_fileinfo;
	push @info, $info{filename}, &MimeDescr($info{mimetype});
	if ($info{size_mb} > 1) { push @info, "$info{size_mb} MB"; }
	elsif ($info{size_kb} > 1) { push @info, "$info{size_kb} kB"; }
	else { push @info, "$info{size_b} bytes"; }
    }
    else {
	my $mime = $this->mime_type;
	my $size = $this->view->length;
	push @info, &MimeDescr($mime), "$size bytes";
    }
    return join(", ",@info);
}

sub httppath {
    my $this = shift;
    return $this->view->httppath;
}

sub diskpath {
    my $this = shift;
    return $this->view->diskpath;
}

# return the timestamp from the last time the content was published

sub is_published {
    my $this = shift;
    if ($this->exists) {
	my $ptime = $this->getdata("ptime");
	return ($ptime !~ /^0+/);
### only indicates that it was published at one time; should also check for
### existence of file on disk
    }
    return 0;
}

### danger - should we allow publishing on arbitrary revisions??

### should we unpublish the previous revision first?

sub publish {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    if ($this->loaded) {
	if ($this->is_active) {
	    if ($this->content->is_static) {
		# write out files, if they are static
		foreach my $viewtype (@{$config{content}{altview}{normal}}) {
		    if ($this->{views}{$viewtype}) {
			my $v = new ExSite::View(revision=>$this,data=>$this->{views}{$viewtype});
			$v->publish(%opt);
			$v->unload(); # done with the view, free up memory
		    }
		}
	    }
	    if ($this->getdata("ptime") =~ /^0/) {
		# first time - set the ptime
		my $null = "NULL";
		$this->setdata("ptime",\$null);
		$this->save();
	    }
	}
    }
}

sub unpublish {
    my $this = shift;
    my $out;
    if ($this->loaded) {
	# no status check, so we can unpublish bad revs
	foreach my $viewtype (@{$config{content}{altview}{normal}}) {
	    if ($this->{views}{$viewtype}) {
		my $v = new ExSite::View(revision=>$this,data=>$this->{views}{$viewtype});
		$out .= $v->unpublish();
		$v->unload(); # done with the view, free up memory
	    }
	}
	# clear ptime publish timestamp
	$this->setdata("ptime","0000-00-00 00:00:00");
	$this->save();
    }
    return $out;
}

sub restore {
    my $this = shift;
    if ($this->allow("update")) {
	my $note = $this->getdata("note");
	if ($note) { $note .= " "; }
	$note .= "(restored revision ".$this->id.")";
	return $this->copy(note=>$note);
    }
    else {
	$this->error("Permission denied.");
    }
    return undef;
}

sub copy {
    my ($this,%data) = @_;
    if ($this->loaded) {
	if (! $data{note}) {
	    my $note = $this->getdata("note");
	    if ($note) { $note .= " "; }
	    $note .= "(copied from revision ".$this->id.")";
	    $data{note} = $note;
	}
	my $new_revid = $this->SUPER::copy(%data);
	foreach my $vtype (qw(large normal small thumbnail icon)) {
	    if ($this->has_view($vtype)) {
		my $v = new ExSite::View(revision=>$this,data=>$this->{views}{$vtype});
		if ($v->loaded()) { # in case it's just a partial view from the cache
		    $v->copy(revision_id=>$new_revid);
		}
	    }
	}
	return $new_revid;
    }
    return undef;
}

# unload: drop optionally loadable data to free up memory

sub unload {
    my $this = shift;
    delete $this->{content};
    delete $this->{view};
    delete $this->{cview};
    delete $this->{views};
    $this->SUPER::unload();
}

#===========================================================================
# Revision workflow
# uses same workflow tools as content, but a more limited set of options

# status checks
# NB: revisions only use a subset of workflow statuses:
# published - taken live
# draft - do not take live yet
#
# archived, approved, queued, canceled, rejected - not used

sub wf_run_publisher { # do nothing
    return;
}

# disable non-meaningful status changes
sub wf_archive { return; }
sub wf_cancel { return; }
sub wf_approve { return; }
sub wf_queue { return; }
sub wf_reject { return; }
sub wf_submit { return; }
sub wf_expire { return; }

=pod

=head1 ExSite::Revision - CMS Revision Handling

Every time a content object is updated, we create a new revision to
track the changes. Old revisions are kept on file until explicitly
deleted. We can track an unlimited number of old revisions.

A few revisions have special importance:

=over 4

=item draft

The draft revision is the most recently added revision.

=item newest

The newest revision is the most recently added revision that is approved for 
public viewing.

=item active

The active revision is the most recently published one. It is the one
that is viewable to the public.

=back

These may all point to the same revision, if the most recent revision has been 
published.

=head2 Setup

There are different methods for creating a revision object:

To get the current revision used by a content object:

    my $r = $content->revision();

To select a specific revision for a particular piece of content:

    my $r = $content->find_revision($rev) 

C<$rev> can be "active", "newest", or a particular revision ID. It
defaults to active.

To create a revision directly:

    my $r = new ExSite::Revision(id=>$revision_id);
    my $r = new ExSite::Revision(data=>\%revision_data);

In both of these cases, you can also optionally pass
C<content=E<gt>$content_object> if you know it. This will speed up some
operations that need to know the context.

=head2 Revision Management

=head3 C<is_published()>

Returns true if the revision has ever been published.

=head3 C<publish()>

Write the revision's files to disk, if possible. Regardless of whether
any files are written, we mark the revision as published, which means
it is viewable by the public.

=head3 C<unpublish()>

Remove the revision's files from disk.

=head3 C<copy(%data)>

Copy this revision, and all its views. Updates the note to reflect 
that it is a copy. A revision can be copied to another content object
by passing the the content_id in the parameter data.

=head3 C<restore()>

Uses copy() to creates a new revision that is identical to this 
revision.  This is used to "restore" an old revision to use, 
without rolling back through all the intermediate revisions.

=head2 Views

The actual content is stored in B<views>. The revision itself only
contains information about the update, such as timestamps and
changelog notes. There are 5 supported views: normal (default), large,
small, thumbnail, and icon. Most revisions will consist of a normal
view, plus some optional alternate views.

The normal view is selected by default, but you can select a different
view using:

    $r->select_view($preferred_view);

To return the current selected view, use:

    $r->view();

where C<$preferred_view> is one of normal, large, small, thumbnail, or
icon. If your preferred view is not avaialable, it will select the
closest matching view. Use the following calls to get information
about the available views:

    $r->has_views();  # returns true if ANY views are available
    $r->has_view($view_type); # returns true if the given view is available

When you ask to display a revision, its mime-type, or fetch its URL,
the result will reflect the selected view. In fact, most calls to
fetch information about the actual content will simply be passed
through to the selected view, such as:

    $r->mime_type();
    $r->is_file();
    $r->is_image();
    $r->is_text();
    $r->get_fileinfo();
    $r->filename();
    $r->get_raw();
    $r->get_html();
    $r->get_html_dynamic();
    $r->get_url();
    $r->get_url_static();
    $r->get_url_dynamic();
    $r->show();
    $r->httppath();
    $r->diskpath();

There are also some shortcut calls to access commonly-used views:

    $r->get_thumb();
    $r->get_thumb_html();
    $r->get_thumb_url();
    $r->get_thumb_raw();
    $r->get_icon();
    $r->get_icon_html();
    $r->get_icon_url();
    $r->get_icon_raw();
    $r->get_generic_icon_url();  # finds an icon, even if there is no such view

See the documentation for ExSite::View for more information.

=cut

1;
