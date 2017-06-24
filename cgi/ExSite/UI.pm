#!/usr/bin/perl
#---------------------------------------------------------------------------
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

package ExSite::UI;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Base;

use vars qw(@ISA $ml %format %tone %dispsize %baseclass);
@ISA = qw(ExSite::Base);

%format = (
    link => '<a[[?url]] href="[[url]]"[[/?url]][[?id]] id="[[id]]"[[/?id]][[?class]] class="[[class]]"[[/?class]][[?target]] target="[[target]]"[[/?target]][[?attributes]] [[attributes]][[/?attributes]]>[[?img]]<span class="toolicon">[[img]]</span>[[/?img]][[label]]</a>',
    button => '<button type="button"[[?id]] id="[[id]]"[[/?id]][[?js]] onclick="[[js]]"[[/?js]][[?class]] class="[[class]]"[[/?class]][[?attributes]] [[attributes]][[/?attributes]]>[[?img]]<span class="toolicon">[[img]]</span>[[/?img]][[label]]</button>',
    icon => '<div class="[[class]]"><a[[?url]] href="[[url]]"[[/?url]][[?js]] onclick="[[js]]"[[/?js]][[?target]] target="[[target]]"[[/?target]]><div class="iconimg">[[img]]</div>[[label]]</a></div>',
    iconinline => '<span class="[[class]]"><a href="[[url]]"[[?target]] target="[[target]]"[[/?target]][[?attributes]] [[attributes]][[/?attributes]]><img src="[[icon]]" alt="[[alt]]" title="[[title]]">[[label]]</a></span>',
    box => '<div class="panel [[class]]"[[?id]] id="[[id]]"[[/?id]][[?style]] style="[[style]]"[[/?style]]>[[?title]]<div class="panel-heading"><h3 class="panel-title">[[title]]</h3>[[/?title]]</div><div class="panel-body">[[pane]]</div></div>',
    overlay => '<div class="modal fade" id="overlay[[id]]" tabindex="-1" role="dialog" aria-labelledby="overlayTitle[[id]]"><div class="modal-dialog" role="document"><div class="modal-content"><div class="modal-header"><button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>[[title]]</div><div class="modal-body">[[pane]]</div>[[foot]]</div></div></div>',
    message => '<p class="[[class]]">[[pane]]</p>',
    alert => '<div class="alert alert-dismissable [[class]]" role="alert"><button type="button" class="close" data-dismiss="alert" aria-label="Close"><span aria-hidden="true">&times;</span></button><strong>[[title]]</strong> [[pane]]</div>',
    framebox => '<div class="framebox[[?class]] [[class]][[/?class]]"><span class="framehead" style="[[style]]">[[title]]</span><div class="framepane">[[pane]]</div></div>',
    accordionpane => '<div class="panel [[class]]"><div role="tab" id="heading[[id]]" class="panel-heading"><h4 class="panel-title"><a data-parent="#accordion[[pid]]" aria-expanded="[[state]]" aria-controls="blind[[id]]" role="button" data-toggle="collapse" href="#blind[[id]]" class="accordionLink[[?titleclass]] [[titleclass]][[/?titleclass]]">[[title]]</a></h4></div><div aria-labelledby="heading[[id]]" class="panel-collapse [[paneclass]]" role="tabpanel" id="blind[[id]]"><div class="panel-body">[[pane]]</div></div></div>',
    tablink => '<li role="presentation"[[?class]] class="[[class]]"[[/?class]]><a href="[[url]]" role="tab">[[label]]</a></li>',
    tab => '<li role="presentation"[[?class]] class="[[class]]"[[/?class]]><a data-toggle="tab" href="#[[target]]" role="tab" aria-controls="[[target]]">[[label]]</a></li>',
    tabpane => '<div class="tab-pane[[?class]] [[class]][[/?class]]" id="[[id]]" role="tabpanel">[[pane]]</div>',
    figure => '<div class="figure[[?class]] [[class]][[/?class]]"><div class="figure-wrapper">[[img]][[?caption]]<div class="caption">[[caption]]</div>[[/?caption]]</div></div>',
    fatool => '<a href="[[url]]" class="fatool[[?class]] [[class]][[/?class]]" title="[[label]]" data-toggle="tooltip"><span class="fa-stack fa-lg"><span class="fa fa-circle fa-stack-2x"></span>[[icon]]</span></span></a>', # too big
    spinner => '<span class="fa fa-spinner fa-pulse fa-fw[[?class]] [[class]][[/?class]]"></span><span class="sr-only">Loading...</span>',
    );

%tone = (
    default => { important => "tone-important",
		 good => "tone-good",
		 warning => "tone-warning",
		 bad => "tone-bad" },
    button => { important => "btn-primary",
		good => "btn-success",
		warning => "btn-warning",
		bad => "btn-danger" },
    panel => { important => "panel-primary",
	       good => "panel-success",
	       warning => "panel-warning",
	       bad => "panel-danger" },
    message => { important => "bg-primary",
		 good => "bg-success",
		 warning => "bg-warning",
		 bad => "bg-danger" },
    alert => { important => "alert-info",
	       good => "alert-success",
	       warning => "alert-warning",
	       bad => "alert-danger" },
    );
%baseclass = ( button=>"btn", 
	       'link-button'=>"btn", 
	       icon=>"icon", 
	       box=>"panel-default",
	       message=>"msg",
    );
%dispsize = ( 
    box => { l=>"box-large", m=>"box-medium", s=>"box-small" },
    framebox => { l=>"box-large", m=>"box-medium", s=>"box-small" },
    message => { l=>"msg-large", m=>"msg-medium", s=>"msg-small" },
    spinner => { l=>"fa-5x", m=>"fa-2x", s=>"" },
    icon => { l=>"icon-lg", m=>"", s=>"icon-sm" },
    menu => { l=>"vmenu-lg", m=>"", s=>"vmenu-sm" },
    );

#========================================================================

sub new ($%) {
    my ($this,%opt) = @_;
    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;
    # copy options into object
    while (my ($key,$val) = each %opt) {
	$obj->{$key} = $val;
    }
    $obj->initialize_object;
    $ml or $ml = &get_obj("ML");
    return $obj;
}

# navitem: internal util for generating links
# options:
# type = link, link-button, button, icon, tab?
# tone = important, good, neutral, warning, bad
# size = l, m, s
# ucicon = unicode icon
# format = html template for the navitem
# tooltip = tooltip popup text
# pane = popup resulting from click, if no url
# url = destination of navitem
# js = javascript function to execute on click of navitem
# * = substitution parameters such as url, class, id, target, label

