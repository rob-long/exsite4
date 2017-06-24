#!/usr/bin/perl
#----------------------------------------------------------------------------
#
#   Copyright 2001-2008 Exware Solutions, Inc.  http://www.exware.com
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

package ExSite::ML;

use strict;
use ExSite::Config;
use ExSite::Base;
use ExSite::Misc;
use vars qw(@ISA %default_child %default_order @alltags @emptytags @no_nl);
@ISA = qw(ExSite::Base);

# defaults are for HTML 4

# default_child gives the sub-element type if not explicitly provided

%default_child = (
		  body => "div",
		  colgroup => "col",
		  dl => "dt",
		  ol => "li",
		  ul => "li",
		  select => "option",
		  table => "tr",
		  tbody => "tr",
		  tfoot => "tr",
		  thead => "tr",
		  tr => "td",
		  );

# default_order gives the sub-element order if not explicitly provided

%default_order = (
		  dl => [ "dt", "dd" ],
		  table => [ "caption","thead","tfoot","tbody" ]
		  );

# recognized tags

@alltags = qw(a abbr acronym address applet area b base big blockquote
body br button caption cite code col colgroup dd del dfn div dl dt em
fieldset form frame frameset h1 h2 h3 h4 h5 h6 head hr html i iframe
img input ins kbd label legend li link map meta noscript object ol
optgroup option p param pre q samp script select small span strong
style sub sup table tbody td textarea tfoot th thead title tr tt ul
var);

# tags that do not contain content

@emptytags = qw(br frame hr meta link area img param input col base);

# tags that should NOT be terminated with newlines

@no_nl = qw(a abbr acronym b big button cite code del dfn em
i img input ins kbd label q samp small span strong sub sup tt var);

sub new ($%) {
    my ($this,%opt) = @_;
    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;
    # copy markup rules into object
    while (my ($key,$val) = each %{$config{markup}}) {
	$obj->{$key} = $val;
    }
    # copy options into object (override rules)
    while (my ($key,$val) = each %opt) {
	$obj->{$key} = $val;
    }
    # setup HTML defaults
    if (! exists $obj->{default_child}) {
	$obj->{default_child} = \%default_child;
    }
    if (! exists $obj->{default_order}) {
	$obj->{default_order} = \%default_order;
    }
    if (! exists $obj->{alltags}) {
	$obj->{alltags} = \@alltags;
    }
    if (! exists $obj->{emptytags}) {
	$obj->{emptytags} = \@emptytags;
    }
    if (! exists $obj->{no_nl}) {
	$obj->{no_nl} = \@no_nl;
    }
    $obj->initialize_object;
    if (! $obj->{doc}) { 
	$obj->Clear(); 
    }
    else {
	$obj->{parent} = [];
    }
    return $obj;
}

sub Write {
    my $this = shift;
    return undef if ($this->{canceled});
    return $this->{doctype} ?
	$this->{doctype}.$this->{doc} :
	$this->{doc};
}

sub Print {
    my $this = shift;
    return if ($this->{canceled});
    print $this->{doctype} ?
	$this->{doctype}.$this->{doc} :
	$this->{doc};
}

sub PrintWithHeader {
    my $this = shift;
    return if ($this->{canceled});
    print "Content-type: text/html\n\n";
    $this->Print();
}

sub Doc {
    my ($this,$text) = @_;
    $this->{doc} = $text;
    return $text;
}

sub Append {
    my ($this,$text) = @_;
    $this->{doc} .= $text;
    return $text;
}

sub Prepend {
    my ($this,$text) = @_;
    $this->{doc} = $text.$this->{doc};
    return $text;
}

sub Wrap {
    my ($this,$tag,$attributes) = @_;
    $this->{doc} = $this->Element($tag,$this->{doc},$attributes);
    return $this->{doc};
}

sub Clear {
    my ($this) = @_;
    $this->{parent} = [];
    $this->{doc} = "";
    delete $this->{canceled};
    return;
}

sub Doctype {
    my ($this,$text) = @_;
    if ($text !~ /\n$/) { $text .= "\n"; }
    $this->{doctype} = $text;
    return $text;
}

# for compatibility with Page, PageBuf

sub cancel {
    my $this = shift;
    $this->{canceled} = 1;
}

sub is_canceled {
    my $this = shift;
    return $this->{canceled};
}

sub location {
    my ($this,$url) = @_;
    $this->cancel;
    print "Location: $url\n\n";
}
sub redirect { location(@_); }

#========================================================================
# SIMPLE ELEMENTS

