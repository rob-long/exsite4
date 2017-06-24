package ExSite::Input;
#----------------------------------------------------------------------------
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

use strict;
use ExSite::Config;
use ExSite::Base;
use ExSite::Misc;
use ExSite::Crypt;
use MIME::Base64;

# inherit from Base
use vars qw(@ISA);
@ISA = qw(ExSite::Base);

# my $preset_input = new ExSite::Input({post=>"mypostdata",get=>"myquery"});

sub new {
    my($this, $preset) = @_;

    # objectify object
    my $cobj = {};
    my $class = ref($this) || $this;
    bless $cobj, $class;

    # input data is stored in share area, not in object, so that it 
    # can serve multiple components simultaneously.

    if (!$share{input}) {
	$share{input} = {};
	foreach my $action ("post","get","combine","path") {
	    $share{input}{$action} = {};
	    $share{input}{$action}{keylist} = [];
	    $share{input}{$action}{data} = {};
	    $share{input}{$action}{raw} = undef;
	}
    }

    # check for preset data: allows programs to manually preset the input
    # (useful for automated testing)

    if (keys %$preset > 0) {
	$share{input}{preset} = $preset;
    }
    elsif (! $share{input}{preset}) {
	$share{input}{preset} = {};
    }

    return $cobj;
}

# query : process QUERY_STRING input, ie. "GET" method

sub query {
    my ($this,$fetch_as) = @_;
    if (! $share{input}{get}{raw}) {
	$share{input}{get}{raw} = 
	    $share{input}{preset}{get} || $ENV{QUERY_STRING};
	$this->decode("get",$share{input}{get}{raw});
	if ($share{input}{get}{data}{_}) {
	    $this->get_protected_input("get");
	    delete $share{input}{get}{data}{_};
	}
	### FIXME? add _fbkey processing in case of GET forms
    }
    return $this->fetch("get",$fetch_as);
}

# get is synonym for query
sub get { return &query(@_); }

# post : process "POST" method input

sub post {
    my ($this,$fetch_as) = @_;
    if ($ENV{REQUEST_METHOD} eq "POST" && ! $share{input}{post}{raw}) {
	if ($ENV{CONTENT_TYPE} =~ /multipart\/form-data/) {
	    $this->info("decoding multipart form");
	    require CGI;
	    # CONTENT_TYPE=multipart/form-data
	    # (this form contains file uploads; use CGI module to decode it;
	    # that means that the "raw" data is really a CGI:: handle.)
	    $share{input}{post}{raw} = 
		$share{input}{preset}{post} || CGI::new();
	    # must use CGI:: to decode
	    my $in = $share{input}{post}{raw};
	    my @loginput;
	    foreach my $par ($in->param) {
		push @{$share{input}{post}{keylist}}, $par;
		# fetch multiple values, in case of repeated inputs
		my @pars = $in->param($par);
		if (@pars > 1) { 
		    # there are multiple values; concatenate them
		    $share{input}{post}{data}{$par} = 
			join($config{form}{multi_sep},@pars);
		}
		else {
		    # single value; do not concatenate, or filehandles
		    # will be wrecked
		    $share{input}{post}{data}{$par} = $in->param($par);
		}
		push @loginput, "$par=$share{input}{post}{data}{$par}";
	    }
	    # log as if url-encoded input
	    &diagnostic({
		type=>"post",
		level=>1,
		message=>"POST:".join("&",@loginput)
		});
	}
	else {
	    # CONTENT_TYPE=application/x-www-form-urlencoded
	    $this->info("decoding regular form");
	    my $clen = $ENV{'CONTENT_LENGTH'};
	    if ($share{input}{preset}{post}) {
		$share{input}{post}{raw} = $share{input}{preset}{post};
	    }
	    elsif ($clen) {
		my $in;
		if ($ENV{CGI_INPUT_FILE}) {
		    # debugging feature: read input from a file
		    # This is useful for very large inputs (eg.file uploads)
		    # that are too long for normal CLI debugging.
		    open F, "<$ENV{CGI_INPUT_FILE}";
		    my $size = 0;
		    my $continue = 1;
		    while ($continue) {
			$continue = read(F,$in,1024,$size);
			$size += $continue;
		    }
		    $ENV{CONTENT_LENGTH} = $size;
		    close F;
		}
		else {
		    # normal read from STDIN
		    read(STDIN,$in,$ENV{'CONTENT_LENGTH'});
		    &diagnostic({
			type=>"post",
			level=>1,
			message=>"POST:".$in,
		    });
		}
		$share{input}{post}{raw} = $in;
	    }
	    $this->decode("post",$share{input}{post}{raw});
	}
	if ($share{input}{post}{data}{_}) {
	    $this->get_protected_input("post");
	    delete $share{input}{get}{data}{_};
	}
	if ($share{input}{post}{data}{_fbkey}) {
	    require ExSite::Crypt;
	    my $crypt = new ExSite::Crypt;
	    my $key = $crypt->decrypt($share{input}{post}{data}{_fbkey});
	    $share{input}{fbkey} = $key;
	    delete $share{input}{post}{data}{_fbkey};
	    $share{input}{form_age} = time - $key;
	    $this->info("form age: $share{input}{form_age} seconds");
	    if ((($ENV{HTTP_REFERER} !~ /$config{server}{CGIpath}/) && # static referer
		 ($share{input}{form_age} > 86400*7)) || # more than 7 days old
		($share{input}{form_age} > 86400)) { # dynamic referrer more than 24 hrs old
		    # post is surprisingly old in relation to its form
		    my $days = int($share{input}{form_age} / 8640)/10;
		    $this->warn("post is $days days older than form");

		    ### FIXME: excessive age may indicate an XSS
		    ### attack in progress ie. attacker captures an
		    ### fbkey, then recycles it later for an XSS attack. In
		    ### this case we could reject the post, or demote
		    ### the access level, or...?
	    }
	}
    }
    return $this->fetch("post",$fetch_as);
}

