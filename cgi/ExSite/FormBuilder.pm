#------------------------------------------------------------------------
# ExSite::FormBuilder
#----------------------------------------------------------------------------
#
#   Copyright 2001-2007 Exware Solutions, Inc.  http://www.exware.com
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

#--------------------------------------------------------------------
#  POD documentation at end of file
#--------------------------------------------------------------------

### TODO:
### customize buttons
### - select which buttons to include
### - customize labels
### - define IDs/names
### - image buttons

package ExSite::FormBuilder;
use strict;
use ExSite::Base;
use ExSite::Misc;
use ExSite::Config;
use ExSite::UI;

use vars qw(@ISA);

@ISA = qw(ExSite::Base);

sub new {
    my ($this,%opt) = @_;
    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;
    $obj->initialize_object;
    $obj->init(%opt);
    return $obj;
}

# reset the object for a new form
# (does not clear templates)
sub init {
    my ($this,%opt) = @_;
    $this->{method} = "POST";
    $this->{formname} = undef;
    $this->{formid} = undef;
    $this->{action} = undef;
    $this->{buttons} = undef;
    $this->{enctype} = undef;
    $this->{onsubmit} = undef;
    $this->{name} = [];
    $this->{validate} = undef;
    $this->{validate_js} = [];
    $this->{validate_script} = [];
    $this->{validate_order} = [];
    $this->{input} = {};
    $this->{subinput} = {};
    $this->{data} = {};
    $this->{prompt} = {};
    $this->{required_id} = {};
    $this->{required_type} = {};
    $this->{required_name} = {};
    $this->{required_prompt} = {};
    $this->{required_done} = {};
    $this->{type} = {};
    if (! exists $this->{id}) { $this->{id} = {}; }
    while (my ($key,$val) = each %opt) {
	$this->{$key} = $val;
    }
    return;
}

# form method (get or post)
sub method {
    my $this = shift;
    $this->{method} = shift;
}

# action
sub action {
    my $this = shift;
    $this->{action} = shift;
}

# encoding type
sub enctype {
    my $this = shift;
    $this->{enctype} = shift;
    if ($this->{enctype} =~ /multipart/) {
	$this->method("POST");
    }
}

# define existing field values
sub values {
    my $this = shift;
    my %data = (@_ > 1) ? @_ : %{$_[0]};
    if (! exists $this->{data}) { $this->{data} = {}; }
    # add to currently-defined values
    foreach my $key (keys %data) {
	$this->{data}{$key} = $data{$key};
    }
}

# validation script
sub validate {
    my ($this,$jscall,$jsscript) = @_;
    push @{$this->{validate_js}}, $jscall;
    push @{$this->{validate_script}}, $jsscript;
    return;
}

## synonyms/shortcuts
sub multipart {
    my $this = shift;
    $this->enctype("multipart/form-data");
}

sub url_encoded {
    my $this = shift;
    #$this->enctype("application/x-www-form-urlencoded");
    $this->enctype("");
}

# form name
sub name {
    my $this = shift;
    $this->{formname} = shift;
}

# make a unique input ID
sub make_id {
    my ($this,$name) = @_;
    my $id = &safetext($name);
    if (exists $this->{id}{$id}) {
	my $idn = 0;
	while (exists $this->{id}{"${id}_${idn}"}) { $idn++; }
	$id .= "_$idn";
    }
    return $id;
}

# install a template
sub template {
    my $this = shift;
    if (@_ == 1) {
	$this->{template} = shift; 
	$this->{template_style} = 1;
    }
    elsif (@_ == 3) {
	$this->{template_top} = shift;
	$this->{template_row} = shift;
	$this->{template_bot} = shift;
	$this->{template_style} = 2;
    }
    elsif (@_ == 0) {
	if ($this->{template_style} != 2 && ! $this->{template_row}) {
	    # install a generic template
	    my $ml = &get_obj("ML");
	    $this->{template_top} = "";
	    $this->{template_row} = $config{form}{css_span} ?
		$ml->p(
# labels are now inserted in input(), because they depend on the type of input
#		    $ml->label(
		       $ml->span("[[prompt]]",{class=>"prompt"}).
		       $ml->br.
		       $ml->span("[[input]]",{class=>"input"}),
#		    ),
		    {class=>"[[rowclass]]"}
		) : 
		$ml->p(
#		       $ml->label("[[prompt]]".$ml->br."[[input]]"),
		       "[[prompt]]".$ml->br."[[input]]",
		       {class=>"[[rowclass]]"}
		       );
	    $this->{template_bot} = "";
	}
	if (exists $this->{template}) {
	    # looks like we were initialized with some kind of template
	    $this->{template_style} = 1;
	}
	if (! $this->{template_style}) { 
	    # set the generic template as our template
	    $this->{template_style} = 2;
	}
    }
    return;
}

# modify the template
sub append_to_template {
    my $this = shift;
    # only works for all-in-one templates
    if (@_ == 1) {
	$this->{template} .= shift; 
	$this->{template_style} = 1;
    }
    return;
}

sub has_allinone_template {
    my $this = shift;
    return ($this->{template_style} == 1);
}

sub has_rowbyrow_template {
    my $this = shift;
    return ($this->{template_style} == 2);
}

# test for input(s)

sub has_inputs {
    my $this = shift;
    return scalar @{$this->{name}} > 0;
}

sub has_input {
    my ($this,$name) = @_;
    return defined $this->{type}{$name};
}

# subinputs (eg. individual radio or checklist buttons)
# can call multiple times to append particular subinputs together

sub set_subinput {
    my ($this,$name,$n,$input) = @_;
    $this->{subinput}{$name}[$n] .= $input;
}

# add an input field to the form
#
# name = name of input field [required]
# prompt = human-friendly prompt
# input = literal input tag
# type = text*, hidden, password, file, checkbox, radio, textarea, select, formatted, preformatted
# value = the preset value of the field
# checked = true/false (for checkbox types only)
# id = ID of input field
# class = class of input field
# accept = accept attribute (for file inputs)
# maxlength = maximum string length in a text input
# readonly = true/false
# disabled = true/false
# size = width of text inputs
# rows,cols = passed to textarea
# required = 1, 0, -1 (treated as true/false)
# top = add to top of form, instead of bottom
# head = extra HTML to add to front of input
# tail = extra HTML to add to end of input
# tooltip = Bootstrap tooltip (for text inputs)
# label = append a label to the input field (useful for radios and checkboxes)
# templated = return a templated input prompt+field if true
# append = append to an existing field, instead of creating a new one
# notranslate = do not run prompts,etc through system messages for translation
# on* = JS event handlers (passed verbatim into the html attributes)
#
# The difference between a preformatted question and a formatted question is
# a formatted question consists of a prompt and input which are 
# inserted into the template; whereas a preformatted question is presumed to
# be templated already, and is simply concatenated to the form.

