#!/usr/bin/perl
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

package ExSite::Misc;

use CGI;
use Encode;
use strict;

#========================================================================

=pod

=head1 ExSite::Misc  --  miscellaneous utility functions needed by ExSite::

This package contains routines and functions that have no dependence
on other ExSite code.

=cut

#========================================================================

BEGIN {
    use Exporter   ();
    use vars       qw($VERSION @ISA @EXPORT);
    $VERSION     = 1.00;
    @ISA         = qw(Exporter);
    @EXPORT = qw(   &EncodeHash &DecodePost &DecodeQuery &DecodeString
		    &DecodeInput &DecodeAttributes &EncodeAttributes
		    &columnwise &keywise &match_hash
		    &MimeType &MimeToFile &guess_MimeType &MimeDescr
		    &ShowHash &ShowList
		    &substitute &get_file &clean_filename
		    &url_escape &url_unescape &html_escape &html_unescape
		    &html_to_plaintext &make_plaintext &make_teaser_text
                    &latin1_to_ascii &utf8_to_ascii
		    &safetext &unsafetext &safehtml &safe_regex
                    &make_printable_string &hyperlink_urls
		    &randtext &randname
		    &array2text &hash2text &compare &wordcount
		    &relink
		    &sizeof &clone &hashcopy
		    &browser_type &is_tainted
		    );
}

# non-exported package globals

use vars qw($multi_sep $ncodechars @decodechars @decodecharre @encodechars
	    %substitution_method %mime_types
	    );

# multiple input separator; used to join multiple data inputs from the
# same input tag name

$multi_sep = "; ";

# characters that should be encoded as %hex values
$ncodechars = 8;
@decodechars = ("%", "+", "&", "@", "\"", "\#", "?", "/");
@decodecharre = ("%", "\\+", "&", "@", "\"", "\#", "\\?", "\/");
@encodechars = ("%25", "%2B", "%26", "%40", "%22", "%23", "%3F", "%2F");

#------------------------------------------------------------------------

=pod

=head2 Hash Encoding Tools 

For purposes of decoding input, these tools are deprecated. See 
ExSite::Input for better input management.  These tools may still 
be used for general-purpose hash encoding, however.

=over 4

=item EncodeHash(%hash)

Converts a hash to a URL-encoded string.
If the hash contains array references, those are converted to
comma-delimited lists of values.  If the hash contains hash
references, those are recursively converted using C<&EncodeHash>.

=item DecodeString($string)

Converts a URL-encoded string to a hash.
DecodeString can also be used to parse any string with key=value pairs
delimited by character X, if X is supplied as the 2nd argument.

Multiply-defined keys have their values appended to each other,
separated by the value of C<$multi_sep> ("; " by default).

=item DecodeQuery()

Decodes the QUERY_STRING. (Passes $ENV{QUERY_STRING} through &DecodeString().)

=item DecodePost()

Deprecated - use ExSite::Input instead.

Decode the POST data.  For URL-encoded form data, passes the data
though &DecodeString().  Multipart-encoded data is more complex (and
required for file uploads); in that case, the CGI:: package is used to
parse the data.

=item DecodeInput()

Deprecated - use ExSite::Input instead.

Decodes the input to the page.
Decodes either the POST or QUERY data, depending on the REQUEST_METHOD.

=item DecodeAttributes($string)

Decodes a string of attributes in HTML tag style, eg.

    key1=val1 key2="quoted val2" key3='another quoted value' key4

Returns a hash or hashref of the keys => values.  Only parses the key/value
pairings and quotes;  does not do any HTML escape handling.

=back

=cut

#------------------------------------------------------------------------

sub EncodeHash {
    # expecting a hash, or key,value pairs in input list
    my %in = @_;
    my @arglist = ();
    while ((my $key, my $val) = each %in) {
	my $arg;
	my $ref = ref($val);
	if ($ref eq "ARRAY") {
	    $arg = "$key=".join(",",@$val);
	}
	elsif ($ref eq "HASH") {
	    $arg = "$key=".&EncodeHash(%$val);
	}
	elsif ($val eq "") {
	    $arg = "$key";
	}
	else {
	    $arg = "$key=$val";
	}
	for (my $i = 0; $i < $ncodechars; $i++) {
	    $arg =~ s/$decodecharre[$i]/$encodechars[$i]/g;
	}
	$arg =~ s/ /\+/g;
	push @arglist,$arg;
    }
    return join("&",@arglist);
}

sub DecodeInput {
    # searches for input in Post first, then Query
    if ($ENV{REQUEST_METHOD} =~ /POST/i) {
        return &DecodePost;
    }
    return &DecodeQuery;
}

sub DecodePost {
    my $in;
    if ($ENV{CONTENT_TYPE} =~ /multipart\/form-data/) {
      # CONTENT_TYPE=multipart/form-data
      # (this form contains file uploads; use CGI module to decode it)
      my %data = ();
      my $in = CGI::new();
      foreach my $par ($in->param) {
	$data{$par} = $in->param($par);
      }
      return %data;
    }
    else {
      # CONTENT_TYPE=application/x-www-form-urlencoded
      my $clen = $ENV{'CONTENT_LENGTH'};
      if ($clen) {
	read(STDIN,$in,$ENV{'CONTENT_LENGTH'});
	return &DecodeString($in);
      }
    }
    return wantarray ? () : [];
}

sub DecodeQuery {
    my $query = $ENV{QUERY_STRING};
    if (defined $query) {
	return &DecodeString($query);
    }
    return wantarray ? () : [];
}

sub DecodeString {
    my $sep = $_[1] || "&";
    my @in = split(/$sep/,$_[0]);
    my %in;
    foreach my $i (0 .. $#in) {
        # Convert pluses to spaces
        $in[$i] =~ s/\+/ /g;

        # Split into key and value.
        (my $key, my $val) = split(/=/,$in[$i],2); # splits on the first =

        # Convert %XX from hex numbers to alphanumeric
        $key =~ s/%(..)/pack("c",hex($1))/ge;
        $val =~ s/%(..)/pack("c",hex($1))/ge;

        # Associate key and value. \0 is the multiple separator
        $in{$key} .= $multi_sep if (defined($in{$key}));
        $in{$key} .= $val;
    }
    return wantarray ? %in : \%in;
}

# decode key/value pairs in HTML format, eg. whitespace-separated keys,
# optionally quoted values.  Implemented as a crude lexical scanner.