# post_or_query, query_or_post : return one or the other, but not both

sub post_or_query {
    my ($this,$fetch_as) = @_;
    my $data = $this->post($fetch_as);
    return $data if (ref $data eq "HASH" && keys %$data > 0);
    return $data if (ref $data eq "ARRAY" && @$data > 0);
    $data = $this->query($fetch_as);
    return $data;
}

sub query_or_post {
    my ($this,$fetch_as) = @_;
    my $data = $this->query($fetch_as);
    return $data if (ref $data eq "HASH" && keys %$data > 0);
    return $data if (ref $data eq "ARRAY" && @$data > 0);
    $data = $this->post($fetch_as);
    return $data;
}

# combine : combine post and query data together into a single input stream

sub combine {
    my ($this,$fetch_as) = @_;
    # no raw input for combined input
    $share{input}{combine}{raw} = undef;
    # load both input streams
    $this->query;
    $this->post;
    # combine the data hashes and key lists
    my @tmplist = 
	(@{$share{input}{get}{keylist}},@{$share{input}{post}{keylist}});
    $share{input}{combine}{keylist} = \@tmplist;

    my %tmphash = %{$share{input}{post}{data}};
    foreach my $key (keys %{$share{input}{get}{data}}) {
	if (! exists $tmphash{$key}) { 
	    $tmphash{$key} = $share{input}{get}{data}{$key};
	}
    }
    $share{input}{combine}{data} = \%tmphash;
    return $this->fetch("combine",$fetch_as);
}

sub is_post {
    my $this = shift;
    return ($ENV{REQUEST_METHOD} eq "POST");
#    my $data = $this->post();
#    return (keys %$data > 0);
}

sub get_protected_input {
    my ($this,$method) = @_;
    my $t = tied %token;
    if ($config{token}{secure_query} && $t->enabled) {
	my $data = $token{$share{input}{$method}{data}{"_"}};
	$this->decode($method,$data);
    }
    else {
	# no token management - use encryption
	my $c = new ExSite::Crypt;
	my $data = $c->decrypt($share{input}{$method}{data}{"_"});
	$this->decode($method,$data);
    }
}

# decode : break input string down into key, value pairs
# arguments: input method, input string, separator character (optional)

sub decode {
    my $this = shift;
    my $method = shift;
    my $data = shift;
    my $sep = shift || "&";
    my @in = split(/$sep/,$data);
    my (%out, @okeys);
    my $out = $share{input}{$method};
    foreach my $i (0 .. $#in) {
        # Convert pluses to spaces
        $in[$i] =~ s/\+/ /g;

        # Split into key and value.
        (my $key, my $val) = split(/=/,$in[$i],2); # splits on the first =

        # Convert %XX from hex numbers to alphanumeric
        $key =~ s/%(..)/pack("c",hex($1))/ge;
        $val =~ s/%(..)/pack("c",hex($1))/ge;

	# save key order
	if (! exists $out->{data}{$key}) { push @{$out->{keylist}}, $key; }
        # Associate key and value. Multiply-defined inputs are concatenated.
	$out->{data}{$key} .= 
	    $config{form}{multi_sep} if (defined($out->{data}{$key}));
	$out->{data}{$key} .= $val;
    }
    return;
}

