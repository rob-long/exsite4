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

=pod

=head1 ExSite::ObjectList

This class represents a list of ExSite::Object objects (in most cases,
this is a list of datahashes).  It is typically used to represent a
set of records from the database.  Common list-handling methods are
supported, such as count, push, pop, shift, and unshift.

Standalone Objects can be extracted from the ObjectList using a
variety of methods.

The ObjectList has an C<index> attribute, which points to a particular
item in the list.  When this is defined, the ObjectList also has the
characteristics of an individual Object, and inherits all the methods
of the Object class for that purpose.  The C<index> can be used to
address particular list items, or to iterate through the list.  That
means the following operations are equivalent:

    # edit the 6th element of the list (index 5)
    $list->select(5);
    my $obj = $list->newobj();
    print $obj->edit();

    # ditto
    $list->select(5);
    print $list->edit();

The C<index> is reset when certain list-altering operations are
performed.

=head1 Define an ObjectList

=head2 new(%opt)

Instantiates a new ObjectList.  Attributes that can be defined in the
C<%opt> hash include B<type> (usually a table whose data is
represented in the list), B<list> (an array of datahashes to
initialize the object with), and B<match> (a match hash to look up
data to initialize the object with).

=head2 load($match)

Fetch a list of datahashes from the database to fill the ObjectList.
They are fetched from the table defined by the B<type> attribute,
according to the selection criteria in the C<$match> hash.

=head1 List Contents and Data

=head2 count()

Returns the number of items in the list.

=head2 index($i)

Gets the current index pointer into the list, as an integer.
(First item is at index 0.)

=head2 select($i)

Sets the current index pointer into the list.

=head2 reset()

Clears the index pointer.

=head2 setlist(@list)

Sets the whole list to the values in C<@list>.  Resets the C<index>.

=head2 getlist()

Returns the list as an array of datahashes.

=head1 List Operations

=head2 push(@list)

Pushes C<@list> onto the end of the ObjectList.

=head2 pop()

Pops the last item in the list, and returns it as an Object.

=head2 shift()

Shifts the first item off the list, and returns it as an Object.

=head2 unshift(@list)

Pushes C<@list> onto the front of the ObjectList.

=head2 cut()

Cuts the current element (the one that is pointed to by C<index>)
out of the list, and splices the rest of the list together.

=head2 next()

Advances the C<index> pointer to the next item in the list, and returns
that item as an Object.  If at the end of the list, returns C<undef>
and resets the C<index> pointer.  Subsequent calls to C<next()> will then
begin iterating from the start of the list again.

=head1 List Order

=head2 sort(@keys)

Re-orders the list in order of the given keys.  The keys are hash keys
of the individual list elements, and the sort order is determined by
the values under those keys.  If more than one key is given, then the
list elements are sorted in that key order (ie. by key1 first, then by
key2 if key1 is identical, etc.)

=head2 reverse()

Reverses the order of the list.

=head2 hash($key)

Returns a hash of the list elements, indexed by C<$key>.  This is 
analogous to C<ExSite::Misc::keywise()>, except that the hash values
are C<ExSite::Object>s.

=head1 Displaying Lists

=head2 show(%opt)

Returns a formatted HTML report of the items in the list.  By default 
this is built using C<ExSite::Report::report>.

=cut

package ExSite::ObjectList;

use strict;
use ExSite::Config;
#use ExSite::Base;
use ExSite::Form;
use ExSite::Object;
use ExSite::ReportBuilder;

use vars qw(@ISA);
@ISA = qw(ExSite::Object);

#=== OBJECT CREATION

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
    if (!$obj->{list}) { $obj->{list} = []; }
    if (!$obj->{type}) { $obj->{type} = $obj->my_type(); }
    $obj->load($this->{match}) if ($obj->{match} && $obj->{type});
    return $obj;
}

# create an object from a list item

