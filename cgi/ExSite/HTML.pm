#!/usr/bin/perl
#---------------------------------------------------------------------------
#
#   Copyright 2001-2004 Exware Solutions, Inc.  http://www.exware.com
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

BUGS

- long tab labels cause formatting problems

=cut

package ExSite::HTML;

use strict;
use ExSite::Config;

use vars qw($list_count %idcount %script_loaded $js_output $active_tab);


#========================================================================

=pod

=head1 ExSite::HTML

=head2 HTML methods and templates

This package contains routines and functions to generate HTML snippets
in various predefined formats.

Most of their appearance and behaviours are controlled by CSS, so you 
need to be using a stylesheet that is sensitive to these classes.
See the ExSite stylesheet for examples.  You can output some generic
compatible CSS using the CSS subroutine.

=head2 Boxes 

These are framed units of content.

=over 4

=item BasicBox 

a framed box with titlebar and content pane.

=item ScrollBox

a BasicBox with fixed height, and a scrollbar if the pane overflows.

=item CropBox 

a BasicBox with fixed height but no scrollbar.  If the pane overflows, 
it will be cropped.

=item FrameBox 

a pane that is framed by a rule.  The frame title is overlaid on the
top left corner of the frame rule.

=item MenuBox

a left-side vertical menu, with a content pane on the right.

=item AccordionBox 

A multi-paned box, in which each pane is collapsible/expandible,
like an accordion.

=item TabBox 

a tab bar, with a content pane beneath it.

=item DynTabBox 

a TabBox, with all tabs/panes preloaded and switchable using DHTML.

=back

=head2 Popups

=over 4

=item Popup

Pops up a box when a link is clicked.  The box covers content underneath it.

=item HelpPopup

Pops up a box when a link is clicked.  The box is inlined into the HTML, so
it does not cover content underneath it.

=item ToolTip

Works like Popup(), but works on a mouseover rather than a click.

=item Overlay

Works like Popup(), but overlays the whole page with a semi-opaque screen
so that the popup must be closed before you can do anything else.

=back

=head2 Other HTML Constructions

=over 4

=item DynList

a nested list, where the sub-lists are normally hidden.  There are
expand/hide icons beside the list items, which can be used to expand
the sub-lists, or hide them.

=item Button

a regular hyperlink, but styled to look like a button.

=item Icon

a graphic icon and label.

=back

=cut

#========================================================================

BEGIN {
    use Exporter   ();
    use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK);
    $VERSION     = 1.00;
    @ISA         = qw(Exporter);
    @EXPORT = qw(   );
    @EXPORT_OK = qw(&BasicBox &ScrollBox &CropBox &FrameBox
		    &FrameBox &MenuBox &TabBox &DynTabBox &AccordionBox
		    &DynList &MultiSelect
		    &HelpPopup &Popup &ResponsivePopup &Overlay &LoginOverlay &HelpPopup
		    &BasicBar &ToolBar &MenuBar &PathBar &IconBar
		    &Icon &Button &Alert &Confirm &Arrow &MailTo
		    &CSS
		    );
}

use vars qw($tag);

sub tag {
    return $tag if $tag;
    $tag = &get_obj("ML");
    return $tag;
}

#------------------------------------------------------------------------
# BasicBox - output a framed box containing content, with a titlebar
#
# title=>      titlebar text
# pane=>       main panel text
# width=>      width of the box
# height=>     height of the box
# padding=>    pane padding
# headwidth=>  width of the titlebar (set short for tab effect)
# paneID=>     id of the pane, in case you want to use it with DHTML
# float=>      left|right, or 1 (left)|0 (none)
#
# WARNING: if your height is insufficient, the pane contents will run
# outside your box.
#------------------------------------------------------------------------

sub BasicBox {
    my %opt = @_;
    my %boxopt = ( 
		   head => $opt{title}, 
		   pane => $opt{pane},
		   paneClass=>$opt{paneClass},
		   headClass=>$opt{headClass},
		   wrapperClass=>$opt{wrapperClass},
		   paneID=>$opt{paneID},
	           paneStyle=>$opt{paneStyle},
	           headStyle=>$opt{headStyle},
		   );
    
    if ($opt{height}) { $boxopt{paneStyle} .= "height:$opt{height};"; }
    if ($opt{width}) { 
	$boxopt{wrapperStyle} .= "width:$opt{width};"; 
    }
    if ($opt{headwidth}) { 
	$boxopt{headStyle} .= "width:$opt{headwidth};"; 
    }
    if ($opt{float}) {
	$boxopt{wrapperStyle} .= ($opt{float} =~ /left|right/i) ?
	    "float:$opt{float};" : "float:left;";
    }
    if ($opt{padding}) { $boxopt{paneStyle} .= "padding:$opt{padding}"; }
    return &box(%boxopt);
}

#------------------------------------------------------------------------
# ErrorBox - BasicBox with error styles
# SuccessBox - BasicBox with success styles
# HelpBox - BasicBox with help styles
#
# Same parameters as BasicBox.
#------------------------------------------------------------------------

sub ErrorBox {
    my %opt = @_;
    $opt{title} or $opt{title} = "Error";
    $opt{wrapperClass} = "errorbox";
    return &BasicBox(%opt);
}
sub SuccessBox {
    my %opt = @_;
    $opt{title} or $opt{title} = "Success";
    $opt{wrapperClass} = "successbox";
    return &BasicBox(%opt);
}
sub HelpBox {
    my %opt = @_;
    $opt{title} or $opt{title} = "Help";
    $opt{wrapperClass} = "helpbox";
    return &BasicBox(%opt);
}