sub DecodeAttributes {
    my ($mode,$key,$str,$qtype,%attr);
    foreach (split //,$_[0]) {
	if ($mode eq "key") {
	    # we're scanning a key name
	    if (/=/) {
		$mode = "eq";
		$key = lc $str;
		$str = undef;
	    }
	    elsif (/\s/) {
		$mode = "beq";
		$key = lc $str;
		$str = undef;
	    }
	    else {
		$str .= $_;
	    }
	}
	elsif ($mode eq "val") {
	    # we're scanning an unquoted value
	    if (/\s/) {
		# end of attribute def
		$attr{$key} = $str;
		$mode = $str = $key = undef;
	    }
	    else {
		$str .= $_;
	    }
	}
	elsif ($mode eq "sqval") {
	    # we're scanning a single-quoted value
	    if (/\'/) {
		# end of attribute def
		$attr{$key} = $str;
		$mode = $str = $key = undef;
	    }
	    else {
		$str .= $_;
	    }
	}
	elsif ($mode eq "dqval") {
	    # we're scanning a double-quoted value
	    if (/\"/) {
		# end of attribute def
		$attr{$key} = $str;
		$mode = $str = $key = undef;
	    }
	    else {
		$str .= $_;
	    }
	}
	elsif ($mode eq "beq") {
	    # we're between a key and equals sign
	    if (/=/) { $mode = "eq"; }
	    elsif (/\S/) {
		# new key
		$attr{$key} = "";
		$mode = "key";
		$str = $_;
	    }
	}
	elsif ($mode eq "eq") {
	    # we're between an equals sign and value
	    if (/\'/) { $mode = "sqval"; }
	    elsif (/\"/) { $mode = "dqval"; }
	    elsif (/[^=\s]/) { 
		$mode = "val"; 
		$str .= $_;
	    }
	}
	else {
	    # we're looking for a key
	    if (/\S/) { 
		$mode = "key"; 
		$str .= $_;
	    }
	}
    }
    if ($key) { $attr{$key} = $str; }
    foreach my $key (keys %attr) { 
	# if we get passed a complete tag, instead of just attributes
	delete $attr{$key} if ($key =~ /^\</ && ! $attr{$key});
    }
    return wantarray ? %attr : \%attr;
}

sub EncodeAttributes {
    # expecting a hash, or key,value pairs in input list
    my %in = @_;
    my @arglist = ();
    while ((my $key, my $val) = each %in) {
	my $arg;
	if ($val =~ /^\d+$/) {
	    push @arglist, "$key=$val";
	}
	elsif (! defined $val) {
	    push @arglist, $key;
	}
	else {
	    push @arglist, "$key=\"$val\"";
	}
    }
    return join(" ",@arglist);
}

#------------------------------------------------------------------------

=pod

=head2 Datahash Array Conversion Functions:

=over 4

=item columnwise($ref)

Convert a list of datahashes into a hash of datalists.

input: an array of hash references with identical keys.

output: a hash of arrays, indexed by the same keys.  For instance, 
C<( { a=E<gt>1, b=E<gt>2 }, { a=E<gt>3, b=E<gt>4 }, { a=E<gt>5, b=E<gt>6 } )>
becomes  C<( a =E<gt> [1,3,5], b =E<gt> [2,4,6] )>

=item keywise($key,$ref)

Convert a list of datahashes into a hash of datahashes.

input: a hash key to index on, and an array of hash references

output: a hash of hashes, indexed by one of the keys.  It is assumed
        that the value associated with this key is unique across all
        the hashes.  If not, the last such key is used.

For example, taking C<( { a=E<gt>1, b=E<gt>2 }, { a=E<gt>3, b=E<gt>4}, { a=E<gt>5, b=E<gt>6 } )> 
and indexing it by key "a", gives 
C<{ 1=E<gt>{a=E<gt>1,b=E<gt>2}, 3=E<gt>{a=E<gt>3,b=E<gt>4 }>.

=back

=cut

#------------------------------------------------------------------------

sub columnwise ($) {
    my ($ref_list_datahash) = shift;
    my @keys = keys %{$ref_list_datahash->[0]};
    my %datahash;
    foreach my $key (@keys) {
      $datahash{$key} = [];
      for (my $i = 0; $i < @$ref_list_datahash; $i++) {
	push @{$datahash{$key}}, $ref_list_datahash->[$i]->{$key};
      }
    }
    return wantarray ? %datahash : \%datahash;
}

sub keywise ($$) {
    my ($key,$ref_list_datahash) = @_;
    my %datahash = ();
    foreach my $rhash (@{$ref_list_datahash}) {
      $datahash{$rhash->{$key}} = $rhash;
    }
    return wantarray ? %datahash : \%datahash;
}

#------------------------------------------------------------------------


=pod

=head2 Text Encoding/Decoding Functions

=over 4

=item url_escape($text,$escape_chars)

Uses URL-escaping conventions to modify C<$text> by escaping the
characters in C<$escape_chars>.  If C<$escape_chars> is not given, escapes
these characters by default:

    %+ &@"?#

=item url_unescape($text)

Removes URL-escape codes from C<$text>, restoring the plaintext.

=item html_escape($text,$escape_chars)

Uses HTML-escaping conventions to modify C<$text> by escaping the
characters in C<$escape_chars>.  If C<$escape_chars> is not given,
the following characters are escaped by default:

    %+ &@"'?#

=item html_unescape($text,$escape_chars)

This reverses the escape codes inserted by C<html_escape()>.

=item safetext($text)

Converts arbitrary data into a string consisting only of the
characters a-z, A-Z, 0-9, and _.  Such strings are safe(er) for use as
variable names or field IDs.

=item unsafetext($text)

Converts a safe string back to its original representation.

=item safehtml($html,@tags)

Makes an untrusted HTML string safer to inline into a web page, by 
disabling all but a limited set of tags, and closing any tags that were
left open.  By default, it uses a set of allowed tags that are useful
for minor text formatting and linking, but disallows everything else,
including layout tags (divs, tables, frames, etc.), I/O tags (forms, 
inputs, etc.), script and style tags, and other advanced features.  
It allows some compound tags, such as ol/ul, li, but does not check
for syntactic correctness in tag nesting.  Disabled tags are rendered
literally, ie. the angle brackets are shown.  If the default tag list is 
not suitable, you can pass a list of allowed tag names.  

=back

=cut

sub url_escape {
    my ($text,$echars) = @_;
    if (! $echars) { $echars = "\%\+\ \&\@\"\'\?\#\:"; }
    my $rechars = '[]+*^$?';
    for (my $i = 0; $i < length($echars); $i++) {
	my $char = substr($echars,$i,1);
	#my $esc = ($char eq " " ? '+' : sprintf("%%%02x",ord $char));
	my $esc = sprintf("%%%02x",ord $char);
	if (index($rechars,$char) > -1) { $char = "\\$char"; }
	$text =~ s/$char/$esc/g;
    }
    return $text;
}

sub url_unescape($) {
    my ($text) = shift;
    # unescape everything...
    $text =~ s/%(..)/pack("c",hex($1))/ge;
    return $text;
}

sub html_escape {
    my ($text,$echars) = @_;
    if (! $echars) { $echars = '&<>"\''; }
    my $rechars = '[]+*^$';
    for (my $i = 0; $i < length($echars); $i++) {
	my $char = substr($echars,$i,1);
#	next if ($char eq "&");
	my $esc = sprintf("&#%d;",ord $char);
	if (index($rechars,$char) > -1) { $char = "\\$char"; }
	$text =~ s/$char/$esc/g;
    }
    return $text;
}

sub html_unescape {
    my ($text,$echars) = @_;
    if (! $echars) { $echars = '&<>"'; }
    my $rechars = '[]+*^$';
    for (my $i = 0; $i < length($echars); $i++) {
	my $char = substr($echars,$i,1);
	my $esc = sprintf("&#%d;",ord $char);
	if (index($rechars,$char) > -1) { $char = "\\$char"; }
	$text =~ s/$esc/$char/g;
    }
    return $text;
}

sub safetext {
    $_ = shift;
    s/([^a-zA-Z0-9])/"_".unpack("H2",$1)/ge;
    return $_;
}

sub unsafetext {
    $_ = shift;
    s/_(..)/pack("c",hex($1))/ge;
    return $_;
}

sub safehtml {
    my ($html,@tags) = @_;

    # build list of allowed tags

    if (@tags == 0) { 
	@tags = qw/a b blockquote br center code dd dl dt em 
	    font h1 h2 h3 h4 h5 h6 hr i img li ol p pre 
	    s strong sub sup tt u ul/; 
    }
    my %allowed = map { $_ => 1; } @tags;

    # escape all tags

    while ($html =~ /<(\/?)([A-Za-z]+?)( .+?)?>/) {
	my $close = $1;
	my $tag = $2;
	my $lctag = lc $tag;
	if ($allowed{$lctag}) {
	    # mask the tag
	    $html =~ s/<($close)?($tag)( .+?)?>/\&\#60;$1$2$3\&\#62;/;
	}
	else {
	    # neuter the tag
	    $html =~ s/<($close)?($tag)( .+?)?>/&lt;$1$2$3&gt;/;
	}
    }
    
    # unescape all allowed tags, and find unclosed tags

    my @notclosed;
    while ($html =~ /\&\#60;([A-Za-z]+?)( .+?)?\&\#62;/) {
	my $tag = $1;
	# unmask this opening tag
	$html =~ s/\&\#60;$tag( .+?)?\&\#62;/<$tag$1>/;
	if ($html =~ /\&\#60;\/$tag\&\#62;/i) {
	    # unmask this closing tag
	    $html =~ s/\&\#60;\/$tag\&\#62;/<\/$tag>/i;
	}
	else {
	    # !! not closed
	    if ($tag !~ /^(br|hr)$/) {
		push @notclosed, $tag;
	    }
	}
    }

    # close the unclosed tags

    foreach my $tag (reverse @notclosed) {
	$html .= "</$tag>";
    }

    # anything left should remain escaped.  This may include close
    # tags that were never opened.
    $html =~ s/\&\#60;/\&lt;/;
    $html =~ s/\&\#62;/\&gt;/;

    # disable onclick and other JS attributes
    $html =~ s/<(.+?\s)(on\w+)([=\s].+?)>/<$1X$2$3>/ig;
    $html =~ s/<(.+?\s)(href\s*=\s*[\'\"]?)(javascript:)(.+?)>/<$1$2X$3$4>/ig;

    return $html;
}

sub make_printable_string {
    $_ = shift;
    # remove non-printing characters, eg. newlines, ctrl chars
    #s/[^\p{XPosixPrint}]/ /g;
    s/[[:cntrl:]]/ /g;
    return $_;
}

sub safe_regex {
    $_ = shift;
    s/([\(\)\[\]\{\}\.\+\*\?\^\$])/\\$1/g;
    return $_;
}

=pod

=head2 General Text-Processing Functions

=over 4

=item substitute($text,$subhash,$startmark,$endmark)

Performs simple text substitutions.

Replaces marker tags such as "[[tag]]" with the value in C<$subhash{"tag"}>.
Does so for all such tags in the text.  Tags may contain word 
characters only (alphanumeric plus _).

=over 4

=item $text

string to perform substitutions on

=item $subhash

hash of marker keys=E<gt>values

=item $startmark

substring denoting the start of a marker tag ("[[" default)

=item $endmark

substring denoting the end of a marker tag ("]]" default)

=back

C<substitute> also recognizes marker tags of the form:

    [[?foo]]
    this text is included if foo is defined
    [[/?foo]]

    [[!foo]]
    this text is included if foo is NOT defined
    [[/!foo]]

C<substitute_simple()> does the same thing, but does not support 
this last conditional substitution feature.

=item html_to_plaintext($html,%opt)

Converts HTML to plaintext, making a modest attempt to preserve
formatting. It accepts the following options (set to 1/true):

=over 4

=item nl

Reformat newlines, in an attempt to get a tidier presentation of text
blocks like paragraphs.  (Works like a text editor fill function.) 
May destroy formatting that depends on linebreaks (eg. text in pre blocks).
Without this, the original newlines are simply preserved.  

=item data

Preserves non-textual data blocks, such as css and scripts.
Without this, data is discarded.

=item nohtml

Escaped HTML markup will be unescaped in plaintext conversion. To also
remove these, so that nothing resembling an HTML tag appears in the 
output, set nohtml=1.

=back

=item make_plaintext($text)

Similar to C<html_to_plaintext()> but does not attempt to preserve any
formatting. Reduces a block of text to its readable words and
characters.

=item make_teaser_text($text)

Takes an input block of text, which can be an HTML document, and 
tries to extract an introductory paragraph or text segment that 
can serve as a teaser or brief description.

=item latin1_to_ascii($text)

Converts Latin-1 text (ISO-8859-1 or Windows-1252 encoding) to plain
ASCII.  Accented characters are converted to unaccented characters;
ligatures are broken out into component characters; symbols are
converted to nearest lookalike, or to character sequences that are
reasonable facsimiles of the original character.

=item hyperlink_urls($text)

Replaces any bare URLs in the passed text with a hyperlink to the URL,
ie. URL =E<gt> E<lt>a href=URLE<gt>URLE<lt>/aE<gt>

=item randtext($len,$src)

Generates strings of random text.  Generated strings will be of length
C<$len>, and composed of characters from C<$src>.  Both parameters are
optional.  Default length is 7-10 characters, and the default source string
includes most of the printable ASCII character set.

This is useful as a secure password or passkey generator.

=item array2text(@data)

Converts a perl array to a text string, similar to how the array would
be represented in perl code if all the references were stripped out.
The array is encoded using arrayref notation C<[...]>.  The array is not
guaranteed to be a perfect perl representation of the data -- the normal
usage is just to provide a unique linearization of the data for use as a 
hash key.  This is faster than linearizing using Storable or JSON, or hashing
using MD5.

=item hash2text(%data)

Converts a perl hash to a text string, similar to how the hash would
be represented in perl code if all the references were stripped out.
The hash is encoded using hashref notation C<{...}>.  See notes under
C<array2text()> above.

=item compare($s1,$s2,$strong)

Compares two strings, and returns a similarity score from 0
(completely different) to 1 (identical). Comparison considers only
case-insensitive alphanumeric characters, so "MR MAGOO" and
"Mr. Magoo" are the same.

$s1 and $s2 can optionally be simple hash or array refs. In this case,
we compare only those fields that are defined in both structures, so
it can determine how likely it is that two incomplete structures are
referring to the same thing. However, if $strong is true, we compare
every field, regardless of whether it contains data. If $s1 and $s2
are hashrefs, we only compare the hash values.

If String::Trigram is installed, we use that for a detailed,
character-by-character comparison. Otherwise, we simply compare the
number of identifical fields to the number of compared fields.

=back

=cut

sub substitute_simple {
    my ($text,$subhash,$startmark,$endmark) = @_;
    if (! $startmark) { $startmark = '\[\['; }
    if (! $endmark)   { $endmark = '\]\]'; }
    $text =~ s/$startmark(.+?)$endmark/$subhash->{$1}/g;
    return $text;
}

sub substitute {
    my ($text,$subhash,$startmark,$endmark) = @_;
    if (! $startmark) { $startmark = '\[\['; }
    if (! $endmark)   { $endmark = '\]\]'; }

    # any include blocks?
    if ($text =~ /$startmark(\?(.+?))$endmark(.+?)$startmark(\/\?(.+?))$endmark/s) {
	# remove include blocks that we don't have data for
	$text =~ s/$startmark(\?(.+?))$endmark(.+?)$startmark(\/\?(.+?))$endmark/defined $subhash->{$2} ? $3 : ""/sge;
    }
    if ($text =~ /$startmark(\!(.+?))$endmark(.+?)$startmark(\/\!(.+?))$endmark/s) {
	# include anti-include blocks that we don't have data for
	$text =~ s/$startmark(\!(.+?))$endmark(.+?)$startmark(\/\!(.+?))$endmark/defined $subhash->{$2} ? "" : $3/sge;
    }
    # substitute
    $text =~ s/$startmark(.+?)$endmark/$subhash->{$1}/g;
    return $text;
}

sub html_to_plaintext {
    my $text = shift;
    my %opt = @_;

    # escape conversion

    my %htmlesc = (
		   quot => '"',
		   amp => '&',
		   lt => '<',
		   gt => '>',
		   trade => '(TM)',
		   copy => '(C)',
		   reg => '(R)',
		   nbsp => ' ',
		   );

    if ($opt{nl}) {
	$text =~ s/\r?\n/ /g;                # remove linebreaks
    }
    else {
	$text =~ s/ (\r?\n)/$1/g;            # remove trailing spaces on each line
    }
    $text =~ s/<[\w]:.*?\/>//g;              # remove MS cruft
    if (! $opt{data}) {
	eval { $text =~ s/<([\w]):(.*?)>.*?<\/$1:$2>//g; };  # remove MS cruft
	$text =~ s/<style>.*?<\/style>//gi;  # remove css
	$text =~ s/<script.*?>.*?<\/script>//gi;   # remove js
    }
    $text =~ s/<br>\s*/\n/ig;                # convert <br> to linebreak
    eval { $text =~ s/<(h\d).*?>(.+?)<\/h\d>/\n\n-- $2 --\n\n/gi; }; # put headings on their own line
    $text =~ s/<p( .+?)?>/\n\n/ig;           # convert <p> to double-linebreak
    $text =~ s/<li>/\n* /ig;                 # convert <li> to text bullet
    $text =~ s/<hr>/"\n".('-'x72)."\n"/ieg;  # convert <hr> to dash line
    $text =~ s/<\/(div|li|ol|ul|dl|dd|dt|pre|table)>/\n/ig; # break lines at common end-blocks
    $text =~ s/<.+?>//g;                     # remove all other tags
    $text =~ s/ +/ /g;                       # collapse multiple spaces
    eval { $text =~ s/(\r?\n\r?\n)(\r?\n)+/$1/g; }; # collapse multiple linebreaks
    eval { $text =~ s/\&\#(\d+);/chr($1)/ge; }; # convert escape characters
    eval { $text =~ s/\&(\w+);/$htmlesc{$1}/ge; };
    if ($opt{nohtml}) {
	$text =~ s/<.+?>//g;                 # remove any formerly-escaped tags
    }
    if ($opt{nl}) {
	eval { $text =~ s/([^\n]{66,}?) /$1\n/g; };   # break long lines up
    }
    $text =~ s/^\s+//;                       # remove leading/trailing whitespace
    $text =~ s/\s+$/\n/;
    return $text;
}

# make_plaintext: similar to html_to_plaintext, but removes most formatting
# the optional remove_nl param also removes linebreaks

sub make_plaintext {
    my $text = shift;
    my $remove_nl = shift;
    my $nl = $remove_nl ? "\n" : " ";
    my $double_nl = $remove_nl ? "\n\n" : " ";
    $text =~ s/\r?\n/ /g; # remove all linebreaks
    $text =~ s/<[\w]:.*?\/>//g;              # remove MS cruft
    $text =~ s/<([\w]):(.*?)>.*?<\/$1:$2>//g;  # remove MS cruft
    $text =~ s/<style>.*?<\/style>//gi;  # remove css
    $text =~ s/<script.*?>.*?<\/script>//gi;   # remove js
    $text =~ s/<(h\d).*?>.+?<\/h\d>/$double_nl/gi; # remove headings
    $text =~ s/<table.*?>.+?<\/table>/$double_nl/gi; # remove tables
    $text =~ s/<[oud]l.*?>.+?<\/[oud]l>/$double_nl/gi; # remove lists
    
    $text =~ s/<br>\s*/$nl/ig;      # convert <br> to nl
    $text =~ s/<p( .+?)?>/$double_nl/ig; # convert <p> to double-nl
    $text =~ s/<\/?div>/$nl/ig;     # convert div to nl

    $text =~ s/<.+?>//g;        # remove all other tags
    $text =~ s/ +/ /g;          # collapse multiple spaces
    $text =~ s/^\s+//g;         # remove leading whitespace
    $text =~ s/\s+$//g;         # remove trailing whitespace
    return $text;
}

sub make_teaser_text {
    my $text = shift;
    if ($text =~ /<\w+( [^>]*)?>/) {
	# looks like HTML - remove elements that do not appear to 
	# be normal prose copy
	$text = &make_plaintext($text);
    }

    # search for start of prose
    my $start = 0;
    my $len = length $text;
    while ($start < $len && substr($text,$start,1) =~ /\s/) { $start++; }

    # search for linebreak
    my $end = $start+1;
    while ($end < $len && substr($text,$end,1) !~ /\n/) { $end++; }

    if ($end > 500) {
	# too long - search for punctuation
	$end = $start+1;
	while ($end < $len && substr($text,$end,1) !~ /[\.\!\?]/) { $end++; }
    }

    if ($end < 10 || $end > 500) {
	# too long/too short - break on whitespace
	$end = 200;
	while ($end < $len && substr($text,$end,1) !~ /\s/) { $end++; }
    }
    
    if ($end > 500) {
	# still too long - just break
	$end = 200;
    }
    
    my $out = substr($text,$start,$end-$start);
    if ($end < $len) {
	# we truncated
	$out =~ s/[\.\,\?\!\;\:]+\s*$//;
	$out .= "...";
    }
    return $out;
}

sub latin1_to_ascii {
    $_ = shift;
    my @ascii = (
	 ' ',' ',' ',' ',' ',' ',' ','',' ','',' ',' ',' ','',' ',' ',
	 ' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ','',' ',' ',' ',' ',
	 ' ','!','"','#','$','%','&',"'",'(',')','*','+',',','-','.','/',
	 '0','1','2','3','4','5','6','7','8','9',':',';','<','=','>','?',
	 '@','A','B','C','D','E','F','G','H','I','J','K','L','M','N','O',
	 'P','Q','R','S','T','U','V','W','X','Y','Z','[','\\',']','^','_',
	 '`','a','b','c','d','e','f','g','h','i','j','k','l','m','n','o',
	 'p','q','r','s','t','u','v','w','x','y','z','{','|','}','~',' ',
	 'E',' ',',','f','"','...','+','++','^','0/00','S','<','OE',' ','Z',' ',
	 ' ',"'","'",'"','"','.','-','--','~','(TM)','s','>','oe',' ','z','Y',
	 ' ','!','c','#','$','Y','|','S',' ','(C)','a','<<','!','-','(R)','-',
	 'o','+/-','^2','^3',"'",'u','P','.',',','^1','^0','>>','1/4','1/2','3/4','?',
	 'A','A','A','A','A','A','AE','C','E','E','E','E','I','I','I','I',
	 'D','N','O','O','O','O','O','x','O','U','U','U','U','Y','P','ss',
	 'a','a','a','a','a','a','ae','c','e','e','e','e','i','i','i','i',
	 'd','n','o','o','o','o','o','/','o','u','u','u','u','y','p','y');
    my $new;
    foreach my $c (split //) {
	my $i = ord $c;
	$new .= $ascii[$i] ? $ascii[$i] : $c;
    }
    return $new;
}

sub utf8_to_ascii {
    $_ = decode("utf8",shift);
    my $new;
    my @ascii = (
	# ASCII
	' ',' ',' ',' ',' ',' ',' ','',' ','',' ',' ',' ','',' ',' ',
	' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ','',' ',' ',' ',' ',
	' ','!','"','#','$','%','&',"'",'(',')','*','+',',','-','.','/',
	'0','1','2','3','4','5','6','7','8','9',':',';','<','=','>','?',
	'@','A','B','C','D','E','F','G','H','I','J','K','L','M','N','O',
	'P','Q','R','S','T','U','V','W','X','Y','Z','[','\\',']','^','_',
	'`','a','b','c','d','e','f','g','h','i','j','k','l','m','n','o',
	'p','q','r','s','t','u','v','w','x','y','z','{','|','}','~',' ',
	# Latin-1 extension
	'E',' ',',','f','"','...','+','++','^','0/00','S','<','OE',' ','Z',' ',
	' ',"'","'",'"','"','.','-','--','~','(TM)','s','>','oe',' ','z','Y',
	' ','!','c','#','$','Y','|','S',' ','(C)','a','<<','!','-','(R)','-',
	'o','+/-','^2','^3',"'",'u','P','.',',','^1','^0','>>','1/4','1/2','3/4','?',
	'A','A','A','A','A','A','AE','C','E','E','E','E','I','I','I','I',
	'D','N','O','O','O','O','O','x','O','U','U','U','U','Y','P','ss',
	'a','a','a','a','a','a','ae','c','e','e','e','e','i','i','i','i',
	'd','n','o','o','o','o','o','/','o','u','u','u','u','y','p','y',
	# Unicode 0100-017F (Latin Extended-A)
	'A','a','A','a','A','a','C','c','C','c','C','c','C','c','D','d',
	'D','d','E','e','E','e','E','e','E','e','E','e','G','g','G','g',
	'G','g','G','g','H','h','H','h','I','i','I','i','I','i','I','i',
	'I','i','IJ','ij','J','j','K','k','k','L','l','L','l','L','l','L',
	'l','L','l','N','n','N','n','N','n','n','n','n','O','o','O','o',
	'O','o','OE','oe','R','r','R','r','R','r','S','s','S','s','S','s',
	'S','s','T','t','T','t','T','t','U','u','U','u','U','u','U','u',
	'U','u','U','u','W','w','Y','y','Y','Z','z','Z','z','Z','z','f',
	# Unicode 0180-024F (Latin Extended-B)
	'b','B','b','b','b','b','C','C','c','D','D','d','d','d','E','e',
	'e','F','f','G','G','h','I','i','K','k','l','l','M','N','n','O',
	'O','o','OI','oi','P','p','R','S','s','S','s','t','T','t','T','U',
	'u','U','V','Y','y','Z','z','Z','Z','z','z','dz','5','5','ts','w',
	'|','||','!=','!','DZ','Dz','dz','LJ','Lj','lj','NJ','Nj','nj','A','a','I',
	'i','O','o','U','u','U','u','U','u','U','u','U','u','e','A','a',
	'A','a','AE','ae','G','g','G','g','K','k','O','o','O','o','Z','z',
	'J','DZ','Dz','dz','G','g','H','W','N','n','A','a','AE','ae','O','o',
	'A','a','A','a','E','e','E','e','I','i','I','i','O','o','O','o',
	'R','r','R','r','U','u','U','u','S','s','T','t','3','3','H','h',
	'N','d','8','8','Z','z','A','a','E','e','O','o','O','o','O','o',
	'O','o','Y','y','l','n','t','j','db','qp','A','C','c','L','T','s',
	'z','?','?','B','U','V','E','e','J','j','q','q','R','r','Y','y',
	);
    foreach my $c (split //) {
	my $i = ord $c;
	$new .= $ascii[$i] ? $ascii[$i] : $c;
    }
    return $new;
}

# Here's a more thorough URL-identification regex from DaringFireball:
# \b(([\w-]+://?|www[.])[^\s()<>]+(?:\([\w\d]+\)|([^[:punct:]\s]|/)))

sub hyperlink_urls {
    my $text = shift;
    # mask real links
    $text =~ s/((\w+)=[\'\"]?)(https?):\/\//$1$3!!!:\/\//g;
    # wrap bare urls
    $text =~ s/(https?:\/\/([^\s]*\w))/<a href="$1" target="_blank">$1<\/a>/g;
    # unmask real links
    $text =~ s/((\w+)=[\'\"]?)(https?)!!!:\/\//$1$3:\/\//g;
    return $text;
}

sub randtext {
    my ($len,$src) = @_;
    if (! $len) { $len = int(rand(4)+7); }  # 7-10 characters
    if (! $src) { $src = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.!@#$%&*-_=+'; }
    my $out;
    for (my $ichar = 0; $ichar < $len; $ichar++) {
	$out .= substr($src,(int(rand(length($src)))),1);
    }
    return $out;
}

# randname : like randtext, but \w chars only, suitable for variable names
sub randname {
    my ($len) = @_;
    if (! $len) { $len = int(rand(4)+7); }  # 7-10 characters
    my $src = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_';
    my $out;
    $out .= substr($src,int(rand(52)),1); # first char is a letter
    for (my $ichar = 1; $ichar < $len; $ichar++) {
	$out .= substr($src,(int(rand(length($src)))),1);
    }
    return $out;
}

sub array2text {
    my @ldata;
    foreach my $dat (@_) {
	if (ref $dat eq "ARRAY") { push @ldata, &array2text(@$dat); }
	elsif (ref $dat eq "HASH") { push @ldata, &hash2text(%$dat); }
	elsif (ref $dat eq "SCALAR") { push @ldata, $$dat; }
	else { push @ldata, (defined $dat ? "\"$dat\"" : ""); }
    }
    return "[".join(",",@ldata)."]";
}

sub hash2text {
    my %hash = @_;
    my $hdata;
    foreach my $k (sort keys %hash) {
	my $v = $hash{$k};
	if (ref $v eq "ARRAY") { $v = &array2text(@$v); }
	elsif (ref $v eq "HASH") { $v = &hash2text(%$v); }
	elsif (ref $v eq "SCALAR") { $v = $$v; }
	else { $v = "\"$v\""; }
	$hdata .= "$k=>$v,";
    }
    return "{$hdata}";
}

sub compare {
    my ($s1,$s2,$strong) = @_;
    my ($str1,$str2);
    my ($ncmp,$nsame);
    if (ref $s1 eq "HASH" and ref $s2 eq "HASH") { 
	foreach my $key (keys %$s1) {
	    my $data1 = uc $s1->{$key};
	    my $data2 = uc $s2->{$key};
	    if ($data1 && $data2) {
		# field is defined in both records; compare them
		$ncmp++;
		$data1 =~ s/[^\w]//g;
		$data2 =~ s/[^\w]//g;
		if ($data1 eq $data2) {
		    $nsame++;
		}
		$str1 .= $data1;
		$str2 .= $data2;
	    }
	    elsif ($strong) {
		# only compare missing fields in strong mode
		$ncmp++;
		if ($data1 eq $data2) {
		    $nsame++;
		}
		$str1 .= $data1;
		$str2 .= $data2;
	    }
	}
    }
    elsif (ref $s1 eq "ARRAY" and ref $s2 eq "ARRAY") { 
	my $l1 = scalar @$s1;
	my $l2 = scalar @$s2;
	my $max = $l1 > $l2 ? $l1 : $l2;
	for (my $i=0; $i < $max; $i++) {
	    my $data1 = uc $s1->[$i];
	    my $data2 = uc $s2->[$i];
	    if ($data1 && $data2) {
		# field is defined in both records; compare them
		$ncmp++;
		$data1 =~ s/[^\w]//g;
		$data2 =~ s/[^\w]//g;
		if ($data1 eq $data2) {
		    $nsame++;
		}
		$str1 .= $data1;
		$str2 .= $data2;
	    }
	    elsif ($strong) {
		# only compare missing fields in strong mode
		$ncmp++;
		if ($data1 eq $data2) {
		    $nsame++;
		}
		$str1 .= $data1;
		$str2 .= $data2;
	    }
	}
    }
    else {
	$str1 = uc $s1;
	$str2 = uc $s2;
	$str1 =~ s/[^\w]//g;
	$str2 =~ s/[^\w]//g;
	$ncmp = 1;
	if ($str1 eq $str2) { $nsame = 1; }
    }
    if ($str1 && $str2 && eval 'require String::Trigram') {
	return String::Trigram::compare($str1,$str2);
    }
    else {
	return $ncmp > 0 ? $nsame / $ncmp : 0;
    }
}

sub wordcount {
    my $text = &html_to_plaintext(shift);
    $text =~ s/[^\w]/ /g;
    my @words = split /\s+/, $text;
    return scalar @words;
}

=pod

=head2 Miscellaneous other functions...

=over 4

=item MimeType($filename)

Guess the MIME type of a file.  This routine uses the filename (in
particular, the suffix) to guess the MIME type of the file.

=item MimeToFile($mimetype)

Guess the file extension for a mime type.  The routine returns a
standard/common file extension for files with the given mime type.

=item ShowHash()

Display a hash's contents in HTML format. 
A hash or hash reference may be passed to this routine;  a block of
HTML is returned.  The routine descends into the hash to display its
full structure.  There is no protection against infinite loops if 
the hash becomes self-referential.

=item ShowList()

Display an array's contents in HTML format.  The routine descends into
the array to display its full structure.  There is no protection
against infinite loops if the array becomes self-referential.

=item match_hash($pattern,$hash)

Returns true (1) if the hash matches the pattern.  The pattern is a hash of
keys/values which must be present and equal to the hash;  the hash may contain
other keys/values that are ignored.

=item clean_filename($filename)

Modifies a file name to make it safe for storage on all filesystems.
This essentially involves removing any special shell meta characters
from the filename.

=item get_file($opt)

Return contents of a file.  C<$opt> is a hash reference, which
presently only accepts one key:

=over 4

=item imgpath

adds this path value in front of any IMG SRC= attributes found in
the file.  (Presumably the file is HTML.)

=back

=item relink(%param)

Generates a recursive link back to same URL, with modified query parameters.

To set a new parameter, give the parameter a value in C<%param>.  To clear
a parameter, set its value in C<%param> to C<undef>.

C<relink()> returns the new URL to link to.

To link back to the same URL, use C<&relink();>,  not C<&relink;>.

See also Modules::BaseDCD::link(), which is better for relinking into
a dynamic content module.

=item sizeof($dat,$max)

Returns the size of $dat, in bytes.  If $dat is an array ref, returns
the sum of the sizes of the elements.  If $dat is a hash ref, returns
the sum of the sizes of the keys and the values.

C<Sizeof()> stops counting at a size of $max, if given.  This avoids
wasted cycles if you're just testing that the size is less than $max.

=back

=cut

#------------------------------------------------------------------------

sub MimeType ($) {
    $_ = shift;
    if    (/\.txt$/i)   { return "text/plain"; }
    elsif (/\.html?$/i) { return "text/html"; }
    elsif (/\.css$/i)   { return "text/css"; }
    elsif (/\.ics$/i)   { return "text/calendar"; }
    elsif (/\.js$/i)    { return "application/x-javascript"; }
    elsif (/\.tex$/i)   { return "application/x-latex"; }
    elsif (/\.doc$/i)   { return "application/msword"; }
    elsif (/\.ppt$/i)   { return "application/powerpoint"; }
    elsif (/\.pdf$/i)   { return "application/pdf"; }
    elsif (/\.e?ps$/i)  { return "application/postscript"; }
    elsif (/\.dvi$/i)   { return "application/x-dvi"; }
    elsif (/\.gif$/i)   { return "image/gif"; }
    elsif (/\.jpe?g$/i) { return "image/jpeg"; }
    elsif (/\.png$/i)   { return "image/png"; }
    elsif (/\.mpe?g$/i) { return "video/mpeg"; }
    elsif (/\.mov$/i)   { return "video/quicktime"; }
    elsif (/\.qt$/i)    { return "video/quicktime"; }
    elsif (/\.avi$/i)   { return "video/x-msvideo"; }
    elsif (/\.wmv$/i)   { return "video/x-ms-wmv"; }
    elsif (/\.rm$/i)    { return "video/x-pn-realvideo"; }
    elsif (/\.au$/i)    { return "audio/basic"; }
    elsif (/\.snd$/i)   { return "audio/basic"; }
    elsif (/\.aif.?$/i) { return "audio/x-aiff"; }
    elsif (/\.wav$/i)   { return "audio/x-wav"; }
    elsif (/\.swf$/i)   { return "application/x-shockwave-flash"; }
    elsif (/\.woff$/i)  { return "application/x-font-woff"; }
    else                { return "application/octet-stream"; }
    my ($ext) = $_ =~ /\.([^.]+)$/;
    return mime_lookup($ext);
}

# return the standard filename suffix used by a mime type

sub MimeToFile ($) {
    $_ = shift;
    if    (/text\/plain/i)             { return "txt"; }
    elsif (/text\/html/i)              { return "html"; }
    elsif (/text\/css/i)               { return "css"; }
    elsif (/text\/javascript/i)        { return "js"; }
    elsif (/application\/javascript/i) { return "js"; }
    elsif (/application\/x-javascript/i) { return "js"; }
    elsif (/application\/x-latex/i)    { return "tex"; }
    elsif (/application\/msword/i)     { return "doc"; }
    elsif (/application\/powerpoint/i) { return "ppt"; }
    elsif (/application\/pdf/i)        { return "pdf"; }
    elsif (/application\/postscript/i) { return "ps"; }
    elsif (/application\/x-dvi/i)      { return "dvi"; }
    elsif (/image\/gif/i)              { return "gif"; }
    elsif (/image\/jpeg/i)             { return "jpg"; }
    elsif (/image\/png/i)              { return "png"; }
    elsif (/video\/mpeg/i)             { return "mpg"; }
    elsif (/video\/quicktime/i)        { return "mov"; }
    elsif (/video\/x-msvideo/i)        { return "avi"; }
    elsif (/video\/x-ms-wmv/i)         { return "wmv"; }
    elsif (/video\/x-pn-realvideo/i)   { return "rm"; }
    elsif (/audio\/basic/i)            { return "au"; }
    elsif (/audio\/x-aiff/i)           { return "aif"; }
    elsif (/audio\/x-wav/i)            { return "wav"; }
    elsif (/application\/x-shockwave-flash/) { return "swf"; }
    elsif (/application\/x-font-woff/) { return "woff"; }
    else                               { return "dat"; }
    return mime_lookup($_,1);  
}

sub MimeDescr ($) {
    $_ = shift;
    if    (/text\/plain/i)             { return "plain text"; }
    elsif (/text\/html/i)              { return "HTML"; }
    elsif (/text\/css/i)               { return "stylesheet"; }
    elsif (/text\/javascript/i)        { return "javascript"; }
    elsif (/application\/javascript/i) { return "javascript"; }
    elsif (/application\/x-javascript/i) { return "javascript"; }
    elsif (/application\/x-latex/i)    { return "LaTeX document"; }
    elsif (/application\/msword/i)     { return "Word document"; }
    elsif (/application\/\.*office\.*/i) { return "Office document"; }
    elsif (/application\/powerpoint/i) { return "Powerpoint presentation"; }
    elsif (/application\/pdf/i)        { return "PDF document"; }
    elsif (/application\/postscript/i) { return "PostScript document"; }
    elsif (/application\/x-dvi/i)      { return "DVI file"; }
    elsif (/image\/gif/i)              { return "GIF image"; }
    elsif (/image\/jpeg/i)             { return "JPEG image"; }
    elsif (/image\/png/i)              { return "PNG image"; }
    elsif (/image\/(.+)/i)             { return "$1 image"; }
    elsif (/video\/mpeg/i)             { return "MPEG video"; }
    elsif (/video\/quicktime/i)        { return "Quicktime video"; }
    elsif (/video\/x-msvideo/i)        { return "AVI video"; }
    elsif (/video\/x-ms-wmv/i)         { return "Windows Media video"; }
    elsif (/video\/(.+)/i)             { return "$1 video"; }
    elsif (/audio\//i)                 { return "Audio file"; }
    elsif (/application\/x-shockwave-flash/) { return "Flash movie"; }
    elsif (/application\/x-font-woff/) { return "Font"; }
    else                               { return "data file"; }
}

sub guess_MimeType {
    my ($data,$fmt) = @_;
    # fmt = text, file, path,, url
    if (! $fmt) {
	if ($data =~ /^[\%\.\w-]+\#[\w-]+$/) {
	    $fmt = "file";
	}
	elsif ($data =~ /^(\/\w[\w\-\.]+)+$/) {
	    $fmt = "path";
	}
	elsif ($data =~ /^(([^:\/?\#]+):)?(\/\/([^\/?\#]*))?([^?\#]*)(\?([^\#]*))?(\#(.*))?$/) {
	    $fmt = "url";
	}
	else {
	    $fmt = "text";
	}
    }

    if ($fmt eq "text") {
	# look for suggestive patterns
	if ($data =~ /<(!--|[\/a-zA-Z])/) {
	    return "text/html";
	}
	elsif ($data =~ /\/\*|[\w-]+:\s*[\w\#]+\;|^\w*\.\w+\s*\{/) {
	    return "text/css";
	}
	else {
	    return "text/plain";
	}
    }
    elsif ($fmt eq "file") {
	my ($filename,$fdata) = split /\#/, $data;
	return &MimeType($filename);
    }
    else {
	# look at file type
	return &MimeType($data);
    }
    return undef;
}

sub mime_lookup {
    my ($key, $mime_to_extension) = @_;
    if (! keys %mime_types) {
	if (open(MIME, "/etc/mime.types")) {
	    while (<MIME>) {
		if (/^(\w\S+)\s+([\S\s]+)\n/) {
		    my $mime = $1;
		    my $tags = $2;
		    while ($tags =~ /\G(\w+)\s?/g) {
			$mime_types{$1} = $mime;
		    }
		}
	    }
	}
    }
    if ($mime_to_extension) {
        my %extensions = reverse %mime_types;
        return $extensions{$key} if ($extensions{$key});
        return "dat";
    } 
    else {
        return $mime_types{$key} if ($mime_types{$key});
        return "application/octet-stream";
    }
}

sub ShowHash {
    my $hash;
    if ($#_ > 0) { my %h = @_; $hash = \%h; }
    else { $hash = shift; }
    if (ref $hash !~ /HASH/) {
	return "Not a hash reference: $hash";
    }
    my $out = "<ul>\n";
    foreach my $key (sort keys %{$hash}) {
	$out .= "<li><strong>$key =&gt; </strong>";
	if ($hash->{$key} =~ /HASH/) {
	    $out .= &ShowHash($hash->{$key});
	} 
	elsif ($hash->{$key} =~ /ARRAY/) {
	    $out .= &ShowList(@{$hash->{$key}});
	} 
	else {
	    my $val = $hash->{key};
	    if (length $val > 100) { $val = substr($val,100,0)."..."; }
	    my $data = "\"$hash->{$key}\"";
	    $data =~ s/</&lt;/g;
	    $data =~ s/>/&gt;/g;
	    $out .= $data;
	}
	$out .= "</li>\n";
    }
    $out .= "</ul>\n";
    return $out;
}

sub ShowList {
    my $out = "<ol>\n";
    foreach my $item (@_) {
	my $data;
	if (ref $item eq "HASH") {
	    $data = &ShowHash($item);
	}
	elsif (ref $item eq "ARRAY") {
	    $data = &ShowList($item);
	}
	elsif (ref $item eq "SCALAR") {
	    $data = "[SCALAR] $$item";
	    $data =~ s/</&lt;/g;
	    $data =~ s/>/&gt;/g;
	}
	else {
	    $data = $item;
	    $data =~ s/</&lt;/g;
	    $data =~ s/>/&gt;/g;
	}
	$out .= "<li>$data</li>\n";
    }
    $out .= "</ol>\n";
    return $out;
}

sub match_hash {
    my ($pattern,$hash) = @_;
    return 1 if (! $pattern);
    foreach my $key (keys %$pattern) {
	return 0 if (! exists $hash->{$key} || 
		     ($pattern->{$key} ne $hash->{$key}));
    }
    return 1;
}

sub clean_filename {
    my $filename = shift;
    # remove file path
    my @path = split /[:\\\/]/, $filename;
    if (@path > 1) { $filename = $path[-1]; }
    # break filename down to prefix and suffix
    my ($prefix,$suffix) = $filename =~ 
	/^
	(.+?)          # non-greedy prefix can contain any character
	(\.[\w]+)?     # optional suffix can contain only word characters
	$/x;
    $prefix =~ s/[^\w\.-]/_/g;
    $prefix =~ s/_{2,}/_/g;
    ### WARNING: this could cause unexpected filename collisions
    ### eg. file#1!.gif, file(1).gif => file_1_.gif
    return $prefix.$suffix;
}

#------------------------------------------------------------------------
# get_file : return the contents of a file, modified according to the
#            calling options:
#
#------------------------------------------------------------------------

sub get_file($$) {
    my ($file, $opt) = @_;

    ### should support paths relative to the HTMLroot

    my $len = -s $file;
    open F,"<$file" or return undef;
    my $data;
    read(F,$data,$len) or return undef;
    close F; # or return undef;
    if ($opt->{imgpath}) {
        $data =~ s/(SRC=\"?)/$1$opt->{imgpath}\//ig;
    }
    if ($opt->{href}) {
        $data =~ s/(HREF=\"?)(?!\#)/$1$opt->{href}\//ig;
    }
    return $data;
}

sub relink {
    my $script = $ENV{SCRIPT_NAME};
    if ($ENV{PATH_INFO}) { $script .= "$ENV{PATH_INFO}"; }
    # go direct to query string, instead of via Input class, so that
    # we can pick up changes to $QUERY_STRING made after it was first
    # read
    my %query = &DecodeString($ENV{QUERY_STRING});
    my %newargs = (@_ == 1) ? %{$_[0]} : @_;
    foreach my $key (keys %newargs) {
	if (defined $newargs{$key}) {
	    $query{$key} = $newargs{$key};
	}
	else {
	    delete $query{$key};
	}
    }
    my $newquery = &EncodeHash(%query);
    
    return "$script?$newquery";
}

# measure the length of data of various structures
# $dat is the datum to measure; 
# $max is the size to stop counting at (saves cycles if you're just 
# testing for a maximum size)
#
# Does not measure real memory usage, just an approximate measure based 
# on aggregate string lengths.
#
# Use Devel::Size for a more accurate measure of object sizes.

sub sizeof {
    my ($dat,$max) = @_;
    if (ref $dat) {
	return length $$dat if (ref $dat eq "SCALAR");
	my $len;
	if (ref $dat eq "ARRAY") {
	    foreach my $d (@$dat) { 
		$len += ref $dat ? sizeof($d,$max) : length $d;
		return $len if ($max && ($len > $max));
	    }
	}
	elsif (ref $dat eq "HASH") {
	    while (my ($k,$v) = each %$dat) { 
		$len += (length $k + (ref $v ? sizeof($v,$max) : length $v));
		return $len if ($max && ($len > $max));
	    }
	}
	return $len;
    }
    return length $dat;
}

# clone : copy a structure in depth

sub clone {
    my ($dat) = @_;
    my ($clone,$key);
    if (ref $dat eq "HASH") {
	$clone = {};
	foreach my $key (keys %$dat) { 
	    $clone->{$key} = clone($dat->{$key});
	}
    }
    elsif (ref $dat eq "ARRAY") {
	$clone = [];
	foreach my $key (@$dat) { 
	    push @$clone, clone($key);
	}
    }
    elsif (ref $dat eq "SCALAR") {
	$key = $$dat;
	my $key2 = $key;
	$clone = \$key2;
    }
    else {
	$clone = $dat;
    }
    return $clone;
}

# hashcopy: copy elements of a hash into another hash

sub hashcopy {
    my ($from,$to,@keys) = @_;
    scalar @keys or @keys = keys %$from;
    foreach my $key (@keys) {
	if (ref $from->{$key}) {
	    $to->{$key} or $to->{$key} = {};
	    hashcopy($from->{$key},$to->{$key});
	}
	else {
	    $to->{$key} = $from->{$key};
	}
    }
}

# guess browser type: msie, gecko, webkit, opera, robot, other

sub browser_type {
    $_ = $ENV{HTTP_USER_AGENT};
    if (/MSIE/) {
	return "msie";
    }
    elsif (/Firefox/) {
	return "gecko";
    }
    elsif (/Safari/) {
	return "webkit";
    }
    elsif (/Chrome/) {
	return "webkit";
    }
    elsif (/Opera/) {
	return "opera";
    }
    elsif (/bot/) {
	return "robot";
    }
    elsif (/Mozilla/) {
	return "gecko";
    }
    return "other";
}

# test for tainted data - only works in Taint mode (perl -T)

sub is_tainted {
    return ! eval {
	join('',@_), kill 0;
	1;
    };
}

1;
