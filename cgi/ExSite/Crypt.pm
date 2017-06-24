package ExSite::Crypt;
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

#======================================================================

=pod

=head1 ExSite::Crypt - ExSite crypto driver

The Crypt class encrypts/decrypts arbitrary data and represents the
ciphertext using URL-safe characters [A-Z][a-z][0-9][-_].  This allows
the ciphertext to easily be placed in URLs, forms, or SQL statements.

The default encryption scheme is TEA (Tiny Encryption Algorithm) as
defined at http://www.ftp.cl.cam.ac.uk/ftp/papers/djw-rmn/djw-rmn-tea.html .
TEA provides strong 128-bit encryption with a very concise algorithm, 
and concise output.  ExSite's implementation has the following features 
not found in other TEA implementations:

=over 4

=item * URL-safe ciphertext (modified MIME encoding)

=item * strong mode (128-bit MD5 passkey hashing, random pad bits, more rounds)

=item * fast mode (simple passkey, no pad bits, fewer rounds)

=item * integration with ExSite kernel tools

=item * allows for substitution of alternate encryption engines

=back

Although ExSite alters your key in strong mode (by salting the unused
pad bits with random data), it is still good practice to use a
different passphrase for strong and fast encryption tasks.

To make the ciphertext URL-safe, we MIME-encode it, then we replace
'+' characters with '-', and '/' with '_'.  We also strip MIME's '='
pad characters, which are superfluous for our purposes.

To override the default crypto algorithms, simply install your own 
'encrypt' and 'decrypt' handlers, and have them do whatever you like.
They receive 1 argument each, the plaintext and ciphertext, respectively.
There is an expectation by some parts of ExSite that the ciphertext is 
URL-safe ASCII.  You can always pass your text through
ExSite::Misc::safetext and ExSite::Misc::unsafetext if not URL-safe.

=head2 Usage

    my $c = new ExSite::Crypt(%options);  # eg.

    my $c = new ExSite::Crypt();  # or

    my $c = new ExSite::Crypt(key=>"a reasonably lengthly passphrase", 
                            mode=>"fast");

    my $c = new ExSite::Crypt(level=>32,mode=>"fast");  # use full number of rounds, but other fast shortcuts

    my $ciphertext = $c->encrypt($plaintext);

    my $plaintext = $c->decrypt($ciphertext);

=head2 Strong or Fast?

Strong mode provides maximum data security, by filling unused pad bits
with random data, MD5 hashing the passkey for better use of the key
space, and using the maximum recommended number of mixing rounds.
Strong mode is recommended for secure data storage, eg. data that is
saved to a database, or critical/sensitive data that is transmitted over
insecure connections.

Fast mode uses unhashed passwords, empty pad bits, and a smaller
number of mixing rounds.  This makes it about 3 times faster than
strong mode, at the expense of being less secure.  Fast mode security
should be adequate to prevent simple sniffing, eavesdropping, or
unsophisticated cracking attempts, but not a concerted attack by
experts.  It is recommended for obfuscating data in URLs or forms to
prevent tampering if the number of such obfuscations is potentially
large and therefore detrimental to performance.

=head2 Automatic Encrpytion

Database columns that are defined (by ExSite) to be of the "crypt" datatype
will have their contents automatically encrypted/decrypted when written to
or read from the database.  These columns otherwise behave like "text"
datatypes.

The user identity will be encrypted in the authentication cookie, if
C<$config{auth}{type} eq "crypt">.  This authentication mode saves
resources since the cookie contents are more trustworthy, so 
the user does not need to be revalidated on every request.

User passwords will be automatically encrypted/decrypted if
C<$config{auth}{password_storage_method} eq "crypt">.

The Crypt class is also invoked automatically for construction and parsing
of authtokens for automatic logins (see ExSite::Auth).

=head2 Key Security

Decryption keys are stored by default in cleartext in your
configuration file.  That means that encrypted data may be reasonably
secure in transmission, or while stored in a database, but if you have
concerns about securing data from users who have server access
(ie. persons who can read the configuration file), then the default
key storage method is inadequate.

To implement a custom key storage system, install a "crypt_key" handler
to return the appropriate decryption key.  The handler is passed 
the key type (usually "key_strong" or "key_fast"), and should return
the appropriate key.  The handler can implement whatever key fetching
methods and security protocols it chooses to.