#------------------------------------------------------------------------
# ScrollBox - BasicBox with a preset height.  Overflow content
# is viewable using a scrollbar.
#
# Same parameters as BasicBox.
#------------------------------------------------------------------------

sub ScrollBox {
    return &BasicBox(@_,(paneClass => "scrollpane"));
}

#------------------------------------------------------------------------
# CropBox - BasicBox with a preset height, but no scrollbar.
# Overflow content is cropped.
#
# Same parameters as BasicBox.
#------------------------------------------------------------------------

sub CropBox {
    return &BasicBox(@_,(paneClass => "croppane"));
}

#------------------------------------------------------------------------
# BlindBox - box rolls up if you click on the head
#
# Same parameters as BasicBox, plus:
# open => 1|0 (defaults to open)
#------------------------------------------------------------------------

sub BlindBox {
    my %opt = @_;
    $opt{wrapperClass} = "blindbox";
    my $out = &js();
    if (! $script_loaded{BlindBox}) { 
	$out .= &tag->script("
\$(document).ready(blindbox_rollup);
",{type=>'text/javascript'});
	$script_loaded{BlindBox} = 1;
    }
    # need a separate wrapper for the title so that we can have 2 backgrounds
    # 1) for headbar BG, 2) for blind state
    if (exists $opt{open} && ! $opt{open}) {
	# pane is closed to start
	$opt{headClass} = "boxhead paneClosed";
	$opt{paneStyle} = "display:none;";
    }
    $opt{title} = &tag->span($opt{title},{class=>"boxtitle"});
    $out .= &BasicBox(%opt);
    return $out;
}

#------------------------------------------------------------------------
# FrameBox - framed box, with a title set into the frame
# NB.: not based on BasicBox.
#
# title=>      frame title text
# pane=>       main panel text
# bgcolor=>    you need to specific the general background color, if not white
# color=>      frame color (#ccc for white bgcolor, else defaults to black)
# style=>      solid,inset,outset,groove
# width=>      width of overall box
# thickness=>  width of the frame (in pixels)
# float=>      left|right, or 1 (left)|0 (none)
#------------------------------------------------------------------------

sub FrameBox {
    my %opt = @_;
    my (%boxopt, %headopt, %paneopt);

    my $title = $opt{title} || "Info";
    $headopt{"background-color"} = $opt{bgcolor} || $config{bgcolor} || "white";
    $paneopt{"border-color"} = $opt{color} || 
	($headopt{"background-color"} eq "white" ? "#ccc" : "black");
    $paneopt{"border-style"} = $opt{style} || "solid";
    if ($opt{width}) {
	$boxopt{width} = $opt{width};
    }
    $paneopt{"border-width"} = ($opt{style} eq "groove") ? 2 : ($opt{thickness} || 1);
    if ($opt{float}) {
	$boxopt{float} = ($opt{float} =~ /left|right/i) ?
	    "float:$opt{float};" : "float:left;";
    }

    my @styles = map { "$_:$boxopt{$_}" } keys %boxopt;
    my $boxstyle = join("; ",@styles);
    @styles = map { "$_:$headopt{$_}" } keys %headopt;
    my $headstyle = join("; ",@styles);
    @styles = map { "$_:$paneopt{$_}" } keys %paneopt;
    my $panestyle = join("; ",@styles);

    my $head = &tag->div(&tag->span($title,{class=>"framehead",style=>$headstyle}),
			 {class=>"framehead"});
    my $pane = &tag->div($opt{pane},{class=>"framepane",style=>$panestyle});

    my $out = &tag->Comment("begin FrameBox");
    $out .= &tag->div( $head.$pane, { class=>"framebox", style=>$boxstyle } );
    $out .= &tag->Comment("end FrameBox");
    return $out;
}

#------------------------------------------------------------------------
# MenuBox - static menu box;  left hand side is a menu of options,
#           right-hand side is the box pane.
#
# This element must be regenerated in its entirety when another menu
# item is selected.
#
# tabs=>        arrayref of menu labels, or menu hashrefs {label=>,url=>}
# menu=>        same as above
# thistab=>     index of the active menu item (starting from 0)
# pane=>        HTML contents of tab pane
# pane_id=>     ID of the pane DIV
# width=>       width of the pane
# height=>      height of the pane (auto scrolls, if necessary)
#
# WARNING: if you pass complete links, instead of menu hashrefs, you will
# not get highlighting of thistab.
#------------------------------------------------------------------------

sub MenuBox {
    my %opt = @_;
    if (! exists $opt{tabs}) { $opt{tabs} = $opt{menu}; }
    return &Entity("p",{class=>"error"},"Invalid MenuBox") 
	if (ref $opt{tabs} ne "ARRAY");

    # Shares a lot of logic with TabBox, below, which is why you'll 
    # references to tabs in the code.  A "tab" in this case is a menu 
    # item.

    my ($tabbar,$tabpane);

    my $ntab = scalar @{$opt{tabs}};

    # build the menu bar

    for (my $itab=0; $itab < $ntab; $itab++) {
	my $ttab = ++$idcount{tab};
	my $id = (defined $opt{thistab} && ($itab == $opt{thistab})) ? 
	    "thistab" : "tab$ttab";
	my $tablabel = ref $opt{tabs}[$itab] eq "HASH" ?
	    &tag->a($opt{tabs}[$itab]{label},
		    { href=>$opt{tabs}[$itab]{url}, id=>$id }) :
	    $opt{tabs}[$itab];
	$tabbar .= "$tablabel\n";
    }

    # build the tab pane

    if ($opt{pane}) {
	my $tpane = ++$idcount{tabpane};
	my %paneopt = (class=>"menuboxpane");
	$paneopt{id} = $opt{pane_id} ? $opt{pane_id} : "tabpane$tpane";
	if ($opt{height}) {
	    $paneopt{style} = "height:$opt{height}";
	}
	$tabpane = &tag->div($opt{pane},\%paneopt);
    }

    my %menuboxopt = (class=>"menubox");
    if ($opt{width}) { $menuboxopt{style} = "width:$opt{width};"; }

    my $vmenu = &tag->td($tabbar,{valign=>"top",class=>"menubox_vmenu"});
    my $pane = &tag->td($tabpane,{valign=>"top"});
    my $menutab = &tag->table(
			      &tag->tr($vmenu.$pane),
			      { class=>"menubox", 
				cellspacing=>0, 
				cellpadding=>0, 
				border=>0 }
			      );


    my $out = &tag->Comment("begin MenuBox");
    $out .= &tag->div($menutab,\%menuboxopt);
    $out .= &tag->Comment("end MenuBox");
    return $out;
}

#------------------------------------------------------------------------
# TabBox - static tab box
#
# This element must be regenerated in its entirety when another tab is
# selected.
#
# tabs=>        arrayref of tab labels, or tab hashrefs {label=>,url=>,js=>,target=>}
# thistab=>     index of the active tab (starting from 0)
# pane=>        HTML contents of tab pane
# pane_id=>     ID of the pane DIV
# width=>       width of the pane
# tabwidth=>    width of the tabs (default is 125px)
# tabfill=>     a string to right-fill the tabbar with
# height=>      height of the pane (auto scrolls, if necessary)
# id=>          ID of the tabbox - useful if more than 1 tabbox on page
#
# WARNING: if you explicitly encode your menu labels, you will not get
# highlighting of the current tab.
#------------------------------------------------------------------------

sub TabBox {
    my %opt = @_;
    return &tag->p("Invalid TabBox",{class=>"error"}) 
	if (ref $opt{tabs} ne "ARRAY");

    my ($tabbar,$tabpane,$ttab,$id,$class,$tablabel,$tabopt,$tabboxid);

    $tabboxid = $opt{id} ? "$opt{id}_" : undef;
    my $ntab = scalar @{$opt{tabs}};

    # build the tab bar

    for (my $itab=0; $itab < $ntab; $itab++) {
	$ttab = ++$idcount{tab};
	$id = "tab$tabboxid$ttab";
	$class = "tab";
	if ($itab == $opt{thistab}) {
	    $class .= " thistab";
	    $active_tab = $id;
	}
	$tablabel = ref $opt{tabs}[$itab] eq "HASH" ?
	    $opt{tabs}[$itab]{label} : $opt{tabs}[$itab];
	$tabopt = {class=>$class,id=>$id};
	if (ref $opt{tabs}[$itab] eq "HASH") {
	    if ($opt{tabs}[$itab]{url}) {
		$tabopt->{onclick} = $opt{tabs}[$itab]{target} ?
		    "gotourl('".$opt{tabs}[$itab]{url}."','".$opt{tabs}[$itab]{target}."')" :
		    "gotourl('".$opt{tabs}[$itab]{url}."')";
	    }
	    elsif ($opt{tabs}[$itab]{js}) {
		$tabopt->{onclick} = $opt{tabs}[$itab]{js};
	    }
	}
	if ($opt{tabwidth}) { $tabopt->{style} = "width:$opt{tabwidth}";}
	$tabbar .= &tag->div($tablabel,$tabopt);
    }
    $tabbar = &tag->div($tabbar,{class=>"tabbar"});

    # build the tab pane

    if ($opt{pane}) {
	my $tpane = ++$idcount{tabpane};
	my $id = $opt{pane_id} ? $opt{pane_id} : "tabpane$tabboxid$tpane";
	my $span = $ntab * 2;
	
	my %panedivopt = ( class=>"tabpane", id=>$id );
	if ($opt{height}) { $panedivopt{style} = "height:$opt{height}"; }
	$tabpane = $tag->div($opt{pane},\%panedivopt);
    }
    else {
	# makes a ruled line instead of a box
	my %panedivopt = ( class=>"tabnopane", id=>$id );
	if ($opt{height}) { $panedivopt{style} = "height:0px"; }
	$tabpane = $tag->div($opt{pane},\%panedivopt);
    }

    my %wrapopt = ( class=>"tabbox" );
    if ($opt{width}) { $wrapopt{style} = "width:$opt{width};"; }

    my $out = &tag->Comment("begin TabBox");
    $out .= &insert_js("misc");
    $out .= &tag->div($tabbar.$tabpane,\%wrapopt);
    $out .= &tag->Comment("end TabBox");
    return $out;
}

#------------------------------------------------------------------------
# DynTabBox (DHTML version of TabBox)
#
# This version of the tabbox uses DHTML to do the tab switching
# and pane loading automatically.
#
# tabs=>        array of tab labels
# panes=>       array of pane contents
# thistab=>     index of the active tab (starting from 0)
# pane_id=>     ID of the pane DIV
# width=>       width of the pane
# height=>      height of the pane (auto scrolls, if necessary)
#
# WARNING: if you have more than one dynamic tab box per page, the tabs
# and boxes will interfere with each other and cause formatting problems.
#------------------------------------------------------------------------

sub DynTabBox {
    my %opt = @_;
    return &tag->p("Invalid TabBox",{class=>"error"}) 
	if (ref $opt{tabs} ne "ARRAY");
    my (@tabs,@panes,$style,$selected_tab,$ipane);
    $ipane = 0;
    my $tid = $idcount{tab};
    foreach my $tablabel (@{$opt{tabs}}) {
	$tid++;
	my $pane = shift @{$opt{panes}};
	push @tabs, { label=>$tablabel, js=>"loadtab($tid,this)" };

	# We use overflow rather than display to show/hide the panes, because
	# undisplayed panes can result in obscure window.onload errors in some
	# browsers.  It seems like undisplayed content is not a 1st class 
	# citizen of the DOM, and may not be found or initialized in some
	# Javascript apps.  This approach works slightly better, although not 
	# a whole lot...

	if ($ipane == $opt{thistab}) {
#	    $display = "block";
	    $style = "overflow:visible;height:auto;";
	    $selected_tab = $tid;
	}
	else {
	    $style = "overflow:hidden;height:0px;";
#	    $display = "none";
	}
	push @panes, &tag->div($pane,{id=>"dyntabpane$tid",style=>$style});
	$ipane++;
    }

    # basic TabBox

    my $out = &js().
	&TabBox(
	tabs=>\@tabs,
	pane=> join("\n",@panes),
	thistab=>$opt{thistab},
	width=>$opt{width},
	height=>$opt{height},
	tabwidth=>$opt{tabwidth},
	tabfill=>$opt{tabfill},
	);

    # tab switching code

    if (! $script_loaded{DynTabBox}) { 
	$out .= &tag->script("
var current_tab = $selected_tab;
");
	$script_loaded{DynTabBox} = 1;
    }

    return $out;
}

#------------------------------------------------------------------------
# AccordionBox - exploding list of boxes (uses DHTML)
#
# An AccordionBox is a sequence of boxes arranged in a stack.  Each box
# can be expanded/shrunk.
#   titles=>[array of box titles]
#   panes=>[array of pane contents]
#   states=>[array of booleans, indicating whether the given pane is open]
#	links=>[array of urls, for linking headers to new pages]
#------------------------------------------------------------------------

sub AccordionBox {
    my %opt = @_;
# update icon img
# update onclick
    my $out = &js();

    ### ML markup needed

    my %boxopt = ( class=>"accordionbox" );
    if ($opt{width}) {
	$boxopt{style} = "width:$opt{width}";
    }

    foreach my $title (@{$opt{titles}}) {
	my $paneid = ++$idcount{accordionpane};
	my $pane = shift @{$opt{panes}};
	my $state = 1;
	if (ref $opt{states} eq "ARRAY") {
	    $state = shift @{$opt{states}};
	}
	my $img = $state ? "darr.png" : "rarr.png";
	my %paneopt = ( class=>"accordionpane",id=>"accordionpane$paneid" );
	if (! $state) { $paneopt{style} = "display:none"; }
	my $action = $state ? "contract" : "expand";

	my ($header,$imgtag);
	if ($pane) {
	$imgtag = &tag->img(undef,{src=>"$config{server}{HTMLpath}/_ExSite/images/$img"});
	}	
	if ($opt{links}) {
	my $img = &tag->img(undef,{src=>"$config{server}{HTMLpath}/_ExSite/images/$img"});
	my $link = &tag->a($title,{href=>shift @{$opt{links}}});

	$header = &tag->div(
		&tag->span(
		&tag->span(
		$imgtag,
		{id=>"accordioncontrolicon$paneid",class=>"accordioncontrolicon"}
		),{class=>"accordioncontrol",id=>"accordioncontrol$paneid",onclick=>"accordion_$action($paneid)"})
		."&nbsp;".$link);
	} else {
	$header = &tag->div(
		&tag->span(
		$imgtag,
		{id=>"accordioncontrolicon$paneid",class=>"accordioncontrolicon"}
		)."&nbsp;$title",
		{class=>"accordioncontrol",id=>"accordioncontrol$paneid",onclick=>"accordion_$action($paneid)"});
	}
	$out .= &tag->tr(&tag->th($header,{class=>"accordioncontrol"}));
	$out .= &tag->tr(&tag->td(&tag->div($pane,\%paneopt)));
    }

    return &tag->Comment("begin AccordionBox").
	&tag->table($out,\%boxopt).
	&tag->Comment("end AccordionBox");
}

#------------------------------------------------------------------------
# DynList - exploding list (uses DHTML)
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
#   prefix=>HTML that should be positioned before the list control
#------------------------------------------------------------------------

sub DynList {
    my $out = &js();
    foreach my $item (@_) {
	$out .= &DynListItem($item);
    }
    my $tag = &tag;
    return $tag->Comment("begin DynList").
	$tag->div($out,{class=>"DynList"}).
	$tag->Comment("end DynList");
}

sub DynListItem {
    my $opt = shift;
    my $tag = &tag;
    return $tag->p("Invalid list item",{class=>"error"}) 
	if (ref $opt ne "HASH");
    my %opt = %$opt;
    my ($next, $script, $itemtext, $img, $target, $sublist_style);
    $list_count++;  # global
    $next = $list_count + 1;
    my $class = $opt->{class} || "listitem";

    my $out;
    if ($opt{open}) {
	$script = "list_contract";
	$sublist_style = {};
    }
    else {
	$script = "list_expand";
	$sublist_style = {style=>"display:none;"};
    }

    my %aopt = ( href=>$opt{url}, class=>"listlink" );
    if ($opt{target}) { $aopt{target} = $opt{target}; }
    $itemtext = $opt{url} ? $tag->a($opt{label},\%aopt) : $opt{label};

    my $dimg = $tag->img(undef,{height=>9,width=>9,border=>0,src=>"$config{server}{HTMLpath}/_ExSite/images/darr.gif"});
    my $rimg = $tag->img(undef,{height=>9,width=>9,border=>0,src=>"$config{server}{HTMLpath}/_ExSite/images/rarr.gif"});

    if ($opt{sublist} || $opt{text}) {

	# output list control elements
	$out .= 
	    $opt{prefix}.
	    $tag->span(
		       $tag->a(
			       $opt{open} ? $dimg : $rimg,
			       {class=>"listcontrol",href=>"javascript:$script($list_count)"}
			       ),
		       { id=>"listcontrol_$list_count" }
		       );

	# now the item text
	$out .= $itemtext;

	# now the sublist
	my $subout;
	my $count = $list_count; 
	if ($opt{sublist}) {
	    foreach my $item (@{$opt{sublist}}) {
		$subout .= &DynListItem($item);
	    }
	}
	$out .= $tag->div( 
			   $tag->span($opt{text},{class=>"list_itemtext"}).$subout,
			   { class=>"list", id=>"list_$count", %$sublist_style }
			   );
    }
    else {
	$out .= 
	    $opt{prefix}.
	    $tag->span(
		       $tag->img(undef,{height=>9,width=>9,border=>0,src=>"$config{server}{HTMLpath}/_ExSite/images/null.gif"}),
		       { id=>"listcontrol_$list_count" }
		       );
	$out .= $itemtext;
    }

    return $tag->div($out,{class=>$class});
}

#------------------------------------------------------------------------
# MultiSelect - drop-in replacement for the standard <select> element with 
# multiple attribute activated
#
# id=>      ID of select input
#------------------------------------------------------------------------

sub MultiSelect {
    my %opt = @_;
    $opt{wrapperClass} = "multiselect";
    my $out;
    if (! $script_loaded{MultiSelect}) { 
    $out .= &tag->script(undef,{type=>'text/javascript', src=>"$config{server}{HTMLpath}/_ExSite/js/jquery.multi-select.js"});
    $out .= &tag->link(undef,{rel=>'stylesheet', href=>"$config{server}{HTMLpath}/_ExSite/css/multi-select.css"});
    $script_loaded{MultiSelect} = 1;
    }    
    my $selector = "#".$opt{id};
    $out .= &tag->script("\$('$selector').multiSelect()");
    return $out;
}

#------------------------------------------------------------------------
# Popup
#
# Displays a CSS popup.  Uses absolute positioning, so it overlays
# content beneath it.  May have problems in forms, or mixed with 
# embedded objects such as Flash.
#
# pane=>      the contents of the popup
# label=>     optional anchor for the popup link/button
# width=>     optional width for the popup
# height=>    optional height for the popup
# top=>       offset of top of popup
# right=>     offset of right of popup
# left=>      offset of left of popup
# closelabel => label of close link
#
# Offsets are relative to the anchor label.
#------------------------------------------------------------------------

sub Popup {
    my %opt = @_;
    my $out = &js();
    my $tag = &tag();
    my $tpop = ++$idcount{Popup};
    my $pop_id = "popup$tpop";
    my %popopt = (class=>"popup", id=>$pop_id);
    my $center = $opt{center} || 0;
    if ($opt{width}) { $popopt{style} = "width:$opt{width}px;"; }
    if ($opt{height}) { $popopt{style} .= "height:$opt{height}px;"; }
    if ($opt{top}) { $popopt{style} .= "top:$opt{top}px;"; }
    elsif ($opt{bottom}) { $popopt{style} .= "bottom:$opt{bottom}px;"; }    
    if ($opt{right}) { $popopt{style} .= "right:$opt{right}px;"; }
    elsif ($opt{left}) { $popopt{style} .= "left:$opt{left}px;"; }
    my $closelabel = $opt{closelabel} || "close";
    my $close = $tag->a($msg{$closelabel},
                        {href=>"javascript:hidepopup('$pop_id')",
                         class=>"popup_close"}
                        );

    my $label = $opt{label} || "Info";
    $out .= $tag->span(
                       $tag->a($label,{class=>"popup",href=>"javascript:showpopup('$pop_id',$center)"}).
                       $tag->div($close.$opt{pane}, \%popopt),
                       { class=>"popup_p" }
                       );
    return $out;
}

#------------------------------------------------------------------------
# ResponsivePopup
#
# Displays a centered jquery/CSS popup. Responsive and supports ajax loading of content.
# Background opacity can be set via css.
#
# label=>     optional anchor for the popup link/button
# type=>      type of popup (inline|iframe|ajax)
# width=>     optional width for the popup
# pane=>      the contents of the popup (for inline)
# url=>       url of content (for iframe|ajax)
#
#------------------------------------------------------------------------

sub ResponsivePopup {
    my %opt = @_;
    my $out = &insert_js("jquery","jqueryui");
    my $tag = &tag();
    $opt{label} = $opt{label} || "";
    $opt{class} = $opt{class} || "white-popup";
    my $type = $opt{type} || "inline";
    my $tpop = ++$idcount{ResponsivePopup}{$opt{type}};
    $opt{id} = $opt{id} || "rpopup$tpop";
    if ($tpop == 1) {
    $out .= $tag->script(undef,{type=>'text/javascript', src=>"$config{server}{HTMLpath}/_ExSite/js/jquery.magnific-popup.min.js"});
    $out .= $tag->link(undef,{rel=>'stylesheet', href=>"$config{server}{HTMLpath}/_ExSite/css/magnific-popup.css"});
    my $ajax_options;
    if ($type eq "ajax") {
        $ajax_options = "alignTop: true, callbacks: { 
  ajaxContentAdded: function() {
    this.contentContainer.wrap('<div class=\"white-popup\">');
  }
}";
    }
    $out .= $tag->script("\$(document).ready(function(){
        \$('.MagPopup-$type').magnificPopup({
type: '$type',
delegate: 'a',
$ajax_options
        }); 
        })",{type=>"text/javascript"});
    }
    my %content_attr = (id=>$opt{id},class=>"$opt{class} mfp-hide");
    if ($opt{pane}) {
    $content_attr{style} = "width: $opt{width}px" if ($opt{width});
    $out .= $tag->div($opt{pane},\%content_attr);
    }
    $out .= $tag->div($tag->a($opt{label},{id=>"open-popup-".$opt{id},class=>"open-popup-link",href=>$opt{url} || "#$opt{id}"}),{class=>"MagPopup-$type"});
    return $out;
}