sub navitem {
    my ($this,%opt) = @_;
    my %attr;

    # basic formatting

    my $type = $opt{type} || "link";
    if ($type eq "link-button") { $type = "link"; }
    my $format = $opt{format} || $format{$type};
    my $tone = $opt{tone} || "neutral";
    my $size = $opt{size} || "m"; # medium
    my $is_button = $opt{type} =~ /button/; # button or link-button
    my @class = $opt{class} ? ($opt{class}) : ();
    if ($baseclass{$opt{type}}) { push @class, $baseclass{$opt{type}}; }
    %attr = %{$opt{attr}} if $opt{attr};

    # link/function

    if ($opt{url}) {
	if ($opt{confirm}) {
	    # replace link with a confirmation dialog
	    $share{page_footer} .= &insert_js("misc");
	    if ($type eq "button") {
		$opt{js} = "confirm_custom('$opt{confirm}','$opt{url}')";
	    }
	    else {
		$opt{url} = "javascript:confirm_custom('$opt{confirm}','$opt{url}')";
		delete $opt{js};
	    }
	}
	elsif ($type eq "button") {
	    # buttons don't link to urls directly
	    $opt{js} = "window.location.href='$opt{url}'";
	}
    }
    elsif ($opt{js}) {
	if ($type ne "button") {
	    $opt{url} = "javascript:$opt{js}";
	    delete $opt{js};
	}
    }

    # size

    if ($is_button) {
	if ($size =~ /^m/) {
	    push @class, "btn-sm";
	}
	elsif ($size =~ /^s/) {
	    push @class, "btn-xs";
	}
    }
    elsif ($type eq "icon") {
	if ($size =~ /^l/) {
	    push @class, "icon-lg";
	}
	elsif ($size =~ /^s/) {
	    # small icons can be inlined
	    $format = $format{iconinline};
	    push @class, "icon-sm";
	    $opt{alt} = $opt{label};
	    $opt{tooltip} = $opt{label} if (! $opt{tooltip});
	    delete $opt{label};
	}
    }

    # tone

#    push @class, $tone{$is_button?"button":"default"}{$tone};
    if (! $opt{tone} && $opt{this}) {
	# no tone passed, but button represents current state
	$tone = "important";
    }
    if ($tone eq "important") {
	if ($is_button) {
	    push @class, "btn-primary";
	}
	elsif ($opt{this}) {
	    push @class, "active",
	}
	else {
	    push @class, "tone-important";
	}
    }
    elsif ($tone eq "good") {
	push @class, ($is_button ? "btn-success" : "tone-good");
    }
    elsif ($tone eq "warning") {
	push @class, ($is_button ? "btn-warning" : "tone-bad");
    }
    elsif ($tone eq "bad") {
	push @class, ($is_button ? "btn-danger" : "tone-bad");
    }
    elsif ($tone eq "neutral") {
	push @class, "btn-default" if $is_button;
    }

    # tooltips

    if ($opt{tooltip}) {
	$share{page_footer} .= $this->js();
	$attr{'data-toggle'} = "tooltip";
	$attr{title} = $opt{tooltip};
    }

    # popups

    if ($opt{pane}) {
	$share{page_footer} .= $this->js();
	if ($opt{pane} =~ /<\w+( [^>]*)?>/) {
	    # contains markup - use an overlay
	    my $tover = ++$share{ui_idcount}{overlay};
	    my $title = $opt{title} ? $ml->h4($opt{title},{class=>"modal-title",id=>"overlayTitle$tover"}) : "";
	    my $foot = $opt{footer} ? $ml->div($opt{footer},{clsas=>"modal-footer"}) : "";
	    # button mods
	    $attr{'data-toggle'} = "modal";
	    $attr{'data-target'} = "#overlay$tover";
	    # works with buttons, other navitems not tested
	    my $popup = $this->dispitem(type=>"overlay",
					id=>$tover,
					title=>$opt{title},
					pane=>$opt{pane});
	    # drop the pane markup in the footer
	    $share{page_footer} .= $popup;
	}
	else {
	    $attr{tabindex} = 0;
	    $attr{role} = "button";
	    $attr{'data-toggle'} = "popover";
	    $attr{'data-trigger'} = "focus";
	    $attr{'data-content'} = $opt{pane};
	}
    }

    # icons
	
    if (exists $opt{icon} && ! exists $opt{img} && $format =~ /\[\[img\]\]/) {
	# image icon
	$opt{img} = $ml->img(undef,{src=>$opt{icon},alt=>$opt{label},title=>$opt{title}});
    }
    elsif ($opt{ucicon}) {
	# text icon - default font
	if ($type eq "icon") {
	    # expecting an image icon
	    $opt{img} = $this->UnicodeIcon($opt{ucicon});
	}
	else {
	    my $ucicon = $opt{ucicon} =~ /^\&\#/ ? $opt{ucicon} : $this->UnicodeIcon($opt{ucicon});
	    if ($ucicon) {
		$ucicon = $ml->span($ucicon,{class=>"ucicon"});
		$opt{label} = $ucicon.$opt{label};
	    }
	}
    }
    elsif ($opt{faicon}) {
	# text icon - special font
	my $icon = $this->FAIcon($opt{faicon},%opt);
	if ($type eq "icon") {
	    # expecting an image icon
	    $opt{img} = $icon;
	}
	else {
	    $opt{label} = $icon.$opt{label}; # needs css spacing
	}
    }

    # dropdown menus

    my ($ddbutton,$menu);
    if ($opt{links} && ref $opt{links} eq "ARRAY") {
	foreach my $link (@{$opt{links}}) {
	    if (ref $link) {
		$menu .= $ml->li($this->navitem(%$link));
	    }
	    else {
		$menu .= $ml->li($link);
	    }
	}
	# reconfig button for dropdown
	$opt{label} .= " ".$ml->span(undef,{class=>"caret"});
	push @class, "dropdown-toggle";
	$attr{'data-toggle'} = "dropdown";
	$attr{'aria-haspopup'} = "true";
	$attr{'aria-expanded'} = "false";
	$share{page_footer} .= $this->js();
    }

    $opt{class} = join " ",@class;
    if (scalar keys %attr > 0) { $opt{attributes} = &EncodeAttributes(%attr); }
    my $out = &substitute($format,\%opt);
    if ($menu) {
	$out = $ml->div($out.$ddbutton.$ml->ul($menu,{class=>"dropdown-menu"}),{class=>"btn-group"});
    }
    return $out;
}

# dispitem: internal util for generating display panels
# options:
# type = box, overlay
# format = html template for the dispitem
# tone = important, good, neutral, bad
# size = l, m, s
# float = left, right
# * = substitution parameters such as title, pane, class, id

sub dispitem {
    my ($this,%opt) = @_;
    my $type = $opt{type} || "box";
    my $format = $opt{format} || $format{$type} || $format{box};
    my $size = $opt{size} || "l";  # large
    my @class = $opt{class} ? ($opt{class}) : ();
    if ($baseclass{$type}) { push @class, $baseclass{$type}; }

    if ($opt{ucicon}) {
	my $iconclass = $opt{tone} ? "ucicon ".$tone{default}{$opt{tone}} : "ucicon";
	my $icon =  $ml->span($this->UnicodeIcon($opt{ucicon}),{class=>$iconclass});
	if ($opt{title}) {
	    $opt{title} = $icon.$opt{title};
	}
	else {
	    $opt{pane} = $icon.$opt{pane};
	}
    }
    elsif ($opt{faicon}) {
	my $icon =  $this->FAIcon($opt{faicon},%opt);
	if ($opt{title}) {
	    $opt{title} = $icon.$opt{title};
	}
	else {
	    $opt{pane} = $icon.$opt{pane};
	}
    }
#    my @style = $opt{style} ? ($opt{style}) : ();
    if ($opt{tone}) {
	if ($class[0] =~ /panel/) {
	    # use bootstrap contextual classes
	    push @class, $tone{panel}{$opt{tone}};
	}
#	elsif ($type eq "message") {
#	    push @class, $tone{message}{$opt{tone}};
#	}
	elsif (exists $tone{$type}) {
	    push @class, $tone{$type}{$opt{tone}};
	}
    }
    if ($size) {
	push @class, $dispsize{$type}{$size};
    }
    if ($opt{float}) {
	push @class, "pull-$opt{float}";
    }
    if ($type eq "message") {
	if ($opt{title}) {
	    # messages don't have title elements
	    my $title = $ml->strong($opt{title});
	    if ($opt{tone}) { $title = $ml->span($title,{class=>$tone{default}{$opt{tone}}}); }
	    $opt{pane} = $title.$ml->br.$opt{pane};
	}
    }
    $opt{class} = join " ",@class;
#    $opt{style} = join " ",@style;
    return &substitute($format,\%opt);
}

#========================================================================
# Standardized shortcut methods

#------------------------------------------------------------------------
# BasicBox - output a framed box containing content, with a titlebar
# see dispitem for options
#------------------------------------------------------------------------