B<Example:> Write a compiled program, say C<getkey.c>, that simply writes
the key phrase to C<stdout>.  Inside this program, conduct whatever tests
you feel are necessary to validate that it is safe to give out the key,
before you actually write it out.  Then make an ExSite handler to invoke
this program, eg.

    sub crypt_key_handler {
        my ($this,$keytype) = @_;
        # NOTE: this example ignores the key type.
        # We simply run our external key fetching program
        return `getkey.exe`;
    }

Using this method, your keys are never stored in plain view.  However,
practically speaking they are still not terribly secure.  Since the key
fetching program must be run in an automated fashion by the webserver, all
an attacker has to do is spoof the webserver environment to fool the program
into thinking it is safe to reveal the key.  Also, if you encode the key 
in a simple string inside the program, it may be possible to extract the
key without even running the program, simply by inspecting the object code.

In general, if the encrypted data is designed to be automatically decrypted
by an automated server process, the ultimate security of your data is not
going to be terribly strong.  Adding stronger ciphers will not help, since
the main point of weakness is that the webserver (an unprivileged process)
requires access to the keys to make use of the encrypted data.

=cut
    


#======================================================================

use strict;
use integer;
use ExSite::Config;
use ExSite::Base;
use ExSite::Misc;
use MIME::Base64;
use FileHandle;     # for external crypt_tea
use IPC::Open2;     # ditto

use vars qw(@ISA $DELTA $NROUND_FAST $NROUND_STRONG);
@ISA = qw(ExSite::Base);

$DELTA = 0x9E3779B9;
$NROUND_FAST   =  8;
$NROUND_STRONG = 64;

#======================================================================
# public methods

sub new ($%) {
    my ($this,%opt) = @_;
    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;

    # fast or strong ?

    my $mode = $opt{mode} || $config{crypt}{default_mode};
    if ($mode eq "fast") {
	$obj->{strong} = 0;
	$obj->{level} = $opt{level} || 
	    $config{crypt}{nround_fast} ||
	    $NROUND_FAST;
# fails with XXTEA, incorrect number of key bits??
#	$obj->{key} = $opt{key} || $obj->get_key("key_fast");
    }
    else {
	$obj->{strong} = 1;
	$obj->{level} = $opt{level} || 
	    $config{crypt}{nround_strong} ||
	    $NROUND_STRONG;
    }
    # use a 128-bit hash of our key instead of the plain key
    use Digest::MD5 qw(md5);
    $obj->{key} = &md5($opt{key} || $obj->get_key("key_strong"));

    # test whether we are 64-bit safe; if so, we can use the pureperl version
    $obj->{pureperl} = ((1<<32)==1);

    $obj->initialize_object;
    return $obj;
}

sub encrypt {
    my ($this,$data) = @_;

    my $crypttext = $this->run_handler("encrypt",$data);
    return $crypttext if (defined $crypttext);

    if ($this->{pureperl}) {
	return $this->encrypt_tea($data,$this->{key});
    }
    else {
	# use our external encryption tool
	my ($rounds,$out);
	if ($this->{level} != $NROUND_STRONG) {
	    $rounds = " -n $this->{level}"
	}
	# scrub the command for uptight 5.8 taint checks
	my $cmd = "./crypt_tea$rounds";
	$cmd =~ /^(\.\/crypt_tea( -n \d+)?)$/;
	my $secure_cmd = $1;
	if ($secure_cmd) {
	    if (&is_tainted($ENV{PATH})) { 
		$ENV{PATH} = $config{server}{securepath};
	    }
	    my $pid = open2(*R, *W, "./crypt_tea$rounds");
	    print W $this->{key};
	    print W $data;
	    close W;
	    $out = <R>;
	    close R;
	}
	else {
	    $out .= $this->error("insecure call to crypt_tea");
	}
	return $out;
    }
}

sub decrypt {
    my ($this,$data) = @_;

    my $crypttext = $this->run_handler("decrypt",$data);
    return $crypttext if (defined $crypttext);

    if ($this->{pureperl}) {
	return $this->decrypt_tea($data,$this->{key});
    }
    else {
	# use our external encryption tool
	my $rounds;
	if ($this->{level} != $NROUND_STRONG) {
	    $rounds = " -n $this->{level}"
	}
	if (&is_tainted($ENV{PATH})) { 
	    $ENV{PATH} = $config{server}{securepath};
	}
	my $pid = open2(*R, *W, "./crypt_tea -d$rounds");
	print W $this->{key};
	print W $data;
	close W;
	my $out = <R>;
	close R;
	return $out;
    }
}

#======================================================================
# private methods

