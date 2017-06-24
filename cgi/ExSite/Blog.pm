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

package ExSite::Blog;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::ML;
use ExSite::Util;
use ExSite::URI;
use ExSite::Content;
use ExSite::Article;
use MIME::Base64;

use vars qw(@ISA);
@ISA = qw(ExSite::Page);

sub my_subtype { return "blog"; }

sub filename {
    return "index.html";
}

# index - display a listing of current articles in the blog

sub index {
    my ($this,%opt) = @_;
    my @article = $this->fetch_articles();
    my $max_index = $opt{index_max} || $this->setting("index_max") || 10;
    my $min_index = $opt{index_min} || $this->setting("index_min") || 3;
    my $index_age = $opt{index_age} || $this->setting("index_age") || 90;
    my $stickiness = $this->setting("stickiness");
    my $n_index;
    my %role = $this->roles();
    my $owns = $role{owner} || $role{editor} || $role{moderator};
    my $ml = &get_obj("ML");
    my ($out,$sticky);
    my $input = new ExSite::Input;
    $opt{mode} = "index";
    foreach my $a (reverse @article) {
	my $article = new ExSite::Article(data=>$a);
	if ($article->is_indexable || # regular index
	    ($article->is_viewable && $opt{archive}) ||  # archive
	    $owns) { # this user is allowed to see this article
	    if ($article->flag("sticky")) {
		$input->path("content",$article->path());
		$article->set("mode","index");
		$sticky .= $article->summary(%opt);
		$n_index++;
	    }
	    else {
#		next if ($article->age() > $index_age && $n_index >= $min_index);
		# with this setting, sticky articles will always remain on top,
		# no matter how old they get
		if (($article->age() > $index_age && $n_index >= $min_index) ||
		    ($n_index >= $max_index)) {
		    if ($stickiness eq "permanent") {
			# permanent stickiness means the article remains at
			# the top of the index always
			next;
		    }
		    else {
			# temporary stickiness means the article remains at
			# the top of the index, while it is on the current index
			last;
		    }
		}
		$input->path("content",$article->path());
		$article->set("mode","index");
		$out .= $article->summary(%opt);
		$n_index++;
	    }
	}
    }
    return $ml->div($sticky.$out,{class=>"Blog"});
}

sub tools {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    my @tool;
    my $diskpath = $this->diskpath();
    my $path = $this->httppath();

    # archives
    if (-e "$diskpath/archive.html") {
	push @tool, $ml->a($ml->img(undef,{src=>"$config{server}{HTMLpath}/_ExSite/images/icons/date.png",width=>16,height=>16})."&nbsp;Archive",{href=>"$path/archive.html"});
    }
    else {
	### secure/dynamic archives ??

    }

    # RSS
    if (-e "$diskpath/index.rss") {
	push @tool, $ml->a($ml->img(undef,{src=>"$config{server}{HTMLpath}/_ExSite/images/icons/rss.png",width=>16,height=>16})."&nbsp;RSS",{href=>"$path/index.rss"});
    }
    else {
	### secure/dynamic RSS ??

    }

    # new post ?

    my $out;
    foreach my $tool (@tool) {
	$out .= $ml->div($tool,{class=>"BlogTool"});
    }
    return $ml->div($out,{class=>"BlogTools"});
}

sub fetch_articles {
    my $this = shift;
    if (! $this->{articles}) {
	$this->{articles} = $share{DB}->fetch_match("content",
						    {parent=>$this->id,type=>$this->isubtype("article")},
						    "ctime");
    }
    return @{$this->{articles}};
}

