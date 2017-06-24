#------------------------------------------------------------------------
# ExSite::Token
#----------------------------------------------------------------------------
#
#   Copyright 2010 Exware Solutions, Inc.  http://www.exware.com
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

=head1 ExSite Tokens

Tokens are short text strings that map to more complex strings in a
token dictionary.  They have many uses, for example:

=over 4

=item * abbreviations

For example, an URL shortener.

=item * security keys

A hard-to-guess string that translates to a privileged function
or piece of information.

=item * captcha solutions

Store the solution to a captcha in a way that is resistant to 
cryptographic attacks, and which allows you to track usage.

=back

Set up your token hash using:

    tie %token, 'ExSite::Token', $single_use, $duration, $uid;

The parameters are optional, and can be adjusted at any time, using:

    (tied %token)->setup($single_use,$duration,$uid);

C<$single_use> means the token can only be looked up once, before it is
deleted.  C<$duration> means the token will only persist for that many
seconds before it is deleted.  C<$uid> ties the token to a particular user
ID.

To translate a token, do this:

    my $value = $token{$key};

Create a token using:

    $token{$key} = $value;

IMPORTANT: this returns the KEY not the VALUE. To set a token to a random
key, use:

    $token{N} = $value;

Where N is an integer; a random key of N characters length will be
used (and returned to the caller).  If N is 0, the default key length
will be used, for example:

    my $key = ( $token{0} = $value );

You can override the default token behaviours when you set it, using:

    (tied %token)->set($key,$value,$single_use,$duration,$uid);

To inspect the value of a token without marking it as used, use:

    my $val = (tied %token)->fetch($key);

=head2 User IDs

Tokens can be tied to particular user IDs.  The token system does nothing
with this information.  It is simply available as a form of metadata on
the token, which can be fetched using:

    (tied %token)->uid($key);

Higher-level systems can use this for whatever purposes they see fit.

=head2 Implementation

Tokens can be stored in the main database and/or the persistent data store.
The following configuration setting determines which method is used:

    token.type = db|store

Store-based tokens are light and fast and are automatically purged
when they expire. They do not require the token table to be present
in the database. However, they may not be as permanent as you require,
since the store can be completely cleared/reset from time to time.

Database-based tokens are more durable, but are slower and require
more resources to process. They also require the token table to be
present in the database. The garbage collection is also somewhat
erratic/random.

=cut

package ExSite::Token;
use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Base;

sub TIEHASH {
    my ($this,%opt) = @_;
    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;
    $obj->setup(%opt);
    return $obj;
}

sub FETCH {
    my ($this,$key) = @_;
    my $token = $this->get($key);
    return defined $token ? $token->{value} : undef;
}

sub STORE {
    my ($this,$key,$val) = @_;
    return $this->set($key,$val);
}

sub DELETE {
    my ($this,$key) = @_;
    return $this->del($key);
}

sub CLEAR {
    my ($this) = @_;
    foreach my $token ($share{DB}->fetch_all("token")) {
	$share{DB}->delete_key("token",{name=>$token->{name}});
    }
}

sub EXISTS {
    my ($this,$key) = @_;
    return defined $this->get($key);
}

sub FIRSTKEY {
    my ($this) = @_;
    $this->{tokens} = &keywise("name",$share{DB}->fetch_all("token"));
    my $dummy = keys %{$this->{tokens}};
    return each %{$this->{tokens}};
}

sub NEXTKEY {
    my ($this,$lastkey) = @_;
    return each %{$this->{tokens}};
}

sub UNTIE {
    my ($this) = @_;
    # randomly purge expired tokens once every 1000 page views or so
    if ($this->{type} eq "db") {
	$this->purge() if (int(rand(1000)) == 1);
    }
    return;
}

sub DESTROY {
    my ($this) = @_;
    return;
}

#=======================================================================
# internal methods

sub setup {
    my ($this,%opt) = @_;
    $this->{single_use} = $opt{single_use};
    $this->{duration} = $opt{duration};
    $this->{uid} = $opt{uid};
    $this->{type} = $opt{type} || $config{token}{type};
}

# key: generate a random, unique key, if needed

sub key {
    my ($this,$size) = @_;
    $size =~ /^\d?\d$/ or $size = 4;
    my $key;
    do {
	$key = &randtext($size,"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz1234567890");
	$size++;
    } until (! $this->fetch($key));
    return $key;
}

# get: retrieve a token for use

sub get {
    my ($this,$key) = @_;
    my $token = $this->fetch($key);
    if ($token) {
	# check expiry
	my $t = new ExSite::Time(); #now
	if ($token->{expiry} !~ /^[-:0 ]*$/ &&
	    $t->diff($token->{expiry},"sql_timestamp") < 0) {
	    # expired
	    $this->del($key);
	    $token = undef;
	}
	elsif ($token->{singleuse} eq "Y") {
	    # single-use
	    $this->del($key);
	}
    }
    return $token;
}

# fetch: retrieve a key from the database

sub fetch {
    my ($this,$key) = @_;
    if ($this->{type} eq "db") {
	my @data = $share{DB}->fetch_match("token",{name=>$key});
	return $data[0];
    }
    else {
	return $store{"token:$key"};
    }
}

# set: define/save a token

sub set {
    my ($this,$key,$val,$single_use,$duration,$uid) = @_;
    defined $single_use or $single_use = $this->{single_use};
    defined $uid or $uid = $this->{uid} || 0;
    defined $duration or $duration = $this->{duration};
    my $data = { 
	name=>$key, 
	value=>$val, 
	singleuse=>$single_use?"Y":"N", 
	uid=>$uid,
	ctime=>undef,
    };
    if ($this->{type} eq "db") {
	$this->set_db($data,$duration);
    }
    else {
	$this->set_store($data,$duration);
    }
    return $val;
}

sub set_store {
    my ($this,$data,$duration) = @_;
    my $etime;
    if ($duration) {
	$etime = time + $duration;
    }
    (tied %store)->put("token:$data->{name}",$data,$etime);
}

sub set_db {
    my ($this,$data,$duration) = @_;
    if ($duration && $duration =~ /^\d+$/) {
	my $t = new ExSite::Time(); #now
	$t->add($duration,"seconds");
	$data->{expiry} = $t->write("sql_timestamp");
    }
    $share{DB}->insert("token",$data);
}

sub del {
    my ($this,$key) = @_;
    if ($this->{type} eq "db") {
	$share{DB}->delete("token",{ name=>$key });
    }
    else {
	delete $store{"token:$key"};
    }
}

# make: create a new token and return the key it is saved under

sub make {
    my ($this,$val,$single_use,$duration,$uid) = @_;
    my $key = $this->key;
    $this->set($key,$val,$single_use,$duration,$uid);
    return $key;
}

# uid: return the UID a key is associated with

sub uid {
    my ($this,$key) = @_;
    my $token = $this->fetch($key);
    return $token->{uid};
}

# purge: remove expired tokens - DB tokens only

sub purge {
    my $this = shift;
    return if ($this->{type} ne "db");
    my $t = new ExSite::Time();
    my $timestamp = $t->write("sql_timestamp");
    $share{DB}->set_query("purge expired tokens",
			  sql=>"delete from token where expiry < ?",
			  mode=>"w",
			  nparam=>1,
			  keys=>["token"]);
    $share{DB}->get_query("purge expired tokens",$timestamp);
    $this->info("purged expired tokens");
}

# enabled: see if tokens are allowed on this system

sub enabled {
    my $this = shift;
    return $this->{type} eq "db" ?
	$share{DB}{map}->is_mapped("token") :
	(tied %store && (tied %store)->is_persistent());
}

1;
