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

### POD documentation is at the end of this file

package ExSite::URI;
use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Base;
use ExSite::Section;
use ExSite::Module;
use ExSite::Crypt;

use vars qw(@ISA);
@ISA = qw(ExSite::Base);

sub new {
    my ($this,%opt) = @_;
    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;
    $obj->{uridata} = {};
    # copy options into object
    while (my ($key,$val) = each %opt) {
	$obj->{$key} = $val;
    }
    $obj->initialize_object;
    $obj->{input} = new ExSite::Input;
    $obj->setup();
    return $obj;
}

# setup : defines the canonical URI we are working with
#         You can pass a specific URI, but it defaults to the current URI.

sub setup {
    my $this = shift;
    my $uri = shift;
    if ($uri) {	$this->{uri} = $uri; }
    $this->parse();
    $this->{uridata}{path_keys} = [];
    $this->setup_output;
}

sub setup_output {
    my $this = shift;
#    if (! $this->{output}) { $this->{output} = {}; }
#    $this->{output}{query_data} = {};
#    $this->{output}{path_data} = {};
#    $this->{output}{path_keys} = [];
#    delete $this->{output}{path_info};
#    delete $this->{output}{fragment};
#
#    # NB: we do not clear script_name

    $this->{output} = {
        query_data=> {},
        path_data => {},
	path_keys => [],
    };
}

sub update_input {
    my $this = shift;
    $this->update_query;
    $this->update_path;
}

sub update_query {
    my $this = shift;
    $this->{uridata}{query_data} = $this->{input}->query;
}

sub update_path {
    my $this = shift;
    $this->{uridata}{path_data} = $this->{input}->fetch("path");
    $this->{uridata}{path_keys} = $this->{input}->fetch("path","keys");
}

sub reset {
    my $this = shift;
    $this->setup_output;
    if ($this->{use_input}) {	
	$this->update_input;
    }
}

### FIXME: clashes with Base::info

sub info {
    my $this = shift;
    return wantarray ? ${$this->{uridata}} : $this->{uridata};
}

sub get {
    my ($this,$key) = @_;
    return $this->{uridata}{$key};
}

# NB: set changes the INPUT value, not the output
sub set {
    my ($this,$key,$val) = @_;
    $this->{uridata}{$key} = $val;
}

# secure URIs will encode their query strings to make them tamper-proof

sub secure {
    my $this = shift;
    $this->{secure_query} = 1;
}

sub insecure {
    my $this = shift;
    $this->{secure_query} = 0;
}

# a shortened URL creates an abbreviation in the token table that points
# to this URL.  Shortened URLs can be single-use, have a limited duration
# (in seconds), and be connected to a UID.  If a UID is defined, that is
# taken to mean that the indicated user should be auto-authenticated when 
# this URL is visted.  Shortened urls are of the general form
# http://domain.com/cgi/page.cgi/token

sub shorten {
    my ($this,$single_use,$duration,$uid) = @_;
    my $newurl;
    my $url = $this->write_full();
    my $t = tied %token;
    if ($t->enabled) {
	my $token = $t->make($url,$single_use,$duration,$uid);
	$newurl = "$config{server}{server}$config{server}{CGIpath}/$config{prog}{page}/$token";
    }
    return $newurl;
}

### modes and constants

sub separator {
    my $this = shift;
    $this->{separator} = shift;
}

sub plaintext {
    my $this = shift;
    $this->{plaintext} = 1;
}

sub html {
    my $this = shift;
    $this->{plaintext} = 0;
}

sub use_input {
    my $this = shift;
    $this->{use_input} = 1;
}

# change one query parameter

sub parameter {
    my ($this,$key,$val) = @_;
    $this->{output}{query_data}{$key} = $val;
}

# change multiple parameters

sub query {
    my ($this,%params) = @_;
    while (my ($key,$val) = each %params) {
	$this->parameter($key,$params{$key});
    }
}

# change path

sub path {
    my ($this,$segment,$path) = @_;
    if (! exists $this->{output}{path_data}{$segment}) {
	push @{$this->{output}{path_keys}}, $segment;
    }
    $this->{output}{path_data}{$segment} = $path;
}

# change fragment

sub fragment {
    my ($this,$frag) = @_;
    $this->{output}{fragment} = $frag;
}

# combine query data to make a new query string

