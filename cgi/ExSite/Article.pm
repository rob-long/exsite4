#!/usr/bin/perl
#-----------------------------------------------------------------------
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

### TODO: 
### Articles should have two standard views:
### normal - the full article, with full-sized photos
### small - a teaser, with thumbnails

package ExSite::Article;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Comment;

use vars qw(@ISA);
@ISA = qw(ExSite::Content);

# my_subtype - the subtype of this object/class

sub my_subtype { return "article"; }

sub embed_comments {
    my $this = shift;
    # articles display their own comments
    return 1;
}

sub is_active {
    my $this = shift;
    # only published articles accept comments
    return (! $this->getdata("status"));
}

sub filename {
    my $this = shift;
    my $rev = $this->revision;
    #return undef if (! $rev->defined);
    my $mime = $rev->defined ? $rev->view->mime_type() : "text/html";
    if ($rev->defined && $rev->is_file) {
	# uploaded file
	return $this->revision->view->filename;
    }
    elsif ($mime !~ /^text\/html$/) {
	# some other (probably text) file type
	my $name = $this->name();
	my $filename = ($name =~ /^\.html$/) ?
	    $name :
	    "$name.html";
	return $filename;
    }
    else {
	# some other (probably text) file type
	return $this->name(). "." .&MimeToFile($mime);
    }
    return undef;
}

sub content_info {
    my $this = shift;
    my $author = $this->author();
    return $author ?
	$this->show_formatted($msg{"by [[author]], posted on [[date]]"}) :
	$this->show_formatted($msg{"posted on [[date]]"});
}

sub show {
    my ($this,%opt) = @_;
#    return undef if (! $this->allow_view);
    return $msg{"Permission denied"} if (! $this->allow_view);

    # show just this article
    my $out;
    my $ml = &get_obj("ML");
    my %data;
    my $viewtype = $opt{view} || "normal";
    if ($viewtype eq "all") { $viewtype = "normal"; }
    $this->{mode} = $opt{mode};  # index or article view
    my $rev = $this->revision();
    if (! $rev->has_view($viewtype)) {
	if ($viewtype eq "small") {
	    if ($rev->mime_type =~ /text/) {
		# small view was requested, but we don't have one on file
		# ... summarize contents instead
		$data{html} = $this->summarize();
	    }
	    $this->warn("No $viewtype view of this revision, using best substitute.");
	}
    }
    if (defined $opt{tools} && ! $opt{tools}) {
	# no tools
	$data{tools} = " ";
    }
    my $format = $opt{format} ? $opt{format} : "article";
    $out .= $this->show_formatted($format,%data);

    # show sub-index if we are showing only this article
    # show full index, if we are showing only this article
    if ($this->{mode} ne "index") {
#    if ($share{Content} && $share{Content}->id == $this->id) {
#    if (! $this->is_publishing) {
	my $input = new ExSite::Input;
	my ($aout,$cout);
	my $tree = $this->get_content_tree();
	my @child = $this->sort("content_id",$tree->get_child($this->id)); # by ID
	foreach my $ch (@child) {
	    my $c = $this->get_content_obj($ch);
	    if ($c->my_subtype eq "article") {
		$input->path("content",$c->path); # necessary?
		$aout .= $ml->div($ml->a($c->title,{href=>$c->get_url_canonical()}),
				  {class=>"ArticleLink"});
	    }
	}
	if ($aout) {
	    $out .= $ml->div($ml->h2("More Reading").$aout,
			     {class=>"Articles"});
	}
	$out .= $this->show_comments(%opt);
    }
    return $out;
}

sub summarize {
    my $this = shift;
    my $ml = &get_obj("ML");
    return $ml->div(
	$ml->div($this->description,{class=>"articleDescription"}),
	{class=>"articleSummary"}
	);
}

