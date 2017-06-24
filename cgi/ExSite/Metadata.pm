package ExSite::Metadata;
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

use strict;
use ExSite::Config;
use ExSite::Form;
use ExSite::Misc;
use ExSite::Attribute;

use vars qw(@ISA);
@ISA = qw(ExSite::Attribute);

# create a metadata object, and tie it to a cnode

sub new {
    my ($this,$id) = @_;
    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;
#    $obj->{table} = "content";
    $obj->setup($id);
    return $obj;
}

# change record

sub setup {
    my ($this,$id) = @_;
    
    # metadata for this record
    $this->{loaded} = undef;
    $this->{raw} = undef;      # copy of metadata records
    $this->{data} = undef;     # attribute values
    $this->{dirty} = undef;    # flag changed metadata

    if (ref $id eq "HASH") {
	$this->{record} = $id;
	$this->{id} = $id->{$share{DB}{map}->get_table_attr($this->{table},"key")};
    }
    else {
	$this->{record} = undef;
	$this->{id} = $id;
    }
    $this->{attr_table} = "metadata";
    $this->{attr_id} = "metadata_id";
    $this->{idcol} = "id";
    $this->{table} = "content";
    $this->{id} = $id;
    return;
}

sub get_content {
    my $this = shift;
    if (! $this->{content}) {
	$this->{content} = $share{DB}->fetch("content",$this->{id});
    }
    return $this->{content};
}

sub get_content_obj {
    my $this = shift;
    if (! $this->{content_obj}) {
	my $obj = new ExSite::Content;
	$this->{content_obj} = $obj->get_content_obj($this->get_content);
    }
    return $this->{content_obj};
}

sub get_map_info {
    my ($this,$name,$mapkey) = @_;
    my $meta = $config{content}{metadata};
    my $c = $this->get_content_obj();
    if (exists $meta->{$c->subtype()}{$name}) {
	return $mapkey ? 
	    $meta->{$c->subtype()}{$name}{$mapkey} :
	    $meta->{$c->subtype()}{$name};
    }
    elsif ($config{content}{contextual_metadata}) {
	my $path = $c->content_path();
	my $cp = $path->last;
	while ($cp) {
	    my $cpid = $cp->id;
	    if (exists $meta->{$cpid} && exists $meta->{$cpid}{$c->subtype}) {
		return $mapkey ?
		    $meta->{$cpid}{$c->subtype}{$name}{$mapkey} :
		    $meta->{$cpid}{$c->subtype}{$name};
	    }
	    $cp = $path->previous;
	}
    }
    return undef;
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

sub load {
    my ($this) = @_;
    if (! $this->{loaded} && $this->ok) {
	$this->{record} = $share{DB}->fetch($this->{table},$this->{id})
	    or return;
	my $meta = (exists $share{Cache_metadata}) ?
	    $share{Cache_metadata}{$this->{id}} : 
	    $this->fetch_match({id=>$this->{id}});
	if (ref $meta eq "ARRAY" && scalar @$meta > 0) {
	    $this->{raw} = &keywise("name",$meta);
	    foreach my $attr (values %{$this->{raw}}) {
		$this->{data}{$attr->{name}} = $attr->{value};
	    }
	}
    	$this->{dirty} = undef;
	$this->{loaded} = 1;
	#$this->SUPER::load();
    }
}

sub load_orig {
    my ($this) = @_;
    if (! $this->{loaded} && $this->ok) {
	my @attr = $this->fetch_match({$this->{idcol}=>$this->{id}});
	$this->{raw} = &keywise("name",\@attr);
	foreach my $attr (values %{$this->{raw}}) {
	    $this->{data}{$attr->{name}} = $attr->{value};
	}
	$this->{dirty} = undef;
	$this->{loaded} = 1;
    }
}

sub load_allowed {
    my ($this) = @_;
    if (! $this->{allowed}) {
	my $meta = $config{content}{metadata};
	my $c = $this->get_content_obj();
	$this->{allowed} = { 
	    %{$meta->{_}},
	    %{$meta->{_DC}},
	};
	if (exists $meta->{$c->subtype}) {
	    # global metadata
	    foreach my $key (keys %{$meta->{$c->subtype}}) {
		$this->{allowed}{$key} = $meta->{$c->subtype}{$key};
	    }
	    # contextual metadata
	    if ($config{content}{contextual_metadata}) {
		my $path = $c->content_path();
		my $cp = $path->last;
		while ($cp) {
		    my $cpid = $cp->id;
		    if ($meta->{$cpid}) {
			foreach my $key (keys %{$meta->{$cpid}{$c->subtype}}) {
			    $this->{allowed}{$key} = $meta->{$cpid}{$c->subtype}{$key};
			}
			last;
		    }
		    $cp = $path->previous;
		}
	    }
	}
    }
}

sub get_allowed_sorted {
    my $this = shift;
    $this->load_allowed();
    # sort by rank if it exists, alphabetically otherwise
    my $by_rank;
    foreach my $key (keys %{$this->{allowed}}) {
	if (exists $this->{allowed}{$key}{rank}) {
	    $by_rank = 1; last;
	}
    }
    if ($by_rank) {
	foreach my $key (keys %{$this->{allowed}}) {
	    if (! exists $this->{allowed}{$key}{rank}) { 
		$this->{allowed}{$key}{rank} = 999;
	    }
	}
	return sort { $this->{allowed}{$a}{rank} <=> $this->{allowed}{$b}{rank} } $this->get_allowed();
    }
    return sort $this->get_allowed(); # alphabetical
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

sub add_allowed {
    my $this = shift;
    $this->error("metadata can only be added and removed through configuration files");
    return 0;
}

sub remove_allowed {
    my $this = shift;
    $this->error("metadata can only be added and removed through configuration files");
    return 0;
}

# copy one or all attributes to another record ID

sub copy { 
    my ($this,$id,$name) = @_;
    if ($this->ok) {
	my @keys = $name ? ($name) : keys %{$this->{data}};
	if (@keys > 0 && $id) {
	    my $m = new ExSite::Metadata($id);
	    foreach my $k (@keys) {
		$m->set_nosave($k,$this->get($k));
	    }
	    $m->save();
	}
    }
}

# DB accessors, for easier overloading

sub make_record {
    my ($this,$name,$value) = @_;
    return { 
	name=>$name, 
	value=>$value, 
	id=>$this->{id}, 
	};
}

sub fetch_match {
    my ($this,$match) = @_;
    return $share{DB}->fetch_match($this->{attr_table},$match);
}

sub insert {
    my ($this,$data) = @_;
    return $share{DB}->insert($this->{attr_table},$data);
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
				      { metadata_id=>$meta_id }
				      );
	}
    }
    return undef;
}

sub input_column {
    my ($this,%options) = @_;
    $options{table} = "metadata";
    $options{column} = "value";
    return $share{DB}->input_column(%options);
}

sub trash {
    my ($this,@data) = @_;
    my @trash;
    foreach my $meta (@data) {
	push @trash, "metadata", (ref $meta) eq "HASH" ? $meta->{cnodemeta_id} : $meta;
    }
    return $share{DB}->trash(@trash);
}

1;


