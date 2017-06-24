package ExSite::Attribute;
#-----------------------------------------------------------------------
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

# ExSite::Attribute - a general-purpose meta-data tool for databases
#
# Allows you to define attributes (name-value pairs) and link them 
# to any ExSite database record.  All attributes are stored in their
# own table.
#
# This allows the end user to extend the effective sets of values 
# in a record, without modifying the database schema.


use strict;
use ExSite::Config;
use ExSite::Form;
use ExSite::Misc;
use ExSite::Base;

use vars qw(@ISA);
@ISA = qw(ExSite::Base);

# create an attribute object, and tie it to a record

sub new {
    my ($this,$table,$id) = @_;
    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;
    $obj->setup($table,$id);
    return $obj;
}

# change record

sub setup {
    my ($this,$table,$id) = @_;
    
    # metadata for this record
    $this->{loaded} = undef;
    $this->{raw} = undef;      # copy of metadata records
    $this->{data} = undef;     # attribute values
    $this->{dirty} = undef;    # flag changed metadata

    # allowed metadata for this table
    # (don't reset this unless we are also changing tables)
    if ($table ne $this->{allow_table}) {
	$this->{allow_table} = undef;
	$this->{allowed} = undef;
    }
    
    $this->{attr_table} = "attribute";
    $this->{attr_id} = "attribute_id";
    $this->{idcol} = "id";
    $this->{table} = $table;
    $this->{id} = $id;
    return;
}

sub id {
    my ($this,$id) = @_;
    if ($id) {
	if (! $this->{id}) {
	    # current object has acquired an ID
	    $this->{id} = $id;
	}
	elsif ($id ne $this->{id}) {
	    # current object ID has changed; reset the object
	    $this->setup($id);
	}
    }
    return $this->{id};
}

# meta_id returns the id of a named metadata attribute

sub meta_id {
    my ($this,$name) = @_;
    if ($this->ok) {
	$this->load;
	if (exists $this->{raw}{$name}) {
	    return $this->{raw}{$name}{$this->{attr_id}};
	}
    }
    return 0;
}

sub ok {
    my ($this) = @_;
    return ($this->{table} && $this->{id});
}

# get the preferred datatype for an attribute

sub get_datatype {
    my ($this,$name) = @_;
    $this->load_allowed();
    if ($this->is_allowed($name)) {
	# check for dbmap-style info
	my $datatype = $this->get_map_info($name,"datatype");
	return $datatype if ($datatype);
	# otherwise, check for a simple value, understood to be a datatype
	if (exists $this->{allowed}{$name}) {
	    if ($this->{allowed}{$name}{value} && 
		$this->{allowed}{$name}{value} !~ /\&/) {
		return $this->{allowed}{$name}{value};
	    } 
	}
    }
    return "string";
}

# dbmap-style data can optionally be encoded in the value field of
# template attribute records

sub get_map_info {
    my ($this,$name,$mapkey) = @_;
    $this->load_allowed();
    if ($this->is_allowed($name)) {
	if (exists $this->{allowed}{$name}) {
	    my %map;
	    if ($this->{allowed}{$name}{map}) {
		return $this->{allowed}{$name}{map}{$mapkey};
	    }
	    else {
		if ($this->{allowed}{$name}{value} =~ /=/) {
		    # appears to be one or more key=value settings
		    %map = &DecodeString($this->{allowed}{$name}{value});
		    $this->{allowed}{$name}{map} = \%map;
		    return $map{$mapkey};
		}
	    }
	}
    }
    return undef;
}

# label: what is the human-readable label for this attribute?

sub label {
    my ($this,$name) = @_;
    my $label = $this->get_map_info($name,"label");
    if ($label) {
	return $msg{$label};
    }
    else {
	$name =~ s/_/ /g;
	return ucfirst $name;
    }
}

sub required {
	my ($this,$name) = @_;
	return ($this->get_map_info($name,"validate")=~/soft|hard/) || 0;
}

# display an attribute

sub showdata {
    my ($this,$name) = @_;
    my $out;
    my $val = $this->get($name);
    if ($val) {
	# test access
	my $readlevel = $this->get_map_info($name,"read");
	defined $readlevel or $readlevel = 1;
	if ($readlevel <= $share{DB}->level) {
	    my $datatype = $this->get_datatype($name);
	    $out = $share{DB}->show_data_noauth(
						$this->{attr_table},
						"value",
						$val,
						$this->{raw}{$name}{$this->{attr_id}},
						$datatype,
						);
	}
	else {
	    $out = $config{report}{permission_denied};
	}
    }
    return $out;
}

