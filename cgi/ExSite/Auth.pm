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

package ExSite::Auth;

use strict;
use ExSite::Config;
use ExSite::Form;
use ExSite::Page;
use ExSite::Base;
use ExSite::Misc;
use ExSite::Util;
use ExSite::URI;
use ExSite::User;
use ExSite::Input;
use ExSite::Mail;
use ExSite::Time;
use ExSite::Crypt;
use Digest::MD5 qw(md5_hex);

our @ISA = qw(ExSite::Base);

#========================================================================

=pod

=head1 ExSite::Auth -- authentication and security tools

Authorization is performed before any standard operation on
the database, when the operation is performed by one of ExSite::DB's
descendant classes.  The authorization process has the following
steps:

=over 4

=item 1. identify - determine who the user claims to be

=item 2. lookup - determine whom we understand that username to represent

=item 3. authenticate - determine if the user's claim matches our knowledge

=item 4. authorize - grant a certain level of access to the database

=item 5. approve - approve a specific operation

=back

Each of the steps in the authorization process may be replaced with
a custom handler if the procedure differs from the default ExSite logic.

=head2 identify() - determine who the user claims to be

Determines the user's claimed identity (such as by checking the
identity cookie), and stores the result so that authorization methods
can check it.  This routine does not authenticate the user's identity
claim, and so is usually not called directly.

=head2 lookup() - look up the user to see if we know who they are

Consult our own database to see if we have a record corresponding to
this user's identity (determined from C<identify()>).  Returns the
user record in a hash, if found.  The default logic for looking up a
user record is to look up the login name, which implies that unique
login names are required.  Once this lookup has occurred, the
following identity query functions can be used:

=head2 my_name() - return the login name of the current user

=head2 my_uid() - return the primary key of the current user's record

=head2 my_gid() - return the primary key of the current user's group record

=head2 my_user_record() - return the user's identity hash

=head2 authenticate() - verify the user's identity claim

Returns true (1) if the user's identity matches the information
returned by lookup(), false (0) otherwise.  This serves as a simple
check that the user is logged in, and that their identity is valid.

=head2 authorize() - grant the user a specific level of access

Returns the user's access level.  Access level is a value of 0 or
higher.  0 corresponds to "nobody", or the general public.  Values of
1 or more correspond to authenticated users, with higher values giving
greater permissions to the database.  The maximum value is
C<$config{auth}-E<gt>{root_auth_level}>, which grants unrestricted
"super-user" access to the data.  (This level of access can be
dangerous, as it allows one to mess with sensitive data fields and
referential integrity.)

The default authorize routine assumes that the user's access level
is stored in the user table.  This value is simply returned without
any sanity checks.

=head2 approve() - approve a specific database operation

Usage: C<$db-E<gt>approve( OP, TABLE, RECORD );>

OP is a low-level database operation (one of "read", "update",
"insert", or "delete").  TABLE is the table that this operation is
being performed on. RECORD is the actual record datahash that this
operation is being performed on (only used for "update" and "delete").

The return value is true if the operation is permitted, or false if:

=over 4

=item * the user does not have permission to read or write to the table

=item * the user is referencing records owned by a different user or group.

=back

=cut

#----------------------------------------------------------------------
# identify : determine whom the user claims to be

sub identify {
    my ($this) = shift;
    my ($name,$pwd,$uid,$gid);
    my $stat = $this->run_handler("identify");
    my $access = 0;
    my $authtype = $config{auth}{type};
    if (defined $stat) {
	# application has its own identify algorithm
	($name,$pwd) = @$stat;
    }
    elsif ($authtype eq "cookie") {
	($name,$pwd) = split /:/, $cookie{$config{site}{identity_cookie}}, 2;
    }
    elsif ($authtype eq "crypt") {
	my $c = new ExSite::Crypt;
	my $id = $c->decrypt($cookie{$config{site}{identity_cookie}});
	($name,$uid,$access) = split /:/,$id;
    }
    elsif ($authtype eq "session") {
	# User identity claim is implicit in the session ID.
	# Therefore this call is kind of meaningless in the case of sessions.
	# Let's return the session ID, and see what happens.
	my $session_cookie = $config{site}->{id}."_sessionID";
	return $cookie{$session_cookie};
	#return &get_cookie($session_cookie);
    }
    elsif ($authtype eq "none") {
	$name = "nobody";
    }
    $share{identity} = { 
	name => $name,
	uid => $uid,
	access => $access,
	password => $pwd 
	};
    return $name;
}

#----------------------------------------------------------------------
# lookup : look up the user, to see if we know who they are

sub lookup {
    my ($this,$login) = @_;
    if ($share{identity}{lookup} && $login eq $share{identity}{lookup}{login}) {
	return $share{identity}{lookup};
    }
    # check for custom lookup algorithm
    my $stat = $this->run_handler("lookup",$login);
    return $stat if (defined $stat);
    #
    return undef if ($this->{authentication} eq "none");
    my $udata = $share{DB}->fetch_match($config{auth}{user_table},
			    {$config{auth}{user_login_column}=>$login});

    if (@$udata > 0) {
	$share{identity}{lookup} = $udata->[0];
	$share{identity}{uid} = $udata->[0]{$config{auth}{user_uid_column}};
	$share{identity}{gid} = $udata->[0]{$config{auth}{user_gid_column}};
	$share{identity}{access} = $udata->[0]{$config{auth}{user_access_column}};
	return $udata->[0];
    }
    return undef;
}

#----------------------------------------------------------------------
# authenticate : verify the user's identity claim
#
# Returns true (1) if the user's identity matches the information
# returned by lookup(), false (0) otherwise.

sub authenticate {
    my ($this) = shift;
    if (exists $this->{authenticated}) {
	return $this->{authenticated};
    }
    # check for custom authentication algorithm
    my $stat = $this->run_handler("authenticate");
    return $stat if (defined $stat);
    
    if ($config{auth}{type} eq "none") {
	$this->{authenticated} = 1;
	return 1;
    }
    elsif ($config{auth}{type} eq "session") {
	if (exists $session{identity}) {
	    # we authenticated on a previous visit
	    # copy identity info from session
	    ### could make this more secure with an IP check
	    if (! $share{identity}) {
		my $identity = $session{identity};
		$share{identity} = $identity;
		$this->info("restoring identity \"$identity->{name}\" from session");
	    }
	    $this->{authenticated} = 1;
	    return 1;
	}
	else {
	    return 0;
	}
    }
    elsif ($config{auth}{type} eq "crypt") {
	# we believe the claimed identity is secure, since it is encrypted
	if (! exists $share{identity}) { &identify($this); }
	if ($share{identity}{access}) { $this->{authenticated} = 1; }
	return $share{identity}{access};
    }
    else {   # this->{authentication} eq "cookie"

	# check identity
	if (!$share{identity}) { &identify($this); }
	if (!$share{identity}{name}) {
	    # nobody logged in - not necessarily an error
	    return 0;
	}
	# look up the user
	$this->info("authenticating user \"$share{identity}{name}\"");
	my $user = &lookup($this,$share{identity}{name});
	if (!$user) {
	    # unknown username
	    $this->warn("no such user \"$this->{identity}->{name}\"");
	    return 0;
	}
	elsif (! $user->{$config{auth}->{user_pwd_column}}) {
	    # password field is blank - deny access
	    $this->warn("blank password for user \"$user->{$config{auth}->{user_login_column}}\"");
	    return 0;
	}

	# compare entered and stored passwords
	# NB: $share{identity}{password} is the encoded pwd in the identity 
	# cookie, which is a hash of the password column in the database.
	# The password column raw value may also be a hash in a variety of
	# different schemes, so the cookie may be a hash of a hash.

	my $salt = substr($share{identity}{password},0,2);
	if ($share{identity}{password} eq
	    crypt($user->{$config{auth}{user_pwd_column}},$salt)) {
	    # passwords match
	    $this->{authenticated} = 1;
	    # store extra user info in identity
	    $share{identity}{gid} = $user->{$config{auth}->{user_gid_column}};
	    $share{identity}{access} = $user->{$config{auth}->{user_access_column}};
	    return 1;
	}
	else {
	    # bad password
	    $this->warn("incorrect password for user \"$user->{$config{auth}->{user_login_column}}\" - access denied");
	    $this->{authenticated} = 0;
	    return 0;
	}
    }
}

#----------------------------------------------------------------------
# authorize : grant the user a specific level of access
#
# Access level is a value of 0 or higher.  0 corresponds to "nobody",
# or the general public.  Values of 1 or more correspond to
# authenticated users, with higher values giving greater permissions
# to the database.  The maximum value is $config::root_auth_level,
# which grants unrestricted "super-user" access to the data.  (This
# level of access can be dangerous, as it allows one to mess with
# sensitive data fields and referential integrity.)
#
# The default authorize routine assumes that the user's access level
# is stored in the user table.  This value is simply returned without
# any sanity checks.

sub authorize {
    my ($this) = shift;
    my $stat = $this->run_handler("authorize");
    return $stat if (defined $stat);

    # if not logged in, check for login request
    if (! exists $this->{authenticated}) {	
	# check if credentials were passed in an authtoken
	$this->check_authtoken();
	# authenticate credentials
	&authenticate($this);
    }

    return $this->{authenticated} ? $share{identity}{access} : 0;
}

#----------------------------------------------------------------------
# clear_authentication : reset authentication to start over

sub clear_authentication {
    my $this = shift;
    delete $this->{authenticated};
    delete $share{identity};
}

#----------------------------------------------------------------------
# approve : approve a specific database operation
#
# Arguments:
# op - "read", "update", "insert", "delete"
# table - the table being operated on
# [record] - reference to a datahash containing the record being
#            operated on (used for update, delete only)
#
# Returns true if the operation is permitted.
# Returns false if:
#   - the user does not have permission to read or write to the table
#   - the user is referencing records owned by a different user or group.

sub approve {
    my ($this,$op,$table,$record) = @_;
    my $stat = $this->run_handler("approve",$op,$table,$record);
    return $stat if (defined $stat);
    my $level = $this->authorize();
    my $tablemap = $share{DB}{map}->get_table($table);
    # script okay, now check table permissions
    if (exists $tablemap->{$op}) {
	if ($op =~ /read|insert|search/) {
	    return ($level >= $tablemap->{$op});
	}
	else {
	    # for updates & deletions, must check row ownership
	    if (!$record) {
		if ($level >= $config{auth}->{root_auth_level} - 1) { 
		    return 1; 
		}
		else { return 0; }
	    }
	    elsif ($share{DB}->user_owns($table,$record)) {
		return ($level >= $tablemap->{$op});
	    }
	    else {
		return 0;
	    }
	}
    }
    elsif ($this->{dbmap}) {
	# dbmap kludge - no tablemap or authentication when editing dbmaps
	return 1;
    }
    else {
	# unknown operation
	return 0;
    }
}

