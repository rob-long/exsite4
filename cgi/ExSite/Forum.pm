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

package ExSite::Forum;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::ML;
use ExSite::Util;
use ExSite::URI;
use ExSite::Content;
use ExSite::Page;
use ExSite::Comment;
use MIME::Base64;

use vars qw(@ISA);
@ISA = qw(ExSite::Page);

sub my_subtype { return "forum"; }

# archived forums no longer accept comments
sub is_active {
    my $this = shift;
    return ($this->wf_status() eq "published");
}

sub embed_comments {
    my $this = shift;
    # forums display thread indexes, not actual threads
    return 0;
}

sub show {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    my $out = $ml->p(scalar $this->navpath,{class=>"navpath"});
    $out .= $ml->h1($this->title);
    # we inherit from Page, but we need lower-level show()
    $out .= ExSite::Content::show($this,%opt);
    return $out;
}

sub show_templated {
    my ($this,%opt) = @_;
    $opt{content}{body} = $this->show(%opt);
    return $this->expand(%opt);
}

# index - display a listing of current comments

sub index {
    my ($this,%opt) = @_;
    my $out;
    my $ml = &get_obj("ML");
    my @thread = $this->fetch_current_threads(%opt);
    my @throw;
    foreach my $c (@thread) {
	push @throw, $ml->tr(
	    $ml->td($ml->a($c->title,{href=>$c->get_url})).
	    $ml->td($c->author).
	    $ml->td($c->posting_date).
	    $ml->td($c->thread_count())
	    );
    }

    #### FIXME: allow for embedded forums as topics

    $out .= $ml->table(
	$ml->caption($msg{Discussions}).
	$ml->thead(
	    $ml->th($msg{Topic}).$ml->th($msg{"Posted by"}).$ml->th($msg{"Started on"}).$ml->th($msg{Responses})
	).
	$ml->tbody(\@throw),
	{class=>"Forum"}
	);
    $out .= $this->tools(%opt);
    return $out;
}

sub preview {
    my $this = shift;
    return $this->show();
}

sub tools {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    my @tool;
    my $diskpath = $this->diskpath();
    my $path = $this->httppath();

    # test for permission to post?
    my $comment = new ExSite::Comment();
    push @tool, $comment->tools(
	prompt=>$msg{"Start a new discussion"},
	parent=>$this
	);

    # Warning - aux. files like archives, rss are published after forum page,
    # so they may not exist yet; we just assume they will exist if the 
    # forum is publishable.

    # archives
    if ($this->is_publishable) {
	push @tool, $ml->a($ml->img(undef,{src=>"$config{server}{HTMLpath}/_ExSite/images/icons/date.png",width=>16,height=>16})."&nbsp;Archive",{href=>"$path/archive.html"});
    }
    else {
	### secure/dynamic archives ??

    }

    # RSS
    if ($this->is_publishable) {
	push @tool, $ml->a($ml->img(undef,{src=>"$config{server}{HTMLpath}/_ExSite/images/icons/rss.png",width=>16,height=>16})."&nbsp;RSS",{href=>"$path/index.rss"});
    }
    else {
	### secure/dynamic RSS ??

    }

    # new post ?

    my $out;
    foreach my $tool (@tool) {
	$out .= $ml->div($tool,{class=>"ForumTool"});
    }
    return $ml->div($out,{class=>"ForumTools"});
}

