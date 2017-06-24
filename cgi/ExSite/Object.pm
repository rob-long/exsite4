#!/usr/bin/perl
#-----------------------------------------------------------------------
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

package ExSite::Object;

use strict;
use ExSite::Config;
use ExSite::Base;
use ExSite::Form;
use ExSite::Misc;
use ExSite::ObjectList;

use vars qw(@ISA);
@ISA = qw(ExSite::Base);

#=== OBJECT CREATION

sub new ($%) {
    my ($this,%opt) = @_;
    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;
    $obj->initialize_object;
    $obj->setup(%opt);
    return $obj;
}

# set/return the database that stores the object
# you can use $obj->set("DB",$some_other_db) to use another DB

sub DB {
    my $this = shift;
    return $this->{DB} || $share{DB};
}

#=== IDENTIFICATION

# setup(%): standard protocol for data object setup is:
#
# type => table name (defaults to my_type())
# id => record ID
# data => datahash

sub setup {
    my $this = shift;
    my %opt = @_;
    $this->{type} = $opt{type} || $this->my_type;
    $this->{id} = $opt{id};
    $this->{data} = $opt{data};
    if ($this->{data} && ! $this->{id}) {
	$this->{id} = $this->{data}{$this->key()};
    }
    delete $this->{children};
    # flag whether we need to save data - assumes data is a clean record,
    # otherwise you should manually set the dirty flag
    $this->{dirty} = exists $opt{dirty} ? $opt{dirty} : 0;
    return;
}

sub my_type { return; }    # generic object has no preset type

sub type {
    my $this = shift;
    return $this->{type} || $this->my_type();
}

sub id {
    my $this = shift;
    # fetch the id
    if ($this->{id}) { 
	return $this->{id};
    }
    elsif ($this->{data}) {
	$this->{id} = $this->{data}{$this->key()};
	return $this->{id};
    }
    return undef;
}

sub name {
    my $this = shift;
    if ($this->defined()) {
	return $this->DB()->title($this->{type},$this->{id},$this->{data});
    }
    return "n/a";
}

sub key {
    my $this = shift;
    my $type = $this->type();
    if ($type) {
	return $this->DB()->{map}->get_table_attr($type,"key");
    }
    return undef;
}

# record ownership

sub owner {
    my $this = shift;
    return $this->DB()->find_owner($this->type(),$this->id(),"user");
}

sub owns {
    my $this = shift;
    return $this->DB()->user_owns($this->type(),$this->id());
}

# ok : returns true if object is fully specified (type & id)

sub ok {
    my $this = shift;
    $this->{status} = undef;
    # return true if object has an identity
    my $type = $this->type();
    if ($type) {
	$this->{status} = "Undefined $type object." if (! $this->id() && ! $this->has_data);
    }
    else {
	$this->{status} = "Undefined object type.";
    }
    return (! $this->{status});
}

# has_data : tests to see if the object has a datahash
#            - does not necessarily mean all data is loaded

sub has_data {
    my $this = shift;
    if (ref $this->{data} eq "HASH") {
	return scalar keys %{$this->{data}};
    }
    return undef;
}

# exists : returns true if the object as specified is found in the DB

sub exists {
    my $this = shift;
    if ($this->ok) {
	# completely defined record - load it if necessary
	if (! defined $this->{data}) { $this->load(@_); }
	return (ref $this->{data}) eq "HASH";
    }
    return undef;
}

# defined : returns true if the object's basic data is present in the object.
# Same as loaded() for simple objects, but loaded() should also test for
# auxiliary data needed to use the object.

sub defined {
    my $this = shift;
    return $this->has_data || $this->exists;
    #return $this->exists() || (ref $this->{data}) eq "HASH";
}

# loaded should be overloaded in more complex cases to also check for 
# auxiliary data - eg. metadata, get_children()...

sub loaded { return &defined(@_); }

#=== DATA

sub get {
    my ($this,$key) = @_;
    if (defined $key) {
	return $this->SUPER::get($key);
    }
    elsif (exists $this->{data}) {
	return $this->{data};
    }
    return undef;
}

sub getdata {
    my ($this,$key) = @_;
    if ($this->defined) {
	if (exists $this->{data}{$key}) {
	    return $this->{data}{$key};
	}
	elsif ($this->loaded()) {
	    # normally, we should not get here because loaded() and defined()
	    # return the same result. However loaded() can be overloaded to 
	    # detect complete/incomplete loading. That way we can prepop 
	    # some objects with partial data, avoiding the cost of a full
	    # load until we ask the object for data that has not been loaded.
	    return $this->{data}{$key};
	}
    }
    return undef;
}

