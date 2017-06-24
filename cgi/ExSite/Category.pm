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

package ExSite::Category;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::ML;
use ExSite::Util;
use ExSite::URI;
use ExSite::Content;
use ExSite::Page;
use MIME::Base64;

use vars qw(@ISA);
@ISA = qw(ExSite::Page);

sub my_subtype { return "category"; }

sub show {
    my ($this,%opt) = @_;
    return $this->index(%opt);
}

sub show_templated {
    my ($this,%opt) = @_;
    $opt{content}{body} = $this->show(%opt);
    return $this->expand(%opt);
}

sub preview {
    my ($this,%opt) = @_;
    $opt{view} = "small";
    return $this->index(%opt);
}

# index - display a listing of current items in the category

sub index {
    my ($this,%opt) = @_;
    my @item = $this->get_contents(); #### UNSORTED ??
    my $ml = &get_obj("ML");
    my $hlevel = $opt{level} || 2;
    if ($hlevel > 6) { $hlevel = 6; }
    my $heading = "h$hlevel";
    my $out = $ml->$heading($this->title);
    while (scalar @item > 0) {
	my $item = pop @item;
	next if (! $item->is_active);
	next if ($item->getdata("status") eq "archived" && ! $opt{archive});
	$opt{level} = $hlevel + 1;
	my $url = $item->get_url();
	$out .= $ml->div(
	    $ml->a($item->title,{href=>$item->get_url}),
	    {class=>"CategoryItem"}
	    );
    }
    # FIXME: archive, RSS ??
    return $ml->div($out,{class=>"Category"});
}

# find - use the category itself as the page body

sub find {
    my ($this,$name) = @_;
    my $content = $this->SUPER::find($name);
    if ($name eq "body" && 
	(! $content ||                                 # error
	 ! $content->defined ||                        # nothing found
	 $content->getdata("parent") != $this->id)) {  # templated body
	# if we don't have an explicitly defined body, show the category
	$content = $this;
    }
    return $content;
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

1;