sub get_key {
    my ($this,$keytype) = @_;
    # use the handler to find the key, if you don't like storing 
    # the key in your config files.
    my $key = $this->run_handler("crypt_key",$keytype);
    return $key || $config{crypt}{$keytype} || $config{crypt}{key};
}

# Remaining methods are the pure-perl implementation of TEA.
# Warning: it only works on 32-bit architectures!

sub encrypt_tea {
    my ($this,$plaintext,$key) = @_;
    if ($this->{strong}) {
	# pad our text out to a 64-bit boundary
	my $npad = 8 - ((length($plaintext) + 1) % 8);
	if ($npad == 8) { $npad = 0; }
	my $head = chr((ord(&randtext(1)) & 0xF8) | $npad);
	my $tail = $npad ? &randtext($npad) : "";
	#$plaintext = chr($npad).$plaintext;
	$plaintext = $head.$plaintext.$tail;
    }
    my @text = $this->str2int($plaintext);  # convert text to 32-bit int array
    my @key  = $this->str2int($key);        # ditto for key
    my @cbin;                         # holds binary crypt data
    while (@text > 0) {
	# encrypt in 64-bit (2-word) blocks
	push @cbin, $this->encrypt64([shift @text, shift @text],\@key);
    }
    return $this->int2str_b64(@cbin);
}

sub decrypt_tea {
    my ($this,$ciphertext,$key) = @_;
    my @text = $this->str2int_b64($ciphertext);
    my @key  = $this->str2int($key);
    my @cbin;
    while (@text > 0) {
	# decrypt in 64-bit (2-word) blocks
	push @cbin, $this->decrypt64([shift @text, shift @text],\@key);
    }
    my $plaintext = $this->int2str(@cbin);
    if ($this->{strong}) {
	# remove padding
	my $npad = ord(substr($plaintext,0,1,'')) & 0x7;
	$plaintext =~ s/.{$npad}$//;
    }
    else {
	# strip trailing nulls
	$plaintext =~ s/\000*$//;
    }
    return $plaintext;
}

# convert to/from binary-encoded strings

sub str2int {
    my $this = shift;
    my @text = split //,shift;  # break input string into chars
    my (@bin,$i);               # binary representation, byte index
    while (@text > 0) {
	if ($i == 0) { push @bin, 0; }
	$_ = shift @text;
	$bin[-1] = ($bin[-1] | (ord($_) << ($i << 3)));  # $i*8
	$i++;
	if ($i == 4) { $i = 0; }
    }
    return @bin;
}

sub int2str {
    my ($this,@bin) = @_;
    my $binstr;
    while (@bin > 0) {
	my $w = shift @bin;
	foreach my $shift (0..3) { 
	    $binstr .= chr(($w >> ($shift << 3)) & 0xff); 
	}
    }
    return $binstr;
}

# convert to/from base64-encoded strings

sub str2int_b64 {
    my $this = shift;
    $_ = shift;
    tr/\-_/\+\//;  # convert back to non-URL-safe chars
    # add pad chars
    my $npad = (3 - ((length $_) % 3)) % 3;
    foreach my $ipad (1..$npad) { $_ .= "="; }
    return $this->str2int(&decode_base64($_));
}

sub int2str_b64 {
    my ($this,@bin) = @_;
    $_ = &encode_base64($this->int2str(@bin),'');
    tr/\+\//\-_/;  # convert non-URL-safe chars
    s/=+$//;       # strip pad chars
    return $_;
}

# encrypt/decrypt a 64-bit cipherblock

sub encrypt64 {
    my $this = shift;
    my ($v,$k) = @_;
    my $y = $v->[0];
    my $z = $v->[1];
    my $n = $this->{level};
    my $sum = 0;
    while ($n-- > 0) {
	$y += ($z << 4 ^ $z >> 5) + $z ^ $sum + $k->[$sum & 3];
	$sum += $DELTA;
	$z += ($y << 4 ^ $y >> 5) + $y ^ $sum + $k->[$sum>>11 & 3];
   }
   return ($y,$z);
}

sub decrypt64 {
    my $this = shift;
    my ($v,$k) = @_;
    my $y = $v->[0];
    my $z = $v->[1];
    my $n = $this->{level};
    my $sum = $DELTA * $n;
    while ($n-- > 0) {
	$z -= ($y << 4 ^ $y >> 5) + $y ^ $sum + $k->[$sum>>11 & 3];
	$sum -= $DELTA;
	$y -= ($z << 4 ^ $z >> 5) + $z ^ $sum + $k->[$sum & 3];
    }
    return ($y,$z);
}

1;