#------------------------------------------------------------------------
# ToolTip
#
# Displays a rollover CSS popup.  Otherwise, works like Popup()
#------------------------------------------------------------------------

sub ToolTip {
    my %opt = @_;
    my $out;
    my $tag = &tag();
    my $tpop = ++$idcount{Popup};
    my $pop_id = "popup$tpop";
    my %popopt = (class=>"popup", id=>$pop_id);
    if ($opt{width}) { $popopt{style} = "width:$opt{width}px;"; }
    if ($opt{height}) { $popopt{style} .= "height:$opt{height}px;"; }
    $opt{top} or $opt{top} = 2;
    $opt{right} or $opt{right} = 5;
    $popopt{style} .= "top:$opt{top}px;";
    $popopt{style} .= "right:$opt{right}px;";
    if (! $script_loaded{Popup}) { 
	### js
	$script_loaded{Popup} = 1;
    }
    my $label = $opt{label} || "Info";
    $out .=
	$tag->span(
		   $tag->span($label,{class=>"tooltip_hotspot",onmouseover=>"javascript:showpopup('$pop_id')",onmouseout=>"javascript:hidepopup('$pop_id')"}).
		   $tag->div($opt{pane}, \%popopt),
		   { class=>"popup_p" }
		   );
    return $out;
}

