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

package ExSite::Catalog;

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

sub my_subtype { return "catalog"; }

sub show_old {
    my ($this,%opt) = @_;
    my $out;
    my $ml = &get_obj("ML");
    $out = $ml->h1($this->title);
    $out .= $this->show_revision(%opt);
    $out .= $this->index(%opt);
    return $out;
}

sub show_templated {
    my ($this,%opt) = @_;
    $opt{content}{body} = $this->show(%opt);
    return $this->expand(%opt);
}

sub preview {
    my ($this,%opt) = @_;
    $this->{admin} = 1;
    $opt{view} = "small";
    return $this->index(%opt);
}

# index - display a listing of current items in the catalog

sub index {
    my ($this,%opt) = @_;
    my $items = $this->get_contents_as_list();
    my $ml = &get_obj("ML");
    my $tree = $this->get_content_tree();
    my ($out, $cout, $pout);
    my $iproduct = $this->isubtype("product");
    my $depth = $opt{depth} || $config{Catalog}{depth} || "0";

    # categories
    $cout = $this->index_categories(0,%opt);
    if ($cout) {
	$out .= $ml->div($cout,{class=>"catalogCategoryIndex"});
    }

    # products
    
    while (my $item = $items->next) {
	next if ($item->subtype() ne "product");
	next if (! $item->is_active);
	next if ($item->wf_status() eq "archived" && ! $opt{archive});
	$pout .= $item->summary();
    }
    if ($pout) {
	$out .= $ml->div($pout,{class=>"catalogProductIndex"});
    }

    return $ml->div($out,{class=>"Catalog"});
}

sub index_categories {
    my ($this,$level,%opt) = @_;
    my $depth = $opt{depth} || $config{Catalog}{depth} || "0";
    return undef if ($depth < $level);

    my $ml = &get_obj("ML");
    my $tree = $this->get_content_tree();
    my ($out, $cout, $pout);
    my $iproduct = $this->isubtype("product");
    my @subcontent = $tree->get_child_data($this->id);
    foreach my $data (@subcontent) {
	my $item = $this->get_content_obj($data);
	next if ($item->subtype() ne "catalog");
	next if (! $item->is_active);
	next if ($item->wf_status() eq "archived" && ! $opt{archive});
	my $product_count = $tree->count({type=>$iproduct,status=>0},$item->id);
	next if (!$this->{admin} && $product_count == 0);
	my $subcat = $item->index_categories($level+1,%opt) if $depth;
	my $what = $product_count == 1 ? "product" : "products";  ### make configurable
	$out .= $ml->div(
	    $ml->a($item->title,{href=>$item->get_url})."\n".
	    $ml->span("($product_count $msg{$what})",{class=>"catalogProductCount"}).
	    $subcat,
	    {class=>"catalogCategory"}
	    );
    }
    return $out;
}

1;
