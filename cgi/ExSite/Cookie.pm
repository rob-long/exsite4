#------------------------------------------------------------------------
# ExSite::Cookie
#----------------------------------------------------------------------------
#
#   Copyright 2001-2013 Exware Solutions, Inc.  http://www.exware.com
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

=head1 ExSite Cookie Management

ExSite::Cookie manages your cookie jar, which is a hash (C<%cookie>)
of your cookie names => cookie values.  For simple cookie operations,
you simply need to set/unset cookie values in C<%cookie>, and ExSite
will take care of managing the HTTP cookie protocol to preserve these
values throughout your session.

C<%cookie> should automatically be populated with all cookie names
and values on start-up.  To check the value of a cookie, simply 
look up the cookie name in  C<%cookie>:

    if ($cookie{foo} eq "bar") { ... }

To set a cookie named "foo" to value "bar":

    $cookie{foo} = "bar";

If this creates a new cookie name or changes the value of an existing
cookie, then ExSite will automatically issue a set-cookie: header so
the browser will remember this cookie setting on future requests.  The
set-cookie header will use automatic expiry, path, and domain
settings.  Default behaviour is to expire after the browser is closed,
and to be valid for the default ExSite domain (C<$config{server}{domain}>)
and CGIpath (C<$config{server}{CGIpath}>).

To set a cookie with custom expiry, path, and domain settings, do this:

    (tied %cookie)->set_cookie($name,$value,$path,$domain,$expiry);

C<$expiry> must be in the accepted date format for cookies.
To obtain a set-cookie header line without actually issuing it, do this:

    (tied %cookie)->cookie_header($name,$value,$path,$domain,$expiry);

To unset (clear) a cookie named "foo", use one of:

    delete $cookie{foo};
    $cookie{foo} = undef;

To temporarily set a cookie for this request only, but not for
subsequent requests, do this:

    (tied %cookie)->store($name,$value);  # set
    (tied %cookie)->store($name,undef);   # unset

This has the effect of altering the contents of C<%cookie> but not
actually issuing any set-cookie headers to preserve that information.
These calls only affect the cookie value in the current program.
If spawning other programs that may revert to the original HTTP_COOKIE
value, you will also want to update HTTP_COOKIE:

    (tied %cookie)->store_update($name,$value);  # set
    (tied %cookie)->store_update($name,undef);   # unset

=head2 Cookie Scope

Cookies normally apply to a specific domain and server path.  The
default cookie jar sets these automatically to:

    domain = $config{server}{domain}
    path   = $config{server}{CGIpath}

Cookies not valid in this scope will not be found in the cookie jar.
Cookies set using normal hash settings (eg. C<$cookie{foo}="bar";>)
will be valid for this scope.  However, you can set cookies outside
this scope by using the C<set_cookie()> internal method, described
above.

To create an alternate cookie jar with a different scope, simply
declare a new cookie hash, and tie it to this class with the new path
and domain:

    tie %my_cookie, 'ExSite::Cookie', $path, $domain;

=head2 Long-Duration Cookies

By default, cookies expire when the browser is closed.  You can
optionally set durable cookies as follows:

    (tied %cookie)->store_remember($key,$val);

This will set an explicit expiry time for the cookie.  However, you
must tell your cookie jar what this duration should be, when you set
it up:

    tie %cookie, 'ExSite::Cookie', $path, $domain, "2 weeks";

The duration is specified as a string of the format "NUMBER
TIME_UNITS", eg. "7 days", or "2 weeks", or "3 months".  The default
cookie jar uses the configuration setting
C<auth.long_cookie_duration>, which defaults to "2 weeks".  If you do
not provide your cookie jar with a duration, the cookies will not have
an extended duration.  However, you can always pass an explicit expiry
date:

    (tied %cookie)->store_remember($key,$val,$expiry);

To get a date string in the correct format for C<$expiry>, use a Time
object.  For example:

    my $t = new ExSite::Time;          # now
    $t->add(2,"weeks");                # 2 weeks in future
    my $expiry = $t->write("cookie");  # a date string in cookie format

=head2 Internals

The cookie object has the following internal attributes:

=over 4

=item path

The path for which this cookie jar is valid.

=item domain

The domain for which this cookie jar is valid.

=item duration

Long-duration cookies will last this long.  The duration is specified
as a string of the format "NUMBER TIME_UNITS", eg. "7 days", or "2
weeks", or "3 months".

=item jar

A hash of cookie names/values in this cookie jar.

=back

=cut

package ExSite::Cookie;
use strict;
use ExSite::Config;

#------------------------------------------------------------------------
# Using perl's tie mechanism, we can implement this class implicitly
# using the %cookie variable.  To do that, we need to support the
# following class methods.
#------------------------------------------------------------------------

sub TIEHASH {
    my ($this,$path,$domain,$duration,$cookiedata) = @_;
    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;
    $obj->{path} = $path;
    $obj->{domain} = $domain;
    $obj->{duration} = $duration;
    $obj->{jar} = {};
    $obj->load_cookies($cookiedata);
    return $obj;
}

sub FETCH {
    my ($this,$key) = @_;
    return $this->{jar}{$key};
}