#------------------------------------------------------------------------
# Overlay
#
# Displays a CSS overlay - like a popup, but it takes over the whole
# screen, and fades out the background page.  (Doesn't work in IE6 due
# poor implementation of transparent PNGs and fixed positioning.)
#
# pane=>      the contents of the popup
# label=>     optional anchor for the popup link/button
# width=>     optional width for the popup
# height=>    optional height for the popup
#------------------------------------------------------------------------

sub Overlay {
    my %opt = @_;
    my $out = &js();
    my $tag = &tag();
    my $tpop = ++$idcount{Popup};
    my $pop_id = "popup$tpop";
    my %olopt = (class=>"overlay", id=>$pop_id);
    my %popopt = (class=>"overlayBox");
    if ($opt{width}) { $popopt{style} = "width:$opt{width}px;"; }
    if ($opt{height}) { $popopt{style} .= "height:$opt{height}px;"; }
    my $close = $tag->a($msg{close},
			{href=>"javascript:hidepopup('$pop_id')",
			 class=>"popup_close"}
			);

    my $label = $opt{label} || $msg{Info};
    $out .= $tag->a($label,{href=>"javascript:showpopup('$pop_id')"});
    $out .= $tag->div(
		      $tag->div($close.$opt{pane},\%popopt),
		      \%olopt
		       );
    return $out;
}