sub BasicBox {
    my ($this,%opt) = @_;
    if ($opt{width}) { 
	# not supported, convert to size
	if ($opt{width} =~ /\%/) {
	    $opt{width} =~ s/\%//;
	    $opt{size} = $opt{width} < 50 ? "s" : "m";
	}
	else {
	    $opt{size} = $opt{width} <= 400 ? "s" : "m";
	}
    }
    return $this->dispitem(%opt);
}

#------------------------------------------------------------------------
# ErrorBox - BasicBox with error styles
# SuccessBox - BasicBox with success styles
# HelpBox - BasicBox with help styles
#
# Same parameters as BasicBox.
#------------------------------------------------------------------------

sub ErrorBox {
    my ($this,%opt) = @_;
    $opt{title} or $opt{title} = "Error";
    $opt{class} = "panel-danger";
    $opt{size} or $opt{size} = "s";
    return $this->BasicBox(%opt);
}
sub SuccessBox {
    my ($this,%opt) = @_;
    $opt{title} or $opt{title} = "Success";
    $opt{class} = "panel-success";
    $opt{size} or $opt{size} = "s";
    return $this->BasicBox(%opt);
}
sub HelpBox {
    my ($this,%opt) = @_;
    $opt{title} or $opt{title} = "Help";
    $opt{class} = "panel-info";
    $opt{size} or $opt{size} = "s";
    return $this->BasicBox(%opt);
}

#------------------------------------------------------------------------
# ErrorMsg 
# SuccessMsg
# HelpMsg
#
# Simpler, smaller versions of previous boxes; no title, just a message
#------------------------------------------------------------------------

sub ErrorMsg {
    my ($this,$msg) = @_;
    return $this->dispitem(pane=>$msg,type=>"message",tone=>"bad",faicon=>"bad");
#    return $this->dispitem(pane=>$msg,type=>"message",tone=>"bad",ucicon=>"bad");
}
sub SuccessMsg {
    my ($this,$msg) = @_;
    return $this->dispitem(pane=>$msg,type=>"message",tone=>"good",faicon=>"good");
#    return $this->dispitem(pane=>$msg,type=>"message",tone=>"good",ucicon=>"good");
}
sub HelpMsg {
    my ($this,$msg) = @_;
    return $this->dispitem(pane=>$msg,type=>"message",tone=>"important",faicon=>"help");
#    return $this->dispitem(pane=>$msg,type=>"message",tone=>"important",ucicon=>"right");
}

#------------------------------------------------------------------------
# AlertBox - dismissable dialog-like box
#------------------------------------------------------------------------

sub AlertBox {
    my ($this,%opt) = @_;
    $opt{type} = "alert";
    $opt{tone} or $opt{tone} = "important";
    return $this->dispitem(%opt);
}

#------------------------------------------------------------------------
# ScrollBox - BasicBox with a preset height.  Overflow content
# is viewable using a scrollbar.
#
# Same parameters as BasicBox.
#------------------------------------------------------------------------

sub ScrollBox {
    my $this = shift;
    return $this->BasicBox(@_,(class => "scrollbox"));
}

#------------------------------------------------------------------------
# CropBox - BasicBox with a preset height, but no scrollbar.
# Overflow content is cropped.
#
# Same parameters as BasicBox.
#------------------------------------------------------------------------

sub CropBox {
    my $this = shift;
    return $this->BasicBox(@_,(class => "cropbox"));
}

#------------------------------------------------------------------------
# FrameBox - framed box, with a title set into the frame
# assumes a bgcolor of white
#------------------------------------------------------------------------

sub FrameBox {
    my ($this,%opt) = @_;
    $opt{type} = "framebox";
    my $bgcolor = $opt{bgcolor} || $this->{bgcolor} || "white";
    if ($opt{style}) {
	$opt{style} .= " background-color:$bgcolor;";
    }
    else {
	$opt{style} = "background-color:$bgcolor;";
    }
    if ($opt{tone}) {
	$opt{class} = $tone{default}{$opt{tone}};
    }
    return $this->dispitem(%opt);
}

#------------------------------------------------------------------------
# BlindBox - box rolls up if you click on the head
#
# Same parameters as BasicBox, plus:
# open => 1|0 (defaults to open)
#------------------------------------------------------------------------

###FIXME: state is ignored

sub BlindBox {
    my ($this,%opt) = @_;
    my $state = $opt{state} || $opt{open}; # backwards compat.
    # implement as a single-pane accordion
    return $this->AccordionBox(
	titles=>[$opt{title}],
	panes=>[$opt{pane}],
	states=>[$state],
	size=>"m",
	);
}

#------------------------------------------------------------------------
# AccordionBox - a list of blindboxes
#
# An AccordionBox is a sequence of boxes arranged in a stack.  Each box
# can be expanded/shrunk.
#   titles=>[array of box titles]
#   panes=>[array of pane contents]
#   states=>[array of box states]
#------------------------------------------------------------------------

###FIXME: states are ignored; all panes close when one is opened

sub AccordionBox {
    my ($this,%opt) = @_;
    $opt{pid} = ++$share{ui_idcount}{accordion};

    # stack a bunch of blindboxes
    my $out;
    foreach my $title (@{$opt{titles}}) {
	my $pane = shift @{$opt{panes}};
	my $state = shift @{$opt{states}} ? "true" : "false";
	my %popt = %opt;
	$popt{type} = "accordionpane";
	$popt{id} = ++$share{ui_idcount}{blind};
	$popt{hid} = ++$share{ui_idcount}{heading};
	$popt{class} = "panel-default";
	$popt{title} = $title;
	$popt{pane} = $pane;
	$popt{state} = $state;
	if ($state eq "false") {
	    $popt{paneclass} = "collapse"; 
	    $popt{titleclass} = "collapsed";
	}
	else {
	    $popt{paneclass} = "collapse in";
	}
	$out .= $this->dispitem(%popt);
    }
    my @class = ("panel-group accordionbox");
    if ($opt{size}) {
	push @class, $dispsize{box}{$opt{size}};
    }
    my $class = join " ", @class;
    return $ml->div($out,{id=>"accordion$opt{pid}", role=>"tablist", 'aria-multiselectable'=>"true", class=>$class});
}

#------------------------------------------------------------------------
# MenuBox - static menu box;  left hand side is a menu of options,
#           right-hand side is the box pane.
#
# Does not use navitem or dispitem. (FIXME? what features does it get us?)
#
# This element must be regenerated in its entirety when another menu
# item is selected.
#
# tabs=>        arrayref of menu menu hashrefs {label=>,url=>}
# menu=>        same as above
# thistab=>     index of the active menu item (starting from 0)
# pane=>        HTML contents of tab pane
# height=>      height of the pane (auto scrolls, if necessary)
#------------------------------------------------------------------------

sub MenuBox {
    my ($this,%opt) = @_;
    my $links = $opt{links} || $opt{tabs} || $opt{menu};
    return $this->error("Invalid MenuBox") if (ref $links ne "ARRAY");
    if ($opt{thistab}) {
	$links->[$opt{thistab}]{this} = 1;
    }
    my $menu = $this->Menu(links=>$links,size=>"s");
    my $out = $ml->Comment("begin MenuBox");
    $out .= $ml->div(
	$menu.
	$ml->div($opt{pane},{class=>"menuboxpane"}),
	{class=>"menubox clearfix",style=>"width:100%"}
	);
    $out .= $ml->Comment("end MenuBox");
    return $out;
}

