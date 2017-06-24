#------------------------------------------------------------------------
# ExSite::Session
#----------------------------------------------------------------------------
#
#   Copyright 2001-2006 Exware Solutions, Inc.  http://www.exware.com
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

=head1 ExSite Session Management

A session is a hash of keys/values that is persistent between web site
visits of a single visitor.  Session values that are set on one
request will persist, and be available on subsequent requests.  Sessions
are therefore excellent ways to preserve state, track identity, and
cache useful information about the visitor.

C<ExSite::Session> uses C<ExSite::Store> for low-level session data
storage.  That means that session expiry, session garbage collection,
and session validation are handled automatically by the data store.

=head2 Session Key

Every user who is maintaining a session has a session ID or session
key.  This value is stored in a cookie, so the user must accept this
cookie to benefit from session management.

The session key is only created when you write data to the session.
If the user has never recorded any session data, they will not have a
session key, nor will they have received a session cookie.

The session key is a random 16-character text string.  It should be
very hard to guess, allowing session data to remain reasonably secure,
and suitable for authentication purposes (ie. once the user has been
authenticated, their mere knowledge of their session ID can be taken
as proof of identity).  ExSite supports a "session" authentication
method, which does this automatically. 

However to protect against session ID sniffing, you should also enable
session security (next).

=head3 Session Security

Session hijacking (or sidejacking) is possible if a session ID can be
sniffed from an unencrypted network connection. If this is a concern,
you can enable extra session security by setting the configuration 
setting

    session.secure = 1

This will digitally sign the session with an MD5 hash of information
that comes from the client, such as IP address, user agent, etc. Any
attempt to reconnect to the session much have a matching signature, or
the session connection will fail and a new session will be started
instead. That means that a session hijack from a computer that is not 
identical in its web configuration to the session originator will fail.

=head2 Session Lifetime

The session lifetime depends on the lifetime of items in the store.
By default this is 1 hour maximim idle time.  Sessions are renewed
when they are used, so the total session lifetime is indefinite if the
time between activity is less than 1 hour in each case.

=head2 Fetching and Saving Session Data

Session data can be found in the global C<%session> hash. which should
be automatically populated at system initialization.  Simply use this
hash as a normal perl hash to read session values.

To save data to the session table, simply add or change keys/values in
the C<%session> hash.  They will automatically be saved for future
requests.

=head2 Enabling Session Management

Session management is not enabled by default.  That is because the
underlying storage engine is not enabled by default, for reasons noted
in its documentation.  If you are not using a persistent data store,
then session data will not persist across requests.  There is no harm
in using C<%session> like a normal hash in this case, but it will be
cleared after each request, like C<%share>, so will not be especially
useful.

To enable session management, you must enable persistent storage.  See
the documentation for C<ExSite::Store> for details.  If persistent
storage is working, then session management should also work.

=head2 Inspecting Session Contents

Use the C<StoreAdm> plug-in to inspect items in the persistent data
store.  Sessions are prefixed with "C<session:>".  Click on the
inspect links to view the contents of a session, or the delete links
to manually terminate the session.

=head2 Inspecting Session Contents

Use the C<StoreAdm> plug-in to inspect items in the persistent data
store.  Sessions are prefixed with "C<session:>".  Click on the
inspect links to view the contents of a session, or the delete links
to manually terminate the session.

=cut

package ExSite::Session;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Util;
use Digest::MD5 qw(md5_hex);
use ExSite::Base;
our @ISA = qw(ExSite::Base);

# flag the session code as loaded
# this lets us ignore sessions (and the resulting errors) on
# scripts that do not use them.
$config{session}{loaded} = 1;

#------------------------------------------------------------------------
# Using perl's tie mechanism, we can implement this class implicitly
# using the %session variable.  To do that, we need to support the
# following class methods.
#------------------------------------------------------------------------

sub TIEHASH {
    my ($this) = @_;
    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;

    my $session_cookie = $config{site}{id}."_sessionID";
    my $id = $cookie{$session_cookie};
    if ($id) {
	# appears to be an active session
	$obj->{id} = $id;
	$obj->{data} = $this->load($id);
	if (keys %{$obj->{data}} == 0) {
	    # no data - session must have expired
	    $obj->warn("session $id expired");
	    delete $cookie{$session_cookie};
	    $obj->{expired} = 1;
	    # restart
	    $id = undef;
	}
	if (! $obj->validate()) {
	    # doesn't match profile of session creator - possible hijack
	    $obj->warn("Connection to session $id rejected due to possible session hijack");
	    delete $cookie{$session_cookie};
	    # restart
	    $id = undef;
	}
	else {
	    $obj->audit("Connected to session $id");
	}
    }
    if (! $id) {
	$obj->init;
    }
    $obj->{dirty} = 0;
    return $obj;
}

sub FETCH {
    my ($this,$key) = @_;
    return $this->{data}{$key};
}