# load up the attributes

sub load {
    my ($this) = @_;
    if (! $this->{loaded} && $this->ok) {
	my @attr = $this->fetch_match({$this->{idcol}=>$this->{id}});
	$this->{raw} = &keywise("name",\@attr);
	foreach my $attr (values %{$this->{raw}}) {
	    my $name = $attr->{name};
	    $this->{data}{$name} = $attr->{value};
	    $this->{row}{$name} = $attr;
	}
	$this->{dirty} = undef;
	$this->{loaded} = 1;
    }
}

sub load_allowed {
    my ($this) = @_;
    if ($this->{allow_table} ne $this->{table}) {
	my @attr = $this->fetch_match({$this->{idcol}=>0});
	$this->{allowed} = &keywise("name",\@attr);
	$this->{allow_table} = $this->{table};
    }
}

# get a list of allowed attribute names
# (allowed names are those in the attribute table that have no record ID)
# datatypes are stored in $this->{datatype}

sub get_allowed {
    my ($this) = @_;
    $this->load_allowed();
    return keys %{$this->{allowed}};
}

# allowed keys can optionally be sorted by rank

sub get_allowed_sorted {
    my ($this) = @_;
    return sort { 
	$this->get_map_info($a,"rank") <=> $this->get_map_info($b,"rank") 
	} $this->get_allowed();
}

sub is_allowed {
    my ($this,$name) = @_;
    $this->load_allowed();
    if (scalar keys %{$this->{allowed}} > 0) {
	# we have an explicit allow list for attributes
	return exists $this->{allowed}{$name};
    }
    # there is no allow list;  all attributes are permitted
    return 1;
}

# add an allowed attribute (admin users only)
# $options is either a datatype, or a URL-encoded set of dbmap settings

sub add_allowed {
    my ($this,$name,$options) = @_;
    
    if ($share{DB}->is_admin) {
	$this->load_allowed();
	if (exists $this->{allowed}{$name}) {
	    $this->error("ExSite::Attribute::add_allowed: $name already exists");
	}
	else {
	    my $meta = $this->make_record($name,$options,0);
	    my $mid = $this->insert($meta);
	    $this->{allowed}{$name} = $meta;
	    return $mid;
	}
    }
    else {
	$this->error("ExSite::Attribute::add_allowed: permission denied");
    }
    return 0;
}

# remove an allowed attribute (admin users only)
# also removes all attributes of that name

sub remove_allowed {
    my ($this,$name) = @_;
    my $db = $share{DB};
    if ($db->is_admin) {
	if ($this->is_allowed($name)) {

	    # remove from database

	    my @attr = $this->fetch_match({name=>$name});
	    my @trash;
	    foreach my $attr (@attr) {
		push @trash, $this->{attr_table}, $attr->{$this->{attr_id}};
	    }
	    $this->trash(@trash);

	    # remove from current object

	    delete $this->{allowed}{$name};
	    delete $this->{raw}{$name};
	    delete $this->{data}{$name};
	    delete $this->{dirty}{$name};

	    return scalar @attr;
	}
	else {
	    $this->error("ExSite::Attribute::remove_allowed: invalid attribute: $name");
	}
    }
    else {
	$this->error("ExSite::Attribute::add_allowed: permission denied");
    }
    return 0;
}

# get all attributes for this record

sub get_all {
    my ($this) = @_;
    $this->load;
    return () if (! defined $this->{data});
    return wantarray ? %{$this->{data}} : $this->{data};
}

sub get_record {
    my ($this,$name) = @_;
    $this->load;
    return undef if (! defined $this->{row});
    if ($name) {
	return wantarray ? %{$this->{row}{$name}} : $this->{row}{name};
    }
    else {
	return wantarray ? %{$this->{row}} : $this->{row};
    }
}

# fetch attribute values

sub get {
    my ($this,$name) = @_;
    $this->load;
    if (! $name) { return $this->get_all(); }
    return exists $this->{data}{$name} ?
	$this->{data}{$name} : undef;
}

# set/save an attribute value

sub set {
    my ($this,$name,$value) = @_;
    if ($this->set_nosave($name,$value)) {
	# attribute was successfully set;  now save it
	$this->save($name);
    }
}