sub make_query {
    my $this = shift;
    my %qdata = (%{$this->{uridata}{query_data}},%{$this->{output}{query_data}});
    my $query_string = $this->encode_query(%qdata);
    if ($this->{secure_query}) {
	my $qval;
	my $t = (tied %token);
	if ($config{token}{secure_query} && $t->enabled) {
	    $qval = $t->make($query_string,0,$config{token}{secure_query_duration});
	}
	else {
	    my $c = new ExSite::Crypt;
	    $qval = $c->encrypt($query_string);
	}
	$query_string = "_=$qval";
    }
    return $query_string;
}

# combine path data to make a new path_info

sub make_path {
    my $this = shift;
    my $path;

    # explicit path?
    return $this->{output}{path_info} if (exists $this->{output}{path_info});

    # reconstruct new path
    my (@pathkeys,%pathdata,@newpath,%used_seg);
    if ($this->{use_input}) {
	# only incorporate input data if working on the URI of the
	# current request
	@pathkeys = @{$this->{input}->path_info("keys")};
	%pathdata = %{$this->{input}->path_info("data")};
    }
    push @pathkeys, @{$this->{output}{path_keys}};
#    push @pathkeys, "_";   # causes many errors

    # the path has been broken into segments or altered, so rebuild it
    # from the defined segments

    if (@pathkeys > 0) {
	%pathdata = (%pathdata,%{$this->{output}{path_data}});
	foreach my $segment (@pathkeys) {
	    next if ($used_seg{$segment});
	    $used_seg{$segment} = 1;
	    my $pathseg = $pathdata{$segment};
	    if (ref $pathseg eq "ARRAY") {
		push @newpath, @$pathseg;
	    }
	    else {
		push @newpath, $pathseg;
	    }
	}
	foreach my $pathel (@newpath) {
	    next if (! $pathel);
	    $path .= $pathel =~ /^\// ? $pathel : "/$pathel";
	}
    }

    # no segmentation is detected, so preserve the original path

    elsif ($this->{uridata}{script_name}) {
	# ExSite URI
	$path = $this->{uridata}{path_info};
    }
    else {
	# unknown URI
	$path = $this->{uridata}{path};
    }
    return &url_escape($path);
}

# parse: break a URI down into its component parts
# regexp taken from RFC 3986, p.50
#
# Returns a hashref, including:
#
# scheme (protocol)
# authority (hostname)
# path (complete path)
# script_name (path to CGI program, if a CGI program is referenced)
# path_info (remaining path after script_name)
# query (query string)
# query_data (decoded query string)
# fragment (bookmark)
#
# Where: URL = scheme://authority/path?query#fragment
#        path= /script_name/path_info

