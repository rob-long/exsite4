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

package ExSite::Library;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::ML;
use ExSite::Util;
use ExSite::URI;
use ExSite::Content;
use MIME::Base64;

use vars qw(@ISA);
@ISA = qw(ExSite::Content);

sub my_subtype { return "library"; }

sub filename {
    my $this = shift;
    return undef;
}

sub show_old {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    my $out = $ml->h1($this->showdata("title") || $this->name);
    my $tree = $this->get_content_tree();
    my $list;
    if ($tree) {
	my @child = $tree->get_child_data($this->id);
	foreach my $data (@child) {
	    my $cnode = $this->get_content_obj($data);
	    #$list .= $ml->div($cnode->show_formatted("listing"),{class=>"libraryContent"});
	    $list .= $cnode->show_formatted("listing");
	}
	$out .= $ml->div($list,{class=>"cnodeList"});
	return $out;
    }
    return $msg{"Library is empty."};
}

sub index {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    my $out; # $ml->h1($this->showdata("title") || $this->name);
    my $tree = $this->get_content_tree();
    my $list;
    if ($tree) {
	my @child = $tree->get_child_data($this->id);
	foreach my $data (@child) {
	    my $cnode = $this->get_content_obj($data);
	    #$list .= $ml->div($cnode->show_formatted("listing"),{class=>"libraryContent"});
	    $list .= $cnode->show_formatted("listing");
	}
	$out .= $ml->div($list,{class=>"cnodeList"});
	return $out;
    }
    return $msg{"Library is empty."};
}

sub preview {
    my ($this,%opt) = @_;
    return $this->show(%opt);
}

1;