sub set_nosave {
    my ($this,$name,$value) = @_;
    $this->load;    

    my $err = $this->validate($name,$value);
    if ($err) {
	$this->error("$name: $err");
	return 0;
    }
    elsif ($this->is_allowed($name)) {
	if ($value ne $this->{data}{$name}) {
	    $this->{data}{$name} = $value;
	    $this->{dirty}{$name} = 1;
	    return 1;
	}
	return 0;
    }
    else {
	$this->error("ExSite::Attribute::add_allowed: permission denied");
	return 0;
    }
}

sub validate {
    my ($this,$name,$value) = @_;
    my $datatype = $this->get_datatype($name);
	if ($this->required && !$value) {
		my $label = $this->label($name);
		return "you must provide a value for $label";
	}
	return undef if (!$value);
    return $datatype ? $share{DB}->validate_datatype($datatype,$value) : undef;
}

sub save { 
    my ($this,$name) = @_;
    return if (! $this->ok());

    my @update;
    if ($name) {
	# save one attribute
	push @update, $name;
    }
    else {
	# save all dirty attributes
	push @update, keys %{$this->{dirty}};
    }

    foreach my $n (@update) {
	if (exists $this->{raw}{$n}) {
	    if ($this->{data}{$n}) {
		# update existing attribute
		$this->update_value($n,$this->{data}{$n});
	    }
	    else {
		# empty value - clear old attribute
		$this->trash($this->meta_id($n));
	    }
	}
	elsif ($this->{data}{$n}) {
	    # new attribute setting
	    my $meta = $this->make_record($n,$this->{data}{$n});
	    my $mid = $this->insert($meta);
	    $this->{raw}{$n} = $meta;
	}
    }
    return;
}

# copy one or all attributes to another record ID

sub copy { 
    my ($this,$id,$name) = @_;
    if ($this->ok) {
	my @keys = $name ? ($name) : keys %{$this->{data}};
	if (@keys > 0 && $id) {
	    my $a = new ExSite::Attribute($this->{table},$id);
	    foreach my $k (@keys) {
		$a->set_nosave($k,$this->get($k));
	    }
	    $a->save();
	}
    }
}

# remove all attribute values

sub clear {
    my ($this,$name) = @_;

    if ($this->ok) {
	$this->load;
	if ($name) {
	    if ($this->{data}{$name}) {
		$this->trash($this->meta_id($name));
		delete $this->{raw}{$name};
		delete $this->{data}{$name};
		delete $this->{dirty}{$name};
		return 1;
	    }
	}
	else {
	    return $this->clear_all();
	}
    }
    
    $this->warn("ExSite::Attribute::clear: no such attribute");
    return 0;
}

sub clear_all {
    my ($this) = @_;

    if ($this->ok) {
	$this->load;
	my @attr = $this->fetch_match({$this->{idcol}=>$this->{id}});
	if (@attr > 0) {
	    my @trash;
	    foreach my $attr (@attr) {
		push @trash, $this->{attr_table}, $attr->{$this->{attr_id}};
	    }
	    $this->trash(@trash);
	    $this->{raw} = undef;
	    $this->{data} = undef;
	    $this->{dirty} = undef;
	    return scalar @attr;
	}
    }
    return 0;
}

# generate an input tag to accept attribute values
# NOTE: cannot do foreign key refs in attributes

sub input {
    my ($this,$input_name,$name,$value) = @_;
    if ($this->is_allowed($name)) {
	if ($input_name) {
	    # hard-coded input name;  the form must know what to do with 
	    # this input
	    return $share{DB}->input_exsite(
					    datatype=>$this->get_datatype($name),
					    name=>$input_name,
					    prompt=>$this->label($name),
					    value=>($value || $this->get($name) || $this->get_map_info($name,"default")),
					    required=>$this->required($name),
					    size=>$this->get_map_info($name,"size"),
					    );
	}
	else {
	    # auto-coded input name; self-processing ExSite forms can figure
	    # this out automatically.
	    my $rec = $this->recid($name);
	    my $datatype = $this->get_datatype($name);
	    return $this->input_column(
#				       table=>$this->{attr_table},
#				       column=>"value",
				       prompt=>$this->label($name),
				       record=>$rec,
				       size=>$this->get_map_info($name,"size"),
				       datatype=>$datatype,
				       value=>($value || $this->get($name)),
				       required=>$this->required($name)			       
				       );
	}
    }
    else {
	return $share{DB}->error("Cannot generate input field for invalid attribute \"$name\"");
    }
}