sub get_archives {
    my ($this,%opt) = @_;
    if (! $this->{archive}) {
	my $ml = &get_obj("ML");
	my @article = $this->fetch_articles();
	my ($datedir,$current_month);
	foreach my $art (@article) {
	    my $a = new ExSite::Article(data=>$art);
	    next if (! $a->is_active);  # not public
	    my $t = new ExSite::Time($a->getdata("ctime"),"sql_timestamp");
	    $datedir = $t->write("/%YYYY/%MM");
	    $this->{count}{$datedir}++;
	    $this->{archive}{$datedir} .= $a->show_formatted("article_archive_link"); #$a->show_index_link(); #$a->show(view=>"small",mode=>"index");
	    my $yeardir = $t->write("/%YYYY");
	    $this->{count}{$yeardir}++;
	    if ($current_month ne $datedir) {
		$this->{archive}{$yeardir} .= $ml->h3($t->write("%MMMM %YYYY"));
		$current_month = $datedir;
	    }
	    $this->{archive}{$yeardir} .= $a->show_formatted("article_archive_link"); #show_index_link();
	}
    }
    return $opt{count} ? $this->{count} : $this->{archive};
}

sub show_archives {
    my $this = shift;
    return if (! $this->owns);
    my $ml = &get_obj("ML");

    my $archive = $this->get_archives();

    my $allout = $ml->h1($this->title);
    foreach my $date (sort keys %$archive) {
	my $t = new ExSite::Time();
	my $datehdr;
	if ($date =~ /^\/\d+\/\d+$/) {
	    $t->set($date,"/%YYYY/%MM");
	    $datehdr = $t->write("%MMMM %YYYY")
	}
	else {
	    $t->set($date,"/%YYYY");
	    $datehdr = $t->write("raw_year");
	}
	my $out .= $ml->h2(&substitute($msg{"[[date]] Archives"},{date=>$datehdr}));
	$out .= $archive->{$date};
	if ($date =~ /\/\d\d\d\d$/) {
	    $allout = $out . $allout; # reverse the year order
	}
    }

    # master archive index
    return $allout;
}

# find - use the blog itself as the page body

sub find {
    my ($this,$name) = @_;
    my $content = $this->SUPER::find($name);
    if ($name eq "body" && 
	(! $content ||                                 # error
	 ! $content->defined ||                        # nothing found
	 $content->getdata("parent") != $this->id)) {  # templated body
	# if we don't have an explicitly defined body, show the blog
	$content = $this;
    }
    return $content;
}

# publish_self - also publish articles, archive folders, and feed

sub publish_self {
    my ($this,%opt) = @_;
    return undef if ($this->alias);
    my $ml = &get_obj("ML");
    $this->{publish} = 1;

    # publish main blog index

    my $page_prev = $share{Page};
    $share{Page} = $this;
    
    if (! $this->is_publishable) {
	# publish a redirect
	my $diskfile = new ExSite::Diskfile( base => $this->basedir,
					     path => $this->subdir,
					     filename => $this->filename,
					     contents => $this->redirect_to_dynamic() );
	$diskfile->publish();
    }
    else {
	# publish blog as regular web page
	my $diskfile = new ExSite::Diskfile( base => $this->basedir,
					     path => $this->subdir,
					     filename => $this->filename,
					     contents => $this->show_templated() );
	$diskfile->publish();
    }
    $share{Page} = $page_prev;

    # publish the archives

    my $allout;
    my $basedir = $this->basedir;
    my $archive = $this->get_archives();
    my $title = $ml->h1($this->title);
    foreach my $date (sort keys %$archive) {
	my $t = new ExSite::Time();
	my $datehdr;
	if ($date =~ /^\/\d+\/\d+$/) {
	    $t->set($date,"/%YYYY/%MM");
	    $datehdr = $t->write("%MMMM %YYYY")
	}
	else {
	    $t->set($date,"/%YYYY");
	    $datehdr = $t->write("raw_year");
	}
	my $out .= $ml->h2(&substitute($msg{"[[date]] Archives"},{date=>$datehdr}));
	$out .= $archive->{$date};
	if ($date =~ /\/\d\d\d\d$/) {
	    $allout = $ml->div($out,{class=>"archiveYear"}) . 
		$allout; # reverse the year order
	}

	$this->unexpand();
	my $arch_out = $this->expand(content=>{body=>$title.$out});

	my $subdir = $this->subdir . $date;
	my $diskfile = new ExSite::Diskfile( base => $basedir,
					     path => $subdir,
					     filename => "index.html",
					     contents => $ml->div($arch_out,{class=>"BlogArchive"}) );
	print $ml->li("Publishing $date archives");
	$diskfile->publish();
    }

    # master archive index

    $this->unexpand();
    my $arch_out = $this->expand(content=>{body=>$title.$allout});
    my $diskfile = new ExSite::Diskfile( base => $basedir,
					 path => $this->subdir,
					 filename => "archive.html",
					 contents => $ml->div($arch_out,{class=>"BlogArchive"}) );
    print $ml->li("Publishing master archive index");
    $diskfile->publish();
    #print "</ul>\n";

    if ($share{publish_content} != $this->id) {
	# publishing related files; we're probably done with the object data
	# try to unload to save memory
	$this->unload();
	$share{DB}{diagnostics}{info} = [];
    }
}