sub input {
    my ($this,%opt) = @_;
    return undef if (! $opt{name});
    if (! $opt{type}) { $opt{type} = "text"; }
    if (!defined $opt{value}) { $opt{value} = $this->{data}{$opt{name}}; }
#    if ($opt{required} > 0) {
	if (! $opt{id}) {
	    $opt{id} = $this->make_id($opt{name});
	}
#    }
    my $input = $opt{input};
    if ($opt{required}) {
	$opt{missing} = (keys %{$this->{data}} > 0 && ! $opt{value});
    }
    my $canlabel; # false by default, for custom inputs
    if (! $input) {
	if ($opt{type} =~ /textarea/) { 
	    $input = $this->textarea(%opt); 
	    $canlabel = 1;
	}
	elsif ($opt{type} =~ /select/) { 
	    $input = $this->select(%opt); 
	    $canlabel = 1;
	}
	elsif ($opt{type} =~ /radio/ && $opt{options}) { 
	    $input = $this->select_radio(%opt); 
	    $canlabel = 0; # multiple inputs, cannot label
	}
	elsif ($opt{type} =~ /formatted/) { 
	    $input = $opt{input}; 
	    $canlabel = 0; # unknown contents, cannot label
	}
	else { 
	    $input = $this->inputtag(%opt); 
	    $canlabel = 1;
	}
    }
    if ($opt{head}) { $input = $opt{head}.$input; }
    if ($opt{tail}) { $input .= $opt{tail}; }

    my $prompt = $opt{type} =~ /formatted/ ?
	$opt{prompt} :
	$opt{prompt} || $opt{label} || $opt{name};

    # required input?
    my $ml = &get_obj("ML");
    if ($opt{required}) {
	if ($opt{required} > 0 && ! $this->{required_done}{$opt{name}}) {
	    # we do JS validation
	    $this->{required_id}{$opt{id}} = $opt{id};
	    $this->{required_type}{$opt{id}} = $opt{type};
	    push @{$this->{validate_order}}, $opt{id};
	    $this->{required_name}{$opt{id}} = $opt{name};
	}
	# if required, but no JS validation, we simply style the
	# field as required, but let the server validate
	#$this->{required_prompt}{$opt{id}} = 
	$this->{required_prompt}{$opt{name}} = 
	    $this->{required_prefix}.$prompt.$this->{required_suffix};

	# markup the field
	my $reqclass = "requiredPrompt";
	if ($opt{missing}) { $reqclass .= " missingPrompt"; }
	
	if ($config{form}{css_span}) {
	    $prompt = $canlabel ?
		$ml->span(
		    $ml->label($prompt,{for=>$opt{id}}),
		    {class=>$reqclass}
		) 
		:
		$ml->span(
		    $prompt,
		    {class=>$reqclass}
		);
	}
	elsif ($canlabel) {
	    $prompt = $ml->label(
		$prompt,
		{for=>$opt{id},class=>$reqclass}
		);
	}
	# flag the required processing as done for this input
	$this->{required_done}{$opt{name}} = 1;
    }
    elsif ($canlabel) {
	$prompt = $ml->label($prompt,{for=>$opt{id}});
    }

    # switch encodings if necesary
    if ($opt{type} =~ /file/) {
	# make sure we can handle file uploads
	$this->multipart();
    }

    # remember attributes
    if ($opt{id}) { 
	$this->{id}{$opt{id}} = $opt{name};
    }
    $this->{prompt}{$opt{name}} = $prompt;
    $this->{type}{$opt{name}} = $opt{type};
	
    if ($opt{append}) {
	# append to existing input
	$this->{input}{$opt{append}} .= $input;
	$input = $this->{input}{$opt{append}};
    }
    else {
	# add it to the stack of known inputs
	if (! $this->{input}{$opt{name}}) {
	    if ($opt{top}) {
		# add to top of form
		unshift @{$this->{name}},$opt{name};
	    }
	    else {
		# add to end of form
		push @{$this->{name}},$opt{name};
	    }
	}

	# append to existing inputs
	$this->{input}{$opt{name}} = $this->{input}{$opt{name}} ? 
	    $this->{input}{$opt{name}}.$input :
	    $input;
    }
    return $opt{templated} ? $this->template_input($prompt,$input,$opt{type}) : $input;
}

sub inputtag {
    my ($this,%opt) = @_;
    my %attr;

#    # select, textarea, radios can't use this
#    if ($opt{type} eq "radio") { return $this->select_radio(%opt); }
#    elsif ($opt{type} eq "select") { return $this->select(%opt); }
#    elsif ($opt{type} eq "long text") { return $this->textarea(%opt); }

    if (! $opt{type}) { $attr{type} = "text"; }

    foreach my $key (qw(type name id class)) {
	if ($opt{$key}) { $attr{$key} = $opt{$key}; }
    }
    if (defined $opt{value}) { 
	$attr{value} = &html_escape($opt{value}); 
    }
    if ($opt{readonly} && $opt{type} =~ /text|password/i) { 
	$attr{readonly} = undef;
    }
    if ($opt{disabled}) { 
	$attr{disabled} = undef; 
    }
    if ($opt{checked} && $opt{type} =~ /checkbox|radio/i) { 
	$attr{checked} = undef;
    }
#    if ($opt{value} && $opt{type} =~ /checkbox/i) { 
#	$attr{checked} = undef;
#    }
    if ($opt{maxlength} && $opt{type} =~ /text/i) { 
	$attr{maxlength} = $opt{maxlength}; 
    }
    if ($opt{accept} && $opt{type} =~ /file/i) { 
	$attr{accept} = $opt{accept}; 
    }
    if ($opt{size} && $opt{type} =~ /text|password|file|string/i) { 
	$attr{size} = ($opt{size} > $config{form}{max_cols}) ? 
	    $config{form}{max_cols} : $opt{size};
    }
    # HTML5 features
    if ($opt{placeholder}) { 
	$attr{placeholder} = $opt{placeholder};
    }
    if ($opt{autofocus} && $opt{type} =~ /text/i) { 
	$attr{autofocus} = undef;
    }
    if ($opt{type} =~ /number|range/) {
	$attr{min} = $opt{min} if (exists $opt{min});
	$attr{max} = $opt{max} if (exists $opt{max});
	$attr{step} = $opt{step} if (exists $opt{step});
    }
    if ($opt{title}) { 
	$attr{title} = $opt{title};
    }
    # Bootstrap features
    if ($opt{tooltip}) {
	$attr{'data-toggle'} = "tooltip";
	$attr{'data-placement'} = "right";
	$attr{'title'} = $opt{tooltip};
	$share{page_footer} .= &insert_js("tooltip");
    }

    # JS event handlers
    foreach my $evt (keys %opt) {
	if ($evt =~ /^on\w+/i) {
	    $attr{$evt} = $opt{$evt};
	}
    }

    # required css
    if ($opt{required}) {
	my $class = "requiredInput";
	$attr{class} = $attr{class} ? $attr{class}." $class" : $class;
    }
    if ($opt{missing}) {
	my $class = "missingInput";
	$attr{class} = $attr{class} ? $attr{class}." $class" : $class;
    }

    my $ml = &get_obj("ML");
    my $input = $ml->input(undef,\%attr);

    if ($opt{subinput}) {
	# save this as a subinput
	$this->set_subinput($opt{name},$opt{subinput},$input);
    }
    if ($opt{type} =~ /radio/ || $opt{label}) {
	my $label = $opt{label} || $opt{value};
	# checkbox labels may need different CSS treatment
	my $class = $opt{type} . "Label";
	my $iclass = $opt{type} . "Input";
	# translations
	$label = $opt{notranslate} ? $label : $msg{$label};
	#$input .= $ml->span("&nbsp;$label&nbsp;&nbsp;",{class=>$class});
	$input = $ml->span($input.$ml->span("&nbsp;$label&nbsp;&nbsp;",{class=>$class}),{class=>$iclass});
    }
    return $input;
}