sub newobj {
    my ($this,$data) = @_;
    if (! $data) { $data = $this->{data}; }
    my $type = $this->type;
    my $class = $this->{class} || $this->DB->{map}->get_table_attr($type,"class");
    my $obj;
    if ($class) {
	if ($class eq "ExSite::Content") {
	    # subtype is unknown; let Content class figure it out
	    my $c = new ExSite::Content();  # assume it's already loaded
	    return $c->get_content_obj($data);
	}
	else {
	    # object has a specialized class
	    $class =~ /^((ExSite|Modules)::.*)$/;
	    my $safe_class = $1;
	    if (eval "require $safe_class") {
		$obj = eval "new $safe_class(type=>\$type,data=>\$data)";
		return $obj if ($obj);
		$this->error("$class: $@");
	    }
	    else {
		$this->error("$class: $@");
	    }
	}
    }
    if (! $obj) {
	# setup as a generic object
	$obj = new ExSite::Object(type=>$this->{type},data=>$data);
    }
    return $obj;
}

#=== DATA

sub index {
    my ($this,$i) = @_;
    return $this->{index};
}

sub count {
    my $this = shift;
    return scalar @{$this->{list}};
}

sub setlist {
    my $this = shift;
    $this->reset;
    $this->{list} = \@_;
}

sub getlist {
    my $this = shift;
    return wantarray ? @{$this->{list}} : $this->{list};
}

sub select {
    my ($this,$index) = @_;
    return undef if ($index !~ /^\d$/ || $index >= $this->count || $index < 0);
    $this->{index} = $index;
    $this->{data} = $this->{list}[$index];
    return $index;
}

sub reset {
    my $this = shift;
    $this->{index} = -1;
    $this->{data} = undef;
}

#=== LIST FUNCS

sub push {
    my $this = shift;
    push @{$this->{list}}, @_;
}

# warning: pop is destructive
sub pop {
    my $this = shift;
    if ($this->{data} eq $this->{list}[-1]) { $this->{data} = undef; }
    my $dat = pop @{$this->{list}};
    return $dat ? $this->newobj($dat) : undef;

    ### reset??
}

sub shift {
    my $this = shift;
    if ($this->{data} eq $this->{list}[0]) { $this->{data} = undef; }
    my $dat = shift @{$this->{list}};
    return $dat ? $this->newobj($dat) : undef;
    ### reset??
}

# warning: unshift is destructive
sub unshift {
    my $this = shift;
    unshift @{$this->{list}}, @_;
    ### reset??
}

# cut the current element out of the list
sub cut {
    my $this = shift;
    if ($this->{data}) {
	splice(@{$this->{list}},$this->{index},1);
	$this->reset;
    }
}

sub next {
    my $this = shift;
    my $n = $this->count();
    if ($n <= 0) {
	# empty list
	return undef;
    }
    else {
	if (! defined $this->{index}) {
	    # first time iteration
	    $this->{index} = 0;
	}
	else {
	    # goto next item in list
	    $this->{index}++;
	    if ($this->{index} >= $n) {
		$this->reset();
		return undef;
	    }
	}
    }
    $this->{data} = $this->{list}[$this->{index}];
    return $this->newobj();
}

sub previous {
    my $this = shift;
    my $n = $this->count();
    if ($n <= 0) {
	# empty list
	return undef;
    }
    else {
	if (! $this->{index}) {
	    # first time iteration, or beginning of list
	    return undef;
	}
	else {
	    # goto previous item in list
	    $this->{index}--;
	    if ($this->{index} < 0) {
		$this->reset();
		return undef;
	    }
	}
    }
    $this->{data} = $this->{list}[$this->{index}];
    return $this->newobj();
}

sub first {
    my $this = shift;
    my $n = $this->count();
    if ($n <= 0) {
	# empty list
	return undef;
    }
    $this->{index} = 0;
    $this->{data} = $this->{list}[$this->{index}];
    return $this->newobj();
}

sub last {
    my $this = shift;
    my $n = $this->count();
    if ($n <= 0) {
	# empty list
	return undef;
    }
    $this->{index} = $n-1;
    $this->{data} = $this->{list}[$this->{index}];
    return $this->newobj();
}

#=== ORDER

sub sort {
    my $this = shift;
    my @keys = @_ > 0 ? @_ : $this->DB->primary_column($this->{type});
    $this->setlist($this->DB->sort_rows($this->{type},
					  $this->{list},
					  @keys)
		   );
    return;
}