sub unpublish_content {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");

    print $ml->li("Removing blog " . $ml->em($this->name));

    # remove articles
    print "<ul>\n";
    foreach my $art ($this->get_contents()) {
	$art->unpublish_content();
    }
    print "</ul>\n";

    # remove main index file
    my $diskfile = new ExSite::Diskfile( base => $this->basedir,
					 path => $this->subdir,
					 filename => $this->filename );
    $diskfile->unpublish();

    # remove RSS feed
    $diskfile->setup(filename=>"index.rss");
    $diskfile->unpublish();

    # remove archive index
    print $ml->li("Removing archives");
    $diskfile->setup(filename=>"archive.html");
    $diskfile->unpublish();
    # remove archives
    my $archive = $this->get_archives();
    $diskfile->setup(filename=>"index.html");
    # remove months
    foreach my $date (sort keys %$archive) {
	if ($date =~ /^\/\d\d\d\d\/\d/) {
	    my $subdir = $this->subdir . $date;
	    $diskfile->setup(path=>$subdir);
	    $diskfile->unpublish();
	    my $out = $diskfile->rmdir();
	    print ((defined $out) ? $out : $diskfile->show_diagnostics("error","html"));
	}
    }
    # remove years
    foreach my $date (sort keys %$archive) {
	if ($date =~ /^\/\d\d\d\d$/) {
	    my $subdir = $this->subdir . $date;
	    $diskfile->setup(path=>$subdir);
	    $diskfile->unpublish();
	    my $out = $diskfile->rmdir();
	    print ((defined $out) ? $out : $diskfile->show_diagnostics("error","html"));
	}
    }
    # remove directory
    $diskfile->setup(path => $this->subdir);
    my $out = $diskfile->rmdir();
    print ((defined $out) ? $out : $diskfile->show_diagnostics("error","html"));
}

sub search_index {
    my ($this,$search) = @_;
    my $ml = &get_obj("ML");
    my $br = $ml->br;
    my $name = $this->subtype." ".$ml->em($this->name);
    my $stat = $this->can_index();
    return "$name already indexed - skipping...$br" if ($stat < 0);
    return "$name - permission denied$br" if (! $stat);

    # index the category title only
    $search->index_url(
	content => { title => $this->title },
	weight => { title => 10 },
	language => $this->getdata("langauge"),
	url => $this->get_url_canonical,
	access => $this->getdata("access"),
	section_id => $this->my_section->id,
	);
    return "indexed $name...$br\n";
}

sub preview {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    my $r = new ExSite::ReportBuilder(title=>$this->title,dynamic=>1);
    $r->headers("Article","Posted","Published","Status");
    my @article = $this->fetch_articles();
    my ($datedir,$current_month);
    foreach my $art (reverse @article) {
	my $a = new ExSite::Article(data=>$art);
	$r->push(
	    $ml->a($a->title,{href=>$this->link(id=>$a->id)}),
	    $a->showdata("ctime"),
	    $a->getdata("ptime") =~ /^0/ ? "N" : "Y",
	    $a->showdata("status")
	    );
    }
    return $r->make();
}

1;