sub get_archives {
    my ($this,%opt) = @_;
    if (! $this->{archive}) {
	my $ml = &get_obj("ML");
	my @thread = $this->fetch_all_threads();
	my %current = map { $_->id() => $_ } $this->fetch_current_threads();
	my ($datedir,$current_month);
	my $set_to_archived = $opt{set_to_archived} && $this->allow("moderate");
	foreach my $thdata (@thread) {
	    # archives do not include current threads
	    next if ($current{$thdata->{content_id}});

	    my $c = new ExSite::Comment(data=>$thdata);
	    next if (! $c->is_viewable);  # not public
	    if ($set_to_archived) {
		# automatically change status to archived
		$c->archive_thread();
	    }
	    my $t = new ExSite::Time($c->getdata("ctime"),"sql_timestamp");
	    $datedir = $t->write("/%YYYY/%MM");
	    $this->{count}{$datedir}++;
	    $this->{archive}{$datedir} .= $this->show_archive_link($c);
	    my $yeardir = $t->write("/%YYYY");
	    $this->{count}{$yeardir}++;
	    if ($current_month ne $datedir) {
		$this->{archive}{$yeardir} .= $ml->h3($t->write("%MMMM %YYYY"));
		$current_month = $datedir;
	    }
	    $this->{archive}{$yeardir} .= $this->show_archive_link($c);
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

sub show_archive_link {
    my ($this,$c) = @_;
    my $ml = &get_obj("ML");
    my $format = $ml->a("[[title]]",{href=>"[[url]]"})." ".
	$ml->span($msg{"[[?date]]Posted on [[date]][[/?date]][[?author]], by [[author]][[/?author]]"},{class=>"commentAbout"});
    my $threadinfo = $c->show_formatted($format);
    my $count = $c->thread_count();
    if ($count) {
	$threadinfo .= "; ".$ml->span(&substitute($msg{"[[count]] response(s)"},{count=>$count}),{class=>"commentReplyCount"});
    }
    return $ml->div($threadinfo,{class=>"commentLink"});
}

sub fetch_current_threads {
    my ($this,%opt) = @_;
    my $max_index = $opt{index_max} || $this->setting("index_max") || 10;
    my $min_index = $opt{index_min} || $this->setting("index_min") || 3;
    my $index_age = $opt{index_age} || $this->setting("index_age") || 90;
    $this->{archived_threads} = 0;
    $this->{active_threads} = 0;
    #my $tree = $this->get_content_tree();
    #my @all_thread = $tree->get_child_data($this->id);
    my @all_thread = $this->fetch_all_threads();
    my @thread;
    foreach my $th (reverse @all_thread) {
	my $c = $this->get_content_obj($th);
	next if ($c->subtype ne "comment");
	next if ($c->wf_status ne "published");
	push @thread, $c;
	if ((scalar @thread > $max_index) ||
	    (scalar @thread > $min_index && $c->age > $index_age)) {
	    last;
	}
    }
    return wantarray ? @thread : \@thread;
}

sub fetch_all_threads {
    my $this = shift;
    if (! $this->{threads}) {
	my $tree = $this->get_content_tree();
	$this->{threads} = $tree->get_child_data($this->id);
    }
    return @{$this->{threads}};
}

sub fetch_comments {
    my $this = shift;
    if (! $this->{comments}) {
	my @comments;
	my @all_comments = $this->fetch_all_comments();
	foreach my $c (@all_comments) {
	    my $comment = new ExSite::Comment(data=>$c);
	    if ($comment->is_viewable) {  # active(published) or archived
		push @comments, $c;
	    }
	}
	$this->{comments} = \@comments;
    }
    return @{$this->{comments}};
}

sub fetch_all_comments {
    my $this = shift;
    if (! $this->{all_comments}) {
	my $tree = $this->get_content_tree();
	$this->{all_comments} = $tree->find({type=>$this->isubtype("comment")},$this->id);
    }
    return @{$this->{all_comments}};
}

sub recent_comments {
    my ($this,$n) = @_;
    $n or $n = 10;
    my @c = $this->fetch_comments();
    my @recent;
    foreach (1..$n) {
	if (scalar @c) {
	    push @recent, pop @c;
	}
    }
    return @recent;
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

# publish - also publish articles, archive folders, and feed

sub publish_self {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    #print $ml->li("Publishing forum " . $ml->em($this->name));

    if (! $this->is_publishable) {
	# publish a redirect
	my $diskfile = new ExSite::Diskfile( base => $this->basedir,
					     path => $this->subdir,
					     filename => $this->filename,
					     contents => $this->redirect_to_dynamic() );
	$diskfile->publish();
    }
    else {
	# publish forum as regular web page
	$this->publish_formatted();
    }

    # republish the archives

### FIXME: do not republish archives if just making a new thread

#    if ($share{publish_content} == $this->id) {
	$this->publish_archives(%opt);
#    }
}

sub publish_archives {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    my $allout;
    my $basedir = $this->basedir;
    my $archive = $this->get_archives(set_to_archived=>1);
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
					     contents => $ml->div($arch_out,{class=>"ForumArchive"}) );
	print $ml->li("Publishing $date archives");
	$diskfile->publish();
    }

    # master archive index

    $this->unexpand();
    my $arch_out = $this->expand(content=>{body=>$title.$allout});
    my $diskfile = new ExSite::Diskfile( base => $basedir,
					 path => $this->subdir,
					 filename => "archive.html",
					 contents => $ml->div($arch_out,{class=>"ForumArchive"}) );
    print $ml->li("Publishing master archive index");
    $diskfile->publish();
}

sub unpublish_content {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");

    # authorize/authenticate ??

    print $ml->li("Removing forum " . $ml->em($this->name));

    # remove comment threads
    print "<ul>\n";
    foreach my $node ($this->get_contents()) {
	$node->unpublish();
    }
    print "</ul>\n";

    # remove file
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

sub rss {
    my ($this,%opt) = @_;
    my @thread = $this->fetch_current_threads();
    if (@thread > 0) {
	my $nitem;
	my $rss = new ExSite::RSS(xml=>1);
	$rss->title($this->title);
	$rss->description($this->description);
	$rss->link($this->get_url);
	while (my $c = shift @thread) {
	    $nitem++;
	    my $description = $c->description;
	    my $count = $c->thread_count();
	    if ($count) {
		$description .= " ($count replies)";
	    }
	    $rss->item($c->title,$description,$c->get_url,$c->posting_date);
	}
	return $rss->write() if $nitem;
    }
    return undef;
}

# post:
# expected fields: from, subject, comment

sub post {
    my ($this) = @_;
    my $out;
    my $ml = &get_obj("ML");
    my $in = new ExSite::Input;
    my $post = $in->post();
    if ($post->{comment}) {
	# we have an attempted post
	if ($this->is_active) {
	    # forum is open for comments
	    if ($share{DB}->level >= $this->access) {  ### access to this area?
		# we have sufficient permission
		my $c = new ExSite::Comment();
		$post->{parent} = $this->id;
		my $reply = $c->make_comment(%$post);
		if ($reply && $reply->ok) {
		    if ($reply->is_viewable) {
			$out .= $ml->p($msg{"Thank you for your post!"},{class=>"commentPostWarning"});
		    }
		    else {
			$out .= $ml->p($msg{"Thank you for your post. It will be reviewed by a moderator before being posted publicly."},{class=>"commentPostWarning"});
		    }
		    $out .= $ml->div($reply->show_comment(tools=>0),{class=>"commentReply"});
		}
		else {
		    $reply->error("Post failed");
		    $out .= $reply->show_diagnostics("error","html");
		    $reply->delete();
		}
	    }
	    else {
		$out .= $this->error($msg{"Sorry, you do not have sufficient permission to post here."});
	    }
	}
	else {
	    my $message = $msg{"Sorry, this forum is closed and is no longer accepting comments."};
	    $this->error($message);
	    $out .= $ml->p($message,{class=>"commentPostWarning"});
	}
    }
    else {
	$out .= $this->warn("Post: nothing posted.");
    }
    return $out;
}

1;