sub recid {
    my ($this,$name) = @_;
    my $rec;
    if ($this->{raw}{$name}) {
	$rec = $this->{raw}{$name}{$this->{attr_id}};
    }
    else {
	if (! $this->{n_attr_input}) { 
	    $this->{n_attr_input} = 1;
	}
	$rec = "_" . $this->{n_attr_input};	
	$this->{n_attr_input}++;
    }
    return $rec;
}

sub input_record {
    my ($this,$opt) = @_;
    my $db = $share{DB};
    if (! $share{added_attribute_handler}) {
	$db->handler("attribute_input_column",\&input_column_handler);
	$share{added_attribute_handler} = 1;
    }
    my $out;
    if ($this->is_allowed($opt->{name})) {
	my $rec;
	if ($this->{raw}{$opt->{name}}) {
	    $rec = $this->{raw}{$opt->{name}}{$this->{attr_id}};
	}
	else {
	    if (! $this->{n_attr_input}) { 
		$this->{n_attr_input} = 1;
	    }
	    $rec = "_" . $this->{n_attr_input};	
	    $this->{n_attr_input}++;
	}
	my %data;
	my $action;
	if (exists $this->{raw}{$opt->{name}}) {
	    # update
	    %data = %{$this->{raw}{$opt->{name}}};
	    $action = "update";
	}
	else {
	    # insert
	    $data{tablename} = $this->{table};
	    $data{id} = $this->{id};
	    $data{name} = $opt->{name};
	    $data{value} = $opt->{value};
	    $action = "insert";
	}

	my $sc = $config{form}{sepchar};
	my $iname = "$this->{attr_table}${sc}${rec}${sc}value";
	$out .= $this->input($iname,$data{name},$data{value});
	foreach my $col ($this->{attr_id}, "name", "tablename", "id") {
	    next if (! $data{$col});
	    $iname = "$this->{attr_table}${sc}${rec}${sc}$col";
	    $out .= $db->form()->input(type=>"hidden", name=>$iname, value=>$data{$col});
	}
	$out .= $db->form()->input(type=>"hidden", name=>"action", value=>$action);
    }
    return $out;
}

# DB accessors, for easier overloading
# All low-level DB logic is defined here.

# make_record() - create a datahash suitable for inserting into the DB
# use insert() to actually insert it.

sub make_record {
    my ($this,$name,$value,$id) = @_;
    return { 
	name=>$name, 
	value=>$value, 
	tablename=>$this->{table},
	$this->{idcol}=>(defined $id ? $id : $this->{id}), 
	};
}

sub fetch_match {
    my ($this,$match) = @_;
    if ($this->{attr_table} eq "attribute") {
	$match->{tablename} = $this->{table};
    }
    return $share{DB}->fetch_match($this->{attr_table},$match);
}

sub insert {
    my ($this,$data) = @_;
    my $id = $share{DB}->insert($this->{attr_table},$data);
    $data->{$this->{attr_id}} = $id;
    return $id;
}

sub update_value {
    my ($this,$name,$value) = @_;
    if ($this->ok) {
	$this->load();
	my $meta_id = $this->meta_id($name);
	if ($meta_id) {
	    return $share{DB}->update(
				      $this->{attr_table},
				      { value=>$value },
				      { "$this->{attr_id}" => $meta_id }
				      );
	}
    }
    return undef;
}

sub input_column {
    my ($this,%options) = @_;
    $options{table} = $this->{attr_table};
    $options{column} = "value";
    return $share{DB}->input_column(%options);
}

sub trash {
    my ($this,@data) = @_;
    my @trash;
    foreach my $attr (@data) {
	push @trash, $this->{attr_table}, (ref $attr) eq "HASH" ? $attr->{$this->{attr_id}} : $attr;
    }
    return $share{DB}->trash(@trash);
}

# deprecated functions

sub fetch {
    my ($this,$name) = @_;
    return $this->get($name);
}

sub rollback {
    my ($this,$name) = @_;
    $this->warn("ExSite::Attribute: rollback no longer supported");
    return 0;
}

sub purge {
    my ($this,$name) = @_;
    $this->warn("ExSite::Attribute: purge no longer supported");
    return 0;
}

1;


