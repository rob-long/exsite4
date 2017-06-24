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

package ExSite::Index;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::ML;
use ExSite::Page;

use vars qw(@ISA);
@ISA = qw(ExSite::Page);

sub my_subtype { return "index"; }

# set index revision handling to content-index, this should be unnecessary:
sub show_old {
    my ($this,%opt) = @_;
    return $this->index(%opt);
}

sub preview {
    my ($this,%opt) = @_;
    return $this->index(%opt);
}

sub show_templated {
    my ($this,%opt) = @_;
    $opt{content}{body} = $this->show(%opt);
    return $this->expand(%opt);
}

sub filename {
    return "index.html";
}

# index - display a listing of all active keywords

sub index {
    my ($this,%opt) = @_;
    my $style = $opt{style} || "list";
    if ($style eq "cloud") {
	return $this->index_cloud(%opt);
    }
    else {
	return $this->index_list(%opt);
    }
}

sub index_list {
    my ($this,%opt) = @_;
    my $keywords = $this->get_keywords();
    my $ml = &get_obj("ML");
    my $out; # = $ml->h1($this->title);
    while (my $kw = $keywords->next) {
	if ($kw->is_active || $opt{admin}) {
	    my $ntag;
	    #foreach my $tag ($kw->get_contents("alias")) {
	    my $tags = $kw->get_contents_as_list();
	    while (my $tag = $tags->next) {
		$ntag++ if ($tag->is_active());
	    }
	    if ($ntag > 0) {
		my $count = &substitute("([[n]] items)",{n=>$ntag});
		$out .= $ml->div($ml->a($kw->label,{href=>$kw->get_url()}).
				 " ".$count,
				 {class=>"indexKeyword"});
	    }
	}
    }
    return $ml->div($out,{class=>"indexList"});
}

sub index_cloud {
    my $this = shift;
    my $out;
    my $ml = &get_obj("ML");
    my %count = $this->count_tags();
    my ($max,$min);
    foreach my $kw (keys %count) {
	if (! $min || $count{$kw} < $min) { $min = $count{$kw}; }
	if ($count{$kw} > $max) { $max = $count{$kw}; }
    }
    foreach my $kw (sort keys %count) {
	# scale is a value from 80% to 150%
	my $scale = ($max == $min) ? 100 : 
	    $max ? int(($count{$kw} - $min) / ($max - $min) * 6) * 10 + 90 : 80;
	my $keyword = $this->{keyword}{$kw};
	$out .= $ml->span(
			  $ml->a($keyword->label,{href=>$keyword->get_url_canonical, style=>"font-size:${scale}\%"})." ",
			  {class=>"indexCloudKeyword"}
			  );
    }
    return $ml->div($out,{class=>"indexCloud"});
}

sub get_keywords {
    my $this = shift;
    my @keyw = $share{DB}->fetch_match("content",
				       {
					   type=>$this->isubtype("keyword"),
					   parent=>$this->id,
				       },
				       ["sortkey","title"]
	);
    my $kwlist = new ExSite::ObjectList(type=>"content",list=>\@keyw);
    return $kwlist;
}

sub count_tags {
    my $this = shift;
    if (! $this->{count}) {
	my @count = $share{DB}->custom_query("select kw.*,count(tag.master) tag_count from content kw, content tag where kw.parent=? and tag.parent=kw.content_id group by kw.content_id",$this->id);
	my %count;
	my %keyword;
	foreach my $tag (@count) {
	    my $kw = $tag->{name};
	    $this->{count}{$kw} = $tag->{tag_count};
	    $this->{keyword}{$kw} = new ExSite::Keyword(data=>$tag);
	}
    }
    return wantarray ? %{$this->{count}} : $this->{count};
}

# find - use the index itself as the page body

#### FIXME: is this needed?

sub find_old {
    my ($this,$name) = @_;
    my $content = $this->SUPER::find($name);
    if ($name eq "body" && 
	(! $content ||                                 # error
	 ! $content->defined ||                        # nothing found
	 $content->getdata("parent") != $this->id)) {  # templated body
	# if we don't have an explicitly defined body, show the index
	$content = $this;
    }
    return $content;
}

1;