sub reverse {
    my $this = shift;
    $this->setlist(reverse @{$this->{list}});
}

sub hash {
    my ($this,$key) = @_;
    my %h;
    foreach my $i (@{$this->{list}}) {
	$h{$i->{$key}} = $this->newobj($i);
    }
    return wantarray ? %h : \%h;
}

sub array_by_key {
    my ($this,$key) = @_;
    my @k;
    foreach my $i (@{$this->{list}}) {
	push @k, $i->{$key};
    }
    return wantarray ? @k : \@k;
}

#=== DISPLAY

sub show {
    my ($this,%opt) = @_;
    my $type = $this->type;
    return $this->error("Undefined object type.") if (! $type);
    return $this->report(%opt);
}

sub report {
    my ($this,%opt) = @_;
    my $out;
    my $ui = &get_obj("UI");
    my $table = $this->{type};

    my $title = $opt{title} || $this->DB->{map}->table_title($table,1);
    my $r = new ExSite::ReportBuilder(
				      title=>$title,
				      foot=>$opt{foot},
				      tools=>$opt{tools},
				      nodata=>"No $title found.",
				      dynamic=>1,
				      );
    my $ml = new ExSite::ML;
    my $mod = $share{Module};

    # fetch the columns to appear in this report

    my @colmap;
    if (ref $opt{columns} eq "ARRAY") {
	# columns to report are provided by the calling agent
	foreach my $col (@{$opt{columns}}) {
	    my %colmap = $this->DB->{map}->get_column($table,$col);
	    push @colmap, \%colmap;
	}
    }
    else {
	# select default set of columns to display
	my $ncol = $this->DB->{map}->get_ncol($table);
	for (my $icol = 0; $icol < $ncol; $icol++) {
	    my %colmap = $this->DB->{map}->get_column($table,$icol);
	    # "key" columns are _ALWAYS_ included
	    if ($colmap{display} =~ /key|brief/) {
		push @colmap, \%colmap;
	    }
	}
    }
    if (@colmap == 0) {
	return $this->error("No columns in $table can be displayed.");
    }
    my @head;
    foreach my $col (@colmap) {
	push @head, $col->{label};
    }
    push @head, "Options";
    $r->headers(\@head);

    # report data

    my @data;
    my $key = $this->DB->get_key($table);
    my $tabletitle = $this->DB->title($table);
    while (my $obj = $this->next()) {
	my @rowdata;
	foreach my $col (@colmap) {
	    push @rowdata, $this->DB->show_data($table,$col->{column},
						$obj->getdata($col->{column}),
						$obj->getdata($key));
	}
	if ($mod) {
	    my $objurl = $mod->link(__path=>{ module=> [ "ObjectBrowser" ],
					      Object => [ $table, $obj->id ] }, ob=>undef);
	    push @rowdata, $ui->FATool("view",label=>"inspect $tabletitle ".$obj->id,url=>$objurl);
	}
	$r->push(@rowdata);
    }

    # finally, the optional insert link

    if ($mod) {
	my $newurl = $mod->link(__path=>{ module=> [ "ObjectBrowser" ],
					  Object => [ $table ] }, 
				ob=>"new");
	$r->tools($ui->FATool("new",label=>"add new $tabletitle",url=>$newurl,tone=>"good"));
    }
    return $r->make;
}

#=== DB

# populate the list from a database query

sub load {
    my $this = shift;
    my $type = $this->type;
    if (! $type) { $this->error("Undefined object list type."); return 0; }
    $this->reset();
    $this->{list} = $this->DB->fetch_match($type,@_);
    return $this->count();
}

# append to the current list with another query

sub loadmore {
    my $this = shift;
    my $type = $this->type;
    if (! $type) { $this->error("Undefined object list type."); return 0; }
    push @{$this->{list}}, $this->DB->fetch_match($type,@_);
    return $this->count();
}

sub unload {
    my $this = shift;
    delete $this->{status};
    delete $this->{data};
    delete $this->{children};
    delete $this->{list};
    delete $this->{index};
}

1;