#------------------------------------------------------------------------
# LoginOverlay
#
# If the user is not logged in, display a login form in an overlay, which 
# logs the user into to the current page.
#------------------------------------------------------------------------

sub LoginOverlay {
    my %opt = @_;
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
    return $opt{pane} ? &Overlay(%opt) : $opt{label};
}

#------------------------------------------------------------------------
# HelpPopup
#
# Displays a CSS popup with some help text when you click a help link.
# Uses relative positioning, so it will push other elements aside, 
# which is useful when mixing with unfriendly elements like some form
# controls, Flash objects, etc.
#
# message=>   the help message
# label=>     optional anchor for the help link
# width=>     optional width for the popup
#------------------------------------------------------------------------

sub HelpPopup {
    my %opt = @_;
    my $out = &js();
    my $tag = &tag();
    my $thelp = ++$idcount{HelpPopup};
    my $help_id = "help$thelp";
    my %helpopt = (class=>"help_popup", id=>$help_id);
    if ($opt{width}) { 
	$helpopt{style} = $opt{width} =~ /\%$/ ?
	    "width:$opt{width};" : 
	    "width:$opt{width}px;";
    }
    my $br = &tag->br();
    $opt{message} =~ s/\n\n/$br$br\n/g;
    my $label = $opt{label} || "?";
    my $close = $tag->a("$msg{close}&nbsp;&nbsp;&times;",
			{href=>"javascript:hidepopup('$help_id')",
			 class=>"popup_close"}
			);
    $out .= &tag->span($label,{class=>"help_hotspot", onclick=>"showpopup('$help_id')"});
    $out .= &tag->div($close.$opt{message},\%helpopt);
    return $out;
}