sub MenuBox_old {
    my ($this,%opt) = @_;
    if (! exists $opt{tabs}) { $opt{tabs} = $opt{menu}; }
    return $this->error("Invalid MenuBox") if (ref $opt{tabs} ne "ARRAY");
    my $tabbar;
    my $itab = 0;
    foreach my $tab (@{$opt{tabs}}) {
	my $label = $tab->{label};
	my %aopt = (href=>$tab->{url});
	my %liopt = (role=>"presentation");
	if ($opt{thistab} && $itab == $opt{thistab}) {
	    $label .= $ml->span(undef,{class=>"tabmarker"});
	    $aopt{class} = "thisitem";
	    $liopt{class} = "active";
	}
	$tabbar .= $ml->li($ml->a($label,\%aopt),\%liopt);
	$itab++;
    }
    my $minheight = ($itab-1) * 40;
    my $out = $ml->Comment("begin MenuBox");
    $out .= $ml->div(
	$ml->ul($tabbar,{class=>"nav nav-pills nav-stacked pull-left",style=>"width:150px"}).
	$ml->div($opt{pane},{class=>"menuboxpane"}),

	{class=>"menubox clearfix",style=>"width:100%"}
	);
    $out .= $ml->Comment("end MenuBox");
    return $out;
}

#------------------------------------------------------------------------
# TabBox - static tab box
#
# TabBoxes can be generated 3 ways:
#
# 1) one tab pane, each tab hits a new URL
#
# tabs => array of navitems
# pane => contents of the tab pane
# thistab => which tab is active
#
# 2) multiple tab panes, dynamic switching
#
# tabs => array of tab labels
# panes => matching array of dispitems 
# thistab => which tab/pane is active
#
# 3) no pane, just a tab bar
#
# tabs => array of navitems
# thistab => which tab is active
#------------------------------------------------------------------------

sub TabBox {
    my ($this,%opt) = @_;
    return $ml->p("Invalid TabBox",{class=>"error"}) 
	if (ref $opt{tabs} ne "ARRAY");

    my (@tabs,$ipane,@panes);
    $ipane = 0;
    my $tid = $share{ui_idcount}{tab};
    foreach my $tablabel (@{$opt{tabs}}) {
	$tid++;
	my %paneopt = ( type=>"tabpane" );
	my %tabopt = ref $tablabel ?
	    ( label=>$tablabel->{label}, url=>$tablabel->{url} ) :
	    ( label=>$tablabel );
	my $pane;
	my $id = "tabpane$tid";
	if ($opt{panes}) {
	    $tabopt{type} = "tab";
	    $pane = shift @{$opt{panes}};
	    $tabopt{target} = $id;
	    $paneopt{id} = $id;
	}
	else {
	    $tabopt{type} = "tablink";
	}
	if ($ipane == $opt{thistab}) {
	    $tabopt{class} = "active";
	    $paneopt{class} = "active";
	    $pane = $opt{pane} if ($opt{pane});
	}
	push @tabs, $this->navitem(%tabopt);
	if ($pane) {
	    $paneopt{pane} = $pane;
	    $paneopt{id} = "tabpane$tid";
	    push @panes, $this->dispitem(%paneopt);
	}
	$ipane++;
    }
    $share{ui_idcount}{tab} = $tid;

    return 
	$ml->div(
	    $ml->ul(join("",@tabs),{class=>"nav nav-tabs",role=>"tablist"}).
	    $ml->div(join("",@panes),{class=>"tab-content"}),
	    {class=>"tabbox"}
	);
}
# for backwards-compatibility:
sub DynTabBox {
    my ($this,%opt) = @_;
    return $this->TabBox(%opt);
}
sub TabBar {
    my ($this,%opt) = @_;
    return $this->TabBox(%opt);
}

#------------------------------------------------------------------------
# Figure - image photo, chart, diagram
#
# img=>      the image to display (tag, url, or hashref)
# lg_img=>   hi-res image to popup (**TODO)
# title=>    title text for image
# class=>    figure class
# caption=>  caption
# float=>    right, left
#------------------------------------------------------------------------

### FIXME: implement lg_img using popup or somesuch

sub Figure {
    my ($this,%opt) = @_;
    if (ref $opt{img}) {
	# hash of img attributes
	$opt{img}{alt} or $opt{img}{alt} = "figure";
	$opt{img} = $ml->img(undef,$opt{img});
    }
    elsif ($opt{img} !~ /^</) {
	# not image tag, assume it's an img src
	$opt{img} = $ml->img(undef,{src=>$opt{img},alt=>"figure"});
    }
    $opt{type} = "figure";
    $opt{caption} or $opt{caption} = $opt{title};
    return $this->dispitem(%opt);
}

#------------------------------------------------------------------------
# TreeView - exploding list (formerly DynList)
#
# This supports nested sublists, to any depth.
#
# A list is a sequence of hashes, each describing a list element:
#   text=>full text of the list element
#   label=>anchor text of the list element, or text string if no url
#   url=>destination of list element link
#   target=>where list element link opens
#   open=>1|0 determines whether this list element is opened
#   sublist=>referece to another list, nested under this element
#   class=>class of the list item wrapper DIV
#------------------------------------------------------------------------

sub TreeView {
    my $this = shift;
    my $out;
    foreach my $item (@_) {
	$out .= $this->TreeViewItem($item);
    }
    return
	$ml->Comment("begin TreeView").
	$this->js("tv.js").
        &insert_js("\$(document).ready(function(){\$(\".tv\").simple_treeview();});").
	$ml->ul($out,{class=>"tv"}).
	$ml->Comment("end TreeView");
}
sub DynList { &TreeView(@_); } # backwards compatibility

sub TreeViewItem {
    my ($this,$opt) = @_;
    return $ml->p("Invalid list item",{class=>"error"}) 
	if (ref $opt ne "HASH");
    my %opt = %$opt;
    my $class = $opt->{class} || "listitem";

    my $out;
    if ($opt{url}) {
	my %link = ( href=>$opt{url} );
	if ($opt{target}) { $link{target} = $opt{target}; }
	$out = $ml->a($opt{label},\%link);
    }
    else {
	$out = $opt{label};
    }
    if ($opt{text}) {
	$out .= $ml->span($opt{text},{class=>"listitem_details"});
    }
    if ($opt{sublist}) {
	my $list;
	foreach my $item (@{$opt{sublist}}) {
	    $list .= $this->TreeViewItem($item);
	}
	$out .= $ml->ul($list);
    }
    my %listopt;
    my @class;
    if ($opt{class}) {
	push @class, $opt{class};
    }
    my $state = $opt{sublist} ? ($opt{state} || $opt{open}) : undef;
    if (! defined $state) { $state = 1; };
    if (! $state) {
	push @class, "closed";
    }
    if (@class > 0) {
	$listopt{class} = join(" ",@class);
    }
    return $ml->li($out,\%listopt);
}

#------------------------------------------------------------------------
# Popup
#
# Displays a CSS popup.
#
# pane=>      the contents of the popup
# type=>      over (default), inline, overlay, tooltip, error
# label=>     optional anchor for the popup link/button
# width=>     optional width for the popup
# height=>    optional height for the popup
# top=>       offset of top of popup
# right=>     offset of right of popup
# left=>      offset of left of popup
# class=>     css class for popup box
# linkclass=> css class for link
# closelabel => label of close link
#
# Offsets are relative to the anchor label.
#------------------------------------------------------------------------

sub Popup {
    my ($this,%opt) = @_;
    # backwards-compatibility settings
    my $type = $opt{type};
    if ($type eq "tooltip") {
	$opt{tooltip} = $opt{pane};
	delete $opt{pane};
    }
    $opt{type} = ($opt{linkclass} =~ /button/) ? "button" : "link";
    return $this->navitem(%opt);
}
sub ResponsivePopup { return &Popup(@_); }

sub ToolTip {
    my ($this,%opt) = @_;
    if (! $opt{tooltip}) {
	$opt{tooltip} = $opt{pane};
	delete $opt{pane};
    }
    $opt{type} = ($opt{linkclass} =~ /button/) ? "button" : "link";
    return $this->navitem(%opt);
}