sub Element {
    my ($this,$tag,$data,$attributes,$nonl) = @_;
    my $attribute_text;

    # setup tag
    my $is_html = (scalar grep(/^$tag$/i,@alltags) > 0);
    if ($this->{xml} && $is_html > 0) { 
	$tag = lc $tag; 
    }

    # setup attributes
    if (ref $attributes eq "HASH") {
	foreach my $attr (keys %$attributes) {
	    my $value = $attributes->{$attr};
	    if ($this->{xml} && $is_html) { $attr = lc $attr; }
	    if ($value && ! $this->{safe_attributes}) {
		$value = &html_escape($value);
	    }
	    if (! defined $value) {
		$attribute_text .= $this->{minattr} ?
		    " $attr" : " $attr=\"$attr\"";
	    }
	    else {
		$attribute_text .= " $attr=\"$value\"";
	    }
	}
    }

    # setup content
    my $content = $this->Content($tag,$data);

    # now compose our full element
    my $element = "<$tag$attribute_text";
    my $empty = 0;
    if (! defined $content) {
	if (grep(/^$tag$/,@{$this->{emptytags}}) > 0) {
	    if ($this->{xml}) {
		$element .= " />";
	    }
	    else {
		$element .= ">";
	    }
	    $empty = 1;
	}
	else {
	    $element .= "></$tag>";
	}
    }
    elsif ($tag =~ /^($this->{nocontent})$/) {
	# ERROR: we were given content for an element that doesn't accept it
	$element .= ">";
    }
    else {
	$element .= ">$content</$tag>";
    }

    $nonl or $nonl = grep(/^$tag$/,@{$this->{no_nl}}) > 0;
    return $nonl ? $element : "$element\n";
}

sub Comment {
    my ($this,$comment) = @_;
    $comment =~ s/--/-=-/g;  # "--" forbidden within comments
    my $comment = "<!-- $comment -->";
    return $this->{nl} ? "$comment\n" : $comment;
}

#========================================================================
# COMPOUND ELEMENTS

# Content - accept a variety of content structures, and convert them to
# a markup string

sub Content {  
    my ($this,$tag,$data) = @_;
    my $content;
    push @{$this->{parent}}, $tag;
    if (ref $data eq "ARRAY") {
	my $inferred_tag = $this->{default_child}{$tag};
	my $type = $this->looks_like_element($data);
	if ($type == 1) {
	    # $data is just an element parameter list
	    $content .= $this->Element(@$data);
	}
	elsif ($type == -1) {
	    if ($inferred_tag) {
		# $data is element parameters, but with an inferred tag
		$content .= $this->Element($inferred_tag,@$data);
	    }
	    else {
		$content .= $this->Element($tag,@$data);
	    }
	}
#	elsif ($type == -1 && $inferred_tag) {
#	    # $data is element parameters, but with an inferred tag
#	    $content .= $this->Element($inferred_tag,@$data);
#	}
	else {
	    # $data is a list of content items
	    foreach my $d (@$data) {
		if (ref $d eq "HASH") {
		    $content .= $this->Content($tag,$d);
		}
		elsif (ref $d eq "ARRAY" && grep(/^$d->[0]$/,@{$this->{alltags}}) > 0 ) {
		    $content .= $this->Content($tag,$d);
		}
		elsif ($inferred_tag) {
		    $content .= $this->Element($inferred_tag,$d);
		}
		elsif (ref $d) {  #ARRAY
		    $content .= $this->Content($inferred_tag || $tag,$d);
		}
		elsif (! $inferred_tag) {
		    $content .= $this->Content($tag,$d);
		}
		else {
		    $content .= $this->Element($inferred_tag || $tag,$d);
		}
	    }
	}
    }
    elsif (ref $data eq "HASH") {
	return $this->{doc} if ($data eq $this);
	my $taglist = $this->{default_order}{$tag};
	if (! $taglist) {
	    my @tags = keys %$data;
	    $taglist = \@tags;
	}
	if (! $taglist) {
	    return $this->error("bad element structure under $tag");
	}
	foreach my $tag (@$taglist) {
	    if ($data->{$tag}) {
		$content .= $this->Element($tag,$data->{$tag});
	    }
	}
    }
    else {
	# explicit content
	return ($data && ! $this->{safe_content}) ? &html_escape($data) : $data;
    }
    pop @{$this->{parent}};
    return $content;
}

# guess if an array is an element parameter list or not
# returns 1 if it appears to be a simple element parameter list; -1 if it
# looks like an elememt parameter list, less the tag; 0 if it does not
# appear to be an element parameter list at all.
sub looks_like_element {
    my ($this,$data) = @_;
    if (ref $data eq "ARRAY") {
	if (scalar @$data == 3) {
	    return (grep(/^$data->[0]$/,@{$this->{alltags}}) > 0) ? 1 : 0;
	}
	elsif (scalar @$data == 2) {
	    if (grep(/^$data->[0]$/,@{$this->{alltags}}) > 0) {
		return 1;
	    }
	    elsif (! ref $data->[0] && ref $data->[1] eq "HASH") {
		return -1;
	    }
	}
	elsif (scalar @$data == 1) {
	    if (! ref $data->[0] && (grep(/^$data->[0]$/,@{$this->{alltags}}) > 0)) {
		return 1;
	    }
	    else {
		return -1;
	    }
	}
    }
    return 0;
}

#========================================================================
# SHORTCUTS FOR STANDARD HTML 4 ELEMENTS