# fetch : retrieve data in various formats

sub fetch {
    my $this = shift;
    my $method = shift;
    local $_ = shift;
    if (/raw/)     { return $share{input}{$method}{raw}; }
    elsif (/keys/) { return $share{input}{$method}{keylist}; }
    else           { return $share{input}{$method}{data}; }
}

sub fetch_file {
    my ($this,$name,$format) = @_;
    my $f = $share{input}{post}{data}{$name};
    if ($f) {
	if ($format eq "name") {
	    return &clean_filename($f);
	}
	my $fdata = undef;
	my $size = 0;
	my $mimedata = "";
	# read file contents
	my $continue = 1;
	while ($continue) {
	    $continue = read($f,$fdata,1024,$size);
	    $size += $continue;
	}
	if ($size > $config{max_upload_size}) {
	    $this->error("file too large - $config{max_upload_size} bytes max");
	    return undef;
	}

	# return raw file contents, if requested

	if ($format eq "raw") {
	    return $fdata;
	}

	# otherwise return MIME-encoded file contents
	my @path = split /[:\\\/]/, $f;
	# strip filesystem cruft
	# convert all quirky characters to _
	my $filename = &clean_filename($path[-1]);
	return "$filename#".encode_base64($fdata,"");
    }
    return undef;
}

# modify the input buffers

sub set {
    my ($this,$key,$val,$action) = @_;
    foreach my $act ("post","get","combine") {
	if (! $action || $action eq $act) {
	    $share{input}{$act}{data}{$key} = $val;
	}
    }
}

sub delete {
    my ($this,$key) = @_;
    # WARNING: only deletes value from data hash, not raw data or keylist
    foreach my $action ("post","get","combine") {
	delete $share{input}{$action}{data}{$key};
    }
}

# path handling...

sub path_info {
    my ($this,$fetch_as) = @_;
    my $p = $share{input}{path};
    if (! $p->{raw}) {
	# initialize path data
	$p->{raw} = $share{input}{preset}{path} || $ENV{PATH_INFO};
	# set the remaining path
	my @path = split /\//,$p->{raw},-1; # includes trailing blanks
	shift @path;
	$p->{data}{_} = \@path;
    }
    if ($fetch_as) {
	return $this->fetch("path",$fetch_as);
    }
    else {
	# aggregate the sub-paths, and combine into a new path
	my @path = ("");
	foreach my $subpath (@{$p->{keylist}}) {
	    push @path, @{$p->{data}{$subpath}};
	}
	push @path, @{$p->{data}{_}};
	return join "/",@path;
    }
}

sub path {
    my ($this,$id,@data) = @_;
    if (! $id) { $id = "_"; }
    if (! exists $share{input}{path}{data}{$id}) {
	if (@data > 0) {
	    $this->new_path($id,@data);
	}
	else {
	    return undef;
	}
    }
    elsif (@data > 0) {
	# setting path
	if (@data == 1) {
	    if ($data[0] =~ /^\//) {
		# setting path to a scalar value
		@data = split /\//,$data[0];
		shift @data;
	    }
	    elsif (! $data[0]) {
		# empty path - delete the path data to avoid a double //
		@data = ();
	    }
	}
	$share{input}{path}{data}{$id} = \@data;
    }
    if (@{$share{input}{path}{data}{$id}} > 0) {
	return wantarray ? 
	    @{$share{input}{path}{data}{$id}} :
	    join "/", "",@{$share{input}{path}{data}{$id}};
    }
    else {
	return wantarray ? () : undef;
    }
}

sub new_path {
    my ($this,$id,@data) = @_;
    my $p = $share{input}{path};
    # add to our list of paths
    if (! exists $p->{data}{$id}) { push @{$p->{keylist}},$id; }
    if (@data == 1 && $data[0] =~ /^\//) {
	# we were passed a scalar instead of an array
	my $path = $data[0];
	# setting path to a scalar value
	@data = split /\//,$path;
	shift @data;
    }
    $this->update_path_remainder(@data);
    $share{input}{path}{data}{$id} = \@data;
}