sub parse {
    my $this = shift;
    return $this->this_uri if (! $this->{uri});
    $this->{uri} =~ 
	/^(([^:\/?\#]+):)?(\/\/([^\/?\#]*))?([^?\#]*)(\?([^\#]*))?(\#(.*))?/;
    $this->{uridata} = {
	scheme    => $2,
	authority => $4,
	path      => $5,
	query     => $7,
	fragment  => $9,
    };
    
    if (! $this->{uridata}{scheme}) { 
	$this->{uridata}{scheme} = $config{server}{protocol} || "http"; 
    }
    if (! $this->{uridata}{authority}) { 
	$this->{uridata}{authority} = $config{server}{host} ?
	    "$config{server}{host}.$config{server}{domain}" :
	    $config{server}{domain}; 
    }
    
    # parse the path
    ($this->{uridata}{script_name},$this->{uridata}{path_info}) = 
	$this->parse_path($this->{uridata}{path});
    $this->{uridata}{path_data} = { "_" => $this->{uridata}{path_info} };

    # parse the query string
    $this->{uridata}{query_data} = $this->{uridata}{query} ?
	$this->decode_query($this->{uridata}{query}) :
        {};

    # flag this as an explicit URL so we don't try to merge it with Input
    $this->{use_input} = 0;

    return wantarray ? %{$this->{uridata}} : $this->{uridata};
}

# this_uri : configure the object with the current environment settings

sub this_uri {
    my $this = shift;
    $this->{uridata} = {
	scheme    => $config{server}{protocol} || "http",
	path      => $ENV{SCRIPT_NAME}.$ENV{PATH_INFO},
	script_name => $ENV{SCRIPT_NAME},
	path_info => $ENV{PATH_INFO},
	query     => $ENV{QUERY_STRING},
	fragment  => "",
	query_data=> $this->{input}->query,
	path_data => {},
    };
    # hostname
    $this->{uridata}{authority} = 
	$ENV{HTTP_HOST} || 
	$ENV{SERVER_NAME} || 
	# nothing in environment - use config settings
	( $config{server}{host} ? 
	  $config{server}{host}.".".$config{server}{domain} :
	  $config{server}{domain} );
    # we can use Input manager data to manipulate this URI
    $this->{use_input} = 1;
    return wantarray ? %{$this->{uridata}} : $this->{uridata};
}

sub parse_path {
    my $this = shift;
    my $path = &url_unescape(shift);
    my $scriptre = shift || join "|",values %{$config{prog}};
    my @path = split /\//,$path;
    my $scriptfile = undef;
    my (@scriptpath,@pathinfo);
    while (@path) {
	my $pathel = shift @path;
	if ($pathel =~ /$scriptre/) { 
	    $scriptfile = $pathel; 
	    push @scriptpath,$pathel;
	}
	elsif ($scriptfile) { push @pathinfo,$pathel; }
	else { push @scriptpath,$pathel; }
    }
    if ($scriptfile) {
	# looks like an ExSite program
	my $scriptpath = join("/",@scriptpath);
	my $pathinfo = join("/",undef,@pathinfo);
	return ($scriptpath,$pathinfo);
    }
    else {
	# some other path
	return (undef, undef);
    }
}

# change path data

sub path_info {
    my ($this,$pinfo) = @_;
    $this->{output}{path_info} = $pinfo;
    # this explicitly sets the whole path_info
    # so we must clear any segments that may have been set
    $this->{output}{path_data} = {};
    $this->{output}{path_keys} = [];
}

sub script_name {
    my ($this,$script_path) = @_;
    if ($script_path) {
	$this->{output}{script_name} = $script_path;
    }
    return $this->{output}{script_name} || $this->{uridata}{script_name};
}

# relink - multi-purpose self-link, with different parameters
#
# $param = new keys/values for query string; undef values are cleared
# $opt = other settings, eg.
#        module => link to a DCD module
#        uridata key 
#
# Automatically generates AJAX calls, if $share{ajax_target} is set.
# These will return a Javascript call, not a URI.

sub relink {
    my ($this,%opt) = @_;

    # do not preserve CMS directives
    $this->parameter("_cms",undef);

    # update params
    foreach my $okey (keys %opt) {
	if ($okey eq "module") {
	    $this->service_page($opt{module});
	}
	elsif ($okey =~ /^query/) {
	    $this->{output}{query_data} = {%{$this->{output}{query_data}},
					   %{$opt{$okey}}};
	}
	else {
	    $this->{output}{$okey} = $opt{$okey};
	}
    }

    my $newuri = $this->write();

    #### ???
    if ($share{ajax_target}) {
	# NB: must load _ExSite/js/httprequest.js for this to work
	my $id = $share{ajax_target};
	return "javascript:subRequestData('$id','$newuri')";
    }

    return $newuri;
}

# redirect to a service page

sub service_page {
    my ($this,$module) = @_;
    return if (! $share{Page});
    my $mod = ref $module ? $module : &ExSite::Module::get_module($module,0,$share{Page}->my_section->id);
    if ($mod && $mod->ioctl("isService")) {

	# this module uses service pages

	my $page = $share{Page};
	my $site;
	if ($page) {
	    $site = $page->my_section->id;
	}
	if ($site) {
	    # look for defined service pages

	    my $name = ref $module ? $mod->module_name() : $module;
	    my $spage = &ExSite::Module::service_page($name,$site);

	    if ($spage) {
		# this link should be serviced by a particular page
		if ($page) {
		    if ($spage->id != $page->id) {
			# the service page is different from the current page
			my $suri = $spage->get_uri();
			# convert $this to $suri
			$this->{input} = $suri->{input};
			$this->{output} = $suri->{output};
			$this->{uri} = $suri->{uri};
			$this->{uridata} = $suri->{uridata};
			$this->{use_input} = 0;
			return 1; # indicates we changed the URI
		    }
		}
	    }
	}
    }
    return undef;
}

# add an authentication token to the URI to allow it to run with 
# special privileges;  the authtoken must be added AFTER all other 
# URI modifications, or it won't authenticate correctly.
#
# Requires a login ID, and an optional expiry (in days).

# authtoken : generate an authtoken for the current URI

sub authtoken {
    my ($this,$login,$expiry) = @_;
    # switch to textmode
    my $textmode_save = $this->{plaintext};
    $this->plaintext;
    # get the URL we are authorizing
    my $url = $this->write;
    # make authtoken for this URL
    my $authtoken = $share{DB}->make_authtoken($login,$expiry,$url);
    # restore the textmode
    $this->{plaintext} = $textmode_save;
    return $authtoken;
}

# apply an authtoken to the current URI, to make it privileged

sub authorize {
    my ($this,$login,$expiry) = @_;
    # get an authtoken for the current URL
    my $authtoken = $this->authtoken($login,$expiry);
    # add the authtoken to the URL
    $this->parameter("_auth",$authtoken);
}

# generate a privileged URI, and then reset the URI back to unprivileged

sub authorize_url {
    my ($this,$login,$expiry) = @_;
    # get an authtoken for the current URL
    $this->authorize($login,$expiry);
    # generate the URL with embedded authtoken
    my $url = $this->write;
    # clear the authtoken so it doesn't persist on new URIs
    $this->parameter("_auth",undef);
    return $url;
}

sub encode_query {
    my $this = shift;
    # expecting a hash, or key,value pairs in input list
    my %in = @_;
    my @arglist = ();
    while ((my $key, my $val) = each %in) {
	next if (! defined $val);
	my $arg;
	if ($val eq "") {
	    $arg = "$key";
	}
	else {
	    $arg = "$key=$val";
	}
	for (my $i = 0; $i < $ExSite::Misc::ncodechars; $i++) {
	    $arg =~ s/$ExSite::Misc::decodecharre[$i]/$ExSite::Misc::encodechars[$i]/g;
	}
	$arg =~ s/ /\+/g;
	push @arglist,$arg;
    }
    return join($this->output_parameter_separator(),@arglist);
}

sub decode_query {
    my $this = shift;
    my $q = shift;
    my %q = &DecodeString($q,$this->parameter_separator());
    return wantarray ? %q : \%q;
}

sub parameter_separator {
    my $this = shift;
    if (! $this->{separator}) {
	$this->{separator} = $config{url_param_sep} || "&";
    }
    return $this->{separator};
}

sub output_parameter_separator {
    my $this = shift;
    my $sep = $this->{separator} || $this->parameter_separator();
    if ($sep eq "&") {
	return $this->{plaintext} ? "&" : "&amp;";
    }
    return $sep;
}

# write out new URIs

sub write {
    my ($this,$type) = @_;
    return ($type eq "relative") ?
	$this->write_relative() :
	$this->write_full();
}

sub write_full {
    my $this = shift;
    my $u = $this->{uridata};
    my $uri = "$u->{scheme}://$u->{authority}";
    my $rel = $this->write_relative();
    if ($rel ne "#") { $uri .= $rel; }
    return $uri;
}

sub write_relative {
    my $this = shift;
    # script
    my $uri = $this->script_name();
    # path
    $uri .= $this->make_path;
    # query string
    my $q = $this->make_query;
    if ($q) { $uri .= "?$q"; }
    # fragment
    my $frag = exists $this->{output}{fragment} ? 
	$this->{output}{fragment} : $this->{uridata}{fragment};
    if ($frag) { $uri .= "#$frag"; }
    return $uri || "#";
}

# indirect URIs are used for links that should not be crawlable
# POSTs are more formally correct, but javascript gets the job done with
# fewer acrobatics - although it will fail if javascript is disabled.
sub write_indirect {
    my $this = shift;
    my $uri = $this->write();
    return "javascript:document.location='$uri'"
}

#=============================

1;

=pod

=head1 ExSite::URI

A class for parsing and composing URIs (web addresses).

Note that a URI is composed of the following components:

    scheme://authority/path?query#fragment

The C<scheme> defaults to "http".

The C<authority> is typically comprised of hostname, domain, and TLD,
delineated by ".".

The C<path> may be comprised of multiple sequential names, delineated
by "/".  This typically consists of multiple path segments, the first of
which refers to a C<script_name>, and the remainder of which is the
C<path_info>, which may in turn consist of several sub-segments that are 
concatenated together.  For example, C</cgi-bin/script.cgi/A/B/1/2>.

The C<query> is typically comprised of multiple C<key=value> pairs, 
delineated by a separator character (which defaults to "&").

=head2 Usage

    my $uri = new ExSite::URI(%option);

C<%option> can include:

    separator    => parameter separator character (eg. ";" or "&")

    plaintext    => output plaintext URLs if true
                    otherwise, output HTML URLs

    uri          => a URI string to initialize the object with

    secure_query => enccode the query data to make it tamper-resistant

By default, the object will be initialized with the current URI, will use 
'&' as the parameter separator, and will output HTML URIs.

The only difference between HTML and plaintext URIs is whether or not
HTML metacharacters such as '&' are escaped.  (In plaintext mode they are 
left unescaped.)

You can change the separator character at any time:

    $uri->separator(';');

The current separator character is used for both parsing URIs and
composing new URIs, so you may need to switch if you want to use a
different separator character for your input and output.

You can change the text mode with the following calls:

    $uri->plaintext;    # output plaintext URIs
    $uri->html;         # output HTML URIs

At any time, you can extract a structure with all of the parsed URI data
using:

    %parsed_uri = $uri->info;

You can also fetch individual URI components using:

    $data = $uri->get($component);

where C<component> is one of the keys in the hash returned by
C<info()>, namely "scheme", "authority", "path", "path_info",
"script_name", "query", "query_data", or "fragment".  Note that
"query" is the raw query string, and "query_data" is a hash of parsed
keys/values.  Also, "path" is the concatenation of "script_name" and
"path_info".

=head2 URI Sources

This class can manage URIs from any source, in principle.  Its
defaults are optimized for handling ExSite URIs.  ExSite URIs use a
conventional format which assumes the following additional rules:

=over 4

=item * path

The path component of the URI constists of a C<script_name> and extra
C<path_info> concatenated together.  For example:
C</cgi-bin/script.cgi/extra/path/data>

=item * query

The query component of the URI consists of multiple C<key=value> pairs, 
joined by a separator character ("&" by default).

=back

These are common URI conventions, so this class should be fairly
versatile, even with non-ExSite URIs.  You might encounter minor
issues with non-ExSite URIs that do not use the same conventions.  For
example, not all query strings are sequences of key/value pairs, so
we might not be able to extract intelligible parameters from unconventional
query strings.  Also, it may not be possible for URI to tell which part
of a path corresponds to a C<script_name> and which to a C<path_info>,
or even if those are sensible ways to divide the path.  In that case,
you may get no C<script_name> or C<path_info> parsed out of the URI,
and it will all be aggregated into a single C<path>.  Attempting to
set query parameters or path segments may not give expected results in
these cases.

If you do not pass an explicit URI, the object will initialize itself
with the URI of the current request, as read from the Apache
environment.

You can re-initialize the object with a different URI at any time:

    $uri->setup($new_uri);

=head3 Resetting the URI

After modifying the URI (see below), it is often the case that you
want to reset it back to its initial state.  You can do this:

    $uri->reset();

If the URI was explicitly passed to the object, this will restore the
original state completely.  If the URI was implicitly determined from
the local environment, however, it may be different, depending on how
local definitions have changed in the meantime.  If the path or query
data have been altered in ExSite's input buffers, then the URI will
reflect those changes.

Sometimes you want this behaviour for explicit URIs.  For example, the
object may be forced to an explicit URI that is meant to reflect a
local URI that would normally be implicit.  (This happens when
publishing, for instance, where we spoof the URI and environment for
each page that we generate.)  To get the implicit reset behaviour on a
an explicit URI, do this:

    $uri->use_input();

This tells the object to use any updated input data when constructing
the implicit URI.

=head2 Query Strings

The query is the part of the URL after a question mark.  It is
typically broken into key=value pairs by a separator character, which
is "&" by default.

To change a parameter in the URI:

    $uri->parameter($key, $value);

To remove a parameter completely:

    $uri->parameter($key,undef);  # OR
    $uri->parameter($key);

To change multiple parameters:

    $uri->query(%parameters);

The query string is written as C<key1=val1&key2=val2...>, although the
parameter separator character "&" can be changed as noted above.

=head3 Secure Links

If you make the URI object secure:

    $uri->secure();

then your query strings will be encoded, making them tamper-proof.
This is not recommended for normal usage, as it is quite convenient to
be able to inspect and alter query strings.  However, you may wish to
make exceptions in some cases where sensitive data may be exposed in
the query string, or there are security issues associated with editable
query strings.

Secure query strings will either be encrypted, or hashed using the built-in
token feature, if that is available. Token-based secure query strings will
expire (by default after 30 days).

To go back to normal query strings, use:

    $uri->insecure();

(This is a misnomer, since there is nothing really insecure about
a normal query string.)

=head2 Path Info

The URI path includes the slash-separated values after the domain
name and before the '?'.  This is typically broken down into two
parts, C<script_name> and C<path_info>.

    /path = 
    /script_name/path_info

The script_name is typically broken down into a diskpath to a CGI
program, while the C<path_info> is treated as path-like data that is
then passed on to this program.  For example:

    /script_name   +  /path_info =
    /cgi/page.cgi  +  /store/catalog.html/widgets/blue_grommet

In principle the C<path_info> can be further broken down into segments
that refer to different types of resources, which are concatenated
together, eg.

    /path_info(CMS segment) +  /path_info(Catalog segment) = 
    /store/catalog.html     +  /widgets/blue_grommet

The breakdown of different C<path_info> segments is done using the
Input manager (C<ExSite::Input>), if this is an implicitly defined
URI.  Once they are defined, you can redefine specific segments in
isolation in the URI object.  For example, if the C<path_info> is
divided into the CMS and Catalog segments, as in the above example,
then we can redefine either segment alone as follows:

    $uri->path("CMS","/store/catalog.html");   # scalar method
    $uri->path("Catalog","widgets","red_grommet"); # array method

These new path segments will replace the original path segments,
without altering the remaining segments of the path.

If you define a new path segment unknown to the Input manager, then
the new path segment will be appended to those that are already
defined.  For example,

    $uri->path("extra","foo");

would result in "/foo" being appended to the existing path, resulting
in a new C<path_info> of:

    /store/catalog.html/widgets/blue_grommet/foo

To delete a path segment, just pass nothing as the segment data:

    $uri->path("Catalog",undef);
    $uri->path("Catalog");        # equivalent

To completely override the path segments defined by the Input manager,
and explicitly define your path, use these:

    $uri->script_name($path);
    $uri->path_info($path);

=head2 Service Pages

A service page is a special page in the ExSite CMS that services
requests for a particular plug-in.  If a page generates a URL that
will be processed by that plug-in, it should automatically adjust the
target URL so that it redirects to the service page.  This is done in
the URI class by the C<service_page()> method.

To change the current URI so that it directs to the service page
instead of whatever page it happens to be on, use this:

    $uri->service_page($module);

where C<$module> is the plug-in (either a module object, or simply the
name of the plug-in).

Not all plug-ins are configured to use service pages, but there is no
harm in calling this method in those cases; it will leave the current
URI unchanged.

=head2 Security - Privileged URIs

Some URIs direct to pages/screens that require a certain level of user
access to view.  Simply using the URI is not sufficient to view the
contents; you also need to be logged in as a user with sufficient
access.  If you do not have this level of access, you are likely to
get a permission denied error message, or be prompted for a login and
password.

There is a feature by which you can include authentication credentials
in a URI so that the user will not receive an error or login prompt.
This trick uses encrypted "authtokens" embedded into the parameter string.

There are two things to consider when using authtokens:

=over 4

=item * what user identity should be assigned to the person who
follows this URI?

It must be an actual login ID that is permitted to view the URI.
Be very careful about disseminating URIs that grant 
administrator-level privileges, as that could be dangerous.

=item * how long should this privileged URI be valid for?

You can give the authtoken a lifetime in days.  For example, it could
expire in 1 day, 7 days, or 365 days, depending on how urgently you
want the user to attend to the link, and the risks of them visiting it
later, or repeatedly.

=back

To generate an encrypted authtoken string:

    my $authtoken = $uri->authtoken($login_id, $expiry_in_days);

To modify the current URI to include an authtoken granting that URI
special access:

    $uri->authorize($login_id, $expiry_in_days);

You then must output the URI (see below) to actually use it.  You
cannot really modify the URI any further at this point, because then
the authtoken won't match the updated URI, and it will fail to
validate.  It may be necessary to reset the URI or remove the C<_auth>
parameter to get back to a working URI.  To generate a URL with an
embedded authtoken, but leave the URI object in a normal working state
so that it can be further modified, use:

    my $auth_url = $uri->authorize_url($lgin_id, $expiry_in_days);

=head2 Output

After a URI has been modified using the above methods, you can obtain
the changed URI using the C<write> methods.

    $newuri = $uri->write($type);

C<$type> can be "relative" or "full" (full is the default):

    $newuri = $uri->write_relative();

This returns the URI after the authority.  It presumes the same
authority as the referrer.

    $newuri = $uri->write_full();

This returns the full URI including the scheme and authority.

Modifications to the URI are cumulative, so you can make changes,
output the new URI, make more changes, output again, etc.  If you want
to reset the URI to its original state so that changes are not
cumulative, use the C<reset> method:

    $uri->reset();

This also syncs with the Input manager to retrieve any new path
segments that were defined since the URI object was instantiated.


=cut

