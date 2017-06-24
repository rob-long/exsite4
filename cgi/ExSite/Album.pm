#!/usr/bin/perl
#----------------------------------------------------------------------------
#
#   Copyright 2015 Exware Solutions, Inc.  http://www.exware.com
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

=pod

Albums are libraries that can display their contents using some kind
of image viewer/browser.

Album parameters should be defined/set using metadata and flags, including:
- viewer jquery plugin (if any)
- transition effects
- timing
- caption handling
- etc.
Use generic names for these parameters, so that different viewers can share
settings when warranted.

Do not solicit for plugin parameters that are likely to be unused, as that
just creates configuration confusion; instead choose a reasonable default.

This class should support a couple of generic viewers that do not require
any special jquery plugin. Stubs for a bsthumb (thumbnail gallery using
BootStrap tools) and bscarousel (carousel/slider using BootStrap tools)
have been provided, as well as two jquery gallery stubs.

=cut

package ExSite::Album;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::ML;
use ExSite::Library;

use vars qw(@ISA $ml);
@ISA = qw(ExSite::Library);  # inherit basic library behaviours

sub my_subtype { return "album"; }

sub filename {
    my $this = shift;
    return "index.html";   # standalone gallery will be published to this file
}

sub setup {
    my ($this,%opt) = @_;
    $this->SUPER::setup(%opt);
    # load this album's flags and metadata for easy lookup
    $this->{myflags} = $this->flags();
    $this->{mymeta} = $this->get_metadata();
}

# show: fallback on generic formatted view
# sub show { }

# index : display our contents
# This is what shows the actual album images!
# Embed the viewer in your album format using [[index]]

sub index {
    my ($this, %opt) = @_;
    $ml or $ml = &get_obj("ML");
    my $viewer = $this->{mymeta}{viewer} || "default";
    my $show = "album_$viewer";
    if ($this->can($show)) {
	return $this->$show();
    }
    else {
	$this->error("No $viewer album viewew.");
	return $this->show_default();
    }
}

# default: simple thumbnail gallery, images popup in own window
# should work under any type of design, requires javascript

sub album_default {
    my ($this) = @_;
    my $out = &insert_js("misc");
    my $in = $this->{input};
    my @img = $this->get_contents();
    my $nimg;
    foreach my $img (@img) {
	if ($img->revision->is_image && $img->allow_view) {
	    $out .= $img->summary(format=>"thumb");
	    $nimg++;
	}
    }
    return $ml->div($out,{class=>"Album"});
}

# bsthumb - simple bootstrap thumbnail gallery, uses ExSite::Content::gallery
# requires Bootstrap

sub album_bsthumb { 
    my ($this) = @_;
    return $this->gallery();
}

# bscarousel - simple responsive carousel using bootstrap tools 
# see: http://getbootstrap.com/javascript/#carousel
# requires Bootstrap

sub album_bscarousel {
    my ($this) = @_;
    my @img = $this->get_contents();
    my $nimg;
    my $indicators;
    my $slides;
    my $first = 1;
    foreach my $img (@img) {
	if ($img->revision->is_image && $img->allow_view) {
	    my $active;
	    if ($first) {
		$active = " active";
		$first = 0;
	    }
	    my $slide = $ml->img(undef,{src=>$img->get_url(),alt=>$img->title});
	    my $caption = $img->caption();
	    if ($caption) {
		$slide .= $ml->div($caption,{class=>"carousel-caption"});
	    }
	    $slides .= $ml->div($slide,{class=>"item".$active});
	    $indicators .= $ml->li(undef,{class=>$active,"data-slide-to"=>$nimg,"data-target"=>"#album_bscarousel"});
	    $nimg++;
	}
    }
    my $controls = $ml->a(
	$ml->span(undef,{class=>"icon-prev", 'aria-hidden'=>"true"}).
	$ml->span($msg{Previous},{class=>"sr-only"}),
	{class=>"left carousel-control",href=>"#album_bscarousel", role=>"button", "data-slide"=>"prev"}).
	$ml->a(
	    $ml->span(undef,{class=>"icon-next", 'aria-hidden'=>"true"}).
	    $ml->span($msg{Next},{class=>"sr-only"}),
	    {class=>"right carousel-control",href=>"#album_bscarousel", role=>"button", "data-slide"=>"next"}
	);
    
    return $ml->div(
	$ml->ol($indicators,{class=>"carousel-indicators"}) . 
	$ml->div($slides,{class=>"carousel-inner",role=>"listbox"}) . 
	$controls, 
	{id=>"album_bscarousel",class=>"carousel slide",'data-ride'=>"carousel"}
	);
}

### TODO: jquery plugin album viewers

sub album_LightBox {

}

sub album_bxSlider {

}

1;