sub a        { my $this = shift; return $this->Element("a",@_); }
sub abbr     { my $this = shift; return $this->Element("abbr",@_); }
sub acronym  { my $this = shift; return $this->Element("acronym",@_); }
sub address  { my $this = shift; return $this->Element("address",@_); }
sub applet   { my $this = shift; return $this->Element("applet",@_); }
sub area     { my $this = shift; return $this->Element("area",@_); }
sub b        { my $this = shift; return $this->Element("b",@_); }
sub base     { my $this = shift; return $this->Element("base",@_); }
sub big      { my $this = shift; return $this->Element("big",@_); }
sub blockquote { my $this = shift; return $this->Element("blockquote",@_); }
sub body     { my $this = shift; return $this->Element("body",@_); }
sub br       { my $this = shift; return $this->Element("br",@_); }
sub button   { my $this = shift; return $this->Element("button",@_); }
sub caption  { my $this = shift; return $this->Element("caption",@_); }
sub cite     { my $this = shift; return $this->Element("cite",@_); }
sub code     { my $this = shift; return $this->Element("code",@_); }
sub col      { my $this = shift; return $this->Element("col",@_); }
sub colgroup { my $this = shift; return $this->Element("colgroup",@_); }
sub dd       { my $this = shift; return $this->Element("dd",@_); }
sub del      { my $this = shift; return $this->Element("del",@_); }
sub dfn      { my $this = shift; return $this->Element("dfn",@_); }
sub div      { my $this = shift; return $this->Element("div",@_); }
sub dl       { my $this = shift; return $this->Element("dl",@_); }
sub dt       { my $this = shift; return $this->Element("dt",@_); }
sub em       { my $this = shift; return $this->Element("em",@_); }
sub fieldset { my $this = shift; return $this->Element("fieldset",@_); }
sub form     { my $this = shift; return $this->Element("form",@_); }
sub frame    { my $this = shift; return $this->Element("frame",@_); }
sub frameset { my $this = shift; return $this->Element("frameset",@_); }
sub h1       { my $this = shift; return $this->Element("h1",@_); }
sub h2       { my $this = shift; return $this->Element("h2",@_); }
sub h3       { my $this = shift; return $this->Element("h3",@_); }
sub h4       { my $this = shift; return $this->Element("h4",@_); }
sub h5       { my $this = shift; return $this->Element("h5",@_); }
sub h6       { my $this = shift; return $this->Element("h6",@_); }
sub head     { my $this = shift; return $this->Element("head",@_); }
sub hr       { my $this = shift; return $this->Element("hr",@_); }
sub html     { my $this = shift; return $this->Element("html",@_); }
sub i        { my $this = shift; return $this->Element("i",@_); }
sub iframe   { my $this = shift; return $this->Element("iframe",@_); }
sub img      { my $this = shift; return $this->Element("img",@_); }
sub input    { my $this = shift; return $this->Element("input",@_); }
sub ins      { my $this = shift; return $this->Element("ins",@_); }
sub kbd      { my $this = shift; return $this->Element("kbd",@_); }
sub label    { my $this = shift; return $this->Element("label",@_); }
sub legend   { my $this = shift; return $this->Element("legend",@_); }
sub li       { my $this = shift; return $this->Element("li",@_); }
sub link     { my $this = shift; return $this->Element("link",@_); }
sub map      { my $this = shift; return $this->Element("map",@_); }
sub meta     { my $this = shift; return $this->Element("meta",@_); }
sub noscript { my $this = shift; return $this->Element("noscript",@_); }
sub object   { my $this = shift; return $this->Element("object",@_); }
sub ol       { my $this = shift; return $this->Element("ol",@_); }
sub optgroup { my $this = shift; return $this->Element("optgroup",@_); }
sub option   { my $this = shift; return $this->Element("option",@_); }
sub p        { my $this = shift; return $this->Element("p",@_); }
sub param    { my $this = shift; return $this->Element("param",@_); }
sub pre      { my $this = shift; return $this->Element("pre",@_); }
sub q        { my $this = shift; return $this->Element("q",@_); }
sub samp     { my $this = shift; return $this->Element("samp",@_); }
sub script   { my $this = shift; return $this->Element("script",@_); }
sub select   { my $this = shift; return $this->Element("select",@_); }
sub small    { my $this = shift; return $this->Element("small",@_); }
sub span     { my $this = shift; return $this->Element("span",@_); }
sub strong   { my $this = shift; return $this->Element("strong",@_); }
sub style    { my $this = shift; return $this->Element("style",@_); }
sub sub      { my $this = shift; return $this->Element("sub",@_); }
sub sup      { my $this = shift; return $this->Element("sup",@_); }
sub table    { my $this = shift; return $this->Element("table",@_); }
sub tbody    { my $this = shift; return $this->Element("tbody",@_); }
sub td       { my $this = shift; return $this->Element("td",@_); }
sub textarea { my $this = shift; return $this->Element("textarea",@_); }
sub tfoot    { my $this = shift; return $this->Element("tfoot",@_); }
sub th       { my $this = shift; return $this->Element("th",@_); }
sub thead    { my $this = shift; return $this->Element("thead",@_); }
sub title    { my $this = shift; return $this->Element("title",@_); }
sub tr       { my $this = shift; return $this->Element("tr",@_); }
sub tt       { my $this = shift; return $this->Element("tt",@_); }
sub ul       { my $this = shift; return $this->Element("ul",@_); }
sub var      { my $this = shift; return $this->Element("var",@_); }

#========================================================================
# SHORTCUTS FOR APPENDING TO CURRENT DOCUMENT