# append_path: same as new_path except it adds to the named
# path element, instead of replacing it

sub append_path {
    my ($this,$id,@data) = @_;
    if (! exists $share{input}{path}{data}{$id}) {
	return $this->new_path($id,@data);
    }
    if (@data == 1 && $data[0] =~ /^\//) {
	# we were passed a scalar instead of an array
	my $path = $data[0];
	# setting path to a scalar value
	@data = split /\//,$path;
	shift @data;
    }
    $this->update_path_remainder(@data);
    push @{$share{input}{path}{data}{$id}},@data;
}

# update_path_remainder - remove elements from the path remainder, _

sub update_path_remainder {
    my ($this,@data) = @_;
    my $p = $share{input}{path};
    if (@data > 0) {
	# check if this replaces any path elements in our remainder
	my $match = 1;
	my $pos = 0;
	foreach my $pathel (@data) {
	    if ($pathel eq $p->{data}{_}[$pos]) {
		$pos++;
	    }
	    else {
		# no match
		$match = 0;
		last;
	    }
	}
	if ($match) {
	    # remove the matching elements from the remainder
	    splice @{$p->{data}{_}}, 0, scalar @data;
	}
    }
}

#============== DOCUMENTATION ================

=pod

=head1 ExSite::Input  --  tools for reading http inputs

Input from the client typically comes in 3 ways:

=over 4

=item * POST data (forms)

Forms typically send their data as POST data, which is a set of 
parameter names and values.  We convert this to a hash of names =E<gt>
values.

=item * GET data (query string) 

Query strings are treated similarly to forms by default;  that is, they 
are presumed to contain parameterized values such as

    /cgi/page.cgi?parameter=value&less=more

Note that the separator character "&" can be changed to ";" or any
other charcter in your configuration file.  For example, if you use a
CSV format such as

    /cgi/page.cgi?value,more

then you can set your separator character to "," and the values will
come through as parameter names.  More on this is given below.  If you
use an entirely different format, then you can always fetch the raw
GET data and parse it yourself.

=item * PATH_INFO

Path info data is a list of values separated by the "/" character.
This list can be broken down into named sub-lists.  The sub-list names
are treated as parameter values, and the sub-list data are treated as
simple arrays.  Any remaining trailing part of the path info is kept
in an unnamed sub-list.  For example, a PATH_INFO like

    /exsite/index.html/blog/my_article

might break down into two sub-lists:

    CMS -> exsite, index.html
    Zine -> blog, my_article

Unlike POST and GET data, these parameter names are not provided by
the input data; they are defined after the fact by code that reads
from the path.

=back

To begin working with inputs of any of these types, declare an Input
object to work with:

    my $in = new ExSite::Input;

=head2 Reading POST and GET data

Input is returned as a hash reference of parameters names =E<gt> values.

=head3 C<query()>

    my $querydata = $in->query();

Reads input passed via GET method (ie. QUERY_STRING)

=head3 C<post()>

    my $postdata = $in->post();

Reads input passed via POST method. 

=head3 C<query_or_post()>

    my $data = $in->query_or_post();

Reads from query preferentially, but if the query contains no data, it will
read from post data as a backup.

=head3 C<post_or_query()>

    my $data = $in->post_or_query();

Reads from post data preferentially, but if the post contains no data, it
will read from the query string as a backup.

=head3 C<combine()>

Usage: C<my $data = $in-E<gt>combine()>

Combines the post data and query data into a single hash.  Post data
is taken preferentially.

=head3 Other QUERY_STRING formats

If your query string is not formatted as a sequence of parameter=value
settings, you can try one of these:

    # fetch a list of the parameter names
    my @parameter_list = $in->fetch("get","keys");

    # fetch the raw QUERY_STRING to be parsed by another program
    my $raw_input = $in->fetch("get","raw");

=head2 Path Info

=head3 C<path_info()>

    my $data = $in->path_info();

Returns the complete PATH_INFO, as a string.

The path info can be comprised of a number of different sub-paths that
are concantenated together.  For example:

    /exsite/page.html/blog/my_article

The first two elements of this path might refer to a path in the CMS
(eg. /SECTION/PAGE), while the last two refer to a path in the Zine
subsystem.  The complete path info is a concatenation of these two
subpaths, but we will often want to deal with the subpaths
individually.