# some identity queries, for convenience:

sub my_name {
    my $this = shift;
#    if ($this->authenticate) {
    if ($this->level) {
	my $stat = $this->run_handler("my_name");
	return $stat if (defined $stat);
	my $udata = $this->my_user_record();
	my @namecol = ref $config{auth}{user_name_column} eq "ARRAY" ?
	    @{$config{auth}{user_name_column}} :
	    ($config{auth}{user_name_column});
	my @name = map { $udata->{$_} } @namecol;
	return wantarray ? @name : join " ",@name;
    }
    return undef;
}

sub user_name {
    my ($this,$user) = @_;
    my $stat = $this->run_handler("user_name",$user);
    return $stat if (defined $stat);
    my $udata = ref $user ? $user : $this->fetch($config{auth}{user_table},$user);
    if (ref $udata eq "HASH") {
	my @namecol = ref $config{auth}{user_name_column} eq "ARRAY" ?
	    @{$config{auth}{user_name_column}} :
	    ($config{auth}{user_name_column});
	my @name = map { $udata->{$_} } @namecol;
	my $name = join " ",@name;
	$name =~ s/\s+/ /g;
	return $name;
    }
    return undef;
}

sub my_login {
    my $this = shift;
#    if ($this->authenticate) {
    if ($this->level) {
	my $stat = $this->run_handler("my_login");
	return $stat if (defined $stat);
	return $share{identity}{name};
    }
    return undef;
}

sub my_email {
    my $this = shift;
#    if ($this->authenticate) {
    if ($this->level) {
	my $stat = $this->run_handler("my_email");
	return $stat if (defined $stat);
	return $share{identity}{lookup}{email};
    }
    return undef;
}

sub my_uid {
    my $this = shift;
#    if ($this->authenticate) {
    if ($this->level) {
	my $stat = $this->run_handler("my_uid");
	return $stat if (defined $stat);
	return $share{identity}{uid};
    }
    return undef;
}

sub my_gid {
    my $this = shift;
#    if ($this->authenticate) {
    if ($this->level) {
	my $stat = $this->run_handler("my_gid");
	return $stat if (defined $stat);
	return $share{identity}{gid};
    }
    return undef;
}

sub my_user_record {
    my $this = shift;
    my $u;
#    if ($this->authenticate) {
    if ($this->level) {
	my $stat = $this->run_handler("my_user_record");
	return $stat if (defined $stat);
	if (exists $share{identity}{lookup}) {
	    $u = $share{identity}{lookup};
	}
	elsif ($this->my_uid) {
	    $u = $share{identity}{lookup} = 
		$share{DB}->fetch($config{auth}{user_table},$this->my_uid);
	}
	else {
	    $u = {};
	}
    }
    else {
	$u = {};
    }
    return (wantarray && defined $u) ? %$u : $u;
}

sub my_user {
    my $this = shift;
    my $uid = $this->my_uid;
    if ($uid) {
	my $stat = $this->run_handler("my_user",$uid);
	return $stat if (defined $stat);
	my $user = new ExSite::User(id=>$uid);
	return $user;
    }
    return new ExSite::User(); # undefined user
}

sub my_password {
    my $this = shift;
#    if ($this->authenticate) {
    if ($this->level) {
	my $stat = $this->run_handler("my_password");
	return $stat if (defined $stat);
	my $u = $this->my_user_record();
	$_ = $this->password_storage_method($u->{$config{auth}{user_login_column}});
	if (/cleartext/) {
	    return $u->{$config{auth}{user_pwd_column}};
	}
	elsif (/crypt/) {
	    my $crypt = new ExSite::Crypt();
	    return $crypt->decrypt($u->{$config{auth}{user_pwd_column}});
	}
	else {
	    # hashed password - cannot retrieve original
	    return undef;
	}
    }
    return undef;
}

# user permission tests...

sub get_section {
    my ($this,$site) = @_;
    my $c = new ExSite::Content();
    my $section = $c->get_content_obj($site);
    return $section->my_section(); # in case $site is not a section
}

sub is_root {
    my $this = shift;
    return ($this->authorize >= $config{auth}{level}{root});
}

sub is_admin {
    my $this = shift;
    return ($this->authorize >= $config{auth}{level}{admin});
}

sub is_manager {
    my ($this,$site) = @_;
    my $level = $this->authorize;
    # false if insufficient level
    return 0 if ($level < $config{auth}{level}{manager});
    # true if a system admin
    return 1 if ($level >= $config{auth}{level}{admin});
    # otherwise, check for admin key
    my $section = $this->get_section($site);
    return $section->has_role();
}

sub is_executive {
    my ($this,$site) = @_;
    my $level = $this->authorize;
    if ($level > 4) {
	if ($site) {
	    my $section = $this->get_section($site);
	    return $section->has_role();
	}
	return 1;
    }
    return 0;
}

sub is_member {
    my ($this,$site,$user) = @_;
    my $stat = $this->run_handler("is_member",$site);
    return $stat if (defined $stat);
    return $this->is_user($site,$user,$config{auth}{level}{member});
}

sub is_user {
    my ($this,$site,$user,$level) = @_;
    my $stat = $this->run_handler("is_user",$site);
    return $stat if (defined $stat);
    return 0 if (! $this->authorize);
    return 1 if ($this->is_manager($site));
    $level or $level = $config{auth}{level}{user};
    my $u = $user || $this->my_user_record();
    return 0 if ($u->{access} < $level);
    if ($u->{section_id}) {
	# the user is tied to a particular site
	if (!$site) { $site = $this->this_site; }
	my $sid = ref $site eq "HASH" ? $site->{section_id} : $site;
	return ($sid == $u->{section_id});
    }
    else {
	# the user belongs to all sites
	return 1;
    }
}

sub is_visitor {
    my ($this,$site) = shift;
    if ($this->authorize <= $config{auth}{level}{visitor}) {
	# yes, regardless of level
	return 1;
    }
    else {
	# user is a visitor if not an executive
	return ! $this->is_executive($site);
    }
}

# local_level: returns an access level in the context of a specific site
# The role is returned numerically (eg. as an access level).
# Essentially the access level of members and managers may be downgraded if
# they are working outside of their sites.

#sub role {
sub local_level {
    my ($this,$site) = @_;
    my $section = $this->get_section($site);
    my $level = $this->level;
    if ($level >= $config{auth}{level}{admin}) {
	return $level;
    }
    elsif ($section->has_role()) {
	return $level;
    }
    else {
	my $u = $this->my_user_record();
	if ($u->{section_id} == $section->id) {
	    return $level;
	}
    }
    return 0;
}

# return the effective access level the user is operating at

sub level {
    my $this = shift;
    if (! exists $this->{effective_level}) {
	$this->{effective_level} = $this->real_level;
    }
    return $this->{effective_level};
}

# return the real access level of the user

sub real_level {
    my $this = shift;
    if (! exists $this->{level}) {
	$this->{level} = $this->authorize;
    }
    return $this->{level};
}

# change to a different (lower) effective access level
#
# This is used when publishing, to make pages render as if being viewed
# by the public.

sub set_level {
    my ($this,$level) = @_;
    $this->{effective_level} = ($level <= $this->real_level) ? $level : 0;
    return $this->{effective_level};
}

# return to our real access level.

sub reset_level {
    my $this = shift;
    delete $this->{effective_level};
}

# demote our access level if necessary

sub adjust_level {
    my $this = shift;
    my $level = $this->level;
    if ($level >= $config{auth}{trust_level} && ! $ENV{EXSITE_DEBUG}) {
	# we are connecting at a higher access level than we can trust
	if ($ENV{REMOTE_ADDR} =~ /$config{auth}{trusted_hosts}/) {
	    # we're good
	    return $level;
	}
	# not a trusted host
	$this->warn("You are accessing this screen from an untrusted location. Permissions have been downgraded.");
	$this->set_level($config{auth}{trust_level} - 1);
    }
    return $this->{effective_level};
}

# remove all traces of current user login

sub clear_login {
    my $this = shift;
    delete $this->{authenticated};  # already authenticated flag
    delete $share{identity};        # user identity information
    if ($config{auth}{logout_kills_session}) {
	my $s = tied %session;
	$s->kill() if $s;
    }
    else {
	delete $session{identity};      # preserved identity data in Session
    }
    return;
}

# return a standard login form - $head and $foot are optional HTML snippets to
# place above and below the form

sub login_form {
    my ($this,$action,$goto,$head,$foot) = @_;
    my $stat = $this->run_handler("login_form",$action,$goto);
    return $stat if (defined $stat);
    my $ml = &get_obj("ML");
    my $out;
    my $in = new ExSite::Input;
    my $data = $in->combine;  # get any input data
    if ($data->{login_action} eq "forgot") {
	return $this->login_recover_form;
    }
    elsif ($data->{login} && $data->{password} && $this->do_login_form($data)) {
	# successful login
	return undef;
    }
    elsif ($data->{login} || $data->{password}) {
	# failed login
	$out .= $ml->p($msg{"Login failed - please try again."},{class=>"error"});
    }

    # Display site logo
    if ($config{site}{use_logo}){
	$out .= $ml->p($config{site}{logo});
    }
    $out .= $ml->h2($msg{"Login"});

    my %formattr = ( method=>"post" );

    # $action determines who process this form; 
    # default is login.cgi - used if $action is undef
    # if $action is defined but blank/false, no action is used (use this
    # to submit the login form to itself)

    if (defined $action && $action) {
	$formattr{action} = $action;
    }
    elsif (! defined $action) {
	# try to use current URL settings, not system URL settings
	my $url = new ExSite::URI;
	$formattr{action} = $url->get("scheme")."://".$url->get("authority").$config{server}{CGIpath}."/".$config{prog}{login};
    }

    # $goto determines where the user logs in to; default is login_destination
    $goto = $goto || "$config{server}{server}$config{server}{CGIpath}/$config{prog}{home}";

    my $login_form;
    if (ref $config{auth}{login_form} eq "ARRAY") {
	$login_form = join("\n",@{$config{auth}{login_form}});
    }
    else {
	my $login_table = $ml->tr(
				  $ml->td("[[login_prompt]]").
				  $ml->td("[[login_input]]")
				  ).
			  $ml->tr(
				  $ml->td("[[password_prompt]]").
				  $ml->td("[[password_input]]")
				  );
	if ($config{auth}{remember_me}) {
	    # add a "remember me" checkbox
	    #push @login_table, [ ["td", "[[remember_input]]", "[[remember_prompt]]" ] ];
	    $login_table .= $ml->tr(
				    $ml->td($ml->div("[[remember_input]]",{style=>"text-align:right"})).
				    $ml->td($msg{$config{auth}{remember_prompt}})
				    );
	}
	$login_form = $ml->table($login_table, { class=>"LoginForm" } );
    }
    my $formtext = &substitute($login_form,
			       {
				login_prompt => $msg{$config{auth}{login_prompt}},
				login_input => $ml->input(undef,{type=>"text",name=>"login"}),
				password_prompt => $msg{$config{auth}{password_prompt}},
				password_input => $ml->input(undef,{type=>"password",name=>"password"}),
				remember_prompt => $msg{$config{auth}{remember_prompt}},
				remember_input => $ml->input(undef,{type=>"checkbox",name=>"remember"}),
			       }
			       );

    # hidden field for destination
    if ($goto) {
	$formtext .= $ml->input(undef,{type=>"hidden",name=>"goto",value=>$goto});
    }

    # buttons
    (tied %msg)->nohighlight;
    $formtext .= $ml->p(
			$ml->input(undef,{type=>"submit", 
					  value=>" ".$msg{"Log in"}." "}).
			"&nbsp;".
			$ml->input(undef,{type=>"button",
					  value=>" $msg{Cancel} ",
					  class=>"cancel",
					  onclick=>"history.back()"})
			);
    (tied %msg)->restore;

    $out .= $ml->form($formtext,\%formattr);

    my $forgoturl = &relink(login_action=>"forgot");
    if ($config{auth}{forgot_login}) {
	$out .= $ml->p(
	    $ml->a($msg{$config{auth}{forgot_prompt}}, {href=>$forgoturl}),
	    {class=>"forgot_login"}
	    );
    }

    return $ml->div($head.$out.$foot,{class=>"LoginForm"});
}

