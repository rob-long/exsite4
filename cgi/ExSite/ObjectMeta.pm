#!/usr/bin/perl
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

package ExSite::ObjectMeta;

use strict;
use ExSite::Config;
use ExSite::Object;
use ExSite::Misc qw(&html_escape);
#use ExSite::Attribute;

use vars qw(@ISA);
@ISA = qw(ExSite::Object);

sub meta {
    my $this = shift;
    return $this->{meta} if ($this->{meta});
    my $class = $this->{metaclass} || "ExSite::Attribute";

    if (eval "require $class") {
	# instantiate the module
	$this->{meta} = $class->new($this->{type},$this->{id});
    }
    else {
	$this->fatal("ObjectMeta: failed to load $class: $@");
    }
    return $this->{meta};
}

sub setup {
    my $this = shift;
    $this->SUPER::setup(@_);
    # setup metadata
    if ($this->{meta}) {
	$this->meta()->setup($this->{type},$this->{id});
    }
    return;
}

# wrappers for Attribute methods

sub meta_get {
    my ($this,$key) = @_;
    return $this->meta()->get($key);
}

sub meta_set {
    my ($this,$key,$val) = @_;
    # we use the _nosave variant to be more efficient, but we have to
    # remember to save when done
    if ($this->defined) {
	return $this->meta()->set_nosave($key,$val);
    }
    return 0;
}

sub meta_show {
    my ($this,$key) = @_;
    return $this->meta()->showdata($key);
}

sub meta_allowed {
    my ($this,$name) = @_;
    return $name ?
	$this->meta()->is_allowed($name) :
	$this->meta()->get_allowed();
}

sub meta_declare {
    my ($this,$name,$datatype) = @_;
    $datatype = "string" if (! $datatype);
    return $this->meta()->add_allowed($name,$datatype);
}

sub meta_undeclare {
    my ($this,$name) = @_;
    return $this->meta()->remove_allowed($name);
}

#=== DISPLAY

sub show {
    my ($this,%opt) = @_;
    if ($this->ok) {
	if (defined $this->meta()->get()) {

	    # add metadata to report footer

	    my @head = sort $this->meta_allowed();
	    my @data;
	    foreach my $h (@head) { push @data, $this->meta_show($h); }
	    my $r = new ExSite::ReportBuilder(title=>"Metadata for ".$this->name(),
					      headers=>\@head,
					      data=>\@data,
					      );
	    $opt{foot} = $r->make();
	}
    }
    return $this->SUPER::show(%opt);
}

#=== DB

# modify database directly

sub insert {
    my $this = shift;
    my $id = $this->SUPER::insert(@_);
    if ($id) {
	$this->meta()->id($id);
	$this->meta()->save();
    }
    return $id;
}

sub update {
    my $this = shift;
    my $stat = $this->SUPER::update(@_);
    $this->meta()->save();
    return $stat;
}

sub force_insert {
    my $this = shift;
    my $id = $this->SUPER::force_insert(@_);
    if ($id) {
	$this->meta()->id($id);
	$this->meta()->save();
    }
    return $id;
}

sub force_update {
    my $this = shift;
    my $stat = $this->SUPER::force_update(@_);
    $this->meta()->save();
    return $stat;
}

# misc DB ops

sub delete {
    my $this = shift;
    if ($this->ok) {
	# we will move the data and metadata to trash in 2 separate operations
	$this->DB()->trash_r($this->{type},$this->{id});
	$this->meta()->clear();
	return 1;
    }
    return 0;
}

sub meta_delete {
    my $this = shift;
    if ($this->ok) {
	# delete meta data only
	$this->meta()->clear();
	return 1;
    }
    return 0;
}

sub copy {
    my $this = shift;

    my $id = $this->SUPER::copy(@_);
    if ($id) {
	$this->meta()->copy($id);
	return $id;
    }
    return 0;
}

#=== FORMS

# editmeta: edit record and its metadata

sub editmeta { 
    my ($this,%opt) = @_;
    if ($this->ok) {
	$this->load();
	$this->meta()->load();
	$this->DB()->set_action($this->action());  # insert/update
	$this->DB()->form(%opt);
	$this->DB()->input_record({table=>$this->{type},
				   record=>$this->{id},
				   hide=>$opt{hide},
				   show=>$opt{show},
				   data=>$this->get(),
				   simplename=>1,
				  });

	my @metafields = $this->meta()->get_allowed();
	if (@metafields == 0) {
	    my %meta = $this->meta()->get_all();
	    @metafields = keys %meta;
	}
	foreach my $key (sort @metafields) {
#	    my $writeaccess = $this->meta()->get_map_info("write");
#	    next if ($writeaccess && $writeaccess > $share{DB}->level());
	    $this->meta()->input(undef,$key);
	}
	return $this->DB()->form()->make;
    }
    return $this->show_diagnostics("error","html");
}

sub do_editmeta { my $this = shift; $this->do_edit; } # ignores meta fields

1;

=pod

=head1 ExSite::ObjectMeta

This is C<ExSite::Object>, extended to include meta-data and notes.

In addition to the main database record that the Object represents, an
Object can also have meta-data.  Meta-data are essentially key-value
pairs that are attached to the object's data record.  They are handled
by the C<ExSite::Attribute> class, although this class can be
inherited to change this logic.  We also provide convenience methods
to fetch, display, and modify the meta-data that is attached to a data
record.

=head1 Methods

=head2 meta_get($key)

Returns the value of the named key in the objects metadata.

=head2 meta_set($key,$value)

Sets the value of the named key in the object's metadata.  Only sets
the value in the object; to make this change permanent, the object
must be saved.

=head2 meta_show($key)

Formats the value of the named key in the object's metadata as HTML.

=head2 meta_allowed($key)

If C<$key> is given, returns a true/false value indicating whether that 
meta-data key is accepted.  Otherwise it returns a list of all allowed 
metadata keys for this type of object.

=head2 meta_declare($key,$datatype)

Add another key to the list of allowed meta data keys.  Only system 
adminsitrators may do this.

=head2 meta_undeclare($key)

Remove a key from the list of allowed meta data keys.  Also removes
any defined meta data under that key.  Only system adminsitrators may
do this.

=head2 show(%opt)

Returns an HTML-formatted report of the object and its metadata.

=head2 insert()

Creates a new object record, along with its metadata records.  This is
normally called from C<ExSite::Object::save()>, which is the
recommended usage.

=head2 update(%data)

Updates an existing object record, along with its metadata records.
This is normally called from C<ExSite::Object::save()>, which is the
recommended usage.

=head2 delete()

Moves the record represented by the Object, plus its descendant
records, and all of its meta data to the trash.  Does not move meta
data of the descendant records.

Object data and meta data are moved to trash in two separate operations.
To restore these data, you must restore each record group separately.

=head2 meta_delete()

Only deletes the meta data associated with the object, but leaves the
Object data intact.

=head2 copy()

Creates a new record and meta data that are a copy of the Object's.
The id of the new Object is returned, but the current Object remains
as it was.

=head2 editmeta()

Generates an HTML form that allows the user to edit the data of the
current Object as well as any defined metadata.

The meta data fields that will be made available for editing are
either the complete list of allowed meta data, or the existing set of
defined meta data.

=head2 do_editmeta()

Process the form generated by C<editmeta()>.

=cut