sub tools {
    my ($this,%opt) = @_;
    my $out;
    my $ml = &get_obj("ML");
    my @tool;

    my %icon;
    # permalink, tags, comments
    if ($config{content}{tool_icons} eq "fa") {
	my $ui = &get_obj("UI");
	$icon{more} = $ui->faicon("right");
	$icon{permalink} = $ui->faicon("link");
	$icon{tags} = $ui->faicon("tag");
	$icon{comment} = $ui->faicon("comment");
    }
    elsif ($config{content}{tool_icons} eq "png") {
	# PNG img icons
	$icon{more} = $ml->img(undef,{src=>"$config{server}{HTMLpath}/_ExSite/images/icons/right.png",width=>16,height=>16,class=>"toolIcon"})."&nbsp;";
	$icon{permalink} = $ml->img(undef,{src=>"$config{server}{HTMLpath}/_ExSite/images/icons/link.png",width=>16,height=>16,class=>"toolIcon"})."&nbsp;";
	$icon{tags} = $ml->img(undef,{src=>"$config{server}{HTMLpath}/_ExSite/images/icons/tag.png",width=>16,height=>16,class=>"toolIcon"})."&nbsp;";
	$icon{comment} = $ml->img(undef,{src=>"$config{server}{HTMLpath}/_ExSite/images/icons/comment.png",width=>16,height=>16,class=>"toolIcon"})."&nbsp;";
    }
    # else - no icons

    # read more/permalink
    my $viewtype = $opt{view} || "normal";
    if ($viewtype eq "all") { $viewtype = "normal"; }
    my $permalink = $this->permalink();
    if (! $this->revision()->has_view($viewtype) && $viewtype eq "small") {
	# using summary view
	push @tool, $ml->a($msg{"Read more"}.$icon{more},{href=>$this->get_url(),class=>"ArticleReadMore"});
    }
    elsif ($this->{mode} eq "index" && $config{content}{article}{permalink}) {
	push @tool, $ml->a($icon{permalink}.$msg{$config{content}{article}{permalink}},{href=>$permalink,class=>"ArticlePermalink"});
    }

    # tags
#    my $taginfo = $this->show_tags();
#    if ($taginfo) {
#	push @tool, $icon{tags}.$taginfo;
#    }

    # comments
    if ($this->{mode} eq "index") {
	my $label = "Comments";
	my $n_comment = $this->count_contents("comment",{status=>0}); ### FIXME: skips archived comments
	if ($n_comment) {
	    $label .= " ([[n]])";
	}
	push @tool, $ml->a($icon{comment}.&substitute($msg{$label},{n=>$n_comment}),{href=>$permalink."#comments"});
    }
    else {
	# no icon in this case
	$out .= $ml->a(undef,{name=>"comments"});
	my $comment = new ExSite::Comment();
	push @tool, $comment->tools(
#	    mode=>$this->{mode},
	    parent=>$this,
#	    comment_type=>"reply",
#	    prompt=>$msg{"Leave a comment"},
	    );
    }

    $out .= $ml->div(
	join("",map { $ml->div($_,{class=>"articleTool"}) } @tool),
	{ class=>"articleTools" }
	);
    return $out;
}

sub show_comments {
    my ($this,%opt) = @_;
    my $out;
    my $ml = &get_obj("ML");
    my $tree = $this->get_content_tree();
    my @child = $tree->get_child($this->id);
    foreach my $ch (@child) {
	my $c = $this->get_content_obj($ch);
	if ($c->my_subtype eq "comment") {
	    my $cout;
	    if ($this->{preview}) {
		$cout = $c->preview(%opt);
	    }
	    elsif ($c->is_viewable && $c->allow_view()) {
		$opt{format} or $opt{format} = "article_comment";
		$cout = $c->show(%opt);
	    }
	    $out .= $cout if $cout;
	}
    }
    if ($out) {
	my $hdg = $opt{heading} || "Comments";
	return $ml->div(
	    $ml->a(undef,{name=>"comments"}).
	    $ml->h2($msg{$hdg}).
	    $out,
	    {class=>"Comments"}
	    );
    }
    elsif ($opt{no_comments}) {
	# optional no comments message
	return $ml->div($ml->a(undef,{name=>"comments"}).
			$msg{$opt{no_comments}},
			{class=>"noComments"});
    }
    return undef;
}

sub get_comments {
    my $this = shift;
    my $id = $this->id;
    if ($id) {
	my $c = new ExSite::Comment;
	return $c->get_comments($id);
    }
    return undef;
}

