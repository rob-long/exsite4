package ExSite::Search;

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
#-----------------------------------------------------------------------

use strict;
use ExSite::Config;
use ExSite::Auth;
use ExSite::Section;
use ExSite::Module qw(&get_module);
use ExSite::Page;
use ExSite::Misc;
use ExSite::ML;
use ExSite::Base;

use vars qw(@ISA);
@ISA = qw(ExSite::Base);

sub new {
    my $this = shift;
    my $obj = {};
    $obj->{section_id} = shift;
    my $class = ref($this) || $this;
    bless $obj, $class;
    $obj->initialize_object;
    $obj->{weight} = $config{search}{weight};
    $obj->{scope} = $config{search}{scope};
    $obj->reset;
    return $obj;
}

sub get_stopwords {
    my $this = shift;
    if (! exists $this->{stopwords}) {
	if (-e "conf/$config{search}{stopwords}") {
	    if (open F, "<conf/$config{search}{stopwords}") {
		my @stopwords = <F>;
		chomp @stopwords;
		my %stopwords = map { $_ => 1 } @stopwords;
		$this->{stopwords} = \%stopwords;
		return;
	    }
	}
	# no stopwords
	$this->{stopwords} = {};
    }
}

sub reset {
    my $this = shift;
    $this->{title} = {};
    $this->{descr} = {};
    $this->{site} = {};
    $this->{access} = {};
    $this->{type} = {};
    $this->{indexed_sections} = [];
    $this->{clear_url} = [];
    return;
}

# doesn't seem to do anything - nobody calls us
sub add_section {
    my ($this,@section_id);
    push @{$this->{indexed_sections}},@section_id;
}

sub search_form {
    my ($this,$term,$title,$width) = @_;
    my $out;
    my $ml = &get_obj("ML");

    my $formfield = $ml->input(undef,{type=>"text",size=>$width,name=>"searchterm",value=>$term});

    my $url = $this->link();
    if (! $width) { $width = 20; }
    if ($title) { $out .= $ml->h1($title); }
    my $searchlabel = $msg{Search};
    $out .= $ml->form(
	$formfield.
	$ml->input(undef,{type=>"submit",placeholder=>$searchlabel,value=>$searchlabel}),
	{method=>"GET",action=>$url,class=>"search",id=>"searchform"}
	);
    return $out;
}

sub do_search {
    my ($this,$term) = @_;
    my $ml = &get_obj("ML");
    my $out .= $ml->h1(&substitute($msg{"Search Results for [[term]]"},{term=>$term}));
    $out .= $this->display_results($this->search($term));
    $out .= $this->search_form($term,$msg{"Search"});
    return $out;
}

# index_site : indexes all content in a site

sub index_site { 
    my $this = shift;
    return $this->error("Search:index_site is deprecated");
}
sub index_section { 
    my $this = shift;
    return $this->error("Search:index_section is deprecated");
}
sub index_pages { 
    my $this = shift;
    return $this->error("Search:index_pages is deprecated");
}
sub index_page { 
    my $this = shift;
    return $this->error("Search:index_page is deprecated");
}

# index_plugins : indexes special content for all plugins in a site

sub index_plugins {
    my ($this,$section) = @_;
    my ($site,$out);
    if ((ref $section) =~ /Section/) {
	$site = $section;
    } 
    else {
	if (ref $section) { $site = new ExSite::Section(section=>$section); }
	else { $site = new ExSite::Section(id=>$section); }
    }
    my @service = $site->get_services;
    foreach my $service (@service) {
	if ($service->{page_id}) {
	    my $p = new ExSite::Page(id=>$service->{page_id});
	    my $modname = $service->{name};
	    my $dcd = &get_module($modname,0,$section);
	    if ($dcd) {
		$out .= $this->index_plugin($dcd,$site,$p);
	    }
	}
    }
    return $out;
}

# index_plugin : indexes special content for a specific plugin

sub index_plugin {
    my ($this,$dcd,$section,$page) = @_;
    my $search = $dcd->ioctl('Search');
    if ($search) {
	# this service has its own search indexing tools
	return $dcd->$search($this,$section,$page);
    }
}

# skip_url : consider this URL scanned and included in our index, but don't
# actually scan it. This improves performance if we detect that
# an URL does not need to be re-indexed, and allows us to detect and remove
# dead URLs.

sub skip_url {
    my ($this,%opt) = @_;
    return if (! $opt{url});
    $opt{title} or $opt{title} = $opt{content}{title};
    $opt{description} or $opt{description} = $opt{content}{description};
    $this->add_url(%opt);
#    $this->add_url($opt{url},$opt{section_id},$title,$description,$opt{access},$opt{type},$opt{language});
    return;
}