# textarea input
#
# options are same as input(), plus:
# rows = height of textarea
# cols = width of textarea
# size = a "length" value, from which reasonable rows and cols are derived

sub textarea {
    my ($this,%opt) = @_;
    my $input;
    return undef if (! $opt{name});
    if ($opt{input}) {
	$input = $opt{input};
    }
    else {
	my %attr = ( wrap=>"virtual", name=>$opt{name} );
	my $value = $opt{value};
	$value =~ s/&\#34;/\"/g;
	if ($opt{required}) {
	    if (! $opt{id}) {
		$opt{id} = $this->make_id($opt{name});
	    }
	}
	if ($opt{id}) { 
	    $attr{id} = $opt{id};
	}
	if ($opt{class}) { $attr{class} = $opt{class}; }
	if ($opt{readonly}) { $attr{readonly} = undef; }
	if ($opt{disabled}) { $attr{disabled} = undef; }
	# dimensions
	my $ncol = $opt{cols} || 
	    ($opt{size} > $config{form}{max_cols} ? 
	     $config{form}{max_cols} : $opt{size}) || 
	     $config{form}{max_cols};
	$attr{cols} = $ncol;
	my $nrows;
	if ($opt{rows}) {
	    $nrows = $opt{rows};
	}
	else {
	    $nrows = int($opt{size}/$ncol) || $config{form}{max_rows};
	    if ($nrows < 2) { 
		$nrows = 2; 
	    }
	    elsif ($nrows > $config{form}{max_rows}) { 
		$nrows = $config{form}{max_rows}; 
	    }
	}
	$attr{rows} = $nrows;

	# JS event handlers
	foreach my $evt (keys %opt) {
	    if ($evt =~ /^on\w+/i) {
		$attr{$evt} = $opt{$evt};
	    }
	}
	# Bootstrap features
	if ($opt{tooltip}) {
	    $attr{'data-toggle'} = "tooltip";
	    $attr{'data-placement'} = "right";
	    $attr{'title'} = $opt{tooltip};
	    $share{page_footer} .= &insert_js("tooltip");
	}

	# required css
	if ($opt{required}) {
	    my $class = "requiredInput";
	    $attr{class} = $attr{class} ? $attr{class}." $class" : $class;
	}
	if ($opt{missing}) {
	    my $class = "missingInput";
	    $attr{class} = $attr{class} ? $attr{class}." $class" : $class;
	}

	my $ml = &get_obj("ML");
	$input = $ml->textarea($value,\%attr);
    }
    return $input;
}

# add a select input field to the form
#
# options are same as input(), plus:
# size = maximum height of multiple select inputs
# width = maximum width of text inputs
# nullvalue = option for no value
# multiple = use multiselect form element
# options = list of options
#    regex => scalar, with options separated by |
#    scalar => literal options string
#    array of scalars => list of values/text labels
#    array of arrayrefs => list of [value,text label]
#    array of hashrefs => list of {value=>value, text=>text label}
#    hash => { value => text label }

sub select {
    my ($this,%opt) = @_;
    my $input;
    return undef if (! $opt{name});
    if ($opt{input}) {
	$input = $opt{input};
    }
    else {
	my %selectattr = (name=>$opt{name});
	if ($opt{required}) {
	    if (! $opt{id}) {
		$opt{id} = $this->make_id($opt{name});
	    }
	}
	if ($opt{id}) { 
	    $selectattr{id} = $opt{id}; 
	}
	if ($opt{class})    { $selectattr{class} = $opt{class}; }
	if ($opt{disabled}) { $selectattr{disabled} = undef; }
	#if ($opt{onchange}) { $selectattr{onchange} = $opt{onchange}; }
	if ($opt{multiple}) { 
	    $selectattr{multiple} = undef; 
	    if ($opt{size}) { $selectattr{size} = $opt{size}; }
	}

	my $ml = &get_obj("ML");

	# options

	my $options;
	if ($opt{nullvalue}) {
	    $options .= $ml->option($msg{$opt{nullvalue}},{value=>''});
	}
	if (ref $opt{options} eq "ARRAY") {
	    # an array of options, in various formats
	    foreach my $item (@{$opt{options}}) {
		my $typ = ref $item;
		my ($val,$text);
		if ($typ eq "ARRAY") { 
		    # reference to an array of value,text
		    $val = $item->[0];
		    $text = $item->[1];
		}
		elsif ($typ eq "HASH") { 
		    # hash with value, text 
		    $val = $item->{value}; 
		    $text = $item->{text}; 
		}
		else { 
		    # just text, no value
		    $val = $text = $item; 
		}
		$val = &html_escape($val,'"');
		if ($opt{width} && length $text > $opt{width}) {
		    $text = substr($text,0,$opt{width})."...";
		}
		my %optattr = ( value => $val );
		if (defined $opt{value}) {
		    if ($opt{multiple}) {
			my %vopt = map { $_ => 1 } split /; /,$opt{value};
			if ($vopt{$val}) {
			    $optattr{selected} = undef; 
			}
		    }
		    elsif ($val eq $opt{value}) { 
			$optattr{selected} = undef; 
		    }
		}
		$options .= $ml->option(($opt{notranslate} ? $text : $msg{$text}),
					\%optattr);
	    }
	}
	elsif (ref $opt{options} eq "HASH") {
	    # a hash of value=>descriptive text pairs
	    while (my ($val,$text) = each %{$opt{options}}) {
		$val = &html_escape($val,'"');
		if ($opt{width} && length $text > $opt{width}) {
		    $text = substr($text,0,$opt{width})."...";
		}
		my %optattr = ( value => $val );
		if ($opt{multiple}) {
		    my %vopt = map { $_ => 1 } split /; /,$opt{value};
		    if ($vopt{$val}) {
			$optattr{selected} = undef; 
		    }
		}
		elsif ($val eq $opt{value}) { 
		    $optattr{selected} = undef; 
		}
		if ($opt{value} && $val eq $opt{value}) { $optattr{selected} = undef; }
		$options .= $ml->option(($opt{notranslate} ? $text : $msg{$text}),
					\%optattr);
	    }
	}
	elsif ($opt{options} =~ /\|/) {
	    my @opt = split /\|/,$opt{options};
	    foreach my $opt (@opt) {
		my %optattr;
		if ($opt{value} && $opt eq $opt{value}) { $optattr{selected} = undef; }
		$options .= $ml->option($opt,\%optattr);
	    }
	}
	else {
	    # assume it is preformatted
	    $options .= $opt{options};
	}

	# JS event handlers
	foreach my $evt (keys %opt) {
	    if ($evt =~ /^on\w+/i) {
		$selectattr{$evt} = $opt{$evt};
	    }
	}
	# Bootstrap features
	if ($opt{tooltip}) {
	    $selectattr{'data-toggle'} = "tooltip";
	    $selectattr{'data-placement'} = "right";
	    $selectattr{'title'} = $opt{tooltip};
	    $share{page_footer} .= &insert_js("tooltip");
	}

	# required css
	if ($opt{required}) {
	    my $class = "requiredInput";
	    $selectattr{class} = $selectattr{class} ? $selectattr{class}." $class" : $class;
	}
	if ($opt{missing}) {
	    my $class = "missingInput";
	    $selectattr{class} = $selectattr{class} ? $selectattr{class}." $class" : $class;
	}

	$input .= $ml->select($options,\%selectattr);
    }
    return $input;
}