sub setdata {
    my ($this,$key,$val) = @_;
    if ($this->ok && ! defined $this->{data}) { $this->load(); }
    # NB: if not defined, this will define the object
    my $oldval = $this->{data}{$key};
    $this->{data}{$key} = $val;
    if (! $this->{dirty}) { 
	# this doesn't work if setting to undef to set DB to NULL
	$this->{dirty} = ($val ne $oldval);
    }
}

sub showdata {
    my ($this,$key) = @_;
    if ($this->defined) {
	my $auth = $this->showauth($key);
	my $show = $auth ? "show_data_noauth" : "show_data";
	return $this->DB()->$show($this->{type},
				  $key,
				  $this->getdata($key),
				  $this->{id});
    }
    return undef;
}

sub showauth { 
    my ($this,$key) = @_;
    # default behaviour is to use the dbmap rules
    return 0;
}

sub dirty {
    my $this = shift;
    return $this->{dirty};
}

#sub approve {
#    my ($this,$op) = @_;
#    return $this->DB()->approve($op,$this->{type},$this->{id});
#}

#=== DISPLAY

# show : display the object for an end-viewer
#
# There is no default show method, show we simply use the report.

sub show {
    my ($this,%opt) = @_;
    return $this->report(%opt);
}

# report : technical or administrator view of the object

sub report {
    my ($this,%opt) = @_;
    if ($this->ok) {
	if ($this->defined()) {
	    return $this->DB()->report({ table=>$this->{type},
					 data=>[$this->{data}], 
					 columns=>"full|brief",
					 type=>"full", 
					 title=>$this->name,
					 %opt });
	}
	else {
	    my $name = ucfirst $this->name;
	    return $this->error("$name does not exist.");
	}
    }
    return $this->error($this->{status});
}

#=== DB

# load record : can pass an ID or a datahash

sub load {
    my ($this,$data) = @_;
    my $id;
    if (ref $data ne "HASH") { $id = $data; $data = undef; }
    $this->{data} = $data;
    my $type = $this->type;
    if (! $type) { $this->error("Undefined object type."); return 0; }
    if (! $id) { $id = $this->id(); }
    if ($id) { 
	$this->{data} = $this->DB()->fetch($type,$id); 
    }
    else { 
	$id = $this->id(); 
    }
    if (! $id && $this->{data}) { 
	$this->error("Mis-configured $type object."); 
	return undef;
    }
    elsif (! $id || ! $this->{data}) { 
	$this->error("Undefined $type object."); 
	return undef;
    }
    return $this->{data};
}

# reload : forces record to be re-read

sub reload {
    my $this = shift;
    if ($this->ok) {
	$this->{data} = $this->DB()->fetch($this->{type},$this->{id}); 
    }
    return $this->{data};
}

# unload restores the object to an unloaded state - should force a reload from the DB

sub unload {
    my $this = shift;
    delete $this->{status};
    delete $this->{children};
    delete $this->{data} if ($this->{id});
}

# permissions
# op = read, write, update, insert, delete
# column is optional

sub approve {
    my ($this,$op,$col) = @_;
    if ($col) {
	# can we do $op on column $col ?
	# op should be read or write
	my $maplevel = $this->DB()->{map}->get_column_attr($this->{type},$col,$op);
	return $maplevel <= $this->DB()->level;
    }
    else {
	# can we do $op on this table?
	if ($op eq "write") {
	    # should be insert or update for table-level operations
	    $op = $this->id ? "insert" : "update";
	}
	return $this->DB()->approve($op,$this->{type},$this->{data});
    }
}

# modify database directly

sub insert {
    my $this = shift;
    my ($force) = @_;
    my $type = $this->type;
    my @err;
    if (! $type) {
	push @err, "Undefined object type.";
    }
    my $data = scalar @_ > 2 ? {@_} : $this->{data}; # deprecated
    if ($data->{$this->key()}) {
	# hm... object already seems to have an identity
	push @err, "cannot insert object that already has a record";
    }
    push @err, $this->validate();
    if (@err > 0) {
	if ($force) {
	    $this->warn(@err);
	}
	else {
	    $this->error(@err);
	    return undef;
	}
    }
    $this->{id} = $this->DB()->insert($type,$data);
    if ($this->{id}) {
	# successful insert; update our data with the id
	$this->{data}{$this->key()} = $this->{id};
	$this->{dirty} = 0;
    }
    return $this->{id};
}

sub update {
    my $this = shift;
    my ($force) = @_;
    my $type = $this->type;
    my @err;
    if (! $type) {
	push @err, "Undefined object type.";
    }
    my $data = scalar @_ > 2 ? {@_} : $this->{data}; # deprecated
    push @err, $this->validate();
    if (@err > 0) {
	if ($force) {
	    $this->warn(@err);
	}
	else {
	    $this->error(@err);
	    return undef;
	}
    }
    # update record
    if ($this->dirty()) {
	if ($this->DB()->update($type,$data)) {
	    # error - failed to force?
	    return 0;
	}
	$this->{dirty} = 0;
	return 1;   # record changed
    }
    return -1;   # no changes (not an error)
}