# index_url : indexes an arbitrary URL consisting of multiple text segments 
# Each text segment (eg. title, body, description, etc.) is given in 
# $opt{content}{segment_name} = $actual_text
# The weight of each text segment given in 
# $opt{weight}{segment_name} = $weight (1-10)
# Use a weight of 1 for normal body text.
# You should also pass:
# url - need this to index the content
# title - the anchor of the link to this URL
# description - the description of the link to this URL
# language - so we can keep different languages separated in the index
# access - level of access control to this content
# section_id - so we can group the URLs being searched in a query
# type - type of content (eg. content_type name or module)
# content_id - content object represented at this URL, if any. This is not neceesarily
#    the content object being indexed; eg. when indexing a body, the content_id should
#    probably be the page

sub index_url {
    my ($this,%opt) = @_;
    if (! $opt{url}) { 
	$this->error("Search::add_to_index: no url to index");
	return;
    }
    $opt{title} or $opt{title} = $opt{content}{title};
    $opt{description} or $opt{description} = $opt{content}{description};
    $this->add_url(%opt);
    foreach my $key (keys %{$opt{content}}) {
	# only index plaintext
	my $text = $opt{content}{$key};
	if ($text =~ /<\w+( [^>]*)?>/) {
	    ### FIXME: extra weight to h1, h2, etc?
	    $text = &html_to_plaintext($text);
	}
	$this->index($opt{url},$opt{weight}{$key},$text);
    }
    return;
}

# index : indexes the words in a block of plaintext

sub index {
    my ($this,$url,$weight,$text) = @_;
    return if (!$text);
    return if (! exists $this->{index}{$url});
    $this->get_stopwords;

    # strip endlines
    $text =~ s/\r?\n/ /g;
    # simplify down to ascii
    #$text = &utf8_to_ascii($text);
    # strip all non-word characters
    $text =~ s/[^\w]/ /g;
    # convert to lower case
    $text = lc($text);
    # convert to an array of words
    my @word = split /\s+/,$text;

    # index the words found
    foreach my $word (@word) {
	$this->index_term($url,$word,$weight);
    }
}

# index_term : add a term to the index

sub index_term {
    my ($this,$url,$term,$weight) = @_;
    return 0 if (! $url);
    return 0 if (! $term);
    return 0 if ($this->{stopwords}{$term});
    if ($config{search}{index_numbers}) {
	return 0 if ($term =~ /^\d+$/ && $term < $config{search}{min_number});
    }
    $weight |= 1;
    $this->{index}{$url}{$term} += $weight;
    # should return current weight for that term
}

# add_url : add a url to the index

sub add_url {
    my ($this,%opt) = @_;
#    my ($this,$url,$section,$title,$descr,$access,$type,$language) = @_;
    my $url = $opt{url};
    if (! exists $this->{index}{$url}) {
	$this->{index}{$url} = {};
	# remember to clear old index for this URL before updating
	push @{$this->{clear_url}},$url;
    }
    $this->{title}{$url} = $opt{title};
    $this->{descr}{$url} = $opt{description};
    $this->{site}{$url} = $opt{section_id} || 0;
    $this->{content}{$url} = $opt{content_id} || 0;
    $this->{access}{$url} = $opt{access} || 0;
    $this->{type}{$url} = $opt{type}; # content type or module
    $this->{language}{$url} = $opt{language};
    return;
}

# clear : clear old search data for a particular site
# NB: queries are defined by ExSite::Content::setup_querylib
# which should have already been called

sub clear_site {
    my ($this,$section_id) = @_;
    if ($section_id) {
#	my $s = new ExSite::Section(id=>$section_id);
	$share{DB}->get_query("clear search index",$section_id);
    }
}

# clear search data for a single URL
# $url can be a searchurl_id or a full URL

sub clear_url {
    my ($this,$url) = @_;
    if ($url =~ /^\d+$/) {
	$share{DB}->delete("searchterm",{searchurl_id=>$url});
	$share{DB}->delete("searchurl",{searchurl_id=>$url});
    }
    else {
	$share{DB}->get_query("clear url from search index",$url);
    }
}

# update : update the DB index