#------------------------------------------------------------------------
# BasicBar 
#
# label=>     bar text
# width=>     optional bar width
#------------------------------------------------------------------------

sub BasicBar {
    my %opt = @_;
    my $ml = &tag;
    my %attr = (class=>"basicbar");
    if ($opt{width}) { $attr{style} = "width:$opt{width}"; }
    return $ml->table($ml->tr($ml->td($opt{label})),\%attr);
}

#------------------------------------------------------------------------
# ToolBar 
#
# tools=>     array of bar texts (containing hyperlinks)
# width=>     optional bar width
#
# example tool text: 
#   <strong>Exit:</strong>&nbsp;&nbsp;
#   <a href=#>Close</a>
#   <a href=#>Logout</a>
#------------------------------------------------------------------------

sub ToolBar {
    my %opt = @_;
    my $ml = &tag;
    my %attr = (class=>"toolbar");
    if ($opt{width}) { $attr{style} = "width:$opt{width}"; }
    my $row;
    foreach my $tool (@{$opt{tools}}) {
	$row .= $ml->td($tool);
    }
    return $ml->table($ml->tr($row),\%attr);
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
    my %opt = @_;
    my $ml = &tag;
    my %attr = (class=>"menubar");
    if ($opt{width}) { $attr{style} = "width:$opt{width}"; }
    my $row;
    foreach my $link (@{$opt{links}}) {
	my $img = ref $link && $link->{img} ? $ml->img(undef,{src=>$link->{img},alt=>""}) : "";
	$row .= ref $link ? 
	    $ml->td($ml->a($img.$link->{label},{href=>$link->{url}})) : 
	    $ml->td($link);
    }
    return $ml->table($ml->tr($row),\%attr);
}