# Same idea as select, but use radio buttons instead.
# (This differs from using input(), which creates one radio button;
# this method creates a complete radio group.)

sub select_radio {
    my ($this,%opt) = @_;
    my $input;
    return undef if (! $opt{name});
    my $nradio = 0;
    if ($opt{input}) {
	$input = $opt{input};
    }
    else {
	my $ml = &get_obj("ML");
	my $base_id;
	my @radio;
	if (ref $opt{options} eq "ARRAY") {
	    # an array of options, in various formats
	    foreach my $item (@{$opt{options}}) {
		$nradio++;
		my %rattr = (type=>"radio", name=>$opt{name});
		if ($opt{required} > 0) {
		    $opt{id} = $this->make_id($opt{name});
		    if (! $base_id) { $base_id = $opt{id}; }
		    # we do JS validation
		    $this->{required_id}{$opt{id}} = $base_id;
		    $this->{required_type}{$opt{id}} = $opt{type};
		    push @{$this->{validate_order}}, $opt{id};
		    $this->{required_name}{$opt{id}} = $opt{name};
		    $this->{required_done}{$opt{name}} = 1;
		}
		if ($opt{id}) { 
		    $this->{id}{$opt{id}} = $opt{name};
		    $rattr{id} = $opt{id};
		}
		if ($opt{class}) { $rattr{class} = $opt{class}; }
		if ($opt{disabled}) { $rattr{disabled} = undef; }
		my $typ = ref $item;
		my ($val,$text);
		if ($typ eq "ARRAY") { 
		    # reference to an array of value,text
		    $val = $item->[0]; 
		    $text = $item->[1];
		}
		elsif ($typ eq "HASH") { 
		    # hash with value, text 
		    $val = $item->{value}; 
		    $text = $item->{text}; 
	        }
		else { 
		    # just text, no value
		    $val = $text = $item; 
		}
		$val = &html_escape($val,'"');
		$rattr{value} = $val;
		if ($val eq $opt{value}) { $rattr{checked} = undef; }
		$input = $ml->input(undef,\%rattr);
		$this->set_subinput($opt{name},$nradio,$input);
		$input .= "&nbsp;".($opt{notranslate} ? $text : $msg{$text})."\n";
		push @radio,$input;
	    }
	}
	elsif (ref $opt{options} eq "HASH") {
	    # a hash of value=>descriptive text pairs
	    while (my ($val,$text) = each %{$opt{options}}) {
		$nradio++;
		$val = &html_escape($val,'"');
		my %rattr = (type=>"radio",name=>$opt{name},value=>$val);
		if ($val eq $opt{value}) { $rattr{checked} = undef; }
		$input = $ml->input(undef,\%rattr);
		$this->set_subinput($opt{name},$nradio,$input);
		$input .= "&nbsp;".($opt{notranslate} ? $text : $msg{$text})."\n";
		push @radio,$input;
	    }
	}
	else {
	    # assume it is preformatted
	    push @radio, $opt{options};
	}
	my $stack_checkboxes = $opt{stack_checkboxes} || $config{form}{stack_checkboxes};
	my $stack = $opt{stack} || (scalar @radio >= $stack_checkboxes);
	$input = join($stack ? $ml->br() : "&nbsp;&nbsp;", @radio);
    }
    return $input;
}

# inject arbitrary informational markup into the form.  Internally, this is
# handled as another input element, with no prompt.

### FIXME: clashes with Base::info

sub info {
    my ($this,$input,$prompt) = @_;

    my $name;
    while (! $name || exists $this->{input}{$name}) {
	# choose a unique name
	$name = "info_".&randtext(5,'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789');
    }
    
    # add to end of form
    push @{$this->{name}},$name;

    # append to existing inputs
    $this->{prompt}{$name} = $prompt;
    $this->{input}{$name} = $input;

    return $input;
}

# signature for the form
sub signature {
    my $this = shift;
    return undef;
}

# buttons
sub buttons {
    my ($this,%opt) = @_;
    if (scalar keys %opt == 0) { 
	%opt = ( submit=>1, cancel=>1, reset=>1 );
    }
    my $ui = new ExSite::UI;
    my (@buttons,$label);
    (tied %msg)->nohighlight;  # non-HTML messages for button labels
    my $ml = &get_obj("ML");   # xhtml-friendly tags
    if ($opt{submit}) {
	$label = $opt{submit} =~ /\D/ ? $opt{submit} : $msg{Submit};
	push @buttons, $ml->input(undef,{type=>"submit", #name=>"submit_action",
					 value=>$ui->UnicodeIcon("check")." ".$label, 
					 class=>"formButton"});
    }
    if ($opt{cancel}) {
	$label = $opt{cancel} =~ /\D/ ? $opt{cancel} : $msg{Cancel};
	push @buttons, $ml->input(undef,{type=>"button", 
					 value=>$ui->UnicodeIcon("cross")." ".$label, 
					 class=>"formButton cancel", 
					 onClick=>"javscript:history.back()"});
    }
    if ($opt{reset}) {
	$label = $opt{reset} =~ /\D/ ? $opt{reset} : $msg{Reset};
	push @buttons, $ml->input(undef,{type=>"reset", 
					 value=>$ui->UnicodeIcon("redo")." ".$label,
					 class=>"formButton"});
    }
    $this->{buttons} = $ml->div( join("&nbsp;&nbsp;",@buttons),
				 { class=>'formButtons' } );
    
    (tied %msg)->restore;  # back to default message highlighting
    return $this->{buttons};
}

# basic submit button only
sub submit {
    my $this = shift;
    return $this->buttons(submit=>1);
}

# add a captcha to the form (call this last if you want the captcha
# added at the end of the form and you haven't explicitly templated 
# it using [[captcha:input]])

sub captcha {
    my ($this,$type) = @_;
    $type or $type = "image";
    my $input = new ExSite::Input();
    my $indata = $input->combine();
    my $c = new ExSite::Captcha(mode=>$indata->{captchamode});
    if ($type eq "text") {
	$c->set("mode","text");
    }
    elsif ($type ne "image") {
	$c->set("mode","passive");
	# if type is "passive", use default passive types,
	# otherwise, you can pass the passive types directly
	$c->set("passive_method",$type eq "passive" ? undef : $type);
    }
    $this->input(name=>"captcha", 
		 type=>"preformatted", 
		 input=>$c->make());
}

