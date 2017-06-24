#!/usr/bin/perl
#----------------------------------------------------------------------------
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

package ExSite::Wizard;

use strict;
use ExSite::Config;
use ExSite::Form;
use ExSite::Base;
use ExSite::Misc;
use ExSite::HTML;

our @ISA = qw(ExSite::Base);


#========================================================================

=pod

=head1 ExSite::Wizard -- create, manage, and process multi-screen forms

Wizards take the user through a multi-screen sequence of forms, collecting 
data at each step.  Collected data is stored in hidden fields in each 
screen.  The submission of the aggregate form data does not occur until
the final screen is submitted.  This allows wizard forms to have branching 
logic, or inputs that vary in character, depending on the inputs provided 
on previous screens.

To create a wizard:

    my $wiz = new ExSite::Wizard(title=>"My Wizard",action=>"mywiz.cgi");

    $wiz->add_step("First",\&create_step_1,\&do_step_1);

    $wiz->add_step("Second",\&create_step_2,\&do_step_2);

C<mywiz.cgi> is your wizard CGI program that processes the input of
each screen; 

C<&create_step_X> is the routine that composes and returns a form for step X.
It should return the HTML for the form in a string.  The Wizard automatically
outputs the form tags, submit buttons, and data from previous steps (as 
hidden fields), so you only need to output the new input fields for this
screen.

C<&do_step_X> is the routine that processes the form from each step.  It 
should return an array of error messages (such as input validation failures,
or other problems).  If this array has no entries, the form input is 
accepted, and the wizard automatically proceeds to the next step.

The last C<&do_step_X> routine in the wizard is responsible for doing
final processing of the collected data, ie. handling the final submit
of the aggregate wizard inputs.  It also returns an array of error strings 
if the final collection of data cannot be processed;  if the error array
is empty, the wizard is assumed to have completed.

If the final stage of the wizard has a C<&create_step_N> routine, but
no C<&do_step_N> routine, then ExSite will run the C<&create_step_N>
routine, but not display any wizard buttons to "do" this step.  In this
case you should do your final form processing in C<&do_step_[N-1]>.  
This configuration is useful if you require a specialized final screen 
for final instructions.

=cut

#========================================================================

# create the wizard object

sub new ($%) {
    my ($this,%opt) = @_;
    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;
    $obj->{title} = $opt{title};
    $obj->{reply} = $opt{reply};
    $obj->{action} = $opt{action};
    $obj->{id} = $opt{id};
    $obj->{step_name} = [];
    $obj->{show_step} = [];
    $obj->{do_step} = [];
    $obj->{db} = $share{DB};
    $obj->{index} = $opt{index};
    $obj->info("creating new Wizard: $opt{title}");
    return $obj;
}

# configure the wizard steps/screens

sub add_step {
    my ($this,$name,$show,$do) = @_;
    if (ref $show ne "CODE") { return 0; }
    push @{$this->{step_name}}, $name;
    push @{$this->{show_step}}, $show;
    if (ref $do eq "CODE") { push @{$this->{do_step}}, $do; }
    return 1;
}

# execute the wizard

sub go {
    my ($this,$init) = @_;
    $this->{db}->get_data;
    my $input = $this->{input} = $this->{db}->{data};
    my $out; # = &ShowHash($input);
    my $ml = &get_obj("ML");

    $this->{current} = $input->{screen};
    
    # javascript resubmit kludge: if the wizard tries to reconfigure screen 1
    # and reload the form, the inputs are lost because the form re-initializes.
    # If we detect this condition, flag it, so that we can pass the form
    # data instead of the initialization data to the start screen.
    my $resubmit = ($this->{current} == -1);

    if ($this->{db}->{submit_action} eq "Cancel") { 
	return $this->abort; 
    }
    elsif ($this->{current} =~ /^\d+$/) {
	my @do_step = @{$this->{do_step}};
	# validate input
	my @error = ();
	if (defined $this->{do_step}[$this->{current}]) {
	    @error = &{$this->{do_step}[$this->{current}]}($this,$input);
	    if (@error > 0) {
		my $message = &ExSite::HTML::ErrorBox(title=>"Problem:",
						      pane=>join($ml->br,@error));
		$message .= &ExSite::HTML::BackButton();
		return $message;
	    }
	}
	if (@error == 0) {
	    # goto next screen
	    #if ($this->{current} == scalar @{$this->{show_step}} - 1) {
	    if ($this->{current} >= scalar @{$this->{show_step}} - 1) {
		# no more screens!
		my $reply = $this->{reply} || $input->{reply};
		if ($reply && exists $share{Page}) {
		    # we can safely do a redirect
		    $share{Page}->location($this->{reply});
		}
		else {
		    # safe redirect uncertain, use a manual link
		    $out = $ml->h2("$this->{title} Complete!");
		    if ($this->{reply}) {
			$out .= $ml->p($ml->a("Continue",{href=>$this->{reply}})." &gt;");
		    }
		}
		return $out;
	    }
	    else {
		$this->{current} ++;
		$out .= &{$this->{show_step}[$this->{current}]}($this,$input);
		if (! $this->{do_step}[$this->{current}]) { 
		    $this->{terminate} = 1;
		}	
		$out = $this->make_wizard_form($out);
	    }
	}
    }
    else {
	# start the wizard sequence
	$this->{current} = 0;
	if ($resubmit) {
	    # rebuild screen 1 based on screen 1 inputs
	    $out .= &{$this->{show_step}[$this->{current}]}($this,$input)
	}
	else {
	    $out .= &{$this->{show_step}[$this->{current}]}($this,$init);
	}
	$out = $this->make_wizard_form($out);
    }
    return $out;
}