#------------------------------------------------------------------------
# PathBar 
#
# links=>     array of links (a tags, or {url=>, label=>, class=>})
# width=>     optional bar width
#------------------------------------------------------------------------

sub PathBar {
    my %opt = @_;
    my $ml = &tag;
    my %attr = (class=>"pathbar");
    if ($opt{width}) { $attr{style} = "width:$opt{width}"; }
    my $row;
    my $lastlink = pop @{$opt{links}};
    foreach my $link (@{$opt{links}}) {
	my $class;
	if (ref $link eq "HASH") {
	    $class = $link->{class} ? "pathLink $link->{class}" : "pathLink";
	}
	$row .= ref $link ? 
	    $ml->td($ml->a($link->{label},{href=>$link->{url},class=>$class})) : 
	    $ml->td($link);
	$row .= $ml->td(undef,{class=>"pathSeparator"});
    }
    my $class;
    if (ref $lastlink eq "HASH") {
	$class = $lastlink->{class} ? "pathLink $lastlink->{class}" : "pathLink";
    }
    $row .= ref $lastlink ? 
	$ml->td($ml->a($lastlink->{label},{href=>$lastlink->{url},class=>$class}),{class=>"pathLast"}) : 
	$ml->td($lastlink,{class=>"pathLast"});
    $row .= $ml->td(undef,{class=>"barPadding"});
    return $ml->table($ml->tr($row),\%attr);
}

#------------------------------------------------------------------------
# IconBar 
#
# links=>     array of links (complete tags, or {url=>, label=>, img=>})
#             use undef array element to insert a separator
# iconsize=>  defaults to 16 (px)
# width=>     optional bar width
# padding=>   0|1 include padding (defaults to yes)
#------------------------------------------------------------------------