sub _Element  { my $this = shift; $this->Append($this->Element(@_)); }
sub _Comment  { my $this = shift; $this->Append($this->Comment(@_)); }
sub _List     { my $this = shift; $this->Append($this->List(@_)); }
sub _Table    { my $this = shift; $this->Append($this->Table(@_)); }

sub _a        { my $this = shift; $this->Append($this->a(@_)); }
sub _abbr     { my $this = shift; $this->Append($this->abbr(@_)); }
sub _acronym  { my $this = shift; $this->Append($this->acronym(@_)); }
sub _address  { my $this = shift; $this->Append($this->address(@_)); }
sub _applet   { my $this = shift; $this->Append($this->applet(@_)); }
sub _area     { my $this = shift; $this->Append($this->area(@_)); }
sub _b        { my $this = shift; $this->Append($this->b(@_)); }
sub _base     { my $this = shift; $this->Append($this->base(@_)); }
sub _big      { my $this = shift; $this->Append($this->big(@_)); }
sub _blockquote { my $this = shift; $this->Append($this->blockquote(@_)); }
sub _body     { my $this = shift; $this->Append($this->body(@_)); }
sub _br       { my $this = shift; $this->Append($this->br(@_)); }
sub _button   { my $this = shift; $this->Append($this->button(@_)); }
sub _caption  { my $this = shift; $this->Append($this->caption(@_)); }
sub _cite     { my $this = shift; $this->Append($this->cite(@_)); }
sub _code     { my $this = shift; $this->Append($this->code(@_)); }
sub _col      { my $this = shift; $this->Append($this->col(@_)); }
sub _colgroup { my $this = shift; $this->Append($this->colgroup(@_)); }
sub _dd       { my $this = shift; $this->Append($this->dd(@_)); }
sub _del      { my $this = shift; $this->Append($this->del(@_)); }
sub _dfn      { my $this = shift; $this->Append($this->dfn(@_)); }
sub _div      { my $this = shift; $this->Append($this->div(@_)); }
sub _dl       { my $this = shift; $this->Append($this->dl(@_)); }
sub _dt       { my $this = shift; $this->Append($this->dt(@_)); }
sub _em       { my $this = shift; $this->Append($this->em(@_)); }
sub _fieldset { my $this = shift; $this->Append($this->fieldset(@_)); }
sub _form     { my $this = shift; $this->Append($this->form(@_)); }
sub _frame    { my $this = shift; $this->Append($this->frame(@_)); }
sub _frameset { my $this = shift; $this->Append($this->frameset(@_)); }
sub _h1       { my $this = shift; $this->Append($this->h1(@_)); }
sub _h2       { my $this = shift; $this->Append($this->h2(@_)); }
sub _h3       { my $this = shift; $this->Append($this->h3(@_)); }
sub _h4       { my $this = shift; $this->Append($this->h4(@_)); }
sub _h5       { my $this = shift; $this->Append($this->h5(@_)); }
sub _h6       { my $this = shift; $this->Append($this->h6(@_)); }
sub _head     { my $this = shift; $this->Append($this->head(@_)); }
sub _hr       { my $this = shift; $this->Append($this->hr(@_)); }
sub _html     { my $this = shift; $this->Append($this->html(@_)); }
sub _i        { my $this = shift; $this->Append($this->i(@_)); }
sub _iframe   { my $this = shift; $this->Append($this->iframe(@_)); }
sub _img      { my $this = shift; $this->Append($this->img(@_)); }
sub _input    { my $this = shift; $this->Append($this->input(@_)); }
sub _ins      { my $this = shift; $this->Append($this->ins(@_)); }
sub _kbd      { my $this = shift; $this->Append($this->kbd(@_)); }
sub _label    { my $this = shift; $this->Append($this->label(@_)); }
sub _legend   { my $this = shift; $this->Append($this->legend(@_)); }
sub _li       { my $this = shift; $this->Append($this->li(@_)); }
sub _link     { my $this = shift; $this->Append($this->link(@_)); }
sub _map      { my $this = shift; $this->Append($this->map(@_)); }
sub _meta     { my $this = shift; $this->Append($this->meta(@_)); }
sub _noscript { my $this = shift; $this->Append($this->noscript(@_)); }
sub _object   { my $this = shift; $this->Append($this->object(@_)); }
sub _ol       { my $this = shift; $this->Append($this->ol(@_)); }
sub _optgroup { my $this = shift; $this->Append($this->optgroup(@_)); }
sub _option   { my $this = shift; $this->Append($this->option(@_)); }
sub _p        { my $this = shift; $this->Append($this->p(@_)); }
sub _param    { my $this = shift; $this->Append($this->param(@_)); }
sub _pre      { my $this = shift; $this->Append($this->pre(@_)); }
sub _q        { my $this = shift; $this->Append($this->q(@_)); }
sub _samp     { my $this = shift; $this->Append($this->samp(@_)); }
sub _script   { my $this = shift; $this->Append($this->script(@_)); }
sub _select   { my $this = shift; $this->Append($this->select(@_)); }
sub _small    { my $this = shift; $this->Append($this->small(@_)); }
sub _span     { my $this = shift; $this->Append($this->span(@_)); }
sub _strong   { my $this = shift; $this->Append($this->strong(@_)); }
sub _style    { my $this = shift; $this->Append($this->style(@_)); }
sub _sub      { my $this = shift; $this->Append($this->sub(@_)); }
sub _sup      { my $this = shift; $this->Append($this->sup(@_)); }
sub _table    { my $this = shift; $this->Append($this->table(@_)); }
sub _tbody    { my $this = shift; $this->Append($this->tbody(@_)); }
sub _td       { my $this = shift; $this->Append($this->td(@_)); }
sub _textarea { my $this = shift; $this->Append($this->textarea(@_)); }
sub _tfoot    { my $this = shift; $this->Append($this->tfoot(@_)); }
sub _th       { my $this = shift; $this->Append($this->th(@_)); }
sub _thead    { my $this = shift; $this->Append($this->thead(@_)); }
sub _title    { my $this = shift; $this->Append($this->title(@_)); }
sub _tr       { my $this = shift; $this->Append($this->tr(@_)); }
sub _tt       { my $this = shift; $this->Append($this->tt(@_)); }
sub _ul       { my $this = shift; $this->Append($this->ul(@_)); }
sub _var      { my $this = shift; $this->Append($this->var(@_)); }