sub validate_js {
    my $this = shift;
    my $js;
    my %validated;
    if ($this->{validate}) {
	$js .= "function validate_$this->{formname}(f) {
    var missing = new Array();
    var r,message,prompt;\n";
#	foreach my $req (keys %{$this->{required_type}}) {
	foreach my $req (@{$this->{validate_order}}) {
	    next if ($validated{$this->{required_id}{$req}});
	    my $type = $this->{required_type}{$req};
	    my $jsid = $this->{required_id}{$req};
	    #my $jsprompt = $this->{required_prompt}{$jsid};
	    my $jsprompt = $this->{required_prompt}{$this->{required_name}{$jsid}};
	    $jsprompt =~ s/\'/\\\'/g;
	    if ($type =~ /radio/) {
		# We must find all input IDs in same group, and loop over
		# all of them to determine whether any one has been checked.
		my @radio_id = ($req);
		if (! $validated{$this->{required_id}{$req}}) {
		    foreach my $id (keys %{$this->{required_name}}) {
			next if ($id eq $req); 
			if ($this->{required_name}{$id} eq $this->{required_name}{$req}) {
			    push @radio_id, $id;
			    $validated{$this->{required_id}{$req}} = 1;
			}
		    }
		    $js .= "    var ${jsid}_checked=0;\n    var $jsid = new Array('";
		    $js .= join("','",@radio_id);
		    $js .= "');\n";
			$js .= "    for (var index=0; index < ".$jsid.".length; ++index) {
        var item = ".$jsid."[index];
        var el = document.getElementById(item);
        if (el.checked) {
            ${jsid}_checked = 1;
        }
    }
    if (! ${jsid}_checked) {
        missing.push('$jsprompt');
    }\n";
		}
	    }elsif ($type =~ /select/){
		# IE 7, 8 select input validation
		$js .= "    var val = f.$jsid.options[f.$jsid.selectedIndex].value;
    if (/MSIE (\\\d+\\\.\\\d+);/.test(navigator.userAgent)){
        var ie_ver = new Number(RegExp.\$1);
        if (ie_ver <= 7){
            val = val || f.$jsid.options[f.$jsid.selectedIndex].text;
        }
    }
    if (! val ) {
        missing.push('$jsprompt');
    }\n";

	    }
	    else {
		my $test;
		if ($type =~ /checkbox/) {
		    $test .= "checked";
		}
		else {
		    ### FIXME: test for particular regex values
		    $test .= "value";
		}
		$js .= "    if (! f.$jsid.$test) {
        missing.push('$jsprompt');
    }\n";
	    }
	    $validated{$this->{required_id}{$req}} = 1;
	}
	(tied %msg)->nohighlight();
	my $missing = $msg{"The following required fields are missing:"};
	(tied %msg)->restore();
	$js .= "    if (missing.length > 0) {
        message = '$missing\\n';
		for (var index=0; index < missing.length; ++index) {
			var item = missing[index];        
			message = message + ' * ' + item + '\\n';
		}
        alert(message);
        return false;
    }
    return true;
}\n";
    }
    if (@{$this->{validate_script}} > 0) {
	foreach my $script (@{$this->{validate_script}}) {
	    $js .= $script."\n";
	}
    }
    my $ml = &get_obj("ML");
    return $js ? $ml->script($js) : "";
}

# generate the form

sub make {
    my $this = shift;
    my $form;
    #$this->template(); # called in make_form_html
    $this->{validate} = scalar keys %{$this->{required_type}};

    # use handler to build the report, if one is defined
    my $out = $this->run_handler("build_form");
    return $out if (defined $out);

    my $form = $this->make_form_html();  # HTML for all inputs

    # assemble the form attributes
    if (! $this->{formname} && $this->{validate}) {
	$this->{formname} = "form_".&randtext(5,'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789');
    }
    my %formattr = ( class => $this->{class} || "Form" );
    if ($this->{method})  { $formattr{method} = $this->{method}; }
    if ($this->{enctype}) { $formattr{enctype} = $this->{enctype}; }
    if ($this->{action})  { $formattr{action} = $this->{action}; }
    if ($this->{formname}){ $formattr{name} = $this->{formname}; }
    if ($this->{formid})  { $formattr{id} = $this->{formid}; }

    # get validation procedure
    my @validation_js;
    if (@{$this->{validate_js}} > 0) {
	push @validation_js, @{$this->{validate_js}};
    }
    if ($this->{validate}) {
	push @validation_js, "validate_$this->{formname}(this)";
    }
    if (@validation_js > 0) {
	$formattr{onsubmit} = "return ".join('&&',@validation_js);
    }

    my $ml = &get_obj("ML");
    my $js = $this->validate_js();
    return $this->{head}. 
	$ml->form($js.$form,\%formattr).
	$this->{foot};
}

sub make_form_html  {
    my $this = shift;
    my $form;
    $this->template();
    if ($this->{template_style} == 1) {
	$form = $this->make_template_1();
    }
    else {
	$form = $this->make_template_2();
    }
    return $form;
}

# template method 1 : pre-formatted template

sub make_template_1 {
    my $this = shift;
    my %subst;

    # see if template includes buttons
    my $buttons_included;
    if ($this->{template} =~ /\[\[buttons\]\]/) {
	$this->buttons() if (! $this->{buttons});
	$subst{buttons} = $this->{buttons};
	$buttons_included = 1;
    }

    # substitute all templated inputs
    foreach my $name (@{$this->{name}}) {
	$subst{"$name:input"} = $this->{input}{$name};
	$subst{"$name:prompt"} = $this->{prompt}{$name} || $name;
	if (exists $this->{subinput}{$name}) {
	    my @subinput = @{$this->{subinput}{$name}};
	    my $nsub = 0;
	    foreach my $sub (@subinput) {
		$nsub++;
		$subst{"$name:input:$nsub"} = $this->{subinput}{$name}[$nsub];
	    }
	}
    }
    my $form = &substitute($this->{template},\%subst);

    # look for extra inputs to append

    foreach my $name (@{$this->{name}}) {
	my $input = $this->{input}{$name};
	my $inputre = quotemeta $input;
	my $addinput = 0;
#	if ($form !~ /$inputre/) {
	if ($this->{template} !~ /\[\[$name:input(:1)?\]\]/) {
	    my $prompt = $this->{prompt}{$name};
	    if ($this->{type}{$name} =~ /hidden/) {
		$form .= $input;
	    }
	    elsif ($this->{type}{$name} =~ /preformatted/) {
		$form .= $prompt.$input;
	    }
	    else {
		if (! $addinput) { $form .= $this->{template_top}; }
		$form .= &substitute($this->{template_row},
				     {prompt=>$prompt,
				      input=>$input});
		if (! $addinput) { $form .= $this->{template_bot}; }
		$addinput = 1;
	    }
	}
    }

    if ($config{form}{key}) {
	$form .= $this->fbkey();
    }
    if (! $buttons_included) {
	$this->buttons() if (! $this->{buttons});
	$form .= $this->{buttons};
    }
    return $form;
}