sub STORE {
    my ($this,$key,$val) = @_;
    if (defined $val) {
	if ($val ne $this->{jar}{$key}) {
	    $this->{jar}{$key} = $val;  # done in cookie_header()
	    $this->set_cookie($key,$val);
	}
    }
    else {
	$this->DELETE($key);
    }
}

sub DELETE {
    my ($this,$key) = @_;
    if ($this->EXISTS($key)) {
	delete $this->{jar}{$key};
	$this->erase_cookie($key);
    }
}

sub CLEAR {
    my ($this) = @_;
    foreach my $key (keys %{$this->{jar}}) {
	$this->DELETE($key);
    }
}

sub EXISTS {
    my ($this,$key) = @_;
    return exists $this->{jar}{$key};
}

sub FIRSTKEY {
    my ($this) = @_;
    my $dummy = keys %{$this->{jar}};
    return each %{$this->{jar}};
}

sub NEXTKEY {
    my ($this,$lastkey) = @_;
    return each %{$this->{jar}};
}

sub UNTIE {
    my ($this) = @_;
    return;
}

sub DESTROY {
    my ($this) = @_;
    return;
}

#=======================================================================
# internal methods

# store()
# this changes the contents of %cookie, without affecting the 
# actual browser cookies.  Use it to temporarily change the cookie
# state on this request, but have it revert to the original setting
# on the next request.

sub store {
    my ($this,$key,$val) = @_;
    if (defined $val) {
	$this->{jar}{$key} = $val;
    }
    else {
	delete $this->{jar}{$key};
    }
}

# store_update()
# calls store(), but also updates the HTTP_COOKIE environment variable.
# Use this if spawning other programs (eg. publish.cgi) that may also
# need the temporary cookie data.

sub store_update {
    my ($this,$key,$val) = @_;
    $this->store($key,$val);
    $this->update_cookie();
}

# store_remember()
# use this to store a cookie for an extended period.  You can provide
# your own expiry time, or it will use a system default.
sub store_remember {
    my ($this,$key,$val,$expiry) = @_;
    if (defined $val) {
	$this->{jar}{$key} = $val;  # done in cookie_header()
	if (! $expiry) {
	    my ($n,$tunit) = ($this->{duration} =~ /^(\d+) (\w+)$/);
	    if ($n && $tunit) {
		my $t = new ExSite::Time;
		$t->add($n,$tunit);
		$expiry = $t->write("cookie");
	    }
	}
	$this->set_cookie($key,$val,undef,undef,$expiry);
    }
    else {
	$this->DELETE($key);
    }
}

sub set_cookie {
    my ($this,$name,$value,$path,$domain,$expiry) = @_;
    if (! defined $value) {
	if ($this->EXISTS($name)) {
	    $value = $this->{jar}{$name};
	}
	else {
	    return undef;
	}
    }
    # don't actually set cookies when publishing
    return if ($this->{publish_mode});
    my $header = $this->cookie_header($name,$value,$path,$domain,$expiry);
    print $header;
    $this->update_cookie();
}

sub cookie_header {
    my ($this,$key,$value,$path,$domain,$expiry) = @_;
    if (! $path) { $path = $this->{path}; }
    if (! $domain) { $domain = $this->{domain}; }
    my $out = "Set-cookie: $key=$value; path=$path; domain=$domain";
    if ($expiry) { $out .= "; Expires=$expiry"; }
    return "$out\n";
}

sub erase_cookie {
    my ($this,$key) = @_;
    # set the cookie value to nothing, in case it lingers around
    # set an old date to facilitate clearing of old cookies
    $this->set_cookie($key,"",undef,undef,"Thu, 01-Jan-1970 00:00:00 GMT");
}

sub load_cookies { 
    my ($this,$data) = @_;
    if ($data) {
	# $data contains cookie data to initialize with
	if (ref $data eq "HASH") {
	    # $data is a hash
	    while (my ($key,$value) = each %$data) {
		$this->{jar}{$key} = $value;
	    }
	}
	else {
	    # data is a scalar; assume it is a raw cookie field
	    my @cookies = split /; /, $data;
	    foreach my $cookie (@cookies) {
		my ($key,$value) = split /=/,$cookie,2;
		$this->{jar}{$key} = $value;
	    }
	}
    }
    if (exists $ENV{'HTTP_COOKIE'}) {
        my @cookies = split /; /, $ENV{'HTTP_COOKIE'};
        foreach my $cookie (@cookies) {
	    my ($key,$value) = split /=/,$cookie,2;
	    $this->{jar}{$key} = $value;
	}
    }
    return;
}

# update_cookie updates the contents of $ENV{HTTP_COOKIE} to reflect the
# current state of the cookies.
#
# This is not necessary if you exclusively interact with cookies through
# %cookie, but if any code inspects the cookie environment variable
# directly, it's a good idea to keep it sync'd with %cookie.

sub update_cookie { 
    my $this = shift;
    my @cookies;
    foreach my $key (keys %{$this->{jar}}) {
	push @cookies, "$key=$this->{jar}{$key}";
    }
    $ENV{HTTP_COOKIE} = join("; ",@cookies);
}

# in publish mode, we don't really set cookies
sub publish_mode {
    my $this = shift;
    $this->{publish_mode} = 1;
}

1;