#========================================================================
# SHORTCUTS FOR WRAPPING CURRENT DOCUMENT
# Elements that do not support contents are commented out.

sub __a        { my $this = shift; $this->Wrap("a",shift); }
sub __abbr     { my $this = shift; $this->Wrap("abbr",shift); }
sub __acronym  { my $this = shift; $this->Wrap("acronym",shift); }
sub __address  { my $this = shift; $this->Wrap("address",shift); }
sub __applet   { my $this = shift; $this->Wrap("applet",shift); }
#sub __area     { my $this = shift; $this->Wrap("area",shift); }
sub __b        { my $this = shift; $this->Wrap("b",shift); }
#sub __base     { my $this = shift; $this->Wrap("base",shift); }
sub __big      { my $this = shift; $this->Wrap("big",shift); }
sub __blockquote { my $this = shift; $this->Wrap("blockquote",shift); }
sub __body     { my $this = shift; $this->Wrap("body",shift); }
#sub __br       { my $this = shift; $this->Wrap("br",shift); }
sub __button   { my $this = shift; $this->Wrap("button",shift); }
sub __caption  { my $this = shift; $this->Wrap("caption",shift); }
sub __cite     { my $this = shift; $this->Wrap("cite",shift); }
sub __code     { my $this = shift; $this->Wrap("code",shift); }
#sub __col      { my $this = shift; $this->Wrap("col",shift); }
sub __colgroup { my $this = shift; $this->Wrap("colgroup",shift); }
sub __dd       { my $this = shift; $this->Wrap("dd",shift); }
sub __del      { my $this = shift; $this->Wrap("del",shift); }
sub __dfn      { my $this = shift; $this->Wrap("dfn",shift); }
sub __div      { my $this = shift; $this->Wrap("div",shift); }
sub __dl       { my $this = shift; $this->Wrap("dl",shift); }
sub __dt       { my $this = shift; $this->Wrap("dt",shift); }
sub __em       { my $this = shift; $this->Wrap("em",shift); }
sub __fieldset { my $this = shift; $this->Wrap("fieldset",shift); }
sub __form     { my $this = shift; $this->Wrap("form",shift); }
sub __frame    { my $this = shift; $this->Wrap("frame",shift); }
sub __frameset { my $this = shift; $this->Wrap("frameset",shift); }
sub __h1       { my $this = shift; $this->Wrap("h1",shift); }
sub __h2       { my $this = shift; $this->Wrap("h2",shift); }
sub __h3       { my $this = shift; $this->Wrap("h3",shift); }
sub __h4       { my $this = shift; $this->Wrap("h4",shift); }
sub __h5       { my $this = shift; $this->Wrap("h5",shift); }
sub __h6       { my $this = shift; $this->Wrap("h6",shift); }
sub __head     { my $this = shift; $this->Wrap("head",shift); }
#sub __hr       { my $this = shift; $this->Wrap("hr",shift); }
sub __html     { my $this = shift; $this->Wrap("html",shift); }
sub __i        { my $this = shift; $this->Wrap("i",shift); }
sub __iframe   { my $this = shift; $this->Wrap("iframe",shift); }
#sub __img      { my $this = shift; $this->Wrap("img",shift); }
#sub __input    { my $this = shift; $this->Wrap("input",shift); }
sub __ins      { my $this = shift; $this->Wrap("ins",shift); }
sub __kbd      { my $this = shift; $this->Wrap("kbd",shift); }
sub __label    { my $this = shift; $this->Wrap("label",shift); }
sub __legend   { my $this = shift; $this->Wrap("legend",shift); }
sub __li       { my $this = shift; $this->Wrap("li",shift); }
#sub __link     { my $this = shift; $this->Wrap("link",shift); }
sub __map      { my $this = shift; $this->Wrap("map",shift); }
#sub __meta     { my $this = shift; $this->Wrap("meta",shift); }
sub __noscript { my $this = shift; $this->Wrap("noscript",shift); }
sub __object   { my $this = shift; $this->Wrap("object",shift); }
sub __ol       { my $this = shift; $this->Wrap("ol",shift); }
sub __optgroup { my $this = shift; $this->Wrap("optgroup",shift); }
sub __option   { my $this = shift; $this->Wrap("option",shift); }
sub __p        { my $this = shift; $this->Wrap("p",shift); }
#sub __param    { my $this = shift; $this->Wrap("param",shift); }
sub __pre      { my $this = shift; $this->Wrap("pre",shift); }
sub __q        { my $this = shift; $this->Wrap("q",shift); }
sub __samp     { my $this = shift; $this->Wrap("samp",shift); }
sub __script   { my $this = shift; $this->Wrap("script",shift); }
sub __select   { my $this = shift; $this->Wrap("select",shift); }
sub __small    { my $this = shift; $this->Wrap("small",shift); }
sub __span     { my $this = shift; $this->Wrap("span",shift); }
sub __strong   { my $this = shift; $this->Wrap("strong",shift); }
sub __style    { my $this = shift; $this->Wrap("style",shift); }
sub __sub      { my $this = shift; $this->Wrap("sub",shift); }
sub __sup      { my $this = shift; $this->Wrap("sup",shift); }
sub __table    { my $this = shift; $this->Wrap("table",shift); }
sub __tbody    { my $this = shift; $this->Wrap("tbody",shift); }
sub __td       { my $this = shift; $this->Wrap("td",shift); }
sub __textarea { my $this = shift; $this->Wrap("textarea",shift); }
sub __tfoot    { my $this = shift; $this->Wrap("tfoot",shift); }
sub __th       { my $this = shift; $this->Wrap("th",shift); }
sub __thead    { my $this = shift; $this->Wrap("thead",shift); }
sub __title    { my $this = shift; $this->Wrap("title",shift); }
sub __tr       { my $this = shift; $this->Wrap("tr",shift); }
sub __tt       { my $this = shift; $this->Wrap("tt",shift); }
sub __ul       { my $this = shift; $this->Wrap("ul",shift); }
sub __var      { my $this = shift; $this->Wrap("var",shift); }