# process a standard login form - return error message, or redirect

sub do_login_form {
    my ($this,$data) = @_;
    my $goto = $data->{goto};
    if ($this->login($data->{login},$data->{password},$goto,$data->{remember})) {
	# success!
	if (! $goto) {
	    # no place to go;  redirect to default location specified
	    # in config file
	    $goto = $config{auth}{login_destination}[$this->level];
	}
	&redirect($goto);
	return 1;
    }
    return 0;
}

# standard form to send login instructions and password reminders
#
# TODO: assumes cleartext password storage; expand to other cases

sub login_reminder_form {
    my $this = shift;
    if (! $config{auth}{forgot_login}) { return undef; }
    my $stat = $this->run_handler("login_reminder_form");
    return $stat if (defined $stat);
    my $in = new ExSite::Input;
    my $data = $in->combine;  # get any input data
    my $ml = &get_obj("ML");
    if ($data->{login} || $data->{email}) {
	return $this->do_login_reminder($data);
    }
    return $ml->div(
		    $ml->form(
			      $ml->p($msg{"To receive login instructions by e-mail, please provide your $config{auth}{login_prompt} if you know it, or your e-mail address if you do not."}).
			      $ml->table([
					  [ $msg{"$config{auth}{login_prompt}:"},
					    $ml->input(undef,{type=>"text",name=>"login"})
					    ],
					  [ $msg{"OR, your email address:"},
					    $ml->input(undef,{type=>"text",name=>"email"})
					    ],
					  ],
					 {cellspacing=>15}
					 ).
			      $ml->p(
				     $ml->input(undef,{type=>"submit",
						       value=>" $msg{Submit} "}).
				     "&nbsp;".
				     $ml->input(undef,{type=>"button",
						       value=>" $msg{Cancel} ",
						       onclick=>"history.back()"})
				     ),
			      { method=>"post" }
			      ),
		    { align=>"center" }
		    );
}

sub do_login_reminder {
    my $this = shift;
    if (! $config{auth}{forgot_login}) { return undef; }
    my $stat = $this->run_handler("do_login_reminder");
    return $stat if (defined $stat);
    my $out;
    my $in = new ExSite::Input;
    my $data = shift || (new ExSite::Input)->combine;  # get any input data
    my $ml = &get_obj("ML");

    # get users and addresses

    my $db = $share{DB} || new ExSite::DB;
    my $admin = $this->owner_email;
    my $user_list;
    if ($data->{login}) {
	$user_list = $db->fetch_match($config{auth}{user_table},
				      {$config{auth}{user_login_column}=>$data->{login}});
    }
    elsif ($data->{email}) {
	$user_list = $db->fetch_match($config{auth}{user_table},
				      {$config{auth}{user_email_column}=>$data->{email}});
    }
	
    # setup template error strings and messages

    my $num_matches = scalar(@$user_list);
    my $url = &relink(login_action=>undef);
    my $forgoturl = &relink(login_action=>"forgot");

    if ($num_matches==0) {

	# user not found

	if ($data->{login}) {
	    $out .= $ml->p(&substitute($msg{$config{auth}{email}{nouser}},
				       {login=>$ml->strong($data->{login})}));
	}
	elsif ($data->{email}) {
	    $out .= $ml->p($msg{"Sorry, that email address was not found."});
	}
	$out .= $ml->p($ml->a($msg{"Try again?"},{href=>$forgoturl}));
	$out .= $ml->p($ml->a($msg{"Return to login screen"},{href=>$url}));
    } 
    elsif ($num_matches>1 && $data->{login}) {

	# whoops, too many users found

	$out .= $ml->p(&substitute($msg{$config{auth}{email}{twousers}},
				   {login=>$ml->strong($data->{login})}).
		       $ml->br().
		       &substitute($msg{$config{auth}{email}{pleasecall}},
				   {admin=>$ml->a($admin,{href=>"mailto:$admin"})}));
	$out .= $ml->p($ml->a($msg{"Try again?"},{href=>$forgoturl}));
	$out .= $ml->p($ml->a($msg{"Return to login screen"},{href=>$url}));
    } 
    else {

	# one user found

	my $email = $data->{email} || $user_list->[0]{$config{auth}{user_email_column}};
	if (not $email) {

	    # user does not have an email address

	    $out .= $ml->p(&substitute($msg{$config{auth}{email}{missingemail}},
				       {login=>$ml->strong($data->{login})}).
			   $ml->br().
			   &substutite($msg{$config{auth}{email}{pleasecall}},
				       {admin=>$ml->a($admin,{href=>"mailto:$admin"})}));
	    $out .= $ml->p($ml->a($msg{"Try again?"},{href=>$forgoturl}));
	    $out .= $ml->p($ml->a($msg{"Return to login screen"},{href=>$url}));
	}
	else {
	    (tied %msg)->nohighlight();
	    my $site = $this->this_site();
	    my $site_title = $site ? $site->{title} : $config{site}{name};
	    my $subject = &substitute($msg{$config{auth}{email}{email_subject}},{site_title=>$site_title});
	    my $body = &substitute($msg{$config{auth}{email}{email_body}},
                                   {user=>($data->{login} ? "user $data->{login}" : $email),
                                    site_title=>$site_title});
	    foreach my $u (@$user_list) {
                $body .= "\n";
		if ($u->{$config{auth}{user_login_column}} && 
		    $u->{$config{auth}{user_pwd_column}} && 
		    $u->{$config{auth}{user_access_column}}) {
		    $body .= &substitute($msg{$config{auth}{email}{email_instructions}},
                                         { login=>$u->{$config{auth}{user_login_column}},
                                           password=>$u->{$config{auth}{user_pwd_column}} } );
		}
		else {
		    $body .= &substitute($msg{$config{auth}{email}{email_error}},
                                         {admin=>$admin});
		}
                $body .= "\n";
	    }
	    if (&SendMail($email,$admin,$subject,$body)) {
		$out .= $ml->p($msg{"ERROR: unable to send email."}.
			       $ml->br().
			       &substitute($msg{$config{auth}{email}{pleasecall}},
                                           { admin=>$ml->a($admin,{href=>"mailto:$admin"}) })
                               );
		$out .= $ml->p($ml->a($msg{"Try again?"},{href=>$forgoturl}));
		$out .= $ml->p($ml->a($msg{"Return to login screen"},{href=>$url}));
	    } 
	    else {
		$out .= $ml->h1($msg{"Thank you"});
		$out .= $ml->p($msg{"Login instructions have been sent to the e-mail address we have on file."});
		$out .= $ml->p(&substitute($msg{$config{auth}{email}{nomyemail}},
                               {email=>$email,admin=>$ml->a($admin,{href=>"mailto:$admin"})}));
		$out .= $ml->p($ml->a($msg{"Return to login screen"},{href=>$url}));
	    }
	    (tied %msg)->restore();
	}
    }
    return $out;
}

# login recovery (automated password recovery or reset)

sub login_recover_form {
    my $this = shift;
    if (! $config{auth}{forgot_login}) { return undef; }
    my $stat = $this->run_handler("login_recover_form");
    return $stat if (defined $stat);
    my $in = new ExSite::Input;
    my $data = $in->combine;  # get any input data
    my $ml = &get_obj("ML");

    if ($data->{login} || $data->{email}) {
	return $this->do_login_recover($data);
    }

    # recover method is *default* recovery method; if the user has specified a
    # non-default password storage method, we may be forced to use reset even if
    # a reminder has been requested.
    my $recover_method = $config{auth}{password_recover_method} ||
	($config{auth}{password_storage_method} =~ /cleartext|crypt/ ? 
	 "reminder" : "reset");

    my %recover_message = (
			   reminder => "receive login instructions",
			   reset => "reset your password",
			   );

    if ($recover_method eq "reminder") {
	$stat = $this->run_handler("login_reminder_form");
	return $stat if (defined $stat);
    }

    return $ml->div(
		    $ml->form(
			      
			      $ml->p($msg{"To $recover_message{$recover_method} by e-mail, please provide your $config{auth}{login_prompt} if you know it, or your email address if not."}).
			      $ml->table([
					  [ $msg{"$config{auth}{login_prompt}:"},
					    $ml->input(undef,{type=>"text",name=>"login"})
					    ],
					  [ $msg{"OR, your email address:"},
					    $ml->input(undef,{type=>"text",name=>"email"})
					    ],
					  ],
					 {cellspacing=>15}
					 ).
			      $ml->p(
				     $ml->input(undef,{type=>"submit",
						       value=>" $msg{Submit} "}).
				     "&nbsp;".
				     $ml->input(undef,{type=>"button",
						       value=>" $msg{Cancel} ",
						       onclick=>"history.back()"})
				     ),
			      { method=>"post" }
			      ),
		    { align=>"center" }
		    );
}