sub update {
    my ($this,$threshold,@site) = @_;
    if (!$threshold) { $threshold = 1; }
    my $db = $share{DB};

    # mark previously indexed items for deletion
    my (%oldurl,%oldterm);
    if (scalar @site == 0) { @site = @{$this->{indexed_sections}}; }
    foreach my $site (@site) {
	my @url = $db->fetch_match("searchurl",{section_id=>$site});
	foreach my $url (@url) {
	    $oldurl{$url->{url}} = 1;
	}
    }
    foreach my $url (@{$this->{clear_url}}) {
	$oldurl{$url} = 1;
    }

    # go through the new indexing data
    my (@urlupdates,@termupdates,@terminserts,@termdeletes);
    foreach my $url (keys %{$this->{index}}) {
	my @oldurl = $db->fetch_match("searchurl",{url=>$url});
	my %oldterm;
	my $url_id;
	if (@oldurl == 1) {
	    $url_id = $oldurl[0]{searchurl_id};
	    # mark old search terms for deletion
	    foreach my $oldurl (@oldurl) {
		my @terms = $db->fetch_child("searchterm","searchurl",$oldurl->{searchurl_id});
		foreach my $t (@terms) {
		    $oldterm{$t->{term}} = $t->{weight};
		}
	    }
	}
	elsif (@oldurl > 1) {
	    # confused index; just clear and start over
	    foreach my $oldurl (@oldurl) {
		$this->clear_url($oldurl->{searchurl_id});
	    }
	}

	# setup search url

	my %surl = (
	    url=>$url,
	    title=>$this->{title}{$url},
	    description=>$this->{descr}{$url},
	    section_id=>$this->{site}{$url},
	    content_id=>$this->{content}{$url},
	    access=>$this->{access}{$url},
	    type=>$this->{type}{$url},
	    language=>$this->{language}{$url},
	    );
	if ($url_id) {
	    $surl{searchurl_id} = $url_id;
	}
	if ($url_id) {
	    $surl{mtime} = undef;   # reset the timestamp
	    push @urlupdates, \%surl;
	}
	else {
	    # can't bulk insert these, because we need the url_id
	    $url_id = $db->insert("searchurl",\%surl);
	}
	if (! $url_id) {
	    $this->error("Search::update: could not create search index entry for $url");
	    return;
	}

	foreach my $word (keys %{$this->{index}{$url}}) {
	    next if (! $word);
	    if (defined $oldterm{$word}) {
		# this term is already indexed
		my $old_weight = $oldterm{$word};
		if ($old_weight == $this->{index}{$url}{$word}) {
		    # no change, skip it
		    delete $oldterm{$word};
		}
		elsif ($old_weight) {
		    # new weight, update it
		    push @termupdates, [ {weight=>$this->{index}{$url}{$word}}, 
					 {searchurl_id=>$url_id,term=>$word} ];
		    delete $oldterm{$word};
		}
		# else: zero weight, will be deleted
	    }
	    else {
		# term is not indexed, add it
		push @terminserts, { searchurl_id=>$url_id,
				     term=>$word,
				     weight=>$this->{index}{$url}{$word} };
	    }
	}
	# any terms remaining in %oldterm were not found in the new index;
	# simply delete them
	foreach my $word (keys %oldterm) {
	    push @termdeletes, {searchurl_id=>$url_id,term=>$word};
	}
	delete $oldurl{$url};
    }
    # any URLs remaining in %oldurl were not found in the new index;
    # simply delete them
    foreach my $url (keys %oldurl) {
	$this->clear_url($url);
    }

    # commit all bulk changes
    $db->bulk_update("searchurl",@urlupdates);
    $db->bulk_update("searchterm",@termupdates);
    $db->bulk_insert("searchterm",@terminserts);
    $db->bulk_delete("searchterm",@termdeletes);
}

# search the search table