1;

=pod

=head1 ML - markup language generator

This is a toolkit of convenience methods for generating tags and
elements in an SGML-like markup language.  It has many shortcuts for
generating HTML markup, but can also be used for XHTML, and even XML.

Most commonly, it will be used to assemble well-formed HTML elements
and tags.  This gives less risk of broken HTML, better portability
between HTML and XHTML, and the ability to build complex and aggregate
structures in a single convenient call.

It can be used to generate snippets of markup, or to assemble numerous
snippets into partial or complete documents.

The settings in C<$config{markup}> define basic syntax rules:

=over 4

=item xml

Use xml syntax for self-closing tags, ie. E<lt>tag /E<gt>, and force
tags to lower case.

=item minattr

Minimize unset attributes, eg. C<selected> instead of C<selected="selected">

=item safe_content

Assume content is HTML-safe.  If not true, then content will be
HTML-escaped before insertion into the document.

=item safe_attributes

Assume attributes are HTML-safe.  If not true, then attributes will
be HTML-escaped before insertion into the tags.

=item nl

Append newline characters to the end of each element, for formatting purposes.

=back

=head2 Document Handling

=head3 new(%opt)

Creates an ML object to work with.  C<%opt> contains settings to
override the default config settings, noted above.

You also pass a B<doc> option, which initializes the ML object with a
preformatted (already marked-up) document.

Example: create a markup language object with XML syntax rules:

    my $ml = new ExSite::ML(xml=>1); 

=head3 Write()

Returns the current document as a string.

=head3 Print(), PrintWithHeader()

Prints the current document to C<stdout>.  The second form includes a 
content-type header.

=head3 Doc($text)

Sets the current document to C<$text>.

=head3 Append($text)

Appends C<$text> to the end of the current document.

=head3 Prepend($text)

Prepends C<$text> to the beginning of the current document.

=head3 Clear()

Blanks or resets the current document.

=head3 Doctype($text)

Sets a document preamble, which will be prepended to the whole
document before C<Write>ing or C<Print>ing.  This is typically used
for doctype declarations such as:

    <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">

or

    <?xml version="1.0"?>

The value of C<$text> should contain the entire preamble string.

Note that the doctype is not considered part of the document contents,
so it will always appear at the top, no matter how or when you use
Append(), Prepend(), or Wrap().

=head2 Basic Element Creation

A markup element is a tag with a set of attributes and some contents.
The tag is essential, and the contents and attributes are optional.

=head3 Element($tag,$data,$attributes)

Generates a markup entity.  We do not validate the element against
any DTD or other standard.  We simply generate a text string with an
SGML-like or XML-like structure, eg.

    $ml->Element("tag");                # outputs <tag> in non-xml mode
                                        # outputs <tag /> in xml mode
                                        # outputs <tag></tag> if element normally holds content

    $ml->Element("tag",
                 "contents");           # outputs <tag>contents</tag>

    $ml->Element("tag",
                 "contents",
                 {attribute=>"value"}); # outputs <tag attribute="value">contents</tag>

The main purpose is to ensure consistent formatting, valid syntax, and
easier switching between XML- and non-XML-based formats (specifically,
HTML and XHTML).