sub IconBar {
    my %opt = @_;
    my $ml = &tag;
    my $iconsize = $opt{iconsize} || 16;
    my %attr = (class=>"iconbar");
    if ($opt{width}) { $attr{style} = "width:$opt{width}"; }
    my $row;
    foreach my $link (@{$opt{links}}) {
	if (! defined $link) {
	    $row .= $ml->td(undef,{class=>"barSeparator"});
	}
	elsif (ref $link eq "HASH") {
	    my $name = $link->{label};
	    $name =~ s/([^a-zA-Z0-9])/"_".unpack("H2",$1)/ge; # like &safetext()
	    $row .= $ml->td($ml->a($ml->img(undef,{src=>$link->{img},height=>$iconsize,width=>$iconsize}).$ml->br.$msg{$link->{label}},{href=>$link->{url}}),{id=>"toolicon_$name"});
	}
	else {
	    $row .= $ml->td($link);
	}
    }
    $row .= $ml->td(undef,{class=>"barPadding"}) if ($opt{padding} || ! defined $opt{padding});
    return $ml->table($ml->tr($row),\%attr);
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
    my %opt = @_;
    my %imgopt = ( src=>$opt{img}, border=>0 );
    my %aopt = ( href=>$opt{url} );
    if ($opt{target}) { $aopt{target} = $opt{target}; }
    my $w = $opt{img_x} || $opt{img_size};
    my $h = $opt{img_y} || $opt{img_size};
    if ($h && $w) {
	$imgopt{width} = $w;
	$imgopt{height} = $h;
    }
    my $ml = &tag;
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
    my %opt = @_;
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
    my $ml = &tag();
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
    my %opt = @_;
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
    my $ml = &tag;
    return $ml->div(
	$ml->div(undef,{class=>"arrow_$dir",onclick=>$onclick}),
	{class=>"arrowbox"}
	);
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
#------------------------------------------------------------------------

sub Button {
    my %opt = @_;
    my $class = $opt{small} ? "button_sm" : "button";
    if ($opt{class}) { $class .= " $opt{class}"; }
    if ($opt{type} eq "button") {
	my %aopt = ( class=>$class, type=>"button" );
	$aopt{onClick} = $opt{url} =~ /^(https?:)?\// ?
	    "window.location.href='$opt{url}'" : $opt{url};
	return &tag->button($opt{label},\%aopt);
    }
    else {
	my $url = $opt{confirm} ?
	    "javascript:confirm_custom('$opt{confirm}','$opt{url}')" : $opt{url};
	my %aopt = ( href=>$url, class=>$class );
	if ($opt{target}) { $aopt{target} = $opt{target}; }
	return &insert_js("misc").&tag->a($opt{label},\%aopt);
    }
}

sub BackButton {
    my %opt = @_;
    $opt{label} or $opt{label} = "&lt; ".$msg{Back};
    $opt{url} or $opt{url} = "javascript:history.back()";
    return &Button(%opt);
}

#------------------------------------------------------------------------
# Alert - creates a link that generates a Javascript alert box 
# containing arbitrary text.
#
# label=>    button text
# button=>   1, if link should be presented as a button
# message=>  text of alert message
#------------------------------------------------------------------------

sub Alert {
    my %opt = @_;
    # escape quotes
    $opt{message} =~ s/\"/\\\"/g;
    $opt{message} =~ s/\'/\\\'/g;
    # insert linebreaks, if not already done
    if ($opt{message} !~ /\\n/ && $opt{message} =~ /\n/) {
	$opt{message} =~ s/\r?\n/\\n/g;
    }
    if ($opt{button}) {
	return &Button(label=>$opt{label},
		       url=>"javascript:alert('$opt{message}')");
    }
    else {
	return &tag->a($opt{label},{ href=> "javascript:alert('$opt{message}')" });
    }
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
    my %opt = @_;
    my $out = &js();
    # escape quotes
    $opt{message} =~ s/\"/\\\"/g;
    $opt{message} =~ s/\'/\\\'/g;
    # insert linebreaks, if not already done
    if ($opt{message} !~ /\\n/ && $opt{message} =~ /\n/) {
	$opt{message} =~ s/\r?\n/\\n/g;
    }
    if ($opt{button}==2) {
	$out .= &insert_js("misc").&Button(label=>$opt{label},
			url=>"javascript:confirm_custom('$opt{message}','$opt{url}')",
			small=>1);
    }
    elsif ($opt{button}) {
	$out .= &insert_js("misc").&Button(label=>$opt{label},
			url=>"javascript:confirm_custom('$opt{message}','$opt{url}')");
    }
    else {
	$out .= &insert_js("misc").&tag->a($opt{label},{ href=> "javascript:confirm_custom('$opt{message}','$opt{url}')" });
    }
    return $out;
}

#------------------------------------------------------------------------
# MailTo - builds mailto: links that are spambot-resistant
#
# label => anchor text
# email => target email address
#------------------------------------------------------------------------

sub MailTo {
    my ($email,$label) = @_;
    return $label if (! $email);
    my ($user, $domain) = split(/\@/,$email,2);
    my $dummy = "$user AT $domain";
    my $anchor;
    if ($label) { $anchor = $label; }
    my $out = &js();
    $out .= &insert_js("HTML").&tag->script("
mailto('$user','$domain','$anchor');
",
			   { language=>"JavaScript" }
			   );
    $out .= &tag->noscript($dummy);
}

#------------------------------------------------------------------------
# CSS
#
# This can be used to auto-insert the necessary CSS if your stylesheet
# does not have it.
#------------------------------------------------------------------------

sub CSS {
    return &tag->link(undef,
		      {rel=>"stylesheet", type=>"text/css",
		       href=>"$config{server}{HTMLpath}/_ExSite/css/HTML.css"});
}

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
    my %opt = @_;

    my ($wrapperClass, $wrapperStyle, $headClass, $headStyle,$paneClass,
	$paneStyle, $paneID, $head, $pane);

    my %headopt = ( class => $opt{headClass} || "boxhead" );
    my %paneopt = ( class => $opt{paneClass} || "boxpane" );
    my %wrapopt = ( class => $opt{wrapperClass} || "box" );

    if ($opt{wrapperStyle}) { $wrapopt{style} = $opt{wrapperStyle}; }
    if ($opt{headStyle})    { $headopt{style} = $opt{headStyle}; }
    if ($opt{paneStyle})    { $paneopt{style} = $opt{paneStyle}; }
    if ($opt{paneID})       { $paneopt{id}    = $opt{paneID}; }
    $head = $opt{head} ? &tag->div($opt{head},\%headopt) : "";
    $pane = &tag->div($opt{pane},\%paneopt);
    return &tag->Comment("begin box").
	&tag->div($head.$pane,\%wrapopt).
	&tag->Comment("end box");
}

#------------------------------------------------------------------------
# Internal javascript output function
#------------------------------------------------------------------------

sub js {
    my $extrajs = shift;
    my $out;
    if (! $share{js}{html}) {
	$out .= &tag->script(undef,{type=>'text/javascript', src=>"$config{server}{HTMLpath}/_ExSite/js/HTML.js"});
	if (! $share{js}{jquery}) {
	    $out .= &tag->script(undef,{type=>'text/javascript',src=>$config{jquery}});
	    $share{js}{jquery} = 1;
	}
	if (! $share{js}{jqueryui}) {
	    $out .= &tag->script(undef,{type=>'text/javascript',src=>$config{jqueryui}});
	    $share{js}{jqueryui} = 1;
	}
	$out .= &tag->script("BASE='$config{server}{HTMLpath}';",
			     {type=>'text/javascript'});
	$share{js}{html} = 1;
    }
    if ($extrajs) {
	$out .= &tag->script($extrajs,{type=>'text/javascript'});
    }
    return $out;
}

1;
