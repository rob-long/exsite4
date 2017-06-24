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

package ExSite::Keyword;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::ML;
use ExSite::Content;
use MIME::Base64;

use vars qw(@ISA);
@ISA = qw(ExSite::Content);

my %format = (
    article => "<div class='contentItem'><a href='[[url]]'>[[title]]</a><div class='articleAbout'>[[?date]]posted on [[date]][[/?date]][[?author]]by [[author]][[/?author]]</div>[[?description]]\n<div class='contentDescription'>[[description]]</div>\n[[/?description]]</div>\n",
    blog => "<div class='contentItem'><a href='[[url]]'>[[title]]</a>\n<div class='contentDescription'>[[description]]</div>\n<div class='contentUrl'>[[curl]]</div></div>\n",
    page => "<div class='contentItem'><a href='[[url]]'>[[title]]</a>\n<div class='contentDescription'>[[description]]</div>\n<div class='contentUrl'>[[curl]]</div></div>\n",
    content => "<div class='contentItem'>><a href='[[url]]'>[[title]]</a>\n<div class='contentInfo'>[[info]]</div></div>\n",
    );

sub my_subtype { return "keyword"; }

sub show {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    my $heading = $config{content}{keyword}{heading} || 
	"Items tagged with ".$ml->em("[[keyword]]");
    my $out = $this->navpath;
    $out .= $ml->h1(&substitute($heading,{keyword=>$this->title}));
    $out .= $this->index();
    return $ml->div($out,{class=>"keywordIndex"});
}

sub index_old {
    my $this = shift;
    my $out;
    my @child = scalar @_ ? @_ : reverse $this->get_contents();
    foreach my $c (@child) {
	my $subtype = $c->subtype;
	if (exists $format{$subtype}) {
	    $out .= $c->show_formatted($format{$subtype});
	}
	else {
	    $out .= $c->summary();
	}
    }
    return $out;
}

sub preview {
    my ($this,%opt) = @_;
    return $this->show(%opt);
}

sub show_templated {
    my ($this,%opt) = @_;
    $opt{content}{body} = $this->show(%opt);
    return $this->expand(%opt);
}

sub filename {
    my $this = shift;
    return &clean_filename($this->name).".html";
}

sub get_url_dynamic {
    my $this = shift;
    return $this->get_page_url_dynamic();
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