=head3 C<path()>

    my $data = $in->path($id);
    my @data = $in->path($id);

Returns a sub-path as a string, or as an array of path elements.  The
complete path can be divided into any number of sub-paths, each with
an ID.  Any remaining path with no ID is called the remainder.  If no
ID is given, the remainder is returned.

    $in->path($id,$data);
    $in->path($id,@data);

Sets a sub-path to a string, or as an array of path elements.  With
the string form, the $data must begin with "/".  To delete a sub-path,
use:

    $in->path($id,"");

To set the remainder, use:

    $in->path("",$data);

=head3 C<new_path()>

This method defines a new sub-path.  It is called automatically from
C<path()> if the C<id> passed to path has not yet been defined.

    $in->new_path($id,$data);
    $in->new_path($id,@data);

Defines a new sub-path, which follows all other sub-paths that have
already been defined.  The path data can be passed as a simple string
(starting with "/"), or as an array of path elements.  If the path
data matches the start of the remainder, the subpath will be removed
from the remainder.  For example, if the remainder is "/foo/bar/baz",
and you define a new subpath as "/foo/bar", then the remainder will
change to "/baz".  If, however, you define a new subpath like
"/bar/foo" which does not match the remainder, then the new subpath
will be inserted into the path, and the remainder will be left
unchanged, resulting in "/bar/foo/foo/bar/baz" as the complete path.

=head2 Raw Input Data

The raw input is also saved, and can be retrieved using:

    my $raw = $in->fetch("post","raw");   # or, use "get" instead of "post"

=head2 Input Order

If the order of the inputs is important, you can fetch the raw key order
using:

    my $keylist_ref = $in->fetch("post","keylist");  # or "get"...

=head1 Notes

The Input class is a replacement for the generic input parsing routines in 
ExSite::Misc::, which are deprecated for processing inputs to page.cgi.

The main purpose in having an Input class is so that POST input can 
be shared by multiple modules working independently.  Without an Input
class, the first module to get its mitts on STDIN gobbles all the input,
and the remaining modules see nothing.  

=head2 Multipart-encoded Forms

Multipart-encoding is handled automatically using the CGI:: class.
Multipart-encoding is normally only enabled by ExSite when the form
accepts file uploads.

To fetch the decoded file data directly, use:

    my $raw_file = $in->fetch_file("input_name","raw"); # binary file data

    $my $encoded_file = $in->fetch_file("input_name");  # encoded file data

ExSite encoded file data looks like this:

    filename.jpg#MIMEDATA....

To convert this back to a regular file, split on the separator character
('#' by default) to get the file name, and the mime-encoded data.  Then use

    use Mime::Base64;
    decode_base64($mimedata);

If you request the raw input data from a multipart-encoded form, you
will receive a CGI:: object.

=head2 Input Storage

ExSite::Input stores all input data in C<%share>, where other modules
will find it if they also play nice and use ExSite::Input.  The input
is parsed and cached automatically, and ExSite::Input is smart enough not 
to redo this work once it has been done.

Input is saved in the following structure:

C<$share{input}{get|post|combine|path}{raw|data|keylist}>

where get/post/combine/path selects the input stream, and raw/data/keylist
selects the format you would like to view the data in.

Get and post data are the parameter/value pairs found in the get and
post input streams, respectively.  Combined data is the merged get and
post data, where post data is taken preferentially if the same
parameter appears in both.

Path data are stored as a hash of subpath IDs mapped to path element
arrays.  The raw data is the scalar version of the subpath; the data 
is the array version of the subpath, and the keylist is the order of 
the subpaths.

=head2 Hacking Input

Typical usage involves passively reading the input data that has been
passed from the web server.  In some cases, however, you want to modify the
input data, or define your own input data.

To modify a single input parameter:

    $in->set("parameter","newvalue","post");  # changes the parameter in the POST data
    $in->set("parameter","newvalue","get");   # changes the parameter in the GET data

To remove a form parameter from the input cache, use:

    $in->delete("parameter");

To change part of the path, see the section on C<path()>, above.

To define the entire set of input data, you can pass the raw data in when 
defining your Input object:

    my $preset_input = new ExSite::Input( { post=>"foo=bar&bat=baz",
					    get=>"x=1&y=2",
					    path=>"/some/path" } );

=cut

1;

