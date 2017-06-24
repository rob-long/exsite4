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

package ExSite::Product;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Content;

use vars qw(@ISA);
@ISA = qw(ExSite::Content);

# my_subtype - the subtype of this object/class

sub my_subtype { return "product"; }

sub show_old {
    my ($this,%opt) = @_;
    my $out;
    my $ml = &get_obj("ML");
    my $viewtype = $opt{view} || "normal";
    if ($viewtype eq "all") { $viewtype = "normal"; }
    my %prod;
    if (! $this->revision()->has_view($viewtype)) {
	return $this->summary if ($viewtype eq "small");
	$this->warn("No $viewtype view of this revision, using best substitute.");
    }
#    if ($opt{mode} eq "index") {
#	$template =~ s/h1>/h2>/g;
#    }
    return $this->show_formatted($config{content}{format}{product},%prod); #&substitute($template,\%prod);
}

# preview: same as show, no cart links

sub preview {
    my ($this,%opt) = @_;
    $this->{admin} = 1;
    return $this->show(%opt);
}

sub publish_rule_heuristic {
    my $this = shift;
    my $stat;
    foreach my $price ($this->get_prices()) {
	next if ($price->{status} ne "active");
	return "dynamic" if ($price->{access}); # price depends on access level
	if ($price->{start}) {
	    my $date = new ExSite::Time($price->{start},"sql_datetime");
	    return "dynamic" if ($date->in_future); # price rules will change in future
	}
	if ($price->{end}) {
	    my $date = new ExSite::Time($price->{end},"sql_datetime");
	    return "dynamic" if ($date->in_future); # price rules will change in future
	}
    }
    return $this->SUPER::publish_rule_heuristic();
}

sub options {
    my $this = shift;
    my %opt;
    my %meta = $this->get_metadata();
    foreach my $key (keys %meta) {
	if ($key =~ /^option_(\w+)$/) {
	    $opt{$1} = $meta{$key};
	}
    }
    return %opt;
}

sub cart_type {
    my $this = shift;
    my $cat = $this->my_ancestor("catalog");
    while ($cat && $cat->defined && $cat->subtype() eq "catalog") {
	# we are in a product catalog, with customizable carts
	my $cart = $cat->meta_get("shopping_cart");
	return $cart if $cart;
	$cat = $cat->parent();
    }
    return "standard";
}

sub tools {
    my ($this,%opt) = @_;
    if ($this->is_active()) {
	# no add to cart if we just did so
	my $input = new ExSite::Input();
	my $post = $input->post();
	return if ($post->{product_id} && $post->{product_id} == $this->id);
	my $cart = $this->cart_type();
	if ($cart eq "none") {
	    return undef;
	}
	elsif ($cart eq "custom") {
	    return $this->run_handler("ProductTools",%opt);
	}
	else {
	    # add std shopping cart button
	    my $ml = &get_obj("ML");
	    my $ui = &get_obj("UI");
	    my $action = $this->get_url_dynamic();
	    my $form = new ExSite::FormBuilder(action=>$action);
	    $form->template("",
			    $ml->div("[[prompt]]",{class=>"productOptionPrompt"}).
			    $ml->div("[[input]]",{class=>"productOptionInput"}),
			    "");
	    $form->input(name=>"product_id",value=>$this->id,type=>"hidden");
	    if ($cart eq "quick") {
		# jump straight to checkout
		$form->input(name=>"cmd",value=>"checkout",type=>"hidden");
	    }
	    my %options = $this->options();
	    foreach my $key (keys %options) {
		my $label = $key;
		$label =~ s/_/ /g;
		$form->input(name=>"opt_".$key,prompt=>$msg{$label},type=>"select",options=>$msg{$options{$key}},nullvalue=>"== select $label ==",required=>1);
	    }
	    $form->set("buttons",$ml->div($ml->input(undef,{type=>"submit",value=>$ui->UnicodeIcon("plus")." ".$msg{"Add to cart"}}),{class=>"productAddToCart"}));
	    return $ml->div($form->make(),{class=>"productAddToCartForm"});
	}
    }
}

sub insert_image {
    my ($this,$img,%opt) = @_;
    $opt{view} or $opt{view} = "small";
    $opt{css_prefix} = "product";
    $opt{caption} = 1;
    return $this->SUPER::insert_image($img,%opt);
}

# post: performs the add to cart function

sub post {
    my $this = shift;
    if ($this->allow_post()) {
	# convert url back to page URLs
	my $uri = new ExSite::URI();
	$uri->path('ExSiteAction','page');
	# get post data
	my $input = new ExSite::Input();
	my $post = $input->post();
	if ($post->{product_id} && $post->{product_id} == $this->id) {
	    my @descr;
	    if ($this->dcmeta("part_number")) {
		push @descr, $this->dcmeta("part_number");
	    }
	    my $price = $this->price();
	    if ($price->{description}) {
		push @descr, $price->{description};
	    }
	    my %option = $this->options();
	    foreach my $key (keys %option) {
		my $label = $key;
		$label =~ s/_/ /g;
		if ($post->{"opt_".$key}) {
		    push @descr, "$label:".$post->{"opt_".$key};
		}
		else {
		    return $this->error("No $label selected.");
		}
	    }
	    my $acctcode = $this->dcmeta("acctcode") || $config{acctcode}{product};
	    my %cartopt = (
		cart=>"add",
		item=>$this->title,
		description=>join("; ",@descr),
		acctcode_id=>$acctcode,
		acctcode2=>$this->parent->id, #category
		acctcode3=>$this->id,         #product
		objid=>$this->id,
		objtype=>"content",
		cost=>$price ? $price->{cost} : "0.00",
		quantity=>1,
		);
	    my $shipping_size = $this->meta->get("shipping_size");
	    if ($shipping_size) {
		$cartopt{size} = $shipping_size;
	    }

	    my $out;
	    if (eval 'require Modules::Finance::Cart') {
		my $ml = &get_obj("ML");
		my $cart = new Modules::Finance::Cart();
		$out .= $cart->add(%cartopt);
		$out .= $cart->show(noedit=>1);
		$session{continue_shopping_url} = $this->parent->get_url();
	    }
	    else {
		$out .= $this->error($msg{"Sorry, there is no shopping cart system installed on this website."});
	    }
#	    my $ml = &get_obj("ML");
#	    my $cartopt = &EncodeHash(%cartopt);
#	    my $out = "<!--&Pay($cartopt)-->\n";
#	    $out .= $ml->div(
#		$ml->a(&substitute("Return to ".$ml->em("[[product]]"),{product=>$this->label}),{href=>$this->get_url(),class=>"productContinue"})."\n".
#		$ml->a(&substitute("Return to ".$ml->em("[[catalog]]"),{catalog=>$this->parent->label}),{href=>$this->parent->get_url(),class=>"productContinue"}),
#		{class=>"continueShopping"}
#		);
	    return $out;
	}
	# else permission denied
    }
    # ignore unrelated post data
}

sub allow_post {
    my $this = shift;
    return $this->is_active() && $this->allow_view();
}

# on confirmation of a sale, mark the product as liked
sub sale_activate {
    my ($this,$item) = @_;
    my $r = $item->receivable();
    $this->like(account=>$r->getdata("account_id"));
}

1;