# template method 2 : row-by-row templating only

sub make_template_2 {
    my $this = shift;
    my $form;
    my $nrow = 0;
    foreach my $name (@{$this->{name}}) {
	$nrow++;
	my $input = $this->{input}{$name};
	my $prompt = $this->{prompt}{$name};
	my $type = $this->{type}{$name};
	my $row = $this->{template_row};
	my $formrow;
	if ($this->{type}{$name} =~ /hidden/) {
	    $formrow = $input;
	}
	else {
	    my $rowclass = $this->{highlight_rows} ?
		($nrow % 2 ? "A" : "B") : "A";
	    if ($this->{type}{$name} =~ /preformatted/) {
		$formrow = &substitute($prompt.$input,
				       {rowclass=>$rowclass});
	    }
	    else {
		$formrow = &substitute($row,{prompt=>$prompt,
					     input=>$input,
					     name=>$name,
					     number=>$nrow,
					     type=>$type,
					     rowclass=>$rowclass});
	    }
	}
	$form .= "$formrow\n";
    }
    if ($form) {
	$form = $this->{template_top}.$form.$this->{template_bot};
    }

    if ($config{form}{key}) {
	$form .= $this->fbkey();
    }
    $this->buttons() if (! $this->{buttons});
    $form .= $this->{buttons};
    return $form;
}

# fbkey: add a token to limit form abuse/XSS attacks

sub fbkey {
    my $this = shift;
    my $ml = &get_obj("ML");
    require ExSite::Crypt;
    my $crypt = new ExSite::Crypt;
    my $key = $crypt->encrypt(time);
    return $ml->input(undef,{type=>"hidden",name=>"_fbkey",value=>$key});
}

# template a single input field

sub template_input {
    my ($this,$prompt,$input,$type) = @_;
    my $ml = &get_obj("ML");
    my $template;
    if ($type eq "preformatted") {
	return $prompt.$input;
    }
    elsif ($this->{template_row}) {
	$template = $this->{template_row};
    }
    else {
	$template = $config{form}{css_span} ?
	    $ml->p(
		$ml->span("[[prompt]]",{class=>"prompt"}).
		$ml->br.
		$ml->span("[[input]]",{class=>"input"})
	    ) : 
	    $ml->p("[[prompt]]".$ml->br."[[input]]");
    }
    return &substitute($template,{prompt=>$prompt,input=>$input});
}

1;

=pod

=head1 FormBuilder

This is a simple utility for building forms.  It is content-agnostic,
so it can easily be adapted to various web applications.  It is used
by higher-level form construction methods in ExSite, which handle all
of the ExSite-specific logic.

=head2 Usage

A typical usage is shown below.

=over 4

=item 1. Make a FormBuilder object

    my $f = new ExSite::FormBuilder(method=>"post",action=>"/cgi-bin/foo.cgi");

In addition to C<method> and C<action>, you can also specify
C<enctype>, which is usually set to "multipart/form-data" for forms
that allow file uploads, and C<name>, which may be used by Javascript
to access the form.

=item 2. Alter the basic form behaviours

These can also be specified in the C<new()> parameters:

    $f->method($get_or_post);
    $f->action($url);
    $f->enctype($encoding_type);
    $f->name($name);

=item 3. Specify a form template

This is optional, as a default template to lay out the form will be
provided.  See the Templating section below for details.

    $f->template($all_in_one_template);
    $f->template($top_of_form, $row_by_row_template, $bottom_of_form);

=item 4. Add input fields to the form

    $f->input(%first_input);
    $f->input(%second_input);
    $f->input(%etc);

The allowed options are described below, under Input Parameters.

=item 5. Generate the form

    print $f->make();

=item 6. Reset the form object, in case you want to re-use it.

    $f->init();

=back

In practice, these steps can be done in any order.  Templates will
override any previously-specified templates, but are not actually used
until C<make()> is called.  C<make()> will only output a form that
reflects the state of the object up to that point.

More advanced usage may involve installation of custom validation 
scripts, and more sophisticated use of the input generation functions.
Details are given below.

=head2 Input Parameters

Input parameters are passed to the C<input()> method in an C<%options> 
hash.

=head3 Input tag attributes

=over 4

=item name

The input field name.

=item type

The input type, one of text (default), password, file, checkbox,
radio, hidden, textarea, and select.  You can also use a type of
"preformatted" if you are passing in a preformatted string of HTML
to insert into the form.

=item value

The preset value of the field.

=item id

The ID of the input element.  This is optional, but if you do not provide
one, FormBuilder may set one automatically if needed for validation.

=item class

The CSS class of the input element.

=item accept

The C<accept> attribute, used by some file uploads.

=item maxlength

Sets the maximum length of a string that will be accepted in text fields.

=item size

Sets the width of the input field for text fields.

=back

=head3 Input field flags

The following parameters accept true/false values:

=over 4

=item checked

Preselects the given input, for radio and checkbox inputs.

=item readonly

Input field is enabled and will be submitted, but cannot be modified.

=item disabled

Form element is greyed out, and will not be submitted.

=item required

Form element is required, and form will not submit unless a value
is specified.  (See Validation, below.)  This is treated as a true/false
value, but there are two true values you can pass.

B<(1)> A basic true value of 1 means the field is required, and automatic 
Javascript validation will be performed.

B<(-1)> A value of -1 means the field is required, but validation will
only be performed server-side, not in Javascript.  The field will be
styled using CSS as a required field, however.  You are responsible
for your own server-side validation; this setting merely sets the CSS
to show that you will be doing so.

=back

=head3 Other modifiers

The following parameters are also accepted, although they are not input
attributes:

=over 4

=item input

You can specify the complete, literal input element with this parameter,
if you wish to override the automatically-constructed one.

=item nullvalue

For select inputs, this adds a null option ('') as the first option in
the list.  The value of this setting is the string displayed in the
options menu.  A typical value is "== select ==".

=item prompt

Specify the human-readable prompt string that informs the viewer
what input is expected in this field.  If no prompt is provided, the
input name will be used as a prompt.

=item top

If true, the input will be added at the top of the form, instead of at
the end.  (This only works with row-by-row templates.)

=item tail

This is an optional string of HTML that will be appended to the input field. 
It can be used to include help text or hints.

=back

Note that each input is generated as a new form field, unless it is a
radio input of the same name as a previous input; in that case, the
radio button is appended to the other radio buttons of that name.

=head2 Form Presets

You can pass individual field values in to each call to C<input>, but
you can also initialize all input values with a single call to
C<values>:

    $f->values(%data);

C<%data> is a hash of input names =E<gt> form values.  One convenient
application of this is regenerating a form that was submitted with
invalid inputs.

=head1 Validation

FormBuilder allows for client-side validation of forms.

If you specify the "required" parameter for any inputs in your form,
then special validation javascript will be built in to ensure that 
these fields contain data before the form will submit.  We only check
that data is present; we do not check that it conforms to any particular
pattern.  To do pattern checks, use a custom validation routine (see below).

