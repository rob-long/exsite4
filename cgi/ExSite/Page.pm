#!/usr/bin/perl
#----------------------------------------------------------------------------
#
#   Copyright 2011 Exware Solutions, Inc.  http://www.exware.com
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

package ExSite::Page;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::ML;
use ExSite::Util;
use ExSite::URI;
use ExSite::Content;
use ExSite::Template;
use MIME::Base64;

use vars qw(@ISA);
@ISA = qw(ExSite::Content);

sub my_subtype { return "page"; }

sub my_page { return shift; }

sub setup {
    my ($this,%opt) = @_;

    if ($opt{path}) {
	if ($opt{path} == 1) {
	    # remember the page representing the current request
	    $share{Content} = $this;
	    # $share{Page} is set by ex.cgi/page()
	}
	$this->{data} = $this->find_path(path=>$opt{path},type=>"page");
	$this->setup_querylib();
    }
    else {
	$this->SUPER::setup(%opt);
	# querylib should already be setup
    }
    
    if ($this->defined) {
	# successfully found the page
	$this->{type} = "content";
	$this->{dirty} = 0;
	if ($opt{revision}) {
	    ######## set revision
	    $this->load_revisions($opt{revision});
	}
	if ($opt{language}) {
	    #### set/change our language
	}
    }
}