sub do_login_recover {
    my $this = shift;
    if (! $config{auth}{forgot_login}) { return undef; }
    my $stat = $this->run_handler("do_login_recover");
    return $stat if (defined $stat);
    my $out;
    my $in = new ExSite::Input;
    my $data = shift || (new ExSite::Input)->combine;  # get any input data
    my $ml = &get_obj("ML");
    my $recover_method = $config{auth}{password_recover_method} ||
	($this->password_storage_method($data->{login}) =~ /cleartext|crypt/ ? 
	 "reminder" : "reset");

    if ($recover_method eq "reminder") {
	$stat = $this->run_handler("do_login_reminder");
	return $stat if (defined $stat);
    }

    if ($data->{uid}) {
	# user has followed the password reset link
	# uid is encrypted to prevent tampering
	my $c = new ExSite::Crypt;
	my $uid = $c->decrypt($data->{uid});
	my $user = $this->fetch($config{auth}{user_table},$uid);
	# sanity check
	if ($user->{$config{auth}{user_login_column}} eq $data->{login}) {
	    $out .= $this->reset_password($uid);
	}
	else {
	    $out .= $this->error($msg{"Permission denied: invalid password reset parameters"});
	}
	return $out;
    }

    my $url = &relink(login_action=>undef,uid=>undef,login=>undef,'_'=>undef);
    my $admin = $this->owner_email;
    my $forgoturl = &relink(login_action=>"forgot",uid=>undef,login=>undef,'_'=>undef);

    # get users and addresses

    my $db = $share{DB} || new ExSite::DB;
    my $user_list;
    if ($data->{login}) {
	$user_list = $db->fetch_match($config{auth}{user_table},
				      {$config{auth}{user_login_column}=>$data->{login}});
    }
    elsif ($data->{email}) {
	$user_list = $db->fetch_match($config{auth}{user_table},
				      {$config{auth}{user_email_column}=>$data->{email}});
    }

    # setup template error strings and messages

    my $num_matches = scalar(@$user_list);

    if ($num_matches==0) {

	# user not found

	if ($data->{login}) {
	    $out .= $ml->p(&substitute($msg{$config{auth}{email}{nouser}},
				       {login=>$ml->strong($data->{login})}));
	}
	elsif ($data->{email}) {
	    $out .= $ml->p($msg{"Sorry, that email address was not found."});
	}
	$out .= $ml->p($ml->a($msg{"Try again?"},{href=>$forgoturl}));
	$out .= $ml->p($ml->a($msg{"Return to login screen"},{href=>$url}));
    } 
    elsif ($num_matches>1 && $data->{login}) {

	# whoops, too many users found
	$out .= $ml->p(&substitute($msg{$config{auth}{email}{twousers}},
				   {login=>$ml->strong($data->{login})}).
		       $ml->br().
		       &substitute($msg{$config{auth}{email}{pleasecall}},
				   {admin=>$ml->a($admin,{href=>"mailto:$admin"})}));
	$out .= $ml->p($ml->a($msg{"Try again?"},{href=>$forgoturl}));
	$out .= $ml->p($ml->a($msg{"Return to login screen"},{href=>$url}));
    } 
    else {

	# one user found

	my $email = $data->{email} || $user_list->[0]{$config{auth}{user_email_column}};
	if (! $email) {

	    # user does not have an email address

	    $out .= $ml->p(&substitute($msg{$config{auth}{email}{missingemail}},
				       {login=>$ml->strong($data->{login})}).
			   $ml->br().
			   &substitute($msg{$config{auth}{email}{pleasecall}},
				       {admin=>$ml->a($admin,{href=>"mailto:$admin"})}));
	    $out .= $ml->p($ml->a($msg{"Try again?"},{href=>$forgoturl}));
	    $out .= $ml->p($ml->a($msg{"Return to login screen"},{href=>$url}));
	}
	else {
	    my $site = $this->this_site();
	    my $site_title = $site ? $site->{title} : $config{site}{name};
	    my $subject = &substitute($msg{$config{auth}{email}{email_subject}},{site_title=>$site_title});
	    my $body;
	    if ($recover_method eq "reminder") {
		$body = &substitute($msg{$config{auth}{email}{email_body}},
				    {user=>($data->{login} ? "user $data->{login}" : $email),
				     site_title=>$site_title});
		foreach my $u (@$user_list) {
		    $body .= "\n";
		    if ($u->{$config{auth}{user_login_column}} && $u->{$config{auth}{user_pwd_column}} && $u->{$config{auth}{user_access_column}} && $u->{$config{auth}{user_access_column}} > 0) {
			$body .= &substitute($msg{$config{auth}{email}{email_instructions}},
					     { login=>$u->{$config{auth}{user_login_column}},
					       password=>$u->{$config{auth}{user_pwd_column}} } );
		    }
		    elsif ($u->{$config{auth}{user_access_column}} == 0) {
			$body .= &substitute($msg{$config{auth}{email}{noaccess}},
					     {admin=>$admin});
		    }
		    else {
			$body .= &substitute($msg{$config{auth}{email}{email_error}},
					     {admin=>$admin});
		    }
		    $body .= "\n";
		}
	    }
	    else { # password reset
		my $reset_instruct;
		my $reset_url = new ExSite::URI;
		$reset_url->plaintext();  # sent via email
		$reset_url->secure();  # encrypt
		$body = &substitute($msg{$config{auth}{email}{reset_body}},
				    {user=>($data->{login} ? "user $data->{login}" : $email),
				     site_title=>$site_title}
				    );
		foreach my $u (@$user_list) {
		    next if ($u->{section_id} && $u->{section_id}!=$site->{section_id});
		    my $c = new ExSite::Crypt;
		    $reset_url->query(login=>$u->{$config{auth}{user_login_column}},
				      uid=>$c->encrypt($u->{$config{auth}{user_uid_column}}));
		    my $authurl = $reset_url->write();
		    $body .= "\n\n";
		    if ($u->{$config{auth}{user_access_column}} > 0) {
			$body .= &substitute($msg{$config{auth}{email}{reset_instructions}},
					     {user=>$u->{$config{auth}{user_login_column}},
					      reset_url=>$authurl}
			    );
		    }
		    else {
			$body .= &substitute($msg{$config{auth}{email}{noaccess}},
					     {admin=>$admin});
		    }
		}
	    }
	    if (&ExSite::Mail::send(to=>$email,from=>$admin,subject=>$subject,body=>$body)) {
		$out .= $ml->p($msg{"ERROR: unable to send email."}.
			       $ml->br().
			       &substitute($msg{$config{auth}{email}{pleasecall}},
                                           { admin=>$ml->a($admin,{href=>"mailto:$admin"}) })
                               );
		$out .= $ml->p($ml->a($msg{"Try again?"},{href=>$forgoturl}));
		$out .= $ml->p($ml->a($msg{"Return to login screen"},{href=>$url}));
	    } 
	    else {
		$out .= $ml->h1($msg{"Thank you"});
		$out .= $ml->p($msg{"Login instructions have been sent to the e-mail address we have on file."});
		$out .= $ml->p(&substitute($msg{$config{auth}{email}{notmyemail}},
                               {email=>$email,admin=>$ml->a($admin,{href=>"mailto:$admin"})}));
		$out .= $ml->p($ml->a($msg{"Return to login screen"},{href=>$url}));
	    }
	}
    }
    return $out;
}

# reset_password : set password to a random string, and mail it to the user

sub reset_password {
    my ($this,$uid) = @_;
    my $out;
    my $user = $this->fetch($config{auth}{user_table},$uid);
    if (! $user) {
	$out .= $this->error($msg{"Cannot reset password: undefined user"});
	return $out;
    }
    if ($user->{$config{auth}{user_access_column}} < 1) {
	$out .= $this->error($msg{"Cannot reset password: user has no login privileges"});
	return $out;
    }
    if (! $user->{$config{auth}{user_email_column}}) {
	$out .= $this->error($msg{"Cannot reset password: no email address defined.  Please contact the webmaster at $config{site}{administrator}."});
	return $out;
    }
    my $ml = &get_obj("ML");
    my $url = &relink(login_action=>undef,uid=>undef,login=>undef,'_'=>undef);
    my $admin = $this->owner_email;
    my $forgoturl = &relink(login_action=>"forgot",uid=>undef,login=>undef,'_'=>undef);

    my $new_pass = &randtext();
    $this->set_password($new_pass,$uid,$this->password_storage_method($user->{$config{auth}{user_login_column}}));

    # now send a reminder email
    my $site = $this->this_site();
    my $site_title = $site ? $site->{title} : $config{site}{name};
    my $subject = &substitute($msg{$config{auth}{email}{email_subject}},{site_title=>$site_title});
    my $body = &substitute($msg{$config{auth}{email}{email_body}},
			   {user=>$user->{$config{auth}{user_login_column}},
			    site_title=>$site_title});
    $body .= "\n";
    $body .= &substitute($msg{$config{auth}{email}{email_instructions}},
			 { login=>$user->{$config{auth}{user_login_column}},
			   password=>$new_pass,
			   login_prompt=>$config{auth}{login_prompt},
			   password_prompt=>$config{auth}{password_prompt} }
			 );
    if (&ExSite::Mail::send(to=>$user->{$config{auth}{user_email_column}},from=>$admin,subject=>$subject,body=>$body)) {
	$out .= $ml->p($msg{"ERROR: unable to send email."}.
		       $ml->br().
		       &substitute($msg{$config{auth}{email}{pleasecall}},
				   { admin=>$ml->a($admin,{href=>"mailto:$admin"}) })
		       );
	$out .= $ml->p($ml->a($msg{"Try again?"},{href=>$forgoturl}));
	$out .= $ml->p($ml->a($msg{"Return to login screen"},{href=>$url}));
    }
    else {
	$out .= $ml->h1($msg{"Thank you"});
	$out .= $ml->p(&substitute($msg{$config{auth}{email}{reset_sent}},{email=>$user->{$config{auth}{user_email_column}}}));
	$out .= $ml->p($ml->a($msg{"Return to login screen"},{href=>$url}));
    }
    return $out;
}

sub password_storage_method {
    my ($this,$login) = @_;
    my $method = $share{Page} ? 
	&preference("auth.password_storage_method") : 
	$config{auth}{password_storage_method};
    if ($login) {
	my @user = $this->fetch_match($config{auth}{user_table},{$config{auth}{user_login_column}=>$login});
	if (scalar @user > 0) {
	    my $pwd = $user[0]{password};
	    if ($pwd =~ /^\[(cleartext|des|crypt|md5\+?)\] (.+)$/) {
		$method = $1;
	    }
	}
    }
    return $method;
}