Validation is automatic;  you need not do anything other than include
the "required" parameter in your C<input()> C<%options> where needed.

This is a convenience for the end-user, to prevent unnecessary submissions
and annoying waits in case of an incorrectly-filled form.  It can be
circumvented, so it does not replace server-side validation, and
should never be considered a security measure.

Validation requires that the required form elements and the form itself
have unique IDs.  FormBuilder will assign unique IDs to these elements
if you have not specified any yourself.  If you specify your own IDs,
FormBuilder will try to use those instead.  However, it does not validate
that the ID you have specified is unique in the form or the document,
so take care when specifying your own IDs.

Failed validation will result in a Javascript alert indicating which
fields are missing.

To require a user to accept some terms before the form will submit, 
simply add a checkbox input that is required, eg.

    $f->input(name=>"termsOfService",
	  prompt=>"I agree to the terms of service",
	  type=>"checkbox",
	  required=>1,
	  );

(Remember that this is not a bulletproof method for ensuring the form does
not get submitted without the box checked.)

B<Warning for radio buttons:> radio buttons consist of multiple input
tags that are grouped under a single name.  If you set a single radio
button as required, that means you must select that one button, and
any other button choices will not be accepted.  This is probably not
what you want.  Similarly if you make all but one required, then you
will not be able to select that one button.  To get the behaviour that
at least one button in the whole group must be selected, and any
button in the group may be selected, then each button in the group
must be set as required.

=head2 Custom Validation

If you want to inject your own validation javascript into the form, do this:

    $f->validate($my_js_call,$my_js_script);

where C<$my_js_call> is the call to your custom javascript function (eg. 
"C<validate_password(this)>"), and C<$my_js_script> contains the full
javascript code for this function.  It's a good idea to include the C<(this)>
in your call, which will pass the form object into your validation function.
If you leave off the script parameter, FormBuilder will assume it has
already been loaded or inserted into the page.

Your validation script must return C<true> for the form to get submitted.
If you return C<false>, you should also throw up your error messages using
C<alert()> calls.

You can define any number of custom validation scripts, and they will
all be executed, joined by the '&&' operator.  Each script can be treated 
as one validation pass;  the last pass does generic automatic validation
(testing that form fields contain data).

All passes must return true for the form to be submitted, and if any
return false, the remaining passes will not execute.  The
auto-generated validation script (described above) is run last in this
sequence.  This allows custom scripts to manipulate form data before
final submission.

=head3 Example

Say we want to not only test a field to make sure that data has been
provided, but also test that it matches an allowed pattern of values.
We can set the field as required, to make sure that data is present:

    $f->input(name=>"email",required=>1);

Then we can add a custom validator:

    $f->validate("validate_email(this)",
      "function validate_email(f) {
      var re = new RegExp('.+@.+\\.com');  // not a very good regexp
      if (f.email.value.match(re)) {
	return true;
      }
      alert('Invalid email address!');
      return false;
      }");

The first pass of validation checks that the email field (among
others) contains data.  If all required fields contain data, then 
C<validate_email()> is called, which tests the value in the email field
against a regular expression.  If it passes, it returns true, which
will take us to the next validation pass.  If not, it throws up an 
appropriate alert, and returns false, which causes the validation pass to
abort, and the form will not submit.

=head2 Styling Required Fields

Required files will be wrapped in some CSS markup to allow you to
highlight them in some way.

If you want the required field highlighting, but do not want
client-side validation (ie. you will handle it server-side), then pass
a negative non-zero value (eg.-1) for the C<required> flag on that
input.  All this does is use the HTML markup for required fields, 
but does not include any validation javascript.

You can also optionally insert additional text/html before or after
the prompt on required fields.  Use the object attributes
C<required_suffix> or C<required_prefix>, eg.

    $f->set("required_suffix","*");  # append a star to required fields

=head1 Custom Inputs

You can manually specify the input field tag using the C<input> option.
If your input is simple (single input, unique name), you can use the
built-in validation by setting the C<required> option to a non-zero value.

If your custom input is complex (for example, multiple input fields,
javascript-driven input controls, etc.), then the built-in validation
may not work.  Built-in validation checks for non-null value in the
form element (ie. C<f.inputname.value>), or if the element is a
checkbox, that it has been checked (C<f.inputname.checked>).  A
compound input (eg. a date field that prompts separately for year,
month, and day) may need to test multiple inputs to completely
validate, and the built-in-validation will not do this.  In these
cases, you will need to leave the C<required> flag off, and supply a
custom validation routine.  (See above.)

=head3 Example (date selector)

Say we want a date selector with separate selectors for day, month,
and year.  We can call the internal C<inputtag()> (or C<select()> and
C<textarea()>) methods to build the actual input fields without
altering the form state.  We can do this for each of day, month, and
year, and concatenate the results together:

    my $date_selector = 
      $f->inputtag(type=>"select",name=>"day",options=>[1..31]) . 
      $f->inputtag(type=>"select",name=>"month",options=>[1..12]) . 
      $f->inputtag(type=>"select",name=>"year",options=>[1990..2020]);

$date_selector now contains the HTML for selecting a date using
this aggregate input.  Now we want to add this to our form as a
"single" input field:

    $f->input(prompt=>"date",input=>$date_selector);

If this field is required, we cannot simply set C<required=E<gt>1> because
basic Javascript validation will get confused by all of our
sub-fields, so it has no way to easily tell if the field is set or
not.  In this case, we have three options:

=over 4

=item * server validation

set C<required=E<gt>-1> to mark the field as required, but let
the validation happen on the server

=item * custom validation

install our own custom validation script that knows how to inspect our
special sub-fields and report problems.  See above for details.

=item * reformat the data

install a custom validation script that aggregates our data into a
single value, copies it into a hidden field in the form.  That
hidden field can be set with C<required=E<gt>1>.

=back

=head1 Form Templates

Templates allow you some control over how forms are laid out in HTML.
There are two styles of template: row-by-row (default), and all-in-one.

=head2 Default Template

By default, forms are built using row-by-row templates, ie. by
concatenating form fields that are each templated using HTML like:

    <p><label>YOUR PROMPT STRING<br>
    YOUR INPUT TAG</label></p>

The p, label, and input tags may include CSS hooks to assist in styling
of the forms.  With the following system configuration parameter

    form.css_span = 1

the prompt and input will be wrapped in additional span tags to assist
with CSS styling.

=head2 Custom Templates

You can replace the default row-by-row template with your own using this call:

    $f->template($top_of_form, $row_by_row_template, $bottom_of_form);

C<$top_of_form> contains some HTML to place in front of all fields
(eg. opening a table).  C<$bottom_of_form> contains some HTML to place after
all fields (eg. closing a table).

C<$row_by_row_template> contains the the actual template to re-use for each 
field in the form.  It should contain two substitution strings, 
C<[[prompt]]> and C<[[input]]>, which will be replaced with the prompt 
string and the input tag respectively.

=head3 Example

    $f->template("<table class='myForm'>",
		 "<tr><td class='prompt'>[[prompt]]</td><td>[[input]]</td></tr>",
		 "</table>");