sub Overlay {
    my ($this,%opt) = @_;
    if ($opt{pane} !~ /<\w+( [^>]*)?>/) {
	# won't trigger overlay option, wrap in markup
	$opt{pane} = $ml->div($opt{pane});
    }
    $opt{type} = "button";
    return $this->navitem(%opt);
}

sub HelpPopup {
    my ($this,%opt) = @_;
    $opt{pane} or $opt{pane} = $opt{message}; # backwards compat
    $opt{title} or $opt{title} = $opt{label};
    $opt{ucicon} = "info";
    $opt{type} = "link";
    $opt{class} = "helplink";
    $opt{size} = "s";
    $opt{tone} = "good";
    return $this->navitem(%opt);
}

sub LoginOverlay {
    my ($this,%opt) = @_;
    my $pane;
    $opt{height} or $opt{height} = "200px";
    $opt{label} or $opt{label} = $msg{"log in"};
    my $url = $opt{url};
    if (! $url) {
        $url = exists $ENV{HTTPS} ? "https" : "http";
        $url .= "://".$ENV{HTTP_HOST}.$ENV{REQUEST_URI};
    }
    # no pwd recovery on popup login forms
    my $forgot_login = $config{auth}{forgot_login};
    $config{auth}{forgot_login} = 0;
    my $loginform = $share{DB}->login_form(undef,$url);
    $config{auth}{forgot_login} = $forgot_login;
    if ($share{Page}) {
	if ($share{Page}->is_publishing || ! $share{DB}->level) {
	    $opt{pane} = $loginform;
	}
    }
    else {
	$opt{pane} = $loginform;
    }
    return $opt{pane} ? $this->Overlay(%opt) : $opt{label};
}

#------------------------------------------------------------------------
# BasicBar 
#
# label=>     bar text
# width=>     optional bar width
#------------------------------------------------------------------------

sub BasicBar {
    my ($this,%opt) = @_;
    return $ml->div($opt{label},{class=>"basicbar"});   
}

#------------------------------------------------------------------------
# TitleBar - application identifier and general links 
#
# tools=>     array of links aligned left
# links=>     array of links aligned right
# title=>     title
# icon=>      url to icon
#------------------------------------------------------------------------

sub TitleBar {
    my ($this,%opt) = @_;
    my $ttool = ++$share{ui_idcount}{toolbar};
    my $icon;
    if ($opt{icon}) { 
	$icon = $ml->img(undef,{src=>$opt{icon},class=>"navbar-brand"}); 
    }
    my $nav = $ml->button($ml->span($msg{"Toggle navigation"},{class=>"sr-only"}).
			  $ml->span(undef,{class=>"icon-bar"}).
			  $ml->span(undef,{class=>"icon-bar"}).
			  $ml->span(undef,{class=>"icon-bar"}),
			  {type=>"button",class=>"navbar-toggle collapsed",'data-toggle'=>"collapse",'data-target'=>"#toolbar$ttool",'aria-expanded'=>"false"});
    $nav .= $ml->a($icon.$opt{title},{class=>"navbar-brand",href=>"#"});
    my $out = $ml->div($nav,{class=>"navbar-header"});
    my @nav;
    foreach my $tool (@{$opt{tools}}) {
	push @nav, $ml->li($this->navitem(%$tool));
    }
    my $links;
#    if ($opt{links}) {
#	foreach my $link (@{$opt{links}}) {
#	    $links .= $this->navitem(%$link);
#	}
#	$links = $ml->p($links,{class=>"navbar-text navbar-right"});
#    }

    $out .= $ml->div(
	$ml->ul(
#	    join($ml->li("|",{class=>"navbar-text hidden-xs"}),@nav),
	    join("",@nav),
	    {class=>"nav navbar-nav navbar-right"}
	).
	$links,
	{class=>"collapse navbar-collapse",id=>"toolbar$ttool"}
	);

    return $ml->Element("nav",
			$ml->div($out,{class=>"container-fluid"}),
			{class=>"navbar navbar-default"}
	);
}

#------------------------------------------------------------------------
# ToolBar - a bar of buttons
# links or tools => list of navitems
#                   use an undef element to insert a separator
#------------------------------------------------------------------------

sub ToolBar {
    my ($this,%opt) = @_;
    my @btn = ("");
    my $linklist = $opt{links} || $opt{tools};
    foreach my $link ($this->link2nav(@$linklist)) {
	if ($link) {
	    if ($link->{class}) {
		$link->{class} = "btn btn-sm $link->{class}";
#		$link->{class} = "btn $link->{class}";
	    }
	    elsif ($link->{this}) {
		$link->{class} = "btn btn-sm btn-primary";
#		$link->{class} = "btn btn-primary";
	    }
	    else {
		$link->{class} = "btn btn-sm btn-default";
#		$link->{class} = "btn btn-default";
	    }
	    if (ref $link->{url}) {
		# link dest is not an url; assume it's another navlist,
		# and use a dropdown
		if ($link->{icon}) {
		    $link->{label} = $link->{icon}.$link->{label};
		}
		elsif ($link->{img}) {
		    $link->{label} = $ml->img(undef,{src=>$link->{img}}).$link->{label};
		}
		my $menu;
		foreach my $ddlink (@{$link->{url}}) {
		    $menu .= $ml->li($this->navitem(%$ddlink));
		}
		my $out = $ml->button($link->{label}." ".$ml->span(undef,{class=>"caret"}),
				      {type=>"button",class=>$link->{class},'data-toggle'=>"dropdown",'aria-haspopup'=>"true",'aria-expanded'=>"false"});
		$out .= $ml->ul($menu,{class=>"dropdown-menu"});
		$btn[-1] .= $ml->div($out,{class=>"btn-group"});
	    }
	    else {
		$btn[-1] .= $this->navitem(%$link);
	    }
	}
	else {
	    push @btn, "";
	}
    }
    my $out;
    foreach my $btngrp (@btn) {
	$out .= $ml->div($btngrp,{class=>"btn-group", role=>"group", 'aria-label'=>"tool group"});
    }
    return $ml->div(
	$ml->div($out,{class=>"btn-toolbar", role=>"toolbar", 'aria-label'=>"tool bar"}),
	{class=>"toolbar"}
	);
}
sub IconBar { # v3 compat
    my $this = shift; return $this->ToolBar(@_);
}

#------------------------------------------------------------------------
# MenuBar 
#
# links=>     array of links (a tags, or {url=>, label=>, img=> (optional)})
# width=>     optional bar width
#
# Using the img option gives something similar to an IconBar, but each
# link occupies more horizontal and less vertical space.
#------------------------------------------------------------------------

sub MenuBar {
    my ($this,%opt) = @_;
    my $out;
    foreach my $link ($this->link2nav(@{$opt{links}})) {
	$out .= ref $link ?
	    $this->navitem(type=>"link-button",%$link) :
	    $this->navitem(type=>"link-button",$this->aparse($link));
    }
    return $ml->div($out,{class=>"btn-group btn-group-justified menubar", role=>"group", 'aria-label'=>"menu bar"});
}

#------------------------------------------------------------------------
# PathBar 
#
# links=>     array of links (a tags, or {url=>, label=>, class=>})
# width=>     optional bar width
#------------------------------------------------------------------------

sub PathBar {
    my ($this,%opt) = @_;
    my $out;

    foreach my $link (@{$opt{links}}) {
	if (ref $link) {
	    if ($link->{url}) {
		my %attr = ( href=>$link->{url} );
		$attr{target} = $link->{target} if $link->{target};
		$out .= $ml->li($ml->a($link->{label},\%attr));
	    }
	    else {
		$out .= $ml->li($link->{label});
	    }
	}
	else {
	    foreach my $sublink ($this->aparse($link)) {
		if ($sublink->{url}) {
		    my %attr = ( href=>$sublink->{url} );
		    $attr{taget} = $sublink->{target} if $sublink->{target};
		    $out .= $ml->li($ml->a($sublink->{label},\%attr));
		}
		else {
		    $out .= $ml->li($sublink->{label});
		}
	    }
	}
    }
    return $ml->ol($out,{class=>"breadcrumb"});
}