sub STORE {
    my ($this,$key,$val) = @_;
    if (defined $val) {
	$this->audit("Session $this->{id}:$key: old value: '$this->{data}{$key}' new value: '$val'");
	$this->{data}{$key} = $val;
	if (! defined $this->{id}) {
	    # we are writing to a brand new session
	    $this->create();
	}
    }
    else {
	delete $this->{data}{$key};
    }
    $this->{data}{_mtime} = time;
    $this->{dirty} = 1;
}

sub DELETE {
    my ($this,$key) = @_;
    $this->audit("Session $this->{id}: deleted $key");
    delete $this->{data}{$key};
    $this->{data}{_mtime} = time;
    $this->{dirty} = 1;
}

sub CLEAR {
    my ($this) = @_;
    $this->audit("Session $this->{id}: cleared");
    foreach my $key (keys %{$this->{data}}) {
	next if ($key =~ /^_[mc]time$/);
	delete $this->{data}{$key};
    }
    $this->{data}{_mtime} = time;
    $this->{dirty} = 1;
}

sub EXISTS {
    my ($this,$key) = @_;
    return exists $this->{data}{$key};
}

sub FIRSTKEY {
    my ($this) = @_;
    my $dummy = keys %{$this->{data}};
    return each %{$this->{data}};
}

sub NEXTKEY {
    my ($this,$lastkey) = @_;
    return each %{$this->{data}};
}

sub UNTIE {
    my ($this) = @_;
    if ($this->{dirty}) {
	# only save dirty session data
	$this->save;
    }
    else {
	$this->{etime} = time + $config{session}{max_idle};
	(tied %store)->renew("session:$this->{id}",
			     $this->{etime});
    }
}

sub DESTROY {
}

#=======================================================================
# internal methods

sub init {
    my $this = shift;
    # initialize an empty session hash
    $this->{id} = undef;
    $this->{data} = {};
    $this->{data}{_ctime} = time;
    if ($config{session}{secure}) {
	$this->{data}{_signature} = $this->signature();
    }
}

# load session data from the store

sub load {
    my ($this,$id) = @_;
    my $data = $store{"session:$id"};
    return (ref $data eq "HASH") ? $data : {};
}

# save

sub save {
    my ($this) = @_;
    if (! defined $this->{id}) {
	# no session ID - it seems like there is nothing to save
	$this->warn("no session to save");
	return 0;
    }
    if (tied %store) {
	# save the session data, and update the expiry time
	$this->{etime} = time + $config{session}{max_idle};
	(tied %store)->put("session:$this->{id}",
			   $this->{data},
			   $this->{etime});
    }
    else {
	# may not be persistent...
	$store{"session:$this->{id}"} = $this->{data};
    }
    $this->info("session $this->{id} updated");
    return 1;
}

# kill

sub kill {
    my ($this) = @_;
    if (! defined $this->{id}) {
	# no session ID - it seems like there is nothing to save
	$this->warn("no session to kill");
	return 0;
    }
    delete $store{"session:$this->{id}"};
    delete $cookie{"$config{site}{id}_sessionID"};
    $this->info("killed session $this->{id}");
    $this->init;
    return 1;
}

# initialize a new session id

sub create {
    my ($this) = @_;

#    # make a session ID from a set of values unique to this visitor
#    my @data = ($ENV{REMOTE_ADDR}, 
#		$ENV{HTTP_USER_AGENT}, 
#		time);
    
#    # add some hard-to-guess data to prevent session key guessing
#    push @data, rand(10);  # approx. 15 random digits
    
#    $this->{id} = md5_hex(@data);

    # use signature() for encoding user profile
    # session key can be purely random
    # this key generator gives 62^16 (10^28) possible keys 

    $this->{id} = &randtext(16,'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789');
    $this->info("creating new session $this->{id}");
    $this->audit("new session $this->{id}");

    # set a session cookie

    $cookie{"$config{site}{id}_sessionID"} = $this->{id};
    return $this->{id};
}

# tell us if this session was just expired

sub expired {
    my $this = shift;
    return $this->{expired};
}

# validate session
#
# When a session is created, we store some profile information about the user,
# such as their IP and user agent. If someone attempts to use the session 
# from a different profile (ie. a different computer), we can reject the 
# connection as a possible session sidejack.
#
# Set the environment variable BYPASS_SECURE_SESSIONS to override the 
# validation check. This is necessary if debugging a live session from
# the CLI debug tool.

sub validate {
    my $this = shift;
    my $ok = 1;
    if ($config{session}{secure} && ! $ENV{BYPASS_SECURE_SESSIONS}) {
	my $sig = $this->signature();
	if ($this->{data}{_signature} ne $sig) {
	    $this->warn("Session profile mismatch");
	    $ok = 0;
	}
    }
    return $ok;
}

# signature : generate a unique hash describing the user's profile (unique
# user-specific data)

sub signature {
    my $this = shift;
    my @profile = (
		   $ENV{REMOTE_ADDR},
		   $ENV{HTTP_USER_AGENT},
		   $ENV{HTTP_ACCEPT},
		   $ENV{HTTP_ACCEPT_CHARSET},
		   $ENV{HTTP_ACCEPT_ENCODING},
		   $ENV{HTTP_ACCEPT_LANGUAGE}
		   );
    return &md5_hex(@profile);
}

1;