sub search {
    my ($this,$terms,$type) = @_;

    my $db = $share{DB};

    ####### FIXME: use proper UTF8 indexing ????

    $terms = &utf8_to_ascii($terms);
    $terms =~ s/(?<=\S)[+-]|[^\w+-]/ /g;  # eliminate punctuation
    my @term = split /\s+/,lc($terms);
    my $nterm = 0;

    # "+foo" means "foo" is a required term in the results
    # "foo" means "foo" is an optional term in the results
    # "-foo" means "foo" is a forbidden term in the results

    my (@required,@optional,@blocked,$resultset,$required_terms);
    my $section = $this->{section_id} ||
	($share{Page} ? $share{Page}->id("section") : 0);
    my $col_searchurl_id = "searchurl.searchurl_id";
    foreach my $term (@term) {
	if ($term =~ /^\+/) {
	    # required term
	    $resultset = \@required;
	    $required_terms = 1;
	    $term =~ s/^\+//;
	    $nterm++;
	}
	elsif ($term =~ /^\-/) {
	    # forbidden term
	    $resultset = \@blocked;
	    $term =~ s/^\-//;
	}
	else {
	    # optional term
	    $resultset = \@optional;
	    $nterm++;
	}
	my $match = {
	    term=>$term,
	    "searchterm.searchurl_id"=>\$col_searchurl_id
	    };
	if ($this->{scope} ne "global") {
	    # restrict to local section, unless global searching is enabled
	    $match->{section_id} = $section;
	}
	if ($type) {
	    # restrict search to a particular plug-in
	    $match->{type} = $type;
	}
	push @$resultset, $db->select(["searchterm","searchurl"],undef,$match);
    }

    # combine the results into a single result hash

    my ($termresult,%result);
    
    $this->{search_results} = {};
    foreach $termresult (@required) {
	$result{$termresult->{searchurl_id}} += ($termresult->{weight} / $nterm);
	$this->{search_results}{$termresult->{searchurl_id}} = $termresult;
    }
    foreach $termresult (@optional) {
	# optional results count if there are no required terms, or 
	# if the result URL was already selected by the required terms
	if (! $required_terms || exists $result{$termresult->{searchurl_id}}) {
	    $result{$termresult->{searchurl_id}} += ($termresult->{weight} / $nterm);
	    $this->{search_results}{$termresult->{searchurl_id}} = $termresult;
	}
    }
    foreach $termresult (@blocked) {
	# remove blocked URLs from the results
	delete $result{$termresult->{searchurl_id}};
	delete $this->{search_results}{$termresult->{searchurl_id}};
    }
    
    return %result;
}

# format the search results 

sub display_results {
    my ($this,%results) = @_;
    my @url_id = sort { $results{$b} <=> $results{$a}; } keys %results;
    my $ml = &get_obj("ML");
    my $out;
    my $db = $share{DB};
    my $nresult = 0;
    foreach my $url_id (@url_id) {
	my $url = $this->{search_results}{$url_id} || 
	    $db->fetch("searchurl",$url_id);
	next if ($url->{access} && $db->level < $url->{access}); # perm.denied
	$nresult++;
	my $score = int($results{$url_id}*10)/10;
	if ($url->{url} =~ /^$config{server}{CGIpath}/) {
	    # show complete URLs
	    $url->{url} = $config{server}{server}.$url->{url};
	}
	$out .= $ml->dt( $ml->a($url->{title},{href=>$url->{url}}) );
	my $descr = $url->{description} . 
	    ($url->{description} ? $ml->br : "") .
	    $ml->span("[$url->{url}, $msg{score}: $score]",{class=>"searchdetails"});
	$out .= $ml->dd($descr);
	last if ($nresult == $config{search}{maxresult});
    }
    if ($nresult == 0) {
	$out .= $ml->dt($config{search}{no_results});
    }
    return $ml->dl($out);
}

sub find_content {
    my ($this,$term,$limit) = @_;
    $limit or $limit = 25;
    my %result = $this->search($term);
    my @result;
    my @url_id = sort { $result{$b} <=> $result{$a}; } keys %result;
    my $list = new ExSite::ObjectList(type=>"content");
    my $c = new ExSite::Content;
    foreach my $urlid (sort { $result{$b} <=> $result{$a}; } keys %result ) {
	my $url = $share{DB}->fetch("searchurl",$urlid);
	if ($url) {
	    push @result, $c->get_content_obj($url->{content_id});
	    $result[-1]->set("search_score",$result{$urlid});
	}
	last if (scalar @result >= $limit);
    }
    return wantarray ? @result : \@result;
}

=pod

=head1 Search.pm

The search system is based on a simple search index that uses 2 tables:

=over 4

=item * searchurl

every searchable URL is represented once here

=item * searchterm

every indexed word at each url is represented once here,
with a weight that is used for calculating relevance.  The weight
is based on the location of the word at the URL, and the number of
occurences.

=back

The search index is constructed by finding all content that is unique
to a URL (eg. the content objects that are page-specific), stripping
out all mark-up, and counting the incidence of each remaining word in
the text.  For web pages, we also index words in filenames, titles,
descriptions, and keywords.

Indexing of a web site consists of:

=over 4

=item 1 indexing the regular content on each page

The search system finds this content and indexes it automatically.  It
ignores content that is not page-specific, such as text that comes
from templates, menus, and so forth.

=item 2 indexing the content in each plug-in