Row-by-row templates can contain the following merge codes:

    [[prompt]] - the prompt string
    [[input]] - the input field
    [[number]] - the question number
    [[name]] - the input name
    [[type]] - the input type (eg. text, radio, etc)
    [[rowclass]] - alternating A/B CSS class for row highlighting

=head2 All-in-one Templates

For more precise control over layout, you can provide an all-in-one template
that specifies where each named input field should go.

    $f->template($all_in_one_template);

C<$all_in_one_template> is a block of HTML that includes miscellaneous
C<[[name:prompt]]> and C<[[name:input]]> tags, where "name" is the
name of the input field in that position.  C<[[name:prompt]]> is replaced 
by the prompt string for that input field, and C<[[name:input]]> is 
replaced by the input tag(s) for that field.

Your all-in-one template should include any required CSS classes in
the template HTML, as no further HTML insertions are performed.

If you add inputs to your form that are not referenced in the
all-in-one template, then FormBuilder will append them to the end of
the form using the row-by-row templating method.  You can actually
specify templates for both methods in this case, by specifying your
row-by-row template first, and your all-in-one template second.  The
last method takes precedence, but the prior method is still saved in
case you have untemplated inputs in your form.

=head3 Example

    # row-by-row fallback template for unexpected inputs
    $f->template("","<p>[[prompt]]<br>[[input]]</p>","");

    # all-in-one template for expected inputs
    $f->template("<table>
        <tr><td>[[login:prompt]]</td><td>[[login:input]]</td></tr>
        <tr><td>[[passwd:prompt]]</td><td>[[passwd:input]]</td></tr>
        </table>");

=head2 Preformatted Rows

Sometimes you need to break with the row-by-row template, and add
some custom HTML (whether an input field or not) onto your form.  You
can append the special HTML, using an input type of "preformatted".
C<FormBuilder> will treat the prompt and input values of the input
like HTML strings that are simply concatenated and appended to the
form.

You can use this trick to insert arbitary HTML text into the middle of
your forms, such as help text or section headings.  There are two
input types you can use: formatted and preformatted.  The formatted
input type consists of prompt and input text that will be inserted
into the form template in the usual way:

    $f->input(type=>"formatted",
	      name=>"foo",
	      prompt=>"New Section",
	      input=>"This is some helful text introducing this new
                      section of the form.");

The preformatted input type does no templating, and simply concatenates
the prompt and input to the end of the form. In this case you should 
include any extra markup that is necessary for formatting:

    $f->input(type=>"preformatted",
	      name=>"foo",
	      prompt=>"<h3>New Section</h3>",
	      input=>"<p>This is some helful text introducing this new
                      section of the form.</p>");

In both cases, you can provide a prompt or input, or both.

Try to ensure that your concatenated prompt and input fields will fit
into the form HTML.  For exmaple, if your form template is a table,
and your row-by-row template is a row in this table, then your
preformatted input should also be a table row that fits into this
HTML.  For example:

    $f->input(type=>"preformatted",
	      name=>"foo",
	      prompt=>"<tr class='[[rowclass]]'><td colspan=2><h3>New Section</h3></td></tr>");

In this example, note that we did not bother to specify an input.  We
also included a template placeholder for C<rowclass>, which is used to
highlight alternating rows if you make use of that feature.

Preformatted rows cannot make use of other FormBuilder features such
as validation.

=head2 Header and Footer HTML

You can also insert arbitrary HTML before and after the form, using:

    $f->set("head",$header_html);
    $f->set("foot",$footer_html);

These HTML snippets will go outside the form tags.

=head1 CSS

The default template makes use of the following CSS classes:

=over 4

=item form.Form

The entire form is given a CSS class of "Form".

=item p.A, p.B

Wraps the prompt and input field.  The class A/B alternates if row
highlighting has been enabled (see below), otherwise they are all
class A.

=item span.prompt, span.input

Wraps the prompt string and input tags, if C<form.css_span> is set.

=item input.formButton

Used for the final form buttons only.

=item div.formButtons 

Wraps the group of final form buttons.

=back

Additionally, required fields may also use the following CSS classes:

=over 4

=item .requiredPrompt

The prompt string of a required field.

=item .requiredInput

The input tag(s) of a required field.

=item .missingPrompt

The prompt string of a required field if the form has been 
populated with data, but the required field has no data.

=item .missingInput

The input tag(s) of a required field if the form has been 
populated with data, but the required field has no data.

=back

=head2 Alternating Row Styles

Set alternate-row highlighting on as follows:

    $f->set("highlight_rows",1);

When using row-by-row templating, this will give each row of the form
an alternating CSS class of "A" or "B".  These can be used to give
each row an alternating background color, as is commonly done for
reports.  This only works for row-by-row templates (including the
default template).

If defining a custom row-by-row template, use the tag C<[[rowclass]]>
to insert the appropriate row class.  For example, here is a tabular
form layout that alternates the style of each table row:

    $f->template("<table class='Form'>",
	     "<tr class='[[rowclass]]'><td class='prompt'>[[prompt]]</td><td class='input'>[[input]]</td>",
	     "</table>");

To ignore the row class entirely, simply do not reference it in your template.

=head2 Custom CSS

You can also specify custom CSS classes when building forms.  The
C<input> method accepts a C<class> attribute, which will be used to
style the tags that it outputs.

You can also specify arbitrary CSS classes in your templates, instead
of using the default classes described above.

=head1 FormBuilder and Form

The C<Form> class also provides form-building functions, but it uses
C<FormBuilder> for the low-level features.  Understanding the
interaction between C<Form> and C<FormBuilder> can be useful when you
want to make use of features from both form handling packages.

C<Form> handles the mapping of database tables and columns to forms
and form fields.  C<ExSite::Form::form()> returns a C<FormBuilder>
object, and that object is used by C<Form> to assemble its
auto-generated forms.  If you call C<ExSite::Form::form()> with no
parameters, you will get the current C<FormBuilder> object; if you
provide parameters, it will discard the current object, and initialize
a new one.  When you invoke any of the C<Form> functions like
C<input_record>, C<input_column>, C<input_exsite>, and C<input_html>,
the resulting form field is appended to the current C<FormBuilder>
object.  That means you can add autogenerated C<Form> fields to the
form using these functions, and also add customized fields to the form
by using the C<FormBuilder> object directly.

=head2 Example

Create a new C<FormBuilder> object via C<Form> so that you can add
fields with ExSite database or datatype logic:

    $db = new ExSite::Form;
    my $f = $db->form(method=>"post",action=>$action);

Add a database field to this form (ie. a field that maps to a particular
database column):

    $db->input_column(table=>"my_table",
                      column=>"my_column",
                      value=>$val);

Add a field to this form that collects data for a special ExSite datatype:

    $db->input_exsite(datatype=>"datetime",
                      name=>"date",
                      value=>"2008-10-01 12:01:00");

Add a basic HTML input element that is required:

    $db->input_html(type=>"text",name=>"email",required=>1);

Or (equivalent to previous, going direct to C<FormBuilder>):

    $f->input(type=>"text",name=>"email",required=>1);

Generate the form:

    my $form_html = $f->make();

=cut

