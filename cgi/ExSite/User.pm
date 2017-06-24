#!/usr/bin/perl
#----------------------------------------------------------------------------
#
#   Copyright 2001-2014 Exware Solutions, Inc.  http://www.exware.com
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
#
#   User.pm : manage user identities and permissions via an Object-style 
#             interface
#
#----------------------------------------------------------------------------

package ExSite::User;

use strict;
use ExSite::Config;
use ExSite::Base;
use ExSite::Form;
use ExSite::Misc;
use ExSite::Object;
use ExSite::ObjectList;

use vars qw(@ISA);
@ISA = qw(ExSite::Object);

sub my_type { return $config{auth}{user_table} || "user"; }

sub setup {
    my ($this,%opt) = @_;
    if (scalar keys %opt == 0) {
	# null setup - try to setup currently-logged-in user
	$opt{data} = $share{DB}->my_user_record();
    }
    return $this->SUPER::setup(%opt);
}

sub uid {
    my $this = shift;
    return $this->id;
}

sub name {
    my $this = shift;
    if ($this->loaded) {
	return $this->DB()->user_name($this->get());
    }
    return "[nobody]";
}

sub email {
    my $this = shift;
    return $this->getdata($config{auth}{user_email_column});
}

# login returns the login ID; log_in actually logs this user in

sub login {
    my $this = shift;
    return $this->getdata($config{auth}{user_login_column});
}

sub log_in {
    my ($this,$remember) = @_;
    return $share{DB}->do_login($this->get(),$remember);
}

# show : display a user profile - this is done by a custom handler

sub show {
    my ($this,%opt) = @_;
    my $stat = $this->run_handler("User_show",%opt);
    return $stat;
}

sub validate {
    my $this = shift;
    return ($msg{"no data"}) if (ref $this->{data} ne "HASH");
    my $db = $share{DB};
    my @err;
    my $conf = $config{auth};
    my $udata = $this->get();

    # check the access level
    my $mylevel = $db->level;
    if ($mylevel < 8 && $udata->{$conf->{user_access_column}} >= $mylevel) {
	push @err, "You cannot setup or modify a user account that has a higher access level than your own.";
	return @err;
    }

    # validate the password

    if (! $this->id) {
	# this is a new user - validate password
	my $stat = $db->validate_password(
	    $udata->{$conf->{user_pwd_column}},
	    $udata->{$conf->{user_login_column}},
	    $udata->{$conf->{user_access_column}},
	    );
	if ($stat) {
	    push @err, $stat;
	}
	else {
	    # assume that new user passwords are cleartext, so encode them
	    $udata->{$conf->{user_pwd_column}} = $db->encode_password($udata->{$conf->{user_pwd_column}});
	}
    }
    # else - do not edit/validate existing passwords, use set_password instead

    # ensure the login ID is unique

    my @u = $db->fetch_match($conf->{user_table}, { $conf->{user_login_column}=>$udata->{$conf->{user_login_column}} });
    foreach my $u ($db->fetch_match($conf->{user_table}, { $conf->{user_login_column}=>$udata->{$conf->{user_login_column}} })) {
	if ($u->{$conf->{user_uid_column}} != $this->id) {
	    push @err, "That $conf->{login_prompt} is already in use - please try another";
	    last;
	}
    }

    # standard validations
    push @err, $this->SUPER::validate();

    return @err;
}

sub set_password {
    my ($this,$password) = @_;
    my $db = $share{DB};
    if ($this->id) {
	my $err = $db->validate_password($password,$this->getdata($config{auth}{user_login_column}),$this->level);
	if ($err) {
	    return $this->error($err);
	}
	else {
	    $db->set_password($password,$this->id);
	    return "Password changed.";
	}
    }
    else {
	return $this->warn("Cannot set_password for a user that does not exist yet.");
    }
}

sub copy {
    my ($this,%newdata) = @_;
    if ($this->ok) {
	if ($newdata{$config{auth}{user_login_column}}) {
	    if ($share{DB}->count("user",{$config{auth}{user_login_column}=>$newdata{$config{auth}{user_login_column}}}) > 0) {
		$this->error("That login already exists.");
		return undef;
	    }
	}
	else {
	    $this->error("Cannot copy user without first setting a new login identity.");
	    return undef;
	}
    }
    return $this->SUPER::copy();
}

#-------------------
# access level tests

sub level {
    my $this = shift;
    return $this->getdata($config{auth}{user_access_column});
}

sub is_root {
    my $this = shift;
    return ($this->level >= $config{auth}{level}{root});
}

sub is_admin {
    my $this = shift;
    return ($this->level >= $config{auth}{level}{admin});
}

sub is_manager {
    my ($this,$site) = @_;
    my $level = $this->level;
    # false if insufficient level
    return 0 if ($level < $config{auth}{level}{manager});
    # true if a system admin
    return 1 if ($level >= $config{auth}{level}{admin});
    # otherwise, check for admin key
    my $section = $share{DB}->get_section($site);
    return $section->has_role($this->id);
}