C<$tag> is a simple string, used as the tag name.  This should be a
word (no whitespace), but this is not validated.

C<$attributes> is a hashref of key/value pairs; values will be quoted.
Attributes with undefined values will be output as either

    name="name"

or

    name

depending on the C<minattr> configuration option.

C<$data> is the contents, which can be a scalar, array or hash. This 
will be interpreted by the C<Content()> method, below.

The safe_content configuration setting indicates that string content
can be safely inlined right into the element; if false, the content
will be escaped (using HTML escape values) first.  The safe_attributes
configuration setting has the same effect for attribute values.

This method only generates regular elements, not other markup such
as comments, document types, CDATA, etc.

=head3 Comment($text)

Generates an HTML-style comment tag, ie.

    <!-- $text -->

Double-hyphens are removed from the comment text to prevent accidental
premature closure of the comment.

=head2 HTML tag shortcuts

All HTML 4 strict elements have a shortcut method

    $ml->tag($content,$attributes);

where C<tag> is an element name.  This is equivalent to

    $ml->Element($tag,$content,$attributes);

C<$content> and C<$attributes> are optional.  C<$content> is run
through C<Content()> (above) to resolve data structures.

Tag shortcuts for the following elements are supported:
a, abbr, acronym, address, applet, area, b, base, big, blockquote,
body, br, button, caption, cite, code, col, colgroup, dd, del, dfn,
div, dl, dt, em, fieldset, form, frame, frameset, h1, h2, h3, h4, h5,
h6, head, hr, html, i, iframe, img, input, ins, kbd, label, legend,
li, link, map, meta, noscript, object, ol, optgroup, option, p, param,
pre, q, samp, script, select, small, span, strong, style, sub, sup,
table, tbody, td, textarea, tfoot, th, thead, title, tr, tt, ul, var.

Note that if you provide content and attributes, the element will be
built accordingly, even if HTML does not support attributes or content
for that tag.  In other words, we compose a syntactically complete
element, not a semantically correct one.

Example:

    my $link = $ml->a( "Google", { href => "http://google.com" } );

=head2 Cumulative Document Composition

Elements can be cumulatively aggregated in the ML object.  The
"current document" is just the current blob of marked-up text that has
been accumulated.  Text can be accumulated from the top-down,
bottom-up, or in layers like an onion.

=head3 Prepend to the document

To add marked-up text to the beginning of the current document:

    $ml->Prepend($text);

Note that in this and the C<Append()> method below, the text is not
validated, which means you can break your syntax if you stuff your own
tags into it carelessly.

=head3 Append to the document

To add marked-up text to the end of the current document:

    $ml->Append($text);

Or, you can use the auto-append methods.  The methods C<Element()>,
C<Comment()>, and the HTML tag shortcuts above all have an auto-append
version which automatically appends their output to the current
document.  The auto-append method begins with an underscore but the
rest of the method is the same.

    # compose a link and return it to the caller
    $ml->a( "Google", { href => "http://google.com" } );

    # compose a link and append it to the current document
    $ml->_a( "Google", { href => "http://google.com" } );

=head3 Wrap the document in another element

To wrap the current document in a markup element (ie. create a markup 
element with the current document as its content):

    $ml->Wrap( $tag, $attributes );

As a convenience you can use the auto-wrap methods.  The methods
C<Element()>, C<Comment()>, and the HTML tag shortcuts above all have
an auto-wrap version which automatically uses the current document
as the element contents.  The auto-wrap method begins with a
double-underscore but the rest of the method name is the same.

    # enclose current document in a body (with optional attributes)
    $ml->__body( $attributes );

    # prepend a head section (containing a title element)
    $ml->Prepend( $ml->head( $ml->title("Document Title") ) );

    # wrap the whole shebang in an html tag
    $ml->__html();

Note that it is easy to create bizarre HTML constructions.  The caller
is responsible for nesting their elements appropriately.  For
instance, the following will be processed without complaint, despite
not being a legal HTML construction:

    $ml->_p("A paragraph.");  # add a paragraph to the document
    $ml->__style();           # wrap document in style tags (!?)

=head2 Compound Element Creation

=head3 Content($data)

Given a data structure of nested elements, we try to transform it into
markup text.  The elements of our data structure may refer to text,
element parameters, or more data structures that have to be resolved
recursively.  We do not necessarily know the tag in all of these
cases, but we can often infer the tag based on the element we are
nesting under (eg. if we are in a C<E<lt>olE<gt>>, then a nested
element is likely to be a C<E<lt>liE<gt>>).

If C<$data> is a scalar, it is taken to be explicit text or mark-up.

If C<$data> is an arrayref, it is taken to be an Element description
([tag,content,attributes], or [content,attributes]), a list of
explicit markup text, or a list of more data structures.

If C<$data> is a hashref, it is taken to be a set of tag =E<gt>
content pairs.

In cases where we are not given the tag explicitly, we can often
determine it from context.  (Eg. if we are in a C<E<lt>olE<gt>>, then
a nested element is likely to be a C<E<lt>liE<gt>>.)  To get a
context, we need to have been called recursively from a parent
element, and that parent element must define a default child tag (see
the C<%default_child> variable). 