# validate a login/password pair, and set an identity cookie
#
# If the destination is set, we validate that the user belongs in that
# destination, and allow them in if so.  Otherwise, the login is rejected
# (user attempting to login to one site using their identity from another
# site).
#
# If you want to override this logic, pass a null destination (or leave
# off the destination).
#
# $login = identity that the user has requested to log in under
# $password = the password they have provided as proof of identity
# $destination = the (restricted access) URL they are attempting to visit
# $remember = if true, set an explicit expiry time on cookies

sub login {
    my ($this,$login,$passwd,$destination,$remember) = @_;
    # check for custom login algorithm
    my $stat = $this->run_handler("login",$login,$passwd,$destination);
    return $stat if (defined $stat);

    my $user = $this->lookup($login);

    if (ref $user eq "HASH") {
	# there is such a user
	if ($this->check_password($passwd,$user)) {
	    # and their password matches
	    if ($config{auth}{scope} eq "local" && 
		$share{identity}{lookup}{section_id} && 
		$destination) {
		# this user is tied to a particular section;
		# is the destination part of that section?
		my $level = $share{identity}{access};
		my $section_id = $this->site_of($destination);
		if ($section_id) {
		    # they are logging in to a particular section
		    #if ($this->is_member($section_id)) {
		    # can't use is_member because it uses the authentication
		    # and identity info, which hasn't been set up yet
		    if ($section_id == $share{identity}{lookup}{section_id} ||
			$level >= ($config{auth}{root_auth_level} - 1)) {
			# the sections match (or this is an admin), proceed
			return $this->do_login($user,$remember);
		    }
		    else {
			# section mis-match, do not proceed
			$this->error("login: you have no access to this site");
			return 0;
		    }
		}
		else {
		    # unknown section; only allow level 2+ users to proceed
		    if ($level > 1) {
			return $this->do_login($user,$remember);
		    }
		    else {
			$this->error("login: permission denied");
			return 0;
		    }
		}
	    }
	    else {
		# global login - user is not tied to a particular section
		return $this->do_login($user,$remember);
	    }
	}
	else {
	    #### track bad login attempts
	    $this->error("login: invalid password");
	    return 0;
	}
    }
    else {
	#### track bad login attempts
	$this->error("login: no such user");
	return 0;
    }
}

# do_login : set login identity, after the user has been authenticated

sub do_login {
    my ($this,$user,$remember) = @_;
    # check for custom login algorithm
    my $stat = $this->run_handler("do_login",$user);
    return $stat if (defined $stat);
    $this->info("login: $user");

    my $cookie;
    my $u = (ref $user eq "HASH" ? $user : $this->lookup($user));

    # set identity for the current request
    # WE NO LONGER GO THROUGH DO_LOGIN_TEMP
    #$this->do_login_temp($u);

    # preserve identity for future requests
    if (ref $u eq "HASH") {
	$share{identity} = {
	    name   => $u->{$config{auth}{user_login_column}},
	    uid    => $u->{$config{auth}{user_uid_column}},
	    gid    => $u->{$config{auth}{user_gid_column}},
	    access => $u->{$config{auth}{user_access_column}},
	    lookup => $u,
	};

	if ($config{auth}{login_kills_session}) {
	    my $s = (tied %session);
	    $s->kill() if $s;
	}

	if ($config{auth}{type} eq "session") {
	    my $id = $share{identity};
	    $session{identity} = $id;
	    # NB: $remember ignored for sessions
	}
	elsif ($config{auth}{type} eq "crypt") {
	    my $cname = $config{site}{identity_cookie};
	    my $cval;
	    # see if our encrypted identity has been saved for us
	    if ($share{login_temp_crypt_cval}) {
		$cval = $share{login_temp_crypt_cval};
	    }
	    else {
		# recompute
		my $c = new ExSite::Crypt;
		$cval = $c->encrypt($u->{$config{auth}{user_login_column}}.":".
				    $u->{$config{auth}{user_uid_column}}.":".
				    $u->{$config{auth}{user_access_column}});
	    }
	    $this->info("setting identity cookie: $cname=$cval");
	    if ($remember) {
		(tied %cookie)->store_remember($cname,$cval);
	    }
	    else {
		$cookie{$cname} = $cval;
	    }
	}
	else {	  # if ($config{auth}{type} eq "cookie") {
	    my $cname = $config{site}{identity_cookie};
	    my $cval  = join(":",$u->{$config{auth}{user_login_column}},crypt($u->{$config{auth}{user_pwd_column}},&randtext(2,'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789')));
	    $this->info("setting identity cookie: $cname=$cval");
	    if ($remember) {
		(tied %cookie)->store_remember($cname,$cval);
	    }
	    else {
		$cookie{$cname} = $cval;
	    }
	}

	$this->{authenticated} = 1;
	$this->{level} = $this->{effective_level} = $u->{$config{auth}{user_access_column}};

	# optional logging of log-ins
	$this->log_login() if ($config{auth}{log_login});

	# note: we return the unadjusted level
	return $this->{level};
    }
    else {
	$this->error("login: no such user: $user");
	return 0;
    }
}

# login_temp : temporary login - valid for one page view only.  No persistent
# cookie is set, so the user identity does not persist.  If $temp_cookie is 
# true, then we set a temporary cookie $ENV{HTTP_COOKIE}.  This is needed if
# spawning subprocesses that may not see our cookie jar (eg. publish.cgi).

sub do_login_temp {
    my ($this,$user,$temp_cookie) = @_;
    # check for custom login_temp algorithm
    my $stat = $this->run_handler("login_temp",$user,$temp_cookie);
    return $stat if (defined $stat);

    my $cookie;
    my $u = (ref $user eq "HASH" ? $user : $this->lookup($user));

    if (ref $u eq "HASH") {
	$this->clear_login;
	if ($config{auth}{type} eq "crypt") {
	    my $cname = $config{site}{identity_cookie};
	    my $c = new ExSite::Crypt;
	    my $cval = $c->encrypt($u->{$config{auth}{user_login_column}}.":".
				   $u->{$config{auth}{user_uid_column}}.":".
				   $u->{$config{auth}{user_access_column}});
	    # save so we don't have to recompute
	    $share{login_temp_crypt_cval} = $cval;
	    # set identity for this request
	    (tied %cookie)->store_update($cname,$cval);
	}
	else {	  # if ($config{auth}{type} eq "cookie") {
	    my $cname = $config{site}{identity_cookie};
	    my $cval  = join(":",$u->{$config{auth}{user_login_column}},crypt($u->{$config{auth}{user_pwd_column}},&randtext(2,'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789')));
	    # set identity for this request
	    (tied %cookie)->store_update($cname,$cval);
	}
	$share{identity} = {
	    name   => $u->{$config{auth}{user_login_column}},
	    uid    => $u->{$config{auth}{user_uid_column}},
	    gid    => $u->{$config{auth}{user_gid_column}},
	    access => $u->{$config{auth}{user_access_column}},
	};
	$this->{authenticated} = 1;
	$this->{level} = $this->{effective_level} = $u->{$config{auth}{user_access_column}};
	# note: we return the unadjusted level
	return $this->{level};
    }
    else {
	$this->error("login: no such user: $user");
	return 0;
    }
}

sub log_login {
    my $this = shift;
    my $stat = $this->run_handler("log_login");
    return $stat if (defined $stat);
    my $user = $this->my_user_record();
    $this->audit("user ".$user->{$config{auth}{user_login_column}}." logged in");
    if (exists $user->{login_count}) {
	$user->{login_count}++;
    }
    if (exists $user->{last_login}) {
	$user->{last_login} = undef;
    }
    return $this->update($config{auth}{user_table},$user);
}

# unset the identity cookie

sub logout {
    my $this = shift;
    $this->run_handler("logout");

    $this->clear_login;

    if ($config{auth}{type} =~ /^(cookie|crypt)$/) {
	delete $cookie{$config{site}{identity_cookie}};
    }
    elsif ($config{auth}{type} =~ /^session$/) {
	delete $cookie{$config{site}{id}."_sessionID"};
    }
    return;
}

#----------------------------------------------------------------------
# check password : compare a password with the stored version
#
# Returns true (1) if the passed password matches the user's

sub check_password {
    my ($this,$password,$user) = @_;
    my $udata;
    if (! defined $user) {
        $udata = $this->my_user_record;
    }
    elsif (ref $user eq "HASH") {
	$udata = $user;
    }
    else {
	$udata = $share{DB}->lookup($user);
    }
    if (!$udata) {
	# unknown user
	$this->warn("check_password: ".$msg{"unknown user"});
	return 0;
    }
    elsif (! $udata->{$config{auth}->{user_pwd_column}}) {
	# password field is blank - deny access
	$this->warn($msg{"blank password for user"}." \"$udata->{$config{auth}->{user_login_column}}\"");
	return 0;
    }

    if (! $password) {
	# blank given password - deny
	return 0;
    }
    if (! $udata->{password}) {
	# blank stored password - deny
	return 0;
    }

    return $this->compare_password($password,$udata->{$config{auth}{user_pwd_column}});
}

# change password