Individual plug-ins can devise their own content indexing logic.  To
make a plug-in search indexing tool available to the system, the
plugin must be defined as a site service, and must reply with a code
reference to the the "Search" ioctl command.  This code reference is
the plugin's search indexer.  It will be invoked with three
parameters:

=over 4

=item an ExSite::Search object

Using this, the plug-in can add terms into the search index.

=item an ExSite::Section object

Using this, the plug-in can constrain which section's content gets indexed.

=item an ExSite::Page object

This indicates the page that should be used to deliver the plugin's
content in saerch results.  In other words, the plug-in should index
URLs that generate this page, albeit with alternate query string
parameters.

=back

=back

=head2 Usage

Make a search object:

    my $s = new ExSite::Search;

You must first index your site(s) before you can perform any searches:

    $s->index_site($section);

C<$section> can be a section ID or a section datahash.

To generate a search form:

    my $form_html = $s->search_form($term,$title,$width);

The parameters are all optional.  C<$term> is a term to prepopulate
the search field with.  C<$title> is a title/heading.  C<$width> is
the size of the search field (in characters).

To perform a search on the terms in a search string:

    my $results_html = $s->do_search($searchstring);

To get just the list of search hits:

    my $results_html = $s->display_results( $s->search($searchstring) );

The Search plug-in provides a simple interface to these functions.

=head2 Search Term Rules

The search system breaks each block of content down to a stream of
plain text.  All tags and non-text content (such as scripts and CSS)
are removed, to leave just the human-readable words and text on the
page.  Then we strip out all punctuation and other non-word characters
to leave just alphanumeric text and whitespace.  We convert the text
to lower case, and break it out into individual terms, splitting on
whitespace.  This has a few consequences that may be important for the
developer to understand, such as:

=over 4

=item * hyphenated words such as "over-easy" will be broken into two terms,
"over" and "easy".

=item * contractions such as "haven't" will be broken into two terms,
"haven" and "t".

=item * it only works on pages/sites that use languages that delimit
their words by whitespace and punctuation.  Other languages, such as
Chinese, will not work.

=back

Each term is then counted, and the count is multiplied by a weight
factor for that content block.  The resulting score determines how
significant a hit on that term is for that URL.

=head3 Advanced Searching Options

Search terms can optionally be prefixed with a + or - character, which
changes the search rules:

=over 4

=item term

The term is desired, but optional, in the search results.  Since at
least one term must produce a hit, if only one optional term is given,
then it is effectively a required term.  If more than one optional
term is given, at least one of them is required.

=item +term

The term is B<required> in the search results.  Results that do not
contain this term will not be reported.

=item -term

The term is B<forbidden> in the search results.  Results that 
contain this term will B<not> be reported.

=back

You can combine these for some extra logical control over your
searches.  For example:

=over 4

=item foo bar

Search for "foo" B<or> "bar".  (But pages that have both terms will tend to
be more relevant.)

=item +foo +bar

Search for "foo" B<and> "bar".

=item +foo bar

Search for "foo" and optionally "bar".  (Ie. search for "foo", but
if "bar" is also found, it will increase the relevance of the hit.)

=item foo -bar

Searches for pages containing "foo", but excludes pages containing
"bar" from the results.

=back

=head3 Stopwords

Certain terms can be ignored entirely by the search index.  These
stopwords are simply not inserted into the index, no matter how often
or where they appear.  They are ignored in search queries, and
attempts to search for just these terms will find nothing.

There are two ways to define the list of stopwords.  Method 1 is to
simply list them in the configuration parameter
C<$config{search}{stopwords}>.  You can add to this list using the
configuration file notation:

    search.stopwords += foo
    search.stopwords += bar

If the C<search.stopwords> parameter is not an array of works, but is
just a scalar string, that string is understood to be a file
containing the stopwords, one per line.  For example:

    search.stopwords = stopwords.txt

This file will be sought in the C<conf> subdirectory of C<cgi-bin>.
A fairly comprehensive sample file is included with ExSite, containing
over 500 words that by themselves carry little meaning and therefore
do not help to distinguish one search topic from another.  This file
may be edited or replaced as needed.

=head2 Limitations

You cannot search for partial words.  For example "surf" does not
match "surfing".

Quotes are ignored, and any words in a quoted phrase are searched for
individually.

Searches for negative numbers, eg. "-99" will be understood to mean
"exclude '99' from the search results".

It does not index alt tags on images.

It does not index any plug-ins that have not been configured as a service.

Only English stopwords are provided.

=cut

1;