#------------------------------------------------------------------------
# Icon
#
# label=>     icon text
# img=>       image url
# img_x=>     image height
# img_y=>     image width
# img_size=>  image height & width
# url=>       url to link to
# target=>    target window/frame
#------------------------------------------------------------------------

sub Icon {
    my ($this,%opt) = @_;
    $opt{type} or $opt{type} = "icon";
    $opt{size} or $opt{size} = "l";
    if (ref $opt{img}) {
	# hash of img attributes
	$opt{img}{alt} or $opt{img}{alt} = "$opt{label} icon";
	$opt{img} = $ml->img(undef,$opt{img});
    }
    elsif ($opt{img} !~ /^</) {
	# not image tag, assume it's an img src
	$opt{img} = $ml->img(undef,{src=>$opt{img},alt=>"$opt{label} icon"});
    }
    return $this->navitem(%opt);

    my %imgopt = ( src=>$opt{img}, border=>0 );
    my %aopt = ( href=>$opt{url} );
    if ($opt{target}) { $aopt{target} = $opt{target}; }
    my $w = $opt{img_x} || $opt{img_size};
    my $h = $opt{img_y} || $opt{img_size};
    if ($h && $w) {
	$imgopt{width} = $w;
	$imgopt{height} = $h;
    }
    return $ml->div(
	$ml->a(
	    $ml->div($ml->img(undef,\%imgopt),{class=>"iconimg"}).
	    $opt{label},
	    \%aopt
	),
	{class=>"icon"});
}

#------------------------------------------------------------------------
# ToolIcon
#
# name=>      use icons from /_ExSite/images/icons
# label=>     tooltip
# img=>       image url
# img_x=>     image height (default 16)
# img_y=>     image width (default 16)
# img_size=>  image height & width
# url=>       url to link to
# target=>    target window/frame
# confirm=>   require confirmation
#------------------------------------------------------------------------

sub ToolIcon {
    my ($this,%opt) = @_;
    my %imgopt = ( border=>0 );
    if ($opt{name}) {
	$imgopt{src} = "$config{server}{HTMLpath}/_ExSite/images/icons/$opt{name}.png";
	$imgopt{width} = $imgopt{height} = 16;
	$opt{label} or $opt{label} = $opt{name};
    }
    else {
	$imgopt{src} = $opt{img};
	my $w = $opt{img_x} || $opt{img_size};
	my $h = $opt{img_y} || $opt{img_size};
	if ($h && $w) {
	    $imgopt{width} = $w;
	    $imgopt{height} = $h;
	}
    }
    my %aopt = $opt{confirm} ?
	( href=>"javascript:confirm_custom('$opt{confirm}','$opt{url}')" ) :
	( href=>$opt{url} );
    if ($opt{target}) { $aopt{target} = $opt{target}; }
    if ($opt{label}) {
	$imgopt{title} = $opt{label};
	$imgopt{alt} = $opt{label};
	$aopt{title} = $opt{label};
    }
    $imgopt{class} = "toolicon";
    return &insert_js("misc").$ml->a($ml->img(undef,\%imgopt),\%aopt);
}

#------------------------------------------------------------------------
# Arrow 
#
# dir=>       up, down, left, right
# url=>       goto this url when clicked
# onclick=>   execute this JS function when clicked
#------------------------------------------------------------------------

sub Arrow {
    my ($this,%opt) = @_;
    my $dir = $opt{dir} || "up";
    my $url = $opt{url};
    my $onclick = $opt{onclick};
    if (! $onclick) {
	# convert URL to JS
	if ($url =~ /^javascript:/) {
	    $onclick = $url;
	    $onclick =~ s/^javascript://;
	}
	else {
	    $onclick = "window.location.href='$url'";
	}
    }
    return $ml->div(
	$ml->div(undef,{class=>"arrow_$dir",onclick=>$onclick}),
	{class=>"arrowbox"}
	);
}

#------------------------------------------------------------------------
# UnicodeIcon - text icons
# pass a name in $icon, this will return the HTML entity for the symbol
#------------------------------------------------------------------------

sub UnicodeIcon {
    my ($this,$icon) = @_;
    # %icon maps icon names to the decimal unicode character
    my %icon = (
	back => 8617,     # back, cancel, undo
	bang => 10082,    # exclamation point
	check => 10004,   # approve, submit
	#copy => 9112,     # (next page)
	copy => 61,     # =
	cross => 10006,   # delete, close, cancel
	down => 11015,
	flag => 9873,
	gear => 9881,
	handleft => 9754, # hand pointing left
	handright => 9755,# hand poiting right
	heart => 9829,
	home => 8962,     # house-shaped pentagon
	in => 10549,      # (right and down arrow)
	info => 9432,
	left => 11013,
	upright => 8599,  # arrow pointing up and right
	list => 8285,     # (vertical ellipsis, like bullets)
	out => 10548,     # (right and up arrow)
	pencil => 9999,   # edit
	plus => 10010,    # add, new
	qmark => 10067,   # question mark
	'redo' => 8635,   # reset, reload, redo
	table => 9783,    # 6 bars in a grid
	right => 10145,
	search => 9906,   # circle with line, like a magnifier
	star => 9733,
	tag => 10070,     # four square, arranged in a diamond
	time => 8986,
	up => 11014,
	warning => 9888,  # hazard
	write => 9997,    # hand with pencil
	xbox => 9746,     # close
	good => 9786,
	bad => 9785,
	);
    my $ucicon = exists $icon{$icon} ? "&#".$icon{$icon} : undef;
    return $ucicon;
    #return $ml->span($ucicon,{class=>"ucicon"}); # might need icons in non-markup contexts
}

sub UnicodeTool {
    my ($this,$function,%opt) = @_;
    # %tool maps a tool function to the best UnicodeIcon name
    my %tool = (
	add => "plus",
	back => "left",
	bad => "frown-o",
	close => "xbox",
	conf => "gear",
	copy => "copy",
	delete => "cross",
	edit => "write",
	help => "info",
	insert => "plus",
	link => "upright",
	list => "table",
	new => "plus",
	search => "search",
	update => "write",
	view => "in",
	);
    $opt{class} = "uctool";
    if ($opt{label}) { 
	$opt{tooltip} = $opt{label};
	delete $opt{label};
    }
    $opt{ucicon} = $tool{$function};
    $opt{size} or $opt{size} = "s";
    $opt{type} or $opt{type} = "link";
    return $this->navitem(%opt);
}
# shortcut
sub uctool { my $this = shift; return $this->UnicodeTool(@_); }

#------------------------------------------------------------------------
# FAIcon - text icons using FontAwesome
# slightly slower that UnicodeIcon because it involves loading a special
# font, but much more variety and better quality than Unicode options.
#
# can pass a simplified name or the FA code
# see http://fontawesome.io/cheatsheet/ for full list of codes
#------------------------------------------------------------------------