sub post {
    my ($this) = @_;
    my $out;
    my $ml = &get_obj("ML");
    my $in = new ExSite::Input;
    my $post = $in->post();
    if ($post->{comment}) {
	# we have an attempted post
	if ($this->is_active()) {
	    # comments allowed
	    if ($share{DB}->level >= $this->access) {
		# we have sufficient permission
		my $c = new ExSite::Comment();
		my $reply = $c->make_comment(subject=>"Re: ".$this->title,parent=>$this->id,%$post);
		if ($reply && $reply->ok) {
		    if (! $reply->is_active) {
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
	    my $message = $msg{"Sorry, this discussion is closed and is no longer accepting comments."};
	    $this->error($message);
	    $out .= $ml->p($message,{class=>"commentPostWarning"});
	}
    }
    else {
	$out .= $this->warn("Post: nothing posted.");
    }
    return $out;
}

# preview - show inactive items, too

sub preview {
    my ($this,%opt) = @_;
    $this->{preview} = 1;
    $opt{link_tool} = 0; # disable individual comment links
    return $this->show(%opt);
}

# publish_self - may need to publish non-HTML contents separately

sub publish_self {
    my ($this,%opt) = @_;
    my $rev = $this->load_revision("newest");
    if ($rev->mime_type !~ /text/) {
	# our "body" appears to be some non-text type (perhaps an image?)
	$rev->publish(%opt);
    }
    # this publishes the article as an HTML file
    $this->SUPER::publish_self(%opt);
}

# publish_content: publish article and all containers up to the section
# Publishing an article affects the blog index, and there may be previews
# right up to the home page.

sub publish_content_old {
    my ($this,%opt) = @_;
    # do not publish if we came from an alias
    return undef if ($this->alias);
    $this->{publish} = 1;
    my $ml = &get_obj("ML");
    print $ml->li("Publishing Article " . $ml->em($this->name));
    print "<ul>\n";
    # publish our contents
    if (! exists $opt{child} || $opt{child}) {
	$this->subpublish(%opt);
    }
    # publish our self
    if (! exists $opt{self} || $opt{self}) {
	$this->publish_self(%opt);
    }
    # publish our container
    if (! exists $opt{parent} || $opt{parent}) {
	$this->superpublish(%opt);
    }
#    $this->subpublish(%opt);  # descendants
#    $this->publish_up(%opt);  # ancestors
    print "</ul>\n";
}

# publish_formatted - publish to an HTML file, regardless of our filename

sub publish_formatted {
    my ($this,%opt) = @_;
    #my $ml = &get_obj("ML");

    # set the version/language
    (tied %msg)->language($this->getdata("language"));
    # rebuild environment as if we were viewing this page
    $this->update_env();  # resets share, among other things

    #print "<ul>\n";
    # we are not a page, but we need a page context to get certain features
    # (such as menus).
    my $orig_page = $share{Page};
    $share{Page} = $this->my_page();
    my $filename = $this->name . ".html";
    my $diskfile = new ExSite::Diskfile( base => $this->basedir,
					 path => $this->subdir,
					 filename => $filename,
					 contents => $this->show_templated() );
    $diskfile->last_modified($this->last_modified());
    $diskfile->publish();
    #print "</ul>\n";
    $share{Page} = $orig_page if $orig_page;
}

# use date directories for articles

sub my_subdir {
    my $this = shift;
    ### FIXME: should we use ptime here instead ??
    my $t = new ExSite::Time($this->getdata("ctime"),"sql_timestamp");
    my $datedir = $t->write("%YYYY/%MM");
    return $datedir;
}

# get_url_dynamic : articles are shown page style by default

sub get_url_dynamic {
    my $this = shift;
    return $this->get_page_url_dynamic();
}

# workflow options
# exclude expire as a workflow option on articles

sub allowed_tasks {
    my $this = shift;
    my @tasks = qw(publish archive);
    return wantarray ? @tasks : \@tasks;
}

sub wf_allow {
    my ($this,$to) = @_;
    my $from = $this->wf_istatus();
    my $allow = $ExSite::Workflow::wf_matrix[$from];
    $allow->[$ExSite::Workflow::status{expired}] = undef; 
    if (defined $to) {
	return $allow->[$to];
    }
    elsif (ref $allow eq "ARRAY") {
	return wantarray ? @$allow : $allow;
    }
    else {
	return undef;
    }
}

1;