sub action {
    my $this = shift;
    return $this->id() ? "update" : "insert";
}

sub save {
    my ($this,$force) = @_;
    if (ref $this->{data} ne "HASH") {
	$this->error("No $this->{type} data to save.");
	return undef;
    }
    my $action = $this->action;
    return $this->$action($force);
}

# force actions - validation generates warnings, not errors

sub force_insert {
    my $this = shift;
    return $this->insert(1);
}

sub force_update {
    my $this = shift;
    return $this->update(1);
}

sub force_save {
    my ($this,%opt) = @_;
    return $this->save(1);
}

sub force_delete {
    my ($this,%opt) = @_;
    return $this->delete(1);
}

# misc DB ops

sub validate {
    my $this = shift;
    return ($msg{"no data"}) if (ref $this->{data} ne "HASH");
    my @err = ($this->action eq "update") ?
	$this->DB->validate_record_update($this->{type},$this->{data}) :
	$this->DB->validate_record_insert($this->{type},$this->{data});
    #if (@err > 0) { $this->error(join("; ",@err)) }; # already logged in insert/update
    return @err;
}

sub delete {
    my ($this,$skip_check) = @_;
    if ($this->ok) {
	return $this->DB()->trash_r($this->{type},$this->{id},$skip_check);
    }
    return undef;
}

# copy creates a copy of the object's record, and writes it to the database
# The copy can optionally be modified using the data passed in %newdata.
# The object itself is unaffected.

sub copy {
    my ($this,%newdata) = @_;
    if ($this->ok) {
	my %data = %{$this->{data}};
	foreach my $key (keys %newdata) { $data{$key} = $newdata{$key}; }
	my $key = $this->DB()->get_key($this->{type});
	delete $data{$key};
	return $this->DB()->insert($this->{type},\%data);
    }
    $this->error("cannot copy a non-existent $this->{type}");
    return undef;
}

# clone changes the current object to be a copy of itself.  The copy
# is not yet saved.

sub clone {
    my $this = shift;
    my $data = $this->{data};
    my $key = $this->DB()->get_key($this->{type});
    delete $data->{$key};
    $this->{id} = undef;
}

#=== FORMS

# make: create a basic record

sub make {
    my $this = shift;
    my $type = $this->type;
    return $this->error("Undefined object type.") if (! $type);
    return $this->DB()->make(table=>$type,@_);
}

# edit: edit basic record

sub edit {
    my $this = shift;
    if ($this->ok) {
	return $this->DB()->make(table=>$this->{type},record=>$this->{id},@_);
    }
    return $this->show_diagnostics("error","html");
}

# input_record

sub input_record {
    my ($this,$opt) = @_;
    my $action;
    if ($opt->{data} && $opt->{data}{evt_date_id}) {
	$action = "update";
    }
    elsif ($this->id) {
	$action = "update";
    }
    else {
	$action = "insert";
    }
    $this->DB()->set_action($action);
    return $this->DB()->input_record({table=>$this->{type},
				      data=>$opt->{data} || $this->{data},
				      hide=>$opt->{hide},
				      show=>$opt->{show},
				      simplename=>$opt->{simplename},
				  });
}

# process forms

sub do_make {
    my $this = shift;
    return $this->DB()->do();
}

sub do_edit {
    my $this = shift;
    return $this->DB()->do();
}

# get child lists

sub get_children {
    my ($this,@child) = @_;
    my %child;
    if ($this->ok) {
	scalar @child > 0 or
	    @child = $this->DB()->{map}->get_children($this->{type});
	foreach my $ch (@child) {
	    my $list = new ExSite::ObjectList(type=>$ch);
	    my @ref = $this->DB()->{map}->get_reference_column($ch,$this->{type},1);
	    my $ref = shift @ref;
	    my $chkey = $this->DB()->{map}->get_table_attr($ch,"key");
	    $list->load({$ref=>$this->{id}},$chkey);
	    if (@ref > 0) {
		# looks like record has multiple reference columns
		while ($ref = shift @ref) {
		    $list->loadmore({$ref=>$this->{id}});
		}
		$list->sort($chkey);
	    }
	    $child{$ch} = $list;
	}
    }
    return wantarray ? %child : \%child;
}