sub FAIcon {
    my ($this,$icon,%opt) = @_;
    # %icon maps simple icon names to Font Awesome css class code
    my %icon = (
	add => "plus",
	back => "arrow-left",
	bad => "frown-o",
	block => "ban",
	#bookmark => "bookmark",
	box => "archive",
	#calendar => "calendar",
	cart => "shopping-cart",
	chart => "line-chart",
	#check => "check",
	close => "times",
	#comment => "comment",
	conf => "cog",
	configure => "cog",
	contact => "address-card",
	#copy => "copy",
	close => "times",
	cross => "times",
	delete => "trash-o",
	down => "arrow-down",
	#download => "download",
	ecommerce => "credit-card",
	edit => "pencil",
	email => "envelope",
	event => "calendar",
	'exit' => "times",
	export => "download",
	#facebook => "facebook",
	#folder => "folder",
	gallery => "th",
	good => "smile-o",
	grid => "th",
	#heart => "heart",
	help => "question",
	hidden => "eye-slash",
	#home => "home",
	#image => "image",
	info => "info-circle",
	insert => "plus",
	#key => "key",
	left => "arrow-left",
	#link => "link",
	#list => "list",
	location => "map-marker",
	#lock => "lock",
	menu => "navicon",
	money => "dollar",
	new => "plus",
	order => "list-ol",
	page => "file-o",
	pages => "files-o",
	photo => "camera",
	#print => "print",
	#qrcode => "qrcode",
	quote => "quote-right",
	reload => "repeat",
	reply => "mail-reply",
	report => "table",
	rewind => "backward",
	right => "arrow-right",
	rss => "rss-square",
	#save => "save",
	#search => "search",
	#sort => "sort",
	#spinner => "spinner",
	#star => "star",
	#tag => "tag",
	template => "object-group",
	text => "file-text-o",
	time => "clock-o",
	#twitter => "twitter",
	up => "arrow-up",
	update => "pencil",
	#upload => "upload",
	#user => "user",
	view => "eye",
	#warning => "warning",

	# workflow

	publish => "arrow-right",
	archive => "archive",
	queue => "clock-o",
	approve => "thumbs-up",
	draft => "edit",
	submit => "send",
	cancel => "times",
	expire => "hourglass-end",
	reject => "thumbs-down",
	workflow => "arrows",
	);
    my $name = $icon{$icon} || $icon;
    my $faclass = "fa fa-fw fa-".$name;
    if ($opt{spin}) {
	$faclass .= " fa-spin";
    }
    if ($opt{size}) {
	# default is small
	if ($opt{size} =~ /^m/) {
	    $faclass .= " fa-lg";
	}
	elsif ($opt{size} =~ /^l/) {
	    $faclass .= " fa-3x";
	}
    }
    if ($opt{tone}) {
	$faclass .= " ".$tone{default}{$opt{tone}};
    }
    # rotation?
    return $ml->span(undef,{class=>$faclass});
}

sub FATool {
    my ($this,$function,%opt) = @_;
    $opt{class} = "fatool";
    $opt{tooltip} = $opt{label} || $function;
    delete $opt{label};
    $opt{faicon} = $function;
    $opt{size} or $opt{size} = "s";
    $opt{type} or $opt{type} = "link";
    return $this->navitem(%opt);
}

sub FATool_stacked {  # too big
    my ($this,$function,%opt) = @_;
    $opt{icon} = $this->faicon($function,class=>"fa-stack-1x fa-inverse");
    $opt{type} = "fatool";
    $opt{label} or $opt{label} = $opt{tooltip} || $function;
    $opt{size} or $opt{size} = "s";
    return $this->navitem(%opt);
}

# lc versions
sub faicon { my $this = shift; return $this->FAIcon(@_); }
sub fatool { my $this = shift; return $this->FATool(@_); }

#------------------------------------------------------------------------
# Menu - vertically-oriented menubar
#------------------------------------------------------------------------

sub Menu {
    my ($this,%opt) = @_;
    my @item;
    my $nitem = 0;
    foreach my $link (@{$opt{links}}) {
	$link->{class} = "list-group-item";
	push @item, $this->navitem(%$link);
	$nitem++;
    }
    my $size = $opt{size} || "m";
    my $class = "list-group vmenu ".$dispsize{menu}{$opt{size}};
    return $ml->div(join("\n",@item),{class=>$class});
}

#------------------------------------------------------------------------
# Button
#
# label=>    button text
# url=>      url to link to
# type=>     link|button (link is default)
# target=>   target window/frame
# small=>    true if a small button (otherwise, a regular button)
# class=>    additional class to apply to the button
# confirm=>  confirmation dialog message (link types only)
# icon=>     unicode icon to prepend to label, if any
#------------------------------------------------------------------------

sub Button {
    my ($this,%opt) = @_;
    if ($opt{small}) { $opt{size} = "s"; }
    $opt{type} or $opt{type} = "button";
    return $this->navitem(%opt);
}

sub BackButton {
    my ($this,%opt) = @_;
    $opt{label} or $opt{label} = $msg{Back};
    $opt{ucicon} = "left";
    $opt{url} or $opt{js} = "history.back()";
    return $this->Button(%opt);
}

#------------------------------------------------------------------------
# Alert - creates a link that generates a Javascript alert box 
# containing arbitrary text.
#
# accepts navitem args, or:
# button=>   1, if link should be presented as a button
# message=>  text of alert message
#------------------------------------------------------------------------

sub Alert {
    my ($this,%opt) = @_;
    $opt{message} or $opt{message} = $opt{pane};
    $opt{message} = $this->clean_text_for_js($opt{message});
    $opt{type} or $opt{type} = $opt{button} ? "button" : "link";
    $opt{js} = "alert('$opt{message}')";
    return $this->navitem(%opt);
}
sub clean_text_for_js {
    my ($this,$text) = @_;
    $text =~ s/\"/\\\"/g;
    $text =~ s/\'/\\\'/g;
    # insert linebreaks, if not already done
    if ($text !~ /\\n/ && $text =~ /\n/) {
	$text =~ s/\r?\n/\\n/g;
    }
    return $text;
}

#------------------------------------------------------------------------
# Confirm - creates a link that requires a confirmation before visiting it
#
# label=>    button text
# button=>   1, if link should be presented as a button, 2 if button_sm
# message=>  text of alert message
# url =>     url to link to
#------------------------------------------------------------------------

sub Confirm {
    my ($this,%opt) = @_;
    $opt{message} or $opt{message} = $opt{pane};
    if ($opt{button}) { $opt{type} = "button"; }
    if ($opt{button} == 2) { $opt{size} = "s"; } # v3 compat
    $share{page_footer} .= $this->js("misc");
    $opt{message} = $this->clean_text_for_js($opt{message});
    $opt{confirm} = $opt{message};
    $opt{tone} or $opt{tone} = "bad";
    return $this->navitem(%opt);
}

#------------------------------------------------------------------------
# MailTo - builds mailto: links that are spambot-resistant
#
# label => anchor text
# email => target email address
#------------------------------------------------------------------------

sub MailTo {
    my ($this,$email,$label) = @_;
    return $label if (! $email);
    my ($user, $domain) = split(/\@/,$email,2);
    my $dummy = "$user AT $domain";
    my $anchor;
    if ($label) { $anchor = $label; }
    my $out = $this->js();
    $out .= &insert_js("HTML", "mailto('$user','$domain','$anchor');");
    $out .= $ml->noscript($dummy);
}

#------------------------------------------------------------------------
# Spinner
#
# size => s, m ,l
#------------------------------------------------------------------------

sub Spinner {
    my ($this,%opt) = @_;
    $opt{class} = $dispsize{spinner}{$opt{size}};
    return &substitute($format{spinner},\%opt);
}

#------------------------------------------------------------------------
# CSS
#
# This can be used to auto-insert the necessary CSS if your stylesheet
# does not have it.
#------------------------------------------------------------------------

sub CSS {
    my $this = shift;
    return 
	$ml->link(undef,
		  {rel=>"stylesheet", type=>"text/css",
		   href=>"$config{server}{HTMLpath}/_ExSite/css/UIbs.css"}).
        $ml->link(undef,
		     {rel=>"stylesheet", type=>"text/css",
		      href=>"$config{server}{HTMLpath}/_ExSite/css/bootstrap/bootstrap.css"});
}
############### UIbs.css

#------------------------------------------------------------------------
# Internal box-building function
#
# wrapperClass
# wrapperStyle
# headClass
# headStyle
# head
# paneClass
# paneStyle
# pane
#------------------------------------------------------------------------