sub find_path {
    my ($this,%opt) = @_;
    my $input;
    my $path = $opt{path};
    if ($path == 1) {
	$input = new ExSite::Input;
	$path = $input->path();
    }
    my $type = $opt{type};
    my $start = $opt{start};
    if (! defined $start) {
	$start = ($path =~ /^\//) ? undef : $this->id;
    }
    if ($type eq "page") {
	my $start = ($path =~ /^\//) ? undef : $this->id;
	my $tree = $this->get_content_tree();
	my @path = $tree->path_is($path,"name",$start);
	# we don't want the whole path, only the path to the last page
	my $itype = $this->isubtype("page");
	while (my $last = pop @path) {
	    my $c = $this->get_content_obj($last);
	    if ($c->is_page) {
		my @namepath = map { $_->{name} } (@path,$last);
		if ($opt{path} == 1) {
		    $input->new_path("Page",@namepath);
		}
		if (wantarray) {
		    my $namepath = "/".join("/",@namepath);
		    return ($last,$namepath);
		}
		else {
		    return $last;
		}
	    }
	}
	# no page in the path
	return undef;
    }
    return $this->SUPER::find_path(%opt);
}

# deprecated???

sub setup_from_path {
    my ($this,$path,$type) = @_;
    if ($type eq "page") {
	my $start = ($path =~ /^\//) ? undef : $this->id;
	my $tree = $this->get_content_tree();
	my @path = $tree->path_is($path,"name",$start);
	# we don't want the whole path, only the path to the last page
	my $itype = $this->isubtype("page");
	while (my $last = pop @path) {
	    my $c = $this->get_content_obj($last);
	    return $last if ($c->is_page);
	}
	# no page in the path
	return undef;
    }
    return $this->SUPER::setup_from_path($path,$type);
}

sub validate_subtype {
    my $this = shift;
    # other classes can act as pages (eg. sections)
    return 1 if ($this->is_page());
    return $this->SUPER::validate_subtype();
}

# get_revisions : get base HTML for the page
# - if we don't define our own base HTML, go to our template

sub get_revisions {
    my $this = shift;
    my @rev = $this->DB->fetch_child("revision","content",$this->id,"revision_id");
    return @rev if (scalar @rev);
    # no revisions in this page; go to the templates
    my $template_id = $this->getdata("template");
    if ($template_id) {
	my $t = new ExSite::Template(id=>$template_id);
	return $t->get_revisions();
    }
    return ();
}

sub set_language {
    my ($this,$lang) = @_;
    my $current_lang = $this->getdata("language");
    if ($lang ne $current_lang) {
	my $master = $current_lang ? 
	    $this->getdata("master") : $this->getdata("content_id");

	my @pages = $share{DB}->fetch_match("content",{
	    master=>$master,
	    language=>$lang});
	if (@pages > 0) {
	    $this->info("setting up $lang version of Page $this->{data}{page_id}");
	    $this->setup(data=>$pages[-1]);
	}
	else {
	    $this->warn("$lang version of Page $this->{data}{page_id} not found.");
	}
    }
}

# get_metadata : also include site metadata

sub get_metadata {
    my $this = shift;
    if ($this->loaded()) {
	# start with page data
	my %meta = %{$this->{data}};

	# add section data
	my $site = $this->my_section();
	my $sitedata = $site->get();
	foreach my $key (keys %$sitedata) {
	    $meta{"site_".$key} = $sitedata->{$key};
	}

	# add explicit metadata
	my %cmeta = $this->meta->get_all;
	while (my ($key,$val) = each %cmeta) {
	    $meta{$key} = $val;
	}
	return wantarray ? %meta : \%meta;
    }
}

# default fields for page configuration

sub editmeta_fields {
    my $this = shift;
    return ["title","label","name","parent","template","sortkey","publish","access","hide","language","status"];
}

=pod

=head1 Access Controls

=head2 is_valid()

Returns TRUE if the page belongs to the site the URL claims.
Valid pages are those that belong to the site they are invoked from.
Ie. if site x.com owns page 98 and site y.org owns page 99, then the
url http://x.com/cgi/page.cgi?_id=99 is not valid.

However, if the user owns the page/site then we allow them to inspect 
it from anywhere.  (This allows them to preview their pages from
a webservice CMS, for instance.)  System administrators can view any
pages from anywhere.

=cut

sub is_active {
    my $this = shift;
    # published pages are active, archived pages are not
    return (! $this->getdata("status"));
}

sub is_valid {
    my $this = shift;
    return 1 if ($share{DB}->is_admin);
    my $domain;
    if ($config{server}{auto}) {
	# config's domain info should be accurate
	$domain = $config{server}{domain};
    }
    else {
	# parse the domain right out of the HTTP_HOST info
	$ENV{HTTP_HOST} =~ /^((.+?)\.)?(.*?\..*?)(:\d+)?$/;
	$domain = $3;
    }
    my $s = $this->my_section();
    my $url = $s->get_host;
    if ($url =~ /^(\w+\.)?$domain$/) {
	# the section URL matches the calling host
	$this->{is_valid} = 1;
    }
    else {
	$this->{is_valid} = 0;
    }
    return $this->{is_valid};
}

# is the current user permitted to view this page dynamically?
### DEPRECATED - use allow()

sub authorize {
    my $this = shift;
    my $stat = $this->run_handler("page_authorize");
    return $stat if (defined $stat);
    return $this->allow("view");
}

=pod

=head1 Displaying Pages

=head2 cancel()

Aborts the page, so that no contents will be displayed to the viewer.
This is typically used if the page is superceded by a redirection.

=head2 header()

Usage:

    $page->header($hdr);

Adds the HTTP header line in $hdr to the list of header directives
that should be sent with this page.  No validation of C<$hdr> is performed.

=head2 show_headers()

Dispatches the accumulated headers for the page to the viewer.  If
there is no content-type header, one is added.

=head2 redirect()

Same as...

=head2 location()

Usage:

    $page->redirect($url);

Cancels the current page, and redirects the viewer to the specified URL.
The redirection is performed by issuing a Location: header.

=head2 errorpage()

Usage:

    $page->errorpage($html);

Cancels the current page, and generates an error page in its place.
C<$html> contains the error message.

This will attempt to use a special _ERROR template to format the page
if the section has such a template defined.  If not, the error message
will be issued "bare", ie. without any wrapper template.

This method is called if there is any problem generating the page as
requested.  Most commonly, this occurs when a non-member attempts to 
view a members-only page.  The error message in this case is the 
login prompt.

=cut

# some page display tools

# public show methods - inherited from ExSite::Content

# preview - display the page for admins

sub preview {
    my ($this,%opt) = @_;
    my @pane;
    my $ml = &get_obj("ML");
    my $ui = &get_obj("UI");
    my $url = $this->get_uri();
    $url->query("_cms"=>1);
    $pane[0] = $ui->ToolBar(tools=>[
	$ml->a("latest revision",{href=>$url->write_full(),target=>"_blank"}).
	$ml->a("published revision",{href=>$this->get_url(),target=>"_blank"}),
	]);
    my $html = $this->get_html();
    if ($html) {
	$html =~ s/\&/&amp;/ig;
	$html =~ s/</&lt;/ig;
	$html =~ s/>/&gt;/ig;
	$html =~ s/\[\[(.+?)\]\]/<span class="urltag">\[\[$1\]\]<\/span>/g;
	$html =~ s/{{(.+?)}}/<span class="purltag">{{$1}}<\/span>/g;
	$html =~ s/(\&lt;!--content\(.+?\)--\&gt;)/<span class="contenttag">$1<\/span>/g;
	$html =~ s/(\&lt;!--\$.+?--\&gt;)/<span class="metatag">$1<\/span>/g;
	$html =~ s/(\&lt;!--\&.+?--\&gt;)/<span class="dcdtag">$1<\/span>/g;
	$html =~ s/\n/<br>\n/g;    
	$html =~ s/(\&lt;.+?\&gt;)/<span class="htmltag">$1<\/span>/g;
    }
    else {
	$html = $ui->HelpMsg("This page has no base HTML. The expanded view will be based on the template.");
    }
    $pane[1] = $html;

    $share{Page} = $this;
    $html = $this->expand();
    $html =~ s/\&/&amp;/ig;
    $html =~ s/</&lt;/ig;
    $html =~ s/>/&gt;/ig;
    $html =~ s/\[\[(.+?)\]\]/<span class="urltag">\[\[$1\]\]<\/span>/g;
    $html =~ s/{{(.+?)}}/<span class="purltag">{{$1}}<\/span>/g;
    $html =~ s/(\&lt;!--content\(.+?\)--\&gt;)/<span class="contenttag">$1<\/span>/g;
    $html =~ s/(\&lt;!--\$.+?--\&gt;)/<span class="metatag">$1<\/span>/g;
    $html =~ s/(\&lt;!--\&.+?--\&gt;)/<span class="dcdtag">$1<\/span>/g;
    $html =~ s/(\&lt;.+?\&gt;)/<span class="htmltag">$1<\/span>/g;
    $html =~ s/\n/<br>\n/g;    
    $pane[2] = $html;
    return $ui->AccordionBox(
	titles=>["Preview","Base HTML","Expanded HTML"],
	panes=>\@pane,
	width=>"100%",
	states=>[1,0,0],
	);
}

=pod

=head1 Page Location

=head2 filename()

Returns the publication name of the page.  For regular pages, this is
the filename; for templates and libraries, it is the directory name.
The bare name is returned; see C<diskpath()> if a full path is needed.
The filename is processed by C<ExSite::Misc::clean_filename()> to
removed sensitive shell characters.  If the page does not have a
filename (should not normally occur), a filename based on the page ID
will be generated.

Note that the return value may not refer to an actual file if the page is 
always rendered dynamically.

=head2 httppath()

Returns the web path to the static page file.  This is the part of the
static URL after the domain name.  For templates and libraries
this returns the folder containing the template and library files.
For normal pages, this returns the folder for the current section.

Note that the return value may not refer to an actual file if the page is 
always rendered dynamically.

=head2 diskpath()

    my $path = $page->diskpath($dir_only);

Returns the server disk path to the static page file.  This returns
the path to the page's file if it is a normal page and $dir_only is
not TRUE.  Otherwise it returns the path to the directory that the
files are written to (ie. the section directory, template directory,
or library directory, as appropriate).

Note that the return value may not refer to an actual file if the page is 
always rendered dynamically.

=head2 get_url()

Return the URL to the page.  If the page is static, it checks to make
sure the page has actually been published before returning a static
URL.  If not, then a dynamic URL is returned instead, to ensure that
the URL will actually generate a meaningful result.

=head2 get_url_canonical()

Returns the correct public URL to the page.  This simply means that if
the page is supposed to be static, then the static URL is always
returned, even if the page has not yet been published.

=head2 get_url_static()

Returns the static URL to a page.  This may not be a valid URL if the
page is configured to only render dynamically.

=head2 get_url_dynamic()

    my $url = $page->get_url_dynamic($path_method);

Returns the dynamic URL to a page.  If C<$path_method> is TRUE, then
the URL is of the form:

    /cgi/page.cgi/section/page.html

Otherwise, the URL is of the form:

    /cgi/page.cgi?_id=123

=head2 link()

    my $url = $page->link(%args);

Generates a URL to a dynamic view of a page, including any optional
query parameters that are given in %args.  It is thus analagous to 
C<ExSite::BaseDCD::link()> in usage.

=cut

sub get_url {
    my $this = shift;
    return undef if (! $this->defined);
    my $url = $this->getdata("url");
    if ($url) {
	# content has a fixed URL
	return $url;
    }
    my $rev = $this->revision;
    my $view = $rev->view;
    my $format = $view->getdata("format");
    if ($format eq "url") {
	return $rev->get_url();
    }
    my $diskpath = $this->diskpath;
    my $httppath = $this->httppath;
    if (! $this->is_subdir) {
	my $file = $rev->filename;
	$diskpath .= "/$file";
	$httppath .= "/$file";
    }
    if (-e $diskpath) {
	if ($view->is_file) {
	    return $httppath . "/" . $view->filename;
	}
	else {
	    return $httppath || "/";
	}
    }
    return $this->get_url_dynamic();
}

sub get_url_static {
    my $this = shift;
    return undef if (! $this->defined);
    my $url = $this->getdata("url");
    if ($url) {
	# content has a fixed URL
	return $url;
    }
    $url = $this->SUPER::get_url_static();
    if ($this->revision->view->is_file) {
	return $url . "/" . $this->revision->view->filename;
    }
    else {
	return $url;
    }
}

sub get_url_dynamic {
    my $this = shift;
    return undef if (! $this->defined);
    my $url;
# cannot get preview URL of a standalone section with this
#    my $url = $this->getdata("url");
#    if ($url) {
#	# content has a fixed URL
#	return $url;
#    }
    $url = "$config{server}{CGIpath}/$config{prog}{page}";
    if ($config{page}{dynamic_method} eq "path") {
#	$url .= $this->httpdir();
	$url .= $this->path();
    }
    else {
	$url .= "?_id=".$this->id;    #########
    }
    if ($config{page}{dynamic_url_type} eq "full") {
	my $host = $this->my_hostname();
	$url = $host.$url;
    }
    return $url;
}

# dynamic pages publish to redirect docs, so we can use those as
# our canonical URL

sub permalink {
    my $this = shift;
    return $this->get_url_static();
}

# return a URI object representing the dynamic page address

sub get_uri {
    my $this = shift;
    my $url = $this->get_url_dynamic(@_);
    my $uri = new ExSite::URI();
    $uri->setup($url);
    return $uri;
}

=pod

=head1 Publishing

=head2 publish_content()

Write a page and its files out to disk, and mark all of its content as
published.

Publishing is equivalent to "approving for public view", so pages and
content that do not get written to static files can still be
published.

In some cases, dynamic pages and templates can be published to static
files.  The purpose in this case is to precompile the page/template so
that less assembly is required at the actual time of page view.
Dynamic page generation will begin from the precompiled file, rather
than from scratch.  Although the precompiled pages can in principle be
viewed using static URLs, the pages will include unresolved CMS tags,
and ExSite will not create links to those files.

If C<$config{search}{reindex_on_publish}> is TRUE, the search index
for the page may also get rebuilt at this time.

WARNING: you need write access to the page's C<diskpath()> to publish
files there.  The webserver normally does not have this access.
Negotiating this access is normally done by the publish program
(ie. publish.cgi), which has special permissions.  If you do not have
these permissions, then you have to ask publish.cgi to do this task on
your behalf, using C<ExSite::Util::run_publisher()>.

=head2 unpublish()

Removes a page's files from disk.  Also deindexes the page from the
search index, if C<$config{search}{reindex_on_publish}> is TRUE.  Does
not, however, unapprove the page content for public viewing.  See
C<publish()> for other warnings.

=cut

# write the page to a file

sub publish_self {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");

    # set the language
    (tied %msg)->language($this->getdata("language"));
    # rebuild environment as if we were viewing this page
    $this->update_env();

    # publish our own data
    my $name = $this->getdata("name");
    my $type = $this->my_subtype || "page";
    #print $ml->li("Publishing $type " . $ml->em($this->name));
    my $page_prev = $share{Page};
    $share{Page} = $this;
    my $format = $this->revision->view->getdata("format");
    
    if (! $this->is_publishable) {
	# publish a redirect
	my $diskfile = new ExSite::Diskfile( base => $this->basedir,
					     path => $this->subdir,
					     filename => $this->filename,
					     contents => $this->redirect_to_dynamic() );
	$diskfile->publish($opt{force});
    }
    elsif ($format eq "file") {
	# other file type
	$this->revision->view->publish();
	# also publish a redirect to this file
	my $base = $this->basedir;
	my $path = $this->subdir;
	my $filename = $this->filename;
	#my ($base,$path) = $this->diskfile_location();
	my $url = $this->get_url . "/" . $filename; #this->revision->view->filename;
	my $ml2 = new ExSite::ML;
	$ml2->Doctype('<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">');
	$ml2->_a("Downloading ".$this->label."...",{href=>$url});
	$ml2->__body();
	$ml2->Prepend(
	    $ml2->head($ml2->title($this->title)).
	    $ml2->meta(undef,{'http-equiv'=>"Refresh",content=>"0;URL=$url"})
	    );
	$ml2->__html();
	my $diskfile = new ExSite::Diskfile( base => $base,
					     path => $path,
					     filename => "index.html",
					     contents => $ml2->Write );
	$diskfile->publish($opt{force});
    }
#    elsif ($format eq "text") {  ### should do this by default for objs with no revs, only indexes
    else { #if ($format eq "text") {
	# regular web page or other text file
	my $diskfile = new ExSite::Diskfile( base => $this->basedir,
					     path => $this->subdir,
					     filename => $this->filename,
					     contents => $this->show_templated() );
	$diskfile->publish($opt{force});
    }
#    else {
#	print $this->warn("Nothing to publish - not a local page.");
#    }
    $share{Page} = $page_prev;
    if ($share{publish_content} != $this->id) {
	# publishing related files; we're probably done with the object data
	# try to unload to save memory
	$this->unload();
	$share{DB}{diagnostics}{info} = [];
    }
}

# remove the page file(s), search index

sub unpublish {
    my $this = shift;
    $this->SUPER::unpublish();
    if ($config{search}{reindex_on_publish} && $share{Search}) {
	# clear the search index for this page
	print $share{Search}->clear_url($this->get_url());
    }
    return;
}

sub search_index {
    my ($this,$search) = @_;
    my $ml = &get_obj("ML");
    my $br = $ml->br;
    my $url = $this->get_url_canonical();
    my $can_index = $this->can_index();
    if ($can_index == -1) {
	return "$url already indexed - skipping...$br";
    }
    elsif (! $can_index) {
	if (defined $can_index) {
	    return "search_index: $url: permission denied$br";
	}
	return undef;
    }

    my %content = (
	name => $this->name,
	title => $this->title,
	description => $this->description,
	);
    my %weight = (
	name => 2,
	title => 10,
	description => 2,
	body => 1,
	);
    my $access = $this->getdata("access");

    # combine all regular content objects as the "body";
    my $body;
    foreach my $c ($this->get_contents("content")) {
	#my $c = $this->get_content_obj($cdata);
	next if ($c->hide_from("search"));
	next if ($c->subtype ne "content");   # don't index other pages
	my $mime = $c->revision->mime_type();
	if ($mime =~ /text\/(html|plain)/) {
	    $body .= $c->get_html();
	}
	elsif ($mime =~ /image/) {
	    # find some descriptive text
	    $body .= "\n".$c->caption."\n";
	}
	else {
	    # unknown
	    $body .= "\n".$c->title."\n";
	}
    }
    $content{body} = $body;

    $search->index_url(
	content => \%content,
	weight => \%weight,
	language => $this->getdata("langauge"),
	url => $url,
	access => $this->getdata("access"),
	section_id => $this->my_section->id,
	);

    return "indexing $url...$br\n";
}

# copy: when copying pages, also create an empty page body

sub copy {
    my ($this,%newdata) = @_;
    my $new_id = $this->SUPER::copy(%newdata);
    if ($new_id) {
	my $p = new ExSite::Page(id=>$new_id);
	my %body = (
	    type=>"content",
	    name=>"body",
	    title=>"body",
	    label=>"body",
	    content_role=>"editorial",
	    status=>"active",
	    );
	$p->add_child(\%body)
    }
    return $new_id;
}

sub expand {
    my ($this,%option) = @_;

    # regular content expansion
    $this->SUPER::expand(%option);

    # append dispatcher, if necessary
#    if (! $share{js}{dispatch}) {
    if ($share{dispatch}) {
	my @param = ( '_id='.$this->id );
	foreach my $target (keys %{$share{dispatch}}) {
	    push @param, $target . "=" . $share{dispatch}{$target};
	}
	if (scalar @param > 1) { 
	    my $ml = &get_obj("ML");
	    #my $param = join("&amp;",@param);
	    my $param = join("&",@param);
	    my $dispurl = "$config{server}{CGIpath}/$config{prog}{dispatch}?$param";
	    my $js;
	    if (! $share{js}{httprequest}) {
		$js = &insert_js("httprequest");
	    }
	    $js .= $ml->script("
dispatch('$dispurl');
");
	    # add dispatcher JS to foot of page
	    $this->{html} .= $js;
	}
	$share{js}{dispatch} = 1;
    }
    if ($share{page_footer}) {
	$this->{html} .= $share{page_footer};
    }
    return $this->{html};
}

1;