sub load_children {
    my ($this,@child) = @_;
    if (@child > 0) {
	my @unloaded_child;
	foreach my $c (@child) { 
	    if (! exists $this->{children}{$c}) {
		push @unloaded_child, $c;
	    }
	}
	if (scalar @unloaded_child) {
	    my %children = $this->get_children(@unloaded_child);
	    foreach my $c (keys %children) {
		$this->{children}{$c} = $children{$c};
	    }
	}
    }
    else {
	$this->{children} = $this->get_children();
    }
    return wantarray ? %{$this->{children}} : $this->{children};
}

sub get_child {
    my ($this,$type) = @_;
    my $list = new ExSite::ObjectList(type=>$type);
    my @ref = $this->DB()->{map}->get_reference_column($type,$this->{type},1);
    my $ref = shift @ref;
    my $chkey = $this->DB()->{map}->get_table_attr($type,"key");
    $list->load({$ref=>$this->{id}},$chkey);
    if (@ref > 0) {
	# looks like record has multiple reference columns
	while ($ref = shift @ref) {
	    $list->loadmore({$ref=>$this->{id}});
	}
	$list->sort($chkey);
    }
    return $list;
#    my $children = $this->load_children($type);
#    return $children->{$type};
}

sub load_child {
    my ($this,$type) = @_;
    if (! exists $this->{children}{$type}) {
	$this->{children}{$type} = $this->get_child($type);
    }
    return $this->{children}{$type};
}

sub child_loaded {
    my ($this,$type) = @_;
    if (! exists $this->{children}{$type}) {
	$this->load_child($type);
    }
    return $this->{children}{$type};
}

1;

=pod

=head1 ExSite::Object

Generic, multi-purpse CMS objects are data objects that an end-user can be
expected to create, edit, delete, and display in reports of one kind or
another.  This class defines a useful set of core behaviours for objects 
that fit this description.

This class can be inherited by specialized objects that can override
the core beheviours to specify custom forms, reports, data handling, etc.

=head2 Attributes

Each Object has two important attributes, B<type> and B<id>.  In the
generic Object, these are taken to be a table name and record ID, and
are used as an "address" to look up the data, and also as raw material for
composing a name (label) for the object.  The type can be treated as a
pseudo-class, since two objects of different types will have slightly
different behaviours, as specified by the lower-level database record
handling tools.

Each Object has a B<data> attribute, consisting of the actual database
record that the Object represents.  This data is only loaded when needed.
You can pass an actual datahash in when instantiating the record, if you
have already loaded it another way.

=head1 Methods

=head2 new(%opt)

Instantiate a new object; the type and id can be passed in the C<%opt> hash.

=head2 setup($type,$id)

Transform the object so that it represents a different record.

=head2 type()

Returns the object's type (by default, it's table).

=head2 id($id)

Returns the object's ID.  An object normally only has an ID if it was
fetched from the database.  An object that has data, but no ID, is a
working object that must be saved for it to be asigned an ID.

=head2 name()

Returns a human-friendly description of the object.

=head2 ok()

Returns true if the object's type and ID are defined.

=head2 key()

Returns the name of the key in the objects datahash that looks up the
objects ID.

=head2 get($attr)

Returns the value of the named attribute (eg. C<type>, C<id>, C<data>,
...); if no attribute name is given, returns the Object's
datahash.

=head2 getdata($key)

Returns the value of the named key in the object's datahash.

=head2 setdata($key,$val)

Sets the value of the named key in the object's datahash.  Only sets
the value in the object; to make this change permanent, the object
must be saved.

=head2 showdata($key)

Formats the value of the named key in the object's datahash as HTML.
Also performs access-control checks to ensure the user is permitted to
view the data.

=head2 dirty()

Returns true (1) if the object's data has been modified and is out of
sync with the saved data.  Returns false (0) if the object matches the 
saved data.

=head2 show()

Formats the entire Object as an HTML report.

=head2 load($data)

Fetches the Object's data.  If C<$data> is passed, it is used as the
object's datahash;  otherwise, the data is fetched from the database.

=head2 insert(%data)

Creates a new record, using C<%data>.  If no data is passed, the
Object's datahash is used.

=head2 update(%data)

Updates an existing record, using C<%data>.  If no data is passed, the
Object's datahash is used.

=head2 save()

Writes the objects datahash out to the database, using either the insert()
or update() method, as appropriate.

=head2 delete()

Moves the record represented by the Object to the trash.

=head2 copy()

Creates a new record that is a copy of the record represented
by the Object (except for the record ID).

=head2 make()

Generates an HTML form that allows the user to enter data for a new
object/record.

=head2 edit()

Generates an HTML form that allows the user to edit the data of the
current Object.

=head2 do_make()

Process the form generated by C<make()>.

=head2 do_edit()

Process the form generated by C<edit()>.

=cut