sub box {
    my ($this,%opt) = @_;

    my ($wrapperClass, $wrapperStyle, $headClass, $headStyle,$paneClass,
	$paneStyle, $paneID, $head, $pane);

    my %headopt = ( class => $opt{headClass} || "panel-heading" );
    my %paneopt = ( class => $opt{paneClass} || "panel-body" );
    my %wrapopt = ( class => "panel " );
    $wrapopt{class} .= $opt{wrapperClass} ? $opt{wrapperClass} : "panel-default";

    if ($opt{wrapperStyle}) { $wrapopt{style} = $opt{wrapperStyle}; }
    if ($opt{headStyle})    { $headopt{style} = $opt{headStyle}; }
    if ($opt{paneStyle})    { $paneopt{style} = $opt{paneStyle}; }
    if ($opt{paneID})       { $paneopt{id}    = $opt{paneID}; }
    $head = $opt{head} ? $ml->div($ml->h3($opt{head},{class=>"panel-title"}),\%headopt) : "";
    $pane = $ml->div($opt{pane},\%paneopt);
    return $ml->Comment("begin box").
	$ml->div($head.$pane,\%wrapopt).
	$ml->Comment("end box");
}

#------------------------------------------------------------------------
# Internal javascript output function
#------------------------------------------------------------------------

sub js {
    my $this = shift;
    my $extrajs = shift;
    my $out;
    if (! $share{js}{ui}) {
	$out .= &insert_js("jquery","jqueryui");
	$out .= &insert_js("bootstrap","tooltip","popover","dropdown");
	$share{js}{ui} = 1;
    }
    if ($extrajs) {
	$out .= &insert_js($extrajs);
    }
    return $out;
}

#------------------------------------------------------------------------
# Internal link deconstruction function
# - converts text <a> links to datahashes
#------------------------------------------------------------------------

sub aparse {
    my ($this,$links) = @_;
    my @link;
    # break links up
    $links =~ s/<\/a><a/<\/a>###<a/ig;
    foreach my $atag (split /###/,$links) {
	$atag =~ /<a (.+?)>(.+)<\/a>/si;
	if ($1 && $2) {
	    my $label = $2;
	    my %link = &DecodeAttributes($1);
	    if ($label =~ /(<img .+?>)(<br>)?(.+)/si) {
		$link{label} = $3;
		$link{icon} = $1;
	    }
	    else {
		$link{label} = $label;
	    }
	    if (! $link{url} && $link{href}) { $link{url} = $link{href}; }
	    push @link, \%link;
	}
	else {
	    # not a link?
	    push @link, { label => $atag };
	}
    }
    return wantarray ? @link : \@link;
}

# link2nav - convert groups of links to arrays of navitems
# groups of links come in 3 formats:
# fmt1 = concatenated link.link.link, link
# fmt2 = link,link,link,undef,link
# fmt3 = linklinklink link

sub link2nav {
    my $this = shift;
    my @navlist;
    foreach my $list (@_) {
	if ((ref $list) eq "HASH") {
	    # already a navitem - fix img attributes
	    if (exists $list->{img}) {
		if ($list->{img} !~ /^</) {
		    # not an img tag, probably an img src, use icon
		    $list->{icon} = $list->{img};
		    delete $list->{img};
		}
	    }    
	    push @navlist, $list;
	}
	elsif ((ref $list) eq "ARRAY") {
	    # sublist; break it down recursively
	    my @list = $this->link2nav(@$list);
	    push @navlist, \@list;
	}
	elsif ($list) {
	    # scalar - hardcoded link(s)
	    my @list = $this->aparse($list);
	    push @navlist, @list;
	    if (scalar @list > 1) { push @navlist, undef; }
	}
	else {
	    # undef / spacer
	    push @navlist, undef;
	}
    }
    return @navlist;
}

#========================================================================

=pod

=head1 ExSite::UI

=head2 User Interface widgets, elements, and templates

This package contains routines and functions to generate complex HTML 
structures. Structures are comprised of combinations of two base strutures:

=over 4

=item C<navitem>

something you click on to access more information, such as a hyperlink, 
button, tool, or tab. Navitems have attributes like label, url, icon, target,
confirm.

=item C<dispitem>

something that displays information, such as a panel, pane, popup, or box.
Dispitems have attributes like title, and pane.

=back

Both C<navitem>s and C<dispitem>s can have attributes like state, class, height, 
and width.

ExSite 4 UI widgets are built from lower-level Bootstrap components, which means
they follow industry-standard accessibility, responsiveness, and theming 
conventions.

=head2 Links and Buttons

These show a single C<navitem> in various ways.

=over 4

=item Button 

a link formatted as a clickable button.

=item MailTo

a mailto: link, obfuscated to prevent email scraping

=item Icon

a link to launch an application, shown as a large icon and label.

=item ToolIcon

an iconized tool link, consisting of a small icon and label, suitable for 
inlining into text, reports, and bars.

=item UnicodeTool (abbreviated uctool)

like ToolIcon, but uses a unicode character instead of a graphical icon,
for better performance.

=item FATool (or fatool)

like UnicodeTool, but uses Font Awesome, for a variety of scalable graphics.

=item Arrow

a CSS arrow that can be used as a button.

=item BackButton 

a button to go back in the history.

=item Alert

a link that raises a Javascript alert dialog.

=item Confirm

a link that requires the user to confirm before they are taken to the URL.

=back

=head2 Boxes

These show a single C<dispitem> as a framed unit of content.

=over 4

=item BasicBox 

a framed box with titlebar and content pane.

=item ScrollBox

a BasicBox with fixed height, and a scrollbar if the pane overflows.

=item CropBox 

a BasicBox with fixed height but no scrollbar.  If the pane overflows, 
it will be cropped.

=item FrameBox (control group)

a pane that is framed by a rule.  The frame title is overlaid on the
top left corner of the frame rule.

=item HelpBox, SuccessBox, ErrorBox

similar to BasicBox, but styled to indicate that the contents provide 
(1) help or how-to information, (2) confirmation that an operation completed,
(3) an error message indicating that an operation did not complete.

=item HelpMsg, SuccessMsg, ErrorMsg

similar to previous, but without a titlebar.

=item BlindBox 

a BasicBox that rolls up and hides its pane when you click on the title.
If the state is C<false> then the BlindBox begins closed.

=back

=head2 Popups

A dispitem that appears over the content when a navitem is activated.

=over 4

=item Popup

Pops up a dispitem when the navitem is activated. The popup covers content 
underneath it.

=item ToolTip

Activated by a mouseover instead of a click.

=item Overlay

Pops up a modal dispitem that takes over the screen. The overlay must be
dismissed before you can access the original screen.

=item LoginOverlay

An overlay that contains a Login dialog.

=back

=head2 Bars

A horizontal bar containing a set of navitems.

=over 4

=item BasicBar

A bar with freeform content.

=item PathBar

A bar with a cookie-crumb set of links showing your current position.

=item MenuBar

A bar divided into buttons/links.

=item ToolBar

A bar containing a number of simple tool buttons.

=item IconBar

Like a toolbar, but the tool buttons are made up of icons+labels.

=back

=head2 TabBoxes

These group together multiple dispitems that are revealed by clicking on 
a corresponding set of navitems.

=over 4

=item TabBox 

a tab bar, with a content pane beneath it. The panes can be dynamic
(revealed by javscript) or there can be a single pane, and the other
tabs will take you to different URLs. Leave off the pane, and you 
get a simple tab bar.

=item MenuBox

similar to a TabBox, but the tabs are oriented vertically on the left
of the pane. This allows for more tabs that can fit in a conventional 
tab configuration.

=item AccordionBox 

A stack of BlindBoxes.

=back

=head2 Lists

=over 4

=item TreeView

a nested list, in which sub-lists can be revealed/hidden by clicking on 
controls.

=back

=cut

1;