sub change_password_form {
    my ($this) = @_;
    my $stat = $this->run_handler("change_password_form");
    return $stat if (defined $stat);
    my $ml = &get_obj("ML");
    my $out;
    my $in = new ExSite::Input;
    my $data = $in->post;  # get any input data
    if ($data->{passwd0} || $data->{passwd1} || $data->{passwd2}) {
	$out .= $this->change_password($data->{passwd0},$data->{passwd1},$data->{passwd2});
	return $ml->p($msg{"Password changed!"}) if (! $out);
    }
    $out .= $ml->h1($msg{"Change Password"});
    my $level = $share{DB}->level();
    my $min_strength = $config{auth}{password_strength}{$level} || $level;
    $out .= &insert_js("jquery");
    $out .= $ml->script("
var base_pwd_strength = $config{auth}{base_pwd_strength};
var min_pwd_strength = $min_strength;
var login_cookie = $config{site}{identity_cookie};
");
    $out .= $ml->script(undef,{src=>"$config{server}{HTMLpath}/_ExSite/js/password.js"});
    $out .= $ml->form(
	$ml->table(
	    $ml->tr(
		$ml->td($msg{"Current password:"}).
		$ml->td($ml->input(undef,{type=>"password",name=>"passwd0"}))
	    ).
	    $ml->tr(
		$ml->td($msg{"New password:"}).
		$ml->td($ml->input(undef,{type=>"password",name=>"passwd1",class=>"NewPassword"}).$ml->span(undef,{id=>"NewPasswordTip"}))
	    ).
	    $ml->tr(
		$ml->td($msg{"Type again, to confirm:"}).
		$ml->td($ml->input(undef,{type=>"password",name=>"passwd2"}))
	    )
	).
	$ml->input(undef,{type=>"submit",value=>$msg{"Change password"}}),
	{method=>"post"}
	);
    return $ml->div($out,{class=>"ChangePassword"});
}

sub change_password {
    my ($this,$old,$new,$new2) = @_;
    if ($new) {
	if (! defined $new2 || ($new eq $new2)) {
	    my $re = $share{DB}{map}->regexp('password');
	    if ($new =~ /^$re$/) {
		if (! defined $old || $this->check_password($old)) {
		    my $stat = $this->set_password($new);
		    return $stat if ($stat); # error
		    # update the login cookie
		    my $login = $this->my_login;
		    $this->clear_login;
		    $this->login($login,$new);
		    return undef;
		}
		else {
		    return $msg{"Password update failed - incorrect password."};
		}
	    }
	    else {
		return $msg{"Insecure password - needs more characters."};
	    }
	}
	else {
	    return $msg{"New passwords do not match."};
	}
    }
    else {
	return $msg{"Cannot set a blank password."};
    }
}

sub set_password {
    my ($this,$password,$uid,$passtype) = @_;
    if (! $uid) {
	$uid = $this->my_uid;
	$passtype or $passtype = $this->password_storage_method($this->my_login);
    }
    if ($uid) {
	# check strength
	my $user = $share{DB}->fetch($config{auth}{user_table},$uid);
	if ($user) {
	    my $strength = $this->password_strength($password,$user->{$config{auth}{user_login_column}});
	    my $access = $this->level();
	    my $min_strength = $config{auth}{password_strength}{$access} || 
		$access;
	    if ($strength < $min_strength) {
		return $msg{"Password is too weak.  Strengthen it with more text, numbers, upper-case, or punctuation characters."};
	    }

	    # convert to storable format
	    $passtype or $passtype = $config{auth}{password_storage_method};
	    my $pass_store = $this->encode_password($password,$passtype);

	    # save it
	    return $share{DB}->update($config{auth}{user_table},
				      {$config{auth}{user_pwd_column}=>$pass_store},
				      {$config{auth}{user_uid_column}=>$uid});
	}
    }
    return $msg{"no such user"};
}

# encode_password: convert password to storable form

sub encode_password {
    my ($this,$password,$passtype) = @_;
    my $pass_store = $this->run_handler("encode_password",$password,$passtype);
    return $pass_store if (defined $pass_store);
    $passtype or $passtype = $config{auth}{password_storage_method};
    if ($passtype eq "des") {
	# DES-encrypt the password
	$pass_store = crypt($password.$config{auth}{salt},&randtext(2,'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'));
    }
    elsif ($passtype eq "md5") {
	# md5 hash the password
	$pass_store = &md5_hex($password.$config{auth}{salt});
    }
    elsif ($passtype eq "md5+") {
	# double-hash the password
	$pass_store = &md5_hex(&md5_hex($password).$config{auth}{salt});
    }
    elsif ($passtype eq "crypt") {
	# encrypt the password using ExSite encryption
	require ExSite::Crypt;  # don't load this unless we need it
	my $c = new ExSite::Crypt(mode=>"strong");
	$pass_store = $c->encrypt($password);
    }
    else { 
	# plaintext storage
	$pass_store = $password;
    }
    if ($passtype ne $config{auth}{password_storage_method}) {
	$pass_store = "[$passtype] $pass_store";
    }
    return $pass_store;
}

# compare a password in plaintext to one in stored format

sub compare_password {
    my ($this,$password,$pass_store,$passtype) = @_;
    my $pass = $this->run_handler("compare_password",$password,$pass_store,$passtype);
    return $pass if (defined $pass);

    if ($pass_store =~ /^\[(cleartext|des|crypt|md5\+?)\] (.+)$/) {
	# storage method coded into the stored password
	$passtype = $1;
	$pass_store = $2;
    }
    $passtype or $passtype = $config{auth}{password_storage_method};
    if ($passtype eq "des") {
	# encrypt the password claim before comparing with stored version
	# NB: 2 salts: $salt is the DES salt, $config{auth}{salt} is the 
	# system salt in case the password is too small
	my $salt = substr($pass_store,0,2);
	$pass = ($pass_store eq crypt($password.$config{auth}{salt},$salt));
    }
    elsif ($passtype eq "md5") {
	# encrypt the password claim before comparing with stored version
	$pass = ($pass_store eq &md5_hex($password.$config{auth}{salt}));
    }
    elsif ($passtype eq "md5+") {
	# encrypt password claim before comparing with stored version
	$pass = ($pass_store eq 
		 &md5_hex(&md5_hex($password).$config{auth}{salt}));
    }
    elsif ($passtype eq "crypt") {
	# decrypt the real password and compare with claim
	require ExSite::Crypt;  # don't load this unless we need it
	my $c = new ExSite::Crypt(mode=>"strong");
	$pass = ($c->decrypt($pass_store) eq $password);
    }
    else {  # cleartext
	# by default we just compare the two values directly
	$pass = ($pass_store eq $password);
    }
    return $pass;
}

# Test Password Strength
# Password strength can be thought of as the number of characters above the 
# minimum that add to the password's security. If a password should be at 
# least 5 characters, then the strength is the number of *additional* secure 
# characters, eg. a 6-character password would have a strength of 1.
#
# Not all characters are equal; duplicate and sequential characters, and 
# dictionary words are less secure. Digits, capital letters, and 
# punctuation marks are more secure.
#
# As a general rule, your password strength should be >= your access level.
#
# For example (based on minimum password length of 5):
# PASSWORD      STRENGTH    NOTES
# -------------------------------------------------
# password      -2          3 characters more than needed, but dictionary words are weak
# password0     0           still weak, but digit helps
# passwerd0     0.5         "pass" is still a dictionary word
# Passwerd0     1.5         capitalization helps
# P4sswerd0     5.5         no dictionary words, but "wer" is sequential on querty keyboards
# pA55w0rd      7           no dictionary words, no sequential characters
# pA55-w0rd!    11          adding punctuation helps

sub password_strength {
    my ($this,$password,$login) = @_;
    # login id is optional, but allows for extra tests
    my $strength = $this->run_handler("password_strength",$password,$login);
    return $strength if (defined $strength);

    my $base_strength = $config{auth}{base_pwd_strength};

    $strength = length($password) - $base_strength;

    # count digits, upper case, and non-alphanumeric characters as double

    foreach my $char (split //,$password) {
	$strength += 1 if ($char=~ /\d/);
	$strength += 1 if ($char=~ /[A-Z]/);
	$strength += 1 if ($char=~ /[^0-9a-zA-Z]/);
    }

    # discount use of username in password
    if ($login && $password =~ /$login/i) {
	$strength -= length $login;
    }

    # discount common character sequences (only count for half character value)
    # eg. "password1234"
    my $discount = 0;
    foreach my $sequence ("1234567890","0987654321",
			  "abcdefghijklmnopqrstuvwxyz",
			  "qwertyuiop","asdfghjkl","zxcvbnm") {
	my @subseq;
	my $found = 0;
	my $multiplier = $sequence =~ /\d/ ? 2 : 1;
	foreach my $char (split //, $sequence) {
	    push @subseq, $char;
	    shift @subseq if (scalar @subseq > 3);
	    next if (scalar @subseq < 3);
	    my $subseq = join("",@subseq);
	    if ($password =~ /$subseq/i) {
		if (! $found) {
		    $discount += 2 * $multiplier;
		    $found = 1;
		}
		$discount += 1 * $multiplier;
	    }
	}
    }
    $strength -= $discount / 2;

    # discount repeated characters (3+ chars)
    # eg. "password1111"
    my @subseq;
    $discount = 0;
    foreach my $char (split //,$password) {
	push @subseq, $char;
	shift @subseq if (scalar @subseq > 3);
	if ($subseq[0] eq $subseq[1] && $subseq[0] eq $subseq[2]) {
	    $discount += 1;
	    $discount += 1 if ($subseq[0] =~ /\d/);
	}
    }
    $strength -= $discount;

    # discount common words (half value)
    # eg. "password" (contains pas, ass, word)
    my @word = ('able','ably','ace','ache','acing','act','add','ado','ads','aft',
'age','ago','ague','aid','ail','aim','air','ale','all','alter',
'amble','amp','anal','and','anger','angle','ani','ant','any','ape',
'apse','apt','arc','are','ark','arm','art','ash','ask','asp',
'ass','aster','ate','aunt','aver','awe','awl','axe','aye','back',
'bad','bag','ban','bar','base','bat','bed','bee','beg','best',
'bet','bid','big','bin','bit','bloc','blur','boa','bomb','bond',
'boo','bound','bow','box','boy','bra','buck','bud','buff','bug',
'bull','bum','bun','bur','bus','but','cab','cad','calm','cam',
'can','cap','car','cast','cat','cave','cede','cent','char','chi',
'cite','city','cock','cod','comb','come','con','coo','cop','cord',
'corn','cost','cot','count','cove','cow','cross','cry','cue','cup',
'cur','cut','cycle','dam','day','deal','deb','deli','den','dew',
'dial','die','dig','dim','din','dip','dis','dive','doc','dog',
'don','door','dot','drop','duct','due','dust','each','ear','ease',
'east','eat','eave','edge','edit','eel','egg','ego','eight','eke',
'elect','elf','ell','ems','end','enter','eon','era','ere','erg',
'err','ester','eta','etch','eve','evil','ewe','expo','eye','fan',
'far','fast','fat','fed','fee','fen','fer','fest','fie','fig',
'file','fin','fir','fish','fit','fix','flat','flu','fly','fog',
'foot','for','foul','free','fresh','fro','full','fun','fur','gab',
'gag','gain','gal','gas','gel','gene','gent','get','gig','gin',
'give','god','goo','got','grad','gun','hack','had','ham','hang',
'hard','harp','has','hat','have','haw','head','heap','heck','help',
'hem','hen','her','hes','hew','hick','hid','hie','high','him',
'hip','his','hit','hive','hoe','hole','home','hook','hoot','hop',
'horn','hos','hot','hove','how','hum','hut','ice','ides','idle',
'idly','ids','ilk','ill','imp','inch','ink','inn','ins','inter',
'ion','ire','irk','iron','ism','itch','its','jack','join','joy',
'just','ken','key','kid','kin','kit','lab','lack','lad','lag',
'lain','lam','lance','lane','lank','lap','last','law','lax','lay',
'laze','lea','led','lee','leg','lent','less','lest','let','lib',
'lick','lid','lie','lift','light','like','limb','lime','line','lip',
'list','lit','live','load','lob','lock','log','long','look','loom',
'lop','lose','loss','lot','loud','love','low','luck','lug','lung',
'lush','lust','lute','lying','mad','main','man','mar','mas','mat',
'mean','meg','men','mes','met','mid','mil','mind','mine','mini',
'miss','mist','mitt','mix','mock','mod','moo','mote','moth','mount',
'move','mud','mum','mute','nab','nag','name','nap','nary','need',
'nest','net','new','nick','nigh','nine','nip','nit','nod','non',
'nor','not','now','nth','numb','nut','oak','oar','oat','odd',
'ode','off','oft','oil','old','once','one','oops','opt','oral',
'orb','order','ore','otter','ouch','ounce','our','out','ova','over',
'owe','owl','own','pack','pad','pain','pal','pan','pap','par',
'pas','pat','paw','pay','pea','peck','pee','pen','per','pet',
'pick','pie','pig','pin','pip','pis','pit','plan','ploy','plum',
'ply','poi','pol','pool','pop','port','pose','post','pot','pound',
'press','print','pro','pun','pus','put','qua','quest','queue','quit',
'rack','rag','rain','raise','ram','ran','rap','rat','rave','raw',
'ray','raze','read','real','ream','red','reed','ref','rely','rent',
'rep','rest','rev','rib','rich','rick','rid','rift','rig','rim',
'ring','riot','rip','rise','risk','rite','road','rob','rock','rod',
'roll','romp','roof','room','root','rope','rose','rot','round','rove',
'row','rub','rude','rue','rug','rum','run','rush','rust','rut',
'sac','sad','safe','sag','salt','sat','saw','say','sea','sect',
'see','sent','serve','set','sex','she','shin','short','shy','sic',
'side','sigh','sign','sin','sir','sis','sit','six','ski','sky',
'sly','sob','sol','some','son','sort','sound','spa','spec','spur',
'step','stud','sty','sub','sue','suit','sum','sun','sup','sure',
'tab','tack','tag','take','talk','tam','tan','tap','tar','tat',
'tax','tea','tee','temp','ten','tern','test','text','the','thin',
'tho','thy','tic','tie','tile','time','tin','tip','tit','tom',
'ton','too','top','tor','tot','tow','tress','try','tub','tun',
'type','ugh','umber','ump','under','ups','urge','urn','use','utter',
'van','vat','vent','verse','very','vest','vet','via','vie','vine',
'viol','vise','void','volt','vote','vow','wag','wait','wake','wan',
'war','was','way','wed','wee','who','wide','win','wise','wit',
'woo','word','work','writ','yea','yon','you','zed','zing');

    $discount = 0;
    foreach my $word (@word) {
	if ($password =~ /$word/i) {
	    $discount += length $word;
	}
    }
    $strength -= $discount / 2;

    return $strength;
}

sub password_strength_old {
    my ($this,$password,$login) = @_;
    # login id is optional, but allows for extra tests
    my $strength = $this->run_handler("password_strength",$password,$login);
    return $strength if (defined $strength);

    # starting strength depends on initial password length
    my $len = length $password;
    if ($len < 7) {
	$strength = -1;
    }
    elsif ($len < 10) {
	$strength = 0;
    }
    else {
	$strength = 1;
    }

    my $pass = $password;
    if ($login) {
	# if login is repeated in password, discount it for strength purposes
	$pass =~ s/$login//i;
    }

    # discount any of the polygrams for strength purposes
    # These indicate the use of common words or names in whole or part,
    # and potential vulnerability to dictionary attacks.
    my $foundgram = " ";
    if (-e "conf/polygrams.txt") {
	if (open F, "<conf/polygrams.txt") {
	    my @polygram = <F>;
	    chomp @polygram;
	    foreach my $gram (@polygram) { 
		# if the polygram exists in lower-case, discount completely
		$pass =~ s/$gram//;
		if ($pass =~ /$gram/i && $foundgram !~ /$gram/) {
		    # polygram found, but mixed case; discount slightly
		    $strength -= 1.0;
		    $foundgram .= "$gram ";
		}
	    }
	}
    }

    $len = length $pass;
    # discount repeated characters
    my @pass = split //,$pass;
    my $last = undef;
    foreach my $p (@pass) {
	if ($p eq $last) {
	    $p = undef;
	}
	else {
	    $last = $p;
	}
    }
    $pass = undef;
    foreach my $p (@pass) {
	$pass .= $p if (defined $p);
    }
    $len = length $pass;

    # increase strength by length of discounted password
    $strength += sqrt $len;
    
    # increase strength if password includes digits, decrease if not
    $pass =~ s/\d//g;
    my $newlen = length $pass;
    my $diff = $len - $newlen;
    $strength += (($diff > 2 ? 2 : $diff) || -1);

    # increase strength if password includes uppercase, decrease if not
    $len = $newlen;
    $pass =~ s/[A-Z]//g;
    $newlen = length $pass;
    $diff = $len - $newlen;
    $strength += (($diff > 3 ? 3 : $diff) || -1);

    # increase strength if password includes non-alphanumeric characters, decrease if not
    $len = $newlen;
    $pass =~ s/[^0-9a-zA-Z]//g;
    $newlen = length $pass;
    $strength += (($len - length($pass)) || -1);

    return $strength * 3;
}

# Authentication Token handling:
# an authtoken is an encrypted string that can be included in the
# query string, which will automatically authenticate the user.

# make_authtoken : generate an authtoken
# $username = the username to auto-validate the user under
# $expiry = number of days in future the authtoken should expire
# $url = the url that the authtoken can be used on

### TODO: support "short" authtokens which use a CRCsum in place of a URL

sub make_authtoken {
    my ($this,$username,$expiry,$url) = @_;
    # accept UID in place of username
    my $udata = ($username =~ /^\d+$/) ?
	$share{DB}->fetch($config{auth}{user_table},$username) : 
	$share{DB}->fetch_match($config{auth}{user_table},{$config{auth}{user_login_column}=>$username})->[-1];
    return undef if (! $udata);  # no such user
    if ($expiry !~ /^-?\d+$/) { $expiry = 0; }
    if ($expiry > 0) {
	# we have been passed a number of days in the future;
	# convert this to a unix-timestamp-style day count 
	# (ie. days since Jan 1, 1970)
	my $t = new ExSite::Time;
	$t->add($expiry,"days");
	$expiry = int($t->write("unix_timestamp") / 86400 + 1);
    }
    if ($url) {
	# store complete URL
	# we need to encode the script name, path info, and query args
	# 1) remove the server to save space
	$url =~ s/^$config{server}{server}//;
    }
    $username = &safetext($udata->{$config{auth}{user_login_column}});
    my $authtoken_plaintext = "$expiry;$username";
    if ($url) { $authtoken_plaintext .= ";$url"; }
    if ($config{token}{authtoken} && (tied %token)->enabled) {
	return (tied %token)->make($authtoken_plaintext);
    }
    else {
	my $crypt = new ExSite::Crypt;
	return $crypt->encrypt($authtoken_plaintext);
    }
}

# validate_authtoken : return the username, if the authtoken is valid

sub validate_authtoken {
    my ($this,$authtoken) = @_;
    my $authtoken_plaintext;
    if ($config{token}{authtoken} && (tied %token)->enabled) {
	$authtoken_plaintext = $token{$authtoken};
    }
    else {
	my $crypt = new ExSite::Crypt;
	$authtoken_plaintext = $crypt->decrypt($authtoken);
    }
    my ($expiry,$username,$url) = split(/;/,$authtoken_plaintext,3);
    $username = &unsafetext($username);

    # validate the expiry time of the authtoken
    $expiry *= 86400;
    if ($expiry > 0 && time > $expiry) {
	$username = undef;
	$this->warn("Sorry, you have tried to connect using an expired authentication token for $username;  access is denied.");
    }

    # validate the user name
    if ($username) {
	my $udata = $share{DB}->lookup($username);
	if (ref $udata ne "HASH") {
	    $this->error("invalid authtoken for $username;  no such user.");
	    $username = undef;
	}
    }

    ### FIXME: use URI for parsing?

    # validate the URL
    if ($username && $url) {
	my ($protocol,$host,$scriptpath,$scriptfile,$pathinfo,$query) = 
	    &parse_url($url);
	if ($share{ENV}{SCRIPT_NAME} =~ /\/$scriptfile$/ &&
	    $share{ENV}{PATH_INFO} =~ /^$pathinfo$/) {
	    my %q1 = &DecodeString($query);
	    my $input = new ExSite::Input;
	    my $q = $input->query;
	    my %q2 = %$q;
	    delete $q2{_auth};
	    foreach my $key (keys %q2) {
		if (exists $q1{$key}) {
		    if ($q1{$key} eq $q2{$key}) {
			delete $q1{$key};
			delete $q2{$key};
		    }
		}
	    }

	    # if q1 and q2 are identical, both should now be empty
	    if (keys %q1 > 0 || keys %q2 > 0) {
		$this->error("invalid authtoken for $username; invalid URL.");
		$this->error(&ShowHash(%q1)." != ".&ShowHash(%q2));
		$username = undef;
		$expiry = 0;
	    }
	}
	else {
	    $this->error("invalid authtoken for $username; invalid URL.$share{ENV}{SCRIPT_NAME} != $scriptfile; $share{ENV}{PATH_INFO} != $pathinfo");
	    $username = undef;
	    $expiry = 0;
	}
    }
    return ($username,$expiry);
}

# process_authtoken : login the user, if the authtoken is valid

sub process_authtoken {
    my ($this,$authtoken) = @_;
    my ($login,$expiry) = $this->validate_authtoken($authtoken);
    if ($login) {
	if ($expiry == 0) {
	    # login expires instantly;  do not set a cookie
	    $this->do_login_temp($login);
	}
	else {
	    # login persists
	    $this->do_login($login);
	}
    }
    return;
}

# check_authtoken : find an authtoken in the input and process it

sub check_authtoken {
    my ($this) = shift;
    my $in = new ExSite::Input;
    my $auth = $in->combine()->{_auth};
    if ($auth) {
	$this->process_authtoken($auth);
	# If the authtoken is accepted, it will reset our identity;
	# if not, we will fall back on the previously set identity.
    }
    return;
}

# fetch all admin tickets

sub my_sites {
    my ($this) = @_;
    my $stat = $this->run_handler("my_sites");
    return $stat if (defined $stat);
    if (! $this->{my_sites}) {
	$this->{my_sites} = $share{DB}->get_query("my sites",$share{DB}->my_uid);
    }
    return wantarray ? @{$this->{my_sites}} : $this->{my_sites};
}

# ditto, but do not count website templates
### website templates not supported yet

sub my_real_sites {
    my ($this) = @_;
    return $this->my_sites();
}

# return list of sites the user has member-level access to

sub my_access_keys {
    my $this;
    my @sites;
    if ($this->level) {
	# start with all sites with admin access
	@sites = $this->my_real_sites;
	# add sites with regular member access
	my $user = $share{DB}->my_user_record;
	if ($user->{section_id}) {
	    push @sites, $share{DB}->fetch("content",$user->{home});
	}
    }
    return @sites;
}

# return the current site data (may require some guesswork)

sub this_site {
    my ($this) = @_;
    if ($share{Page}) {
	# we're on a page, so return the page's section
	return $share{Page}->my_section->get();
    }
    elsif ($share{Section}) {
	# we're on a section, so return it
	return $share{Section}->get();
    }
    else {
	# we're somewhere else, possibly an admin screen
	my $input = new ExSite::Input;
	my $claimed_section_id = $input->combine()->{section_id};
	if ($claimed_section_id) {
	    # the input data declares our section; validate it
	    return $this->owns($claimed_section_id) ?
		$share{DB}->fetch("content",$claimed_section_id) :
		undef;
	}
	my @sites = $this->my_real_sites;
	if (scalar @sites == 1) {
	    # the user only has key to one section, use it
	    return $sites[0];
	}
	my %u = $share{DB}->my_user_record();
	if ($u{home}) {
	    # user has a primary site defined
	    return $share{DB}->fetch("content",$u{home});
	}
    }
    return undef;
}

#----------------------------------------------------------------------
# site_of : returns the section of a dyanmic content URL
#
# Only works for page and view.  For all other URLs,
# returns "0".

sub site_of {
    my ($this,$url) = @_;
    my $uri = new ExSite::URI(uri=>$url);
    my $q = $uri->get("query_data");
    my $p = $uri->get("path_info");
    if ($uri->get("script_name") =~ /$config{prog}{page}/) {
	if ($q->{_id}) {
	    # specified as id
	    my $p = $share{DB}->fetch("content",$q->{_id});
	    if ($p) {
		my $c = new ExSite::Content(data=>$p);
		return $c->my_section->id;
	    }
	    else {
		return 0;
	    }
	}
	elsif ($p) {
	    # specified as path
	    my $c = new ExSite::Content();
	    my @path = $c->path_to_obj();
	    while ($c = pop @path) {
		return $c->id if ($c->subtype eq "section");
	    }
	    return 0;
	}
    }
    elsif ($uri->get("script_name") =~ /$config{prog}{view}/) {
	# specified as path
	my $c = new ExSite::Content();
	my @path = $c->path_to_obj();
	while ($c = pop @path) {
	    return $c->id if ($c->subtype eq "section");
	}
	return 0;
    }
    return 0;
}

# test for "ownership" of a site, ie. an admin key

sub owns {
    my ($this,$site,$uid) = @_;    # $site can be a section hash, or a section ID
    my $stat = $this->run_handler("owns",$site,$uid);
    return $stat if (defined $stat);    
    if (! $site) { $site = $this->this_site(); }
    my $sid = ref $site eq "HASH" ? $site->{content_id} : $site;
    return 0 if (! $sid);
    my $section = $this->get_section($site);
    return $section->has_role($uid); # accept any role
}

#
# user management
#

# fetch_admins : fetch all users with unrestricted access

sub fetch_admins {
    my ($this,$site) = @_;
    return $this->fetch_users_by_level($site,$config{auth}{level}{admin});
}

# fetch all users with manager level access (does not include admins)

sub fetch_managers {
    my ($this,$site) = @_;
    return $this->fetch_users_by_level($site,$config{auth}{level}{manager});
}

# fetch all users with a certain level of access (does not include admins)

sub fetch_users_by_level {
    my ($this,$site,$level) = @_;
    if (! defined $level) { $level = 1; }
    my @users_by_level;
    if ($site) {
	my $sid;
	$sid = (ref $site eq "HASH") ? $site->{section_id} : $site;

	# fetch everyone with an admin key
	my @users = $share{DB}->fetch_m2m($config{auth}{user_table},"content",$sid,"content_key");
	# select only those at our level of access
	foreach my $u (@users) {
	    if ($u->{$config{auth}{user_access_column}} == $level) {
		push @users_by_level, $u;
	    }
	}

	# fetch everyone with this as their home site
	push @users_by_level, $share{DB}->fetch_match($config{auth}{user_table}, 
						      { $config{auth}{user_access_column}=>$level, section_id=>$sid});

	my %user = map { $_->{$config{auth}{user_uid_column}} => $_ } @users_by_level;
	return values %user;
    }
    else {
	# no site given, just take everyone
	@users_by_level = $share{DB}->fetch_match($config{auth}{user_table},{$config{auth}{user_access_column}=>$level});
	return @users_by_level;
    }
}

# find most authoritative user on a site (or any content)

sub fetch_owner {
    my ($this,$content) = @_;
    if (! $content) { $content = $this->this_site; }
    if ($content) {
	my $c = new ExSite::Content(data=>$content);
	$c = $c->get_content_obj();

	# 1) check the keyring

	my $roles = $c->all_roles();

	foreach my $role (qw(owner administrator editor reviewer designer)) {
	    my @uid = scalar keys %{$roles->{$role}};
	    if (scalar @uid > 0) {
		return $this->fetch($config{auth}{user_table},$uid[0]);
	    }
	}

	# 2) check for admins/manager who have this as their home site

	my @u = $this->fetch_match($config{auth}{user_table},"section_id=$content->{content_id} and $config{auth}{user_access_column}>=$config{auth}{level}{manager}");
	if (@u > 0) {
	    foreach my $u (@u) {
		if ($u->{$config{auth}{user_access_column}} >= $config{auth}{level}{administrator}) {
		    return $u;
		}
	    }
	    return $u[0];
	}
    }

    # 3) just take any high-level admin
    my @u = $this->fetch_match($config{auth}{user_table},{$config{auth}{user_access_column}=>$config{auth}{level}{administrator}});
    if (@u > 0) {
	return $u[0];
    }
    return undef;
}

sub owner_email {
    my ($this,$site) = @_;
    if ($site) {
	my $u = $this->fetch_owner($site);
	if (ref $u eq "HASH" && $u->{$config{auth}{user_email_column}}) {
	    return $u->{$config{auth}{user_email_column}};
	}
    }
    # no owner email found; use config administrator email
    return $config{site}{administrator};
}

#------ groups -------

sub groups {
    my ($this,$site) = @_;
    if ($site) {
	my $section = $this->get_section($site);
	return $share{DB}->fetch_match("group",$section->id);
    }
    else {
	return $share{DB}->fetch_all("group");
    }
}

sub in_group {
    my ($this,$group,$uid,$site) = @_;
    my @groups = $this->groups();
    return 0 if (scalar @groups == 0);
    return 1 if (! $group); # in a group, not specified which one
    my (%grname,%grid);
    foreach my $gr (@groups) {
	$grid{$gr->{gid}} = $gr;
	$grname{$gr->{section_id}}{$gr->{name}} = $gr;
    }
    if (ref $group eq "HASH") {
	return exists $grid{$group->{gid}};
    }
    elsif ($group =~ /^\d+$/) {
	return exists $grid{$group};
    }
    else {
	# assume it is a group name
	my $section = $this->get_section($site);
	return exists $grname{$section->id}{$group};
    }
}

sub adduser {
    my $this = shift;
    my $stat = $this->run_handler("adduser",@_);
    return $stat if (defined $stat);

    my $udata = shift;  # member datahash
    my @keys = @_;      # admin keys
    my $db = $share{DB};
    my @err;

    # 1) validate the password

    my $stat = $db->validate_password(
				      $udata->{$config{auth}{user_pwd_column}},
				      $udata->{$config{auth}{user_login_column}},
				      $udata->{$config{auth}{user_access_column}},
				      );
    if ($stat) {
	push @err, $stat;
    }

    # 2) ensure the login ID is unique

    my @u = $db->fetch_match($config{auth}{user_table}, { login=>$udata->{$config{auth}{user_login_column}} });
    if (@u > 0) {
	push @err, "That $config{auth}{login_prompt} is already in use - please try another";
    }

    # 3) name

    if (!$this->user_name($udata)) {
	push @err, "Cannot insert member - no name provided";
    }

    # 4) validate the email

    $stat = $db->validate_column($config{auth}{user_table},"email",$udata->{$config{auth}{user_email_column}});
    if ($stat) {
	push @err, "Invalid email address";
    }

    # 5) home site

    if ($udata->{$config{auth}{user_gid_column}}) {
	$stat = $db->validate_column($config{auth}{user_table},
				     $config{auth}{user_gid_column},
				     $udata->{$config{auth}{user_gid_column}});
	if ($stat) { 
	    push @err, $stat;
	}
    }

    # abort if there are errors
    if (@err > 0) {
	$this->error(@err);
	return 0;
    }
    
    # insert the user
    if ($udata->{$config{auth}{user_uid_column}}) { 
	$this->warn("removing UID of new user");
	delete $udata->{$config{auth}{user_uid_column}}; 
    }
    my $uid = $db->insert($config{auth}{user_table},$udata);
    if (! $uid) {
	$this->error("failed to add user $udata->{$config{auth}{user_login_column}}");
	return 0;
    }

    # add admin keys

    foreach my $key (@_) {
	next if (ref $key ne "HASH");
	$key->{uid} = $uid;
	my @err = $db->validate_record("content_key",$key);
	if (@err) {
	    $this->error(@err);
	}
	else {
	    $db->insert("content_key",$key);
	}
    }

    return $uid
}

sub deluser {
    my $this = shift;
    my $user = shift;
    my $uid = ref $user eq "HASH" ? $user->{$config{auth}{user_uid_column}} : $user;
    $share{DB}->trash_r($config{auth}{user_table},$uid);
}

# referer check - is there a referer?
# This check is used mostly to reduce crawling or snooping of the database.

sub referer_check {
    my $this = shift;
    # check can be disabled across the board
    return 1 if (! $config{auth}{referer_check});
    # check can be disabled for logged-in users
    my $level = $this->authorize();
    if ($level > 1 && ! $config{auth}{owner_referer_check}) {
	# skip check for admins
	return 1;
    }
    elsif ($level && ! $config{auth}{member_referer_check}) {
	# skip check for regular members
	return 1;
    }
    return defined $ENV{HTTP_REFERER};
}

1;

