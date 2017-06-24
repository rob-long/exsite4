#!/usr/bin/perl
#----------------------------------------------------------------------------
#
#   Copyright 2014 Exware Solutions, Inc.  http://www.exware.com
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

package ExSite::Group;

use strict;
use ExSite::Config;
use ExSite::Base;
use ExSite::Form;
use ExSite::Misc;
use ExSite::Object;
use ExSite::ObjectList;

use vars qw(@ISA);
@ISA = qw(ExSite::Object);

sub my_type { "usergroup"; }

sub name {
    my $this = shift;
    return $this->getdata("name");
}

sub gid {
    my $this = shift;
    return $this->id;
}

sub show {
    my ($this,%opt) = @_;
    my $stat = $this->run_handler("Group_show",%opt);
    return $stat;
}

sub content_keys {
    my $this = shift;
    my $c = new ExSite::Content();
    my $all_keys = $c->all_keys();
    if (exists $all_keys->{gid}{$this->id}) {
	return wantarray ? 
	    @{$all_keys->{gid}{$this->id}} : 
	    $all_keys->{gid}{$this->id};
    }
    return ();
}

sub group_keys {
    my $this = shift;
    my @k = $share{DB}->fetch_match("groupkey",{gid=>$this->id});
    my $list = new ExSite::ObjectList(type=>"groupkey",list=>\@k);
    return $list;
}

sub users {
    my $this = shift;
    my @users = $share{DB}->get_query("users in group",$this->id);
    my $userlist = new ExSite::ObjectList(type=>"user",list=>\@users);
    return $userlist;
}

sub count_users {
    my $this = shift;
    my $userlist = $this->users;
    return $userlist->count;
}

sub has_user {
    my ($this,$user) = @_;
    if (ref $user =~ /^User$/) {
	return $this->uid($user->id)->defined;
    }
    elsif ($user =~ /^\d$/) {
	return $this->uid($user)->defined;
    }
    elsif ($user =~ /\@/) {
	return $this->email($user)->defined;
    }
    else {
	return $this->user_login($user)->defined;
    }
}

sub get_user {
    my ($this,$key,$val) = @_;
    my $users = $this->users();
    my %u = $users->hash($key);
    return $u{$val};
}

sub uid {
    my ($this,$uid) = @_;
    return $this->get_user($config{auth}{user_id_column},$uid) if $uid;
    return undef;
}

sub user_login {
    my ($this,$login) = @_;
    return $this->get_user($config{auth}{user_login_column},$login) if $login;
    return undef;
}

sub user_email {
    my ($this,$email) = @_;
    return $this->get_user($config{auth}{user_email_column},$email) if $email;
    return undef;
}

sub user_emails {
    my ($this) = @_;
    my $users = $this->users();
    my %email = $users->hash($config{auth}{user_email_column});
    # don't include entries for users with no email addr
    delete $email{undef};
    delete $email{''};
    return keys %email;
}

1;