# build standard HTML for wizard form

sub make_wizard_form {
    my ($this,$contents) = @_;
    my $ml = &get_obj("ML");
    my $step = $this->{current} + 1;
    my $out;
    if ($this->{title}) { $out .= $ml->h1($this->{title}); }
    my %opt = ( id=>"wizard", method=>"post" );
    $out .= $this->path;
    $out .= $ml->h3("Step $step: $this->{step_name}[$this->{current}]");
    if (! $this->{terminate}) {
	if ($this->{action}) { $opt{action} = $this->{action}; }
	if ($this->{db}{htmleditor}) {
	    $opt{onSubmit} = "validate()";
	    $out = $this->{db}->editor_javascript() . $out;
	}
	if ($this->{db}{enctype}) {
	    $opt{enctype} = $this->{db}{enctype};
	}
	$out .= $ml->div( $this->include_input . $contents, { class=>"form" });
	$out .= $ml->input(undef,{type=>"hidden",name=>"screen",value=>$this->{current}});
	if ($this->{current} > 0) {
	    $out .= $ml->input(undef,{type=>"button",value=>"&lt; Back",onclick=>"history.back()"})."&nbsp;&nbsp;";
	}
	my $next = ($this->{current} == scalar @{$this->{show_step}} - 1 ? 
		    "FINISH" : "NEXT &gt;");
	$out .= 
	    $ml->input(undef,{type=>"submit",name=>"submit_action",value=>$next})."&nbsp;&nbsp;".
	    $ml->input(undef,{type=>"submit",name=>"submit_action",value=>"Cancel",class=>"cancel"})."&nbsp;&nbsp;".
	    $ml->input(undef,{type=>"reset"});
	return $ml->form($out,\%opt);
    }
    else {
	$out .= $contents;
    }
    return $out;
}

# abort wizard 
# (does nothing, really, except print a message instead of wizard form)

sub abort {
    my $this = shift;
    $this->terminate;
    my $url = &relink();
    my $ml = &get_obj("ML");
    return 
	$ml->h3("$this->{title} Aborted").
	$ml->p($ml->a("Back to start of wizard",{href=>$url}).".");
}

# terminate wizard 
# blocks the wizard buttons, effectively terminating progression of the
# wizard.  The wizard control routines determine what the screen text
# will say.

sub terminate {
    my $this = shift;
    $this->{terminate} = 1;
    return;
}

# show a little index of where we are in the wizard sequence

sub index { return &path(@_); }
sub path {
    my $this = shift;
    my $ml = &get_obj("ML");
    my @path;
    for (my $istep = 0; $istep < @{$this->{step_name}}; $istep++) {
	my $num = ($istep + 1) . ". ";
	my $item = $this->{step_name}[$istep];
	push @path, ($istep == $this->{current}) ? 
	    $ml->span($num.$item,{class=>"currentStep"}) : $num.$item;
    }
    return $ml->div(join(" ".$ml->big("&#8680;")." ",@path),{class=>"wizardPath"});
}

# include_input : grab input from previous step, and insert it as hidden

sub include_input {
    my $this = shift;
    my $input = $this->{input};
    my $ml = &get_obj("ML");
    delete $input->{screen};
    delete $input->{submit_action};
    my $out;
    while (my ($key, $val) = each %$input) {
	$val = &html_escape($val,'&"');
	$out .= $ml->input(undef,{type=>"hidden",name=>$key,value=>$val});
    }
    return $out;
}

# should probably call this before final form processing...
# will act on a passed input hash, or the share input hash

sub unescape_input {
    my $this = shift;
    my $input = shift;
    if (! $input) { $input = $share{input}{post}; }
    foreach my $key (keys %$input) {
       $input->{$key} = &html_unescape($input->{$key},'&"',1);
    }
    return;
}

1;