To get a sense for how this works, you can examine the HTML shortcut
calls in the following examples.  The shortcut call defines the
top-level element, which gives a context for determining how the
content data structure should be converted into markup.

B<List Examples>: These calls will all generate lists, using various
structures to represent the list items.

    # list items are explicit contents
    $ml->ul( [
	      "list item 1",
	      "list item 2",
	      "list item 3",
	     ] );

    # list items are element descriptors (tag, content)
    $ml->ol( [
	      [ "li", "list item 1" ], 
	      [ "li", "list item 2" ], 
	      [ "li", "list item 3" ], 
	     ], 
	     { type=>"i" } );

    # list items are hashes of tag=>content
    $ml->dl( [ 
	       { dt => $title1, dd => $description1 },
	       { dt => $title2, dd => $description2 },
	       { dt => $title3, dd => $description3 },
	     ] );

B<Table Examples>:  These calls will all generate a 2-column table with 
numeric data in the cells.  Some have header and footer rows, others
do not.

    # simple table, no headers or footers
    $ml->table( [ 
		  [ 123, 456 ], 
		  [ 789, 123 ], 
		  [ 456, 789 ], 
		],
		{class=>"Report"},
	      );

    # table with head, body, foot, and caption
    $ml->table( { caption => "Sample Table",
		  thead => [ 
			     [ "head1", "head2" ] 
			   ],
		  tbody => [ 
			     [ 123, 456 ], 
			     [ 789, 123 ], 
			     [ 456, 789 ], 
			   ],
		  tfoot => [ 
			     [ 1368, 1368 ] 
			   ],
		},
		{class=>"Report"},
	      );

=head3 Compound Element Composition Rules

When creating markup, there are a few parameters that we use for defining 
some basic nesting and formatting rules.

=over 4

=item alltags 

This references a list of all standard tags.  This is not used to
validate tags, so you can create tags not in this list.  However, it
is used to help identify items that look like tag names in data
structures.

=item emptytags

This references a list of tags that are not supposed to contain
content.  If these tags are created with undefined content, they will
result in a single (self-closing) tag; otherwise, an open and close
tag will be created.

=item no_nl

We normally terminate all closing tags with a newline character for tidier
formatting.  In inline elements, newlines are treated as whitespace, and 
can cause minor formatting defects in some cases.  Tags in this list will 
not receive any terminating newline.

=item default_child

This is a hashref of tag =E<gt> child-tag, which helps us guess what
element nests underneath a parent tag, if it has not been explicitly
defined in a data structure.

=item default_order

This is a hashref of tag =E<gt> list of tags, which helps us figure
out which order to output tags when they have been provided to us in
an unordered hash.

=back

The ML class includes default rules for all of the above, which are
sufficient for HTML 4 or XHTML composition.  If building a markup
document of a different type and you want to make use of the data
structure feature to build complex markup in one call, then you will
need to provide a set of rules to replace the default HTML rules.  You
can set these rules by providing alternate definitions for the above
parameters, like this:

    $ml->set("emptytags",["foo", "bar"]);

=head2 XML and XHTML

To make your output XHTML-compatible, set the C<xml> option when
creating your ML document, or set C<markup.xml=1> in your
configuration file to make this the default.  This forces tags to be
lower case, and changes the format of self-closing tags.  For example,
the call

    $ml->Element("BR");

will produce E<lt>BRE<gt> if xml is off, and E<lt>br /E<gt> if xml is on.
Note that 

    $ml->br();

will produce a lower-case C<br> in all cases.

This effectively changes the syntax to xml, but it still does not
validate against a DTD.  It also does not manage the syntax of
explicitly-coded markup that may have been passed in as content.  It
only affects the syntax of elements it itself has generated.

For instance, the following will generate correct output all of the time:

    $ml->br();

However, if the C<safe_content> flag is on, then the following will
not produce correct XML, since the content contains explicitly-coded
markup that is not XML-compatible:

    $ml->p("Linebreak<br>");

(If C<safe_content> is off, then the C<br> tag will be escaped and
will be presented as regular content, which keeps it XML-compatible,
but may not be what the author intended.)

If you can avoid the latter situation, then it is possible to switch 
quickly from HTML to XHTML with a single configuration setting.

=head3 XML documents

This class has a lot of convenience functions for HTML markup, but it
actually doesn't care about the tags you use.  That means you can use
it to generate XML documents that have no relation to HTML.  For
example, here is a recipe to generate an XML RSS file:

    # make an RSS feed
    my $rss = new ExSite::ML(xml=>1);
    $rss->Doctype('<?xml version="1.0"?>');

    # note auto-append calls
    $rss->_Element("title","My Feed");
    $rss->_Element("description","About My Feed");
    $rss->_Element("link","http://myurl.com");

    # make an item - do not use auto-append methods
    $item = $rss->Element("title","1st Item");
    $item .= $rss->Element("description","1st description");
    $item .= $ress->Element("link","http://link.com");
    # now append this item to the document
    $rss->_Element("item",$item);
    # repeat for as many items as necessary

    # wrap the document up - note wrap calls
    $rss->__Element("channel");
    $rss->__Element("rss",{ version => "2.0" });

    $rss->Print;

=cut