sub is_executive {
    my ($this,$site) = @_;
    my $level = $this->level;
    if ($level >= $config{auth}{level}{executive}) {
	if ($site) {
	    my $section = $share{DB}->get_section($site);
	    return $section->has_role($this->id);
	}
	return 1;
    }
    return 0;
}

sub is_member {
    my ($this,$site,$user) = @_;
    return $share{DB}->is_member($site,$this->get());
}

sub is_user {
    my ($this,$site,$user) = @_;
    return $share{DB}->is_user($site,$this->get());
}

sub is_visitor {
    my ($this,$site) = @_;
    if ($this->level <= $config{auth}{level}{visitor}) {
	# yes, regardless of level
	return 1;
    }
    else {
	# is a visitor if not an executive
	return ! $this->is_executive($site);
    }
}

#-------------
# affiliations

# keys are permissions

sub keys {
    my $this = shift;
    my @key;
    # private keys
    my $all_keys = ExSite::Content->new()->all_keys();
    if (exists $all_keys->{uid}{$this->id}) {
	push @key, @{$all_keys->{uid}{$this->id}};
    }
    # group keys
    my $groups = $this->groups;
    $groups->reset;
    while (my $gr = $groups->next) {
	if (exists $all_keys->{gid}{$gr->id}) {
	    push @key, @{$all_keys->{gid}{$gr->id}};
	}
    }
    return new ExSite::ObjectList(type=>"content_key",list=>\@key);
}

# home is the section(s) the user belongs to
# in scalar mode, it returns the home site; in array mode, it returns
# the home site plus all keyed content nodes

sub home {
    my $this = shift;
    my @home;
    my $c = new ExSite::Content();
    push @home, $c->get_content_obj($this->getdata("section_id"));
    if (wantarray) {
	my @keys = $this->keys();
	my %done;
	# some keys grant, some revoke; make a list of content objs that
	# we have some kind of permission to
	foreach my $key (@keys) {
	    if (! $done{$key->{content_id}}) {
		my $kc = $c->get_content_obj($key->{content_id});
		if ($kc->has_role($this->id)) {
		    push @home, $kc;
		}
		$done{$key->{content_id}} = 1;
	    }
	}
	return @home;
    }
    else {
	return $home[0];
    }
}

# test for "ownership" of a site, ie. a key

sub owns {
    my ($this,$site) = @_;
    return $share{DB}->owns($site,$this->id);
}

sub groups {
    my ($this,$site) = @_;
    my @group = $share{DB}->get_query("user groups",$this->id);
    return new ExSite::ObjectList(type=>"usergroup",list=>\@group);
}

sub in_group {
    my ($this,$group) = @_;
    my $groups = $this->groups();
    return 0 if ($groups->count() == 0);
    return 1 if (! $group); # in a group, not specified which one
    my %grname = $groups->hash("name");
    my %grid = $groups->hash("gid");
    if (ref $group eq "HASH") {
	return exists $grid{$group->{gid}};
    }
    elsif ($group =~ /^\d+$/) {
	return exists $grid{$group};
    }
    else {
	# assume it is a group name
	return exists $grname{$group};
    }
}

#--------- permission checks ----------

sub allow {
    my ($this,$obj,$op,$col) = @_;
    if ($obj->isa("ExSite::Content")) {
	return $obj->allow($op,$this);
    }
    else {
	# not content; use DB map access controls; $col is optional
	return $obj->approve($op,$col);
    }
}

sub allow_view {
    my ($this,$obj) = @_;
    return $obj->allow_view($this);
}

sub deny {
    my ($this,$obj,$op) = @_;
    return ! $this->allow($obj,$op);
}

#-------- forms -----------

sub make {
    my $this = shift;
    return $share{DB}->make(
	table=>$config{auth}{user_table},
	simplename=>1,
	action=>&relink(),
	@_);
}

sub edit {
    my $this = shift;
    return $share{DB}->make(
	table=>$config{auth}{user_table},
	record=>$this->{id},
	simplename=>1,
	action=>&relink(),
	@_);
}

sub do_make {
    my $this = shift;
    my $input = new ExSite::Input();
    my $data = $input->post();
    my %u = $share{DB}->parse_parts(%$data);
    delete $u{action};
    $this->setup(data=>\%u);
    $this->set("dirty",1);
    if ($this->save()) {
	return "New user saved.";
    }
    else {
	return &ExSite::Config::show_diagnostics();
    }
}

sub do_edit {
    my $this = shift;
    my $input = new ExSite::Input();
    my $data = $input->post();
    my %u = $share{DB}->parse_parts(%$data);
    delete $u{action};
    $this->set("data",\%u);
    $this->set("dirty",1);
    if ($this->save()) {
	return "Saved user info.";
    }
    else {
	return &ExSite::Config::show_diagnostics();
    }
}

1;
