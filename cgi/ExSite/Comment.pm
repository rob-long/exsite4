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
#
# Things you needs to know about comments:
# - comments are grouped into threads under the top-level post
# - comments are published to static files - one file per thread
# - publishing a non-top-level comment actually publishes the whole thread
# - publishing a thread also publishes the object that contains the thread
#
# TODO:
# - subject lines
# - 
#----------------------------------------------------------------------------

package ExSite::Comment;

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Util;
use ExSite::Diskfile;
use ExSite::Time;
use ExSite::Article;
use ExSite::Module qw(&get_module);

use vars qw(@ISA);
@ISA = qw(ExSite::Article);

# my_subtype - the subtype of this object/class

sub my_subtype { return "comment"; }

sub is_top_of_thread {
    my $this = shift;
    return ($this->parent->subtype ne "comment");
}

sub my_thread {  # returns top-level comment
    my $this = shift;
    my $top = $this->parent;
    return $this if ($top->subtype ne "comment");
    my $last;
    while ($top->subtype eq "comment") {
	$last = $top;
	$top = $top->parent;
    }
    return $last;
}

sub thread_parent {  # returns container object that holds this comment thread
    my $this = shift;
    my $top = $this->parent;
    return $top if ($top->subtype ne "comment");
    while ($top->subtype eq "comment") {
	$top = $top->parent;
    }
    return $top;
}

# embedded: return true if comments are embedded in a higher-level container object
# (for example, comments on an article); false if comments are displayed as 
# independent content objects (for example, comments in a forum).
# Note that comments are presumed to be embedded unless the container object
# declares otherwise.

sub embedded {
    my $this = shift;
    my $parent = $this->thread_parent();
    return $parent->can("embed_comments") ?
	$parent->embed_comments() : 1;
}

sub is_open { # is this discussion accepting new comments?
    my $this = shift;
    my $obj = $this;
    while ($obj->wf_status eq "published") {
	$obj = $obj->parent();
	if ($obj->isubtype != $this->isubtype) {
	    # this is the thread parent, stop here
	    return $obj->wf_status eq "published";
	}
    }
    # one of our ancestors is inactive; this disables comments below it
    return 0;
}

sub allow_view {
    my ($this) = @_;
    # admin preview override
    return 1 if ($this->{preview} && $this->allow("edit"));
    return $this->SUPER::allow_view();
}

# organize threads by date

sub my_subdir {
    my $this = shift;
    if ($this->is_top_of_thread) {
	my $t = new ExSite::Time($this->getdata("ctime"),"sql_timestamp");
	my $datedir = $t->write("%YYYY/%MM");
	return $datedir;
    }
    return undef;
}

sub preview {
    my ($this,%opt) = @_;
    $this->{preview} = 1;   # preview mode enables extra tools
    return $this->show_thread(%opt);
}

sub show {
    my ($this,%opt) = @_;

    my $input = new ExSite::Input;
    my $ml = &get_obj("ML");

    # display the main comment
    return undef if (! $this->allow_view);

    my $out;
    if (($share{Content} && $this->id == $share{Content}->id &&
	$this->is_top_of_thread) || $this->is_publishing) {
	# include navpath at top of thread-only views
	$out = $this->show_thread_with_navbar(%opt);
    }
    else {
	$out = $this->show_thread(%opt);
    }
    return $out ? $ml->div($out,{class=>"commentList"}) : $out;
}

sub show_thread {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    return undef if (! $this->allow_view);
    my $out = $this->show_comment(%opt);

    # display remainder of thread
    my $cout;
    my $tree = $this->get_content_tree();
    my @child = $this->sort("content_id",$tree->get_child($this->id)); # by ID
    foreach my $ch (@child) {
	my $c = $this->get_content_obj($ch);
	next if ((ref $c) !~ /Comment$/);
	$c->set("preview",$this->{preview});
	next if (! $c->allow_view());
	$cout .= $ml->div($c->show_thread(%opt),
			  {class=>"commentReply"});
    }
    $out .= $ml->div($cout,{class=>"commentList"}) if $cout;

    return $out;
}

# include some navigation context at top of thread...

sub show_thread_with_navbar {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    my $out .= $ml->p(scalar $this->navpath(),{class=>"navPath"});
    $out .= $this->show_thread();
    return $out;
}

sub show_comment {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    my %data;
    if (defined $opt{tools} && ! $opt{tools}) {
	# no tools
	$data{tools} = " ";
    }
    my $format = $opt{format} || $share{comment_format};
    if (! $format) {
	$format = $ml->div(
	    $ml->h3($ml->a(undef,{name=>"Comment[[id]]"})."[[title]]",{class=>"commentSubject",id=>"Comment[[id]]"}).
	    $ml->div($msg{"Posted on [[date]][[?author]], by [[author]][[/?author]]"},{class=>"commentAbout"}).
	    $ml->div("[[html]]",{class=>"commentBody"}).
	    "[[attachments]]".
	    "[[tools]]",
	    {class=>"commentWrapper"});
	$share{comment_format} = $format; # so we don't have to rebuild the format for every comment in a long thread
    }
    $data{html} = $this->body();
    return $this->show_formatted($format,%data);
}

sub show_index_link {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    my $format = $ml->a("[[title]]",{href=>"[[url]]"})." ".
	$ml->span("[[?date]]Posted on [[date]][[/?date]][[?author]], by [[author]][[/?author]]",{class=>"CommentAbout"});
    return $ml->p($this->show_formatted($format),
		  {class=>"CommentLink"});
}

sub summary {
    my $this = shift;
    my $ml = &get_obj("ML");
    return $ml->div(
	$ml->div($this->description,{class=>"articleDescription"}),
	{class=>"articleSummary"}
	);
}

sub description {
    my $this = shift;
    return &make_teaser_text($this->body());
}

sub body {
    my $this = shift;
    my $view = $this->revision()->view();
    my $plaintext = ($view->mime_type() eq "text/plain");
    my $mime = $view->mime_type();
    my $ml = &get_obj("ML");
    my $body = $plaintext ?  $view->get_raw() : $view->get_html();

    # kill/neuter any hidden CMS tags
    $body =~ s/<!--/<!--&\#00/g;
    $body =~ s/\{\{(?![^<>]*>)/\{&\#00;\{/g;
    $body =~ s/\}\}(?![^<>]*>)/\}&\#00;\}/g;
    $body =~ s/\[\[(?![^<>]*>)/\[&\#00;\[/g;
    $body =~ s/\]\](?![^<>]*>)/\]&\#00;\]/g;

    my $br = $ml->br();
    if ($plaintext) {
	# escape all HTML
	$body = $share{DB}->clean_text($body,0);
	$body = $this->highlight_quote($body);
	# convert NL to <br> to preserve formatting
	$body =~ s/(?<!>)\n/$br\n/g;
	$body = $ml->p($body);
    }
    else {
	# allow light markup; ensure HTML has good structure
	$body = $this->highlight_quote($body);
	$body = &safehtml($share{DB}->clean_text($body,1));
	# convert NL to <br> in quotes to preserve formatting
	#$body =~ s/\n(>|&gt;)/$br\n$1/g;
    }

    # try to impose some style rules on the quoted sections, in case
    # the designer wants to highlight them

    my @text = split /\n/,$body;
    $body = undef;
    my $quote = 0;
    my $quoted;
    foreach my $line (@text) {
	if ($line =~ /^(>|&gt;)/) {
	    $line =~ s/^(>|&gt;)//;
	    $quoted .= $line;
	}
	else {
	    if ($quoted) {
		$body .= $ml->div($quoted,{class=>"replyQuote"});
		$quoted = undef;
	    }
	    $body .= $line;
	}
    }
    if ($quoted) {
	$body .= $ml->div($quoted,{class=>"replyQuote"});
	$quoted = undef;
    }

    # emoticons

    if ($config{content}{comment}{emoticons}) {
	foreach my $key (@{$config{content}{comment}{emoticon_re}}) {
	    $body =~ s/$key/<img src="$config{server}{HTMLpath}\/_ExSite\/images\/icons\/$config{content}{comment}{emoticon_img}{$key}" alt="emoticon">/g;
	}
    }

    return $body;
}

sub highlight_quote {
    my ($this,$body) = @_;
    my @text = split /\n/,$body;
    my $out;
    my $quote = 0;
    my $quoted;
    my $ml = &get_obj("ML");
    foreach my $line (@text) {
	if ($line =~ /^(>|&gt;)/) {
	    $line =~ s/^(>|&gt;)//;
	    $quoted .= $line;
	}
	else {
	    if ($quoted) {
		$quoted =~ s/<.+?>//g;
		$out .= $ml->blockquote($quoted);
		$quoted = undef;
	    }
	    $out .= $line;
	}
    }
    if ($quoted) {
	$out .= $ml->blockquote($quoted);
	$quoted = undef;
    }
    return $out;
}

# comment tools are post/reply

sub tools {
    my ($this,%opt) = @_;
    my $out;
    my $ml = &get_obj("ML");
    my $p = $opt{parent} || $this;
    my $id = $p->id;
    my $prompt = $opt{prompt};
    
    # elid is ajax container for comment form
    my $elid;
    if ($opt{comment_type} eq "reply" || $p->subtype eq "comment") {
	$elid = "reply";
	$prompt or $prompt = "Reply";
    }
    else {
	$elid = "post";
	$prompt or $prompt = "Post a comment";
    }
    $elid .= $id;
    $out .= $this->comment_js();
    # fetch the comment form
    #my $url = new ExSite::URI(uri=>$p->get_view_url_dynamic());
    #$url->parameter("comment",2);  # AJAX mode
    my $url = "$config{server}{CGIpath}/$config{prog}{post}".$this->path();
#    if ($share{DB}->level) {
#	# add an authkey because AJAX doesn't allow cookies
#	# authkey is good for 1 day
#	$url->authorize($share{DB}->my_login,1);
#    }
#    my $formurl = $url->write;

    if ($p->is_active) {
	if ($elid =~ /reply/) {
	    $out .= $ml->input(undef,{type=>"button",value=>$prompt,class=>"commentReplyButton",id=>"commentReplyButton_$elid"});
	}
	else {
	    $out .= $ml->input(undef,{type=>"button",value=>$prompt,class=>"commentPostButton",id=>"commentPostButton_$elid"});
	}
    }
    if ($this->{preview}) {
	# extra tools in admin view
	my $wfstatus = $this->wf_status();
	my $status = $wfstatus eq "draft" ? "pending" : $wfstatus;
	$out .= $ml->span($status,{class=>"commentStatus comment".(ucfirst $wfstatus)});
	$out .= $this->moderation_links();
#	$this->{URI} = new ExSite::URI;
	if (! exists $opt{link_tool} || $opt{link_tool}) {
	    $out .= $ml->a("link",{href=>$this->link(id=>$this->id)});
	}
    }
    # empty ajax container
    $out .= $ml->div(undef,{id=>"commentBox_$elid",class=>"commentBox",style=>"display:none;"});
    #$out .= $ml->div(undef,{id=>"commentBox_$id",class=>"commentBox",style=>"display:none;"});
    return (! exists $opt{wrap} || $opt{wrap}) ?
	$ml->div($out,{class=>"commentTools",id=>"commentTools_$id"}) :
	$out;
}

# moderation links are AJAX posts, so that higher-level modules do not have
# to create their own moderation code if they don't want to
sub moderation_links {
    my $this = shift;
    my $out = $this->comment_js();
    my $ml = &get_obj("ML");

    my %statuscode;
    my @opt = split /\|/, $share{DB}->{map}->regexp("enum:content_status");
    foreach my $stat (@opt) {
	my ($num,$val) = split /:/,$stat,2;
	$statuscode{$val} = $num;
    }

#    my $elid = "commentModerationLinks_".$this->id;
    my $status = $this->wf_status();
    my %post;
#    my $cookie = $config{site}{identity_cookie}."=".$cookie{$config{site}{identity_cookie}};
#    my $link = "$config{server}{CGIpath}/$config{prog}{post}?id=".$this->id."&_cookie=".$cookie;
    if ($status eq "published") {
	$post{archived} = "archive";
	$post{canceled} = "cancel";
    }
    elsif ($status eq "archived") {
	$post{published} = "publish";
	$post{canceled} = "cancel";
    }
    elsif ($status eq "approved") {
	$post{published} = "publish";
	$post{draft} = "resubmit";
    }
    elsif ($status eq "queued") {
	$post{published} = "publish";
	$post{draft} = "resubmit";
    }
    elsif ($status eq "draft") {
	$post{published} = "publish";
	$post{approved} = "approve";
	$post{rejected} = "reject";
    }
    elsif ($status eq "canceled") {
	$post{draft} = "resubmit";
    }
    elsif ($status eq "rejected") {
	$post{draft} = "resubmit";
    }
    foreach my $modcmd (sort keys %post) {
#	my $url = "javascript:getRequestDataAsync_Post(this.parentNode,'${elid}','${link}');";
#	$out .= $ml->form(
#	    $ml->button($post{$modcmd},{type=>"button",name=>"_mod",value=>$modcmd,onclick=>$url}),
#	    {method=>"post",action=>$link,class=>"commentModerationForm"}
#	    );
	$out .= $ml->button($post{$modcmd},{type=>"button",name=>"_mod",value=>$statuscode{$modcmd},class=>"commentModerateButton",id=>"commentModerate_".$this->id});
    }
    return $ml->div($out,{class=>"commentModerationButtons"});
}

sub get_comments {
    my ($this,$id) = @_;
    $id or $id = $this->id; # starting node for fetching comments
    my %match;
    $match{type} = $this->isubtype("comment");
    my $tree = $this->get_content_tree();
    my @comments = $tree->find(\%match,$id);
    return wantarray ? @comments : \@comments;
}

sub get_active_comments {
    my ($this,$id) = @_;
    my $comments = $this->get_comments($id);
    my @active_comments;
    foreach my $c (@$comments) {
	push @active_comments, $c if ($c->{status} =~ /^(active|archived)$/);
    }
    return wantarray ? @active_comments : \@active_comments;
}

sub comment_js {
    my ($this) = @_;
    my $out;
    if (! $share{js}{comment}) {
	my $ml = &get_obj("ML");
	if (! $share{js}{jquery}) {
	    $out .= $ml->script(undef,{src=>$config{jquery},type=>"text/javascript"});
	    $share{js}{jquery} = 1;
	}
	if (! $share{js}{jqueryui}) {
	    $out .= $ml->script(undef,{src=>$config{jqueryui},type=>"text/javascript"});
	    $share{js}{jqueryui} = 1;
	}
	if (! $share{js}{httprequest}) {
	    $out .= $ml->script(undef,{src=>"$config{server}{HTMLpath}/_ExSite/js/httprequest.js",type=>"text/javascript"});
	    $share{js}{httprequest} = 1;
	}
	$out .= $ml->script("\nvar posturl = '$config{server}{CGIpath}/$config{prog}{post}';
var c_uid = '$config{site}{identity_cookie}';\n",{type=>"text/javascript"});
	$out .= $ml->script(undef,{src=>"$config{server}{HTMLpath}/_ExSite/js/comment.js", type=>"text/javascript"});
	$share{js}{comment} = 1;
    }
    return $out;
}

# post: a post to a comment is a reply
# expected fields: from, comment

# a post is a new content object created under the current object
# isubtype is the type of content being posted
# uid is the user doing the posting

### FIXME: $access is read access, but posting is write access

sub post {
    my ($this) = @_;
    my $out;
    my $ml = &get_obj("ML");
    my $in = new ExSite::Input;
    my $post = $in->post();
    if ($post->{comment}) {
	# we have an attempted post
	if ($this->is_open()) {
	    # conversation is open
	    if ($share{DB}->level >= $this->access) {  ### access to this area?
		# we have sufficient permission
		my $reply = $this->make_comment(%$post);
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
    elsif (exists $post->{mod}) {
	# we have an attempted moderation
	my $status = $post->{mod};
	if ($status =~ /^\d$/ && $status <= 6) { # 0-6 are valid codes
	    if ($this->allow("moderate")) {
		$this->wf_set_status($status,1); # preapproved
		$this->{preview} = 1; # output new mod buttons
		return $this->tools(wrap=>0,link_tool=>0);
	    }
	    else {
		return "Permission denied: you do not have moderator privileges here.";
	    }
	}
	else {
	    return "Unknown moderation: $status";
	}
    }
    else {
	$out .= $this->warn("Post: nothing posted.");
    }
    return $out;
}

# make_comment - creates a comment
# subject, from, owner, status, comment

sub make_comment {
    my ($this,%opt) = @_;

    # sanitize comment
    my ($body,$warnings) = $share{DB}->validate_language($opt{comment});
    if ($warnings) {
	$this->warn($warnings);
    }
    my $ml = &get_obj("ML");
    my $br = $ml->br;
    $body =~ s/\n/$br\n/g;
    my $comment_body = &safehtml($body);

    my %data = (
	type=>$this->isubtype("comment"),
	parent=> $opt{parent} || $this->id,
	content_role=>"user",
	ctime=>undef,
	);
    $data{name} = "comment_".&randtext(5,"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789");
    $data{status} = $opt{status} || $config{content}{comment}{status};
    $data{title} = $opt{subject};
    if (! $data{title}) {
	$data{title} = $this->getdata("title");
	if ($data{title} !~ /^Re:/i) {
	    $data{title} = "Re: ".$data{title};
	}
    }
    my $reply = $this->new_content_obj(%data);
    if ($reply && $reply->ok) {
	### we reload the content from the DB here???
	$reply = $reply->get_content_obj();  # set type
	$reply->add_key();

	### FIXME: sanitize the body

	my $rev_id = $reply->revise(data=>$comment_body,format=>"text");
	if ($rev_id) {
	    # success
	    my $from = $opt{from} || $share{DB}->my_name;
	    if ($opt{from}) {
		### could validate this is user is logged in
		### we reload the content from the DB here???
		$reply->meta->set("author",$from);
	    }
	}
    }
    if ($reply->wf_status eq "published") {
	$reply->publish(approve=>1);
    }

    # notification -> moderator

    if ($config{content}{comment}{moderate}) {
	my $thparent = $reply->thread_parent();
	my $mod = $thparent->subtype_attr("plugin");
	if (! $mod) {
	    # parent might be an article; look at its container
	    $mod = $thparent->parent->subtype_attr("plugin");
	}
	if ($mod) {
	    # this content type has its own module for managing
	    # notifications and moderation
	    my $module = &get_module($mod);
	    if ($module) {
		if ($module->can("notify_post")) {
		    $module->notify_post($reply);
		}
	    }
	}
    }

    # notification, moderation

    return $reply;
}

sub thread_count {
    my ($this,$id) = @_;
    $id or $id = $this->id;
    my $count = 0;
    my $tree = $this->get_content_tree();
    foreach my $reply ($tree->get_child_data($id)) {
	my $c = $this->get_content_obj($reply);
	next if (! $c->is_active);
	next if ($c->subtype ne "comment");
	$count++;
	$count += $this->thread_count($c->id);
    }
    return $count;
}

# publish_self: publish a thread file

sub publish_self {
    my $this = shift;
    # do not publish if we came from an alias
    return undef if ($this->alias);

    # publish the thread
    if ($this->is_publishable) {
	if (! $this->embedded) {
	    # republish the thread file
	    my $ml = &get_obj("ML");
	    if ($this->is_top_of_thread || $share{publish_comment}==$this->id) { 
		my $thread = $this->my_thread;
		print $ml->li("Publishing comment thread " . $ml->em($thread->title));
		$thread->publish_formatted();
	    }
	}
	if ($this->getdata("ptime") =~ /^0/) {
	    # first time - set the ptime
	    $share{DB}->update("content",
			       {ptime=>undef},
			       {content_id=>$this->id()});
	}
    }
}

# superpublish: publish comment container to update embedded threads or
# comment counts

sub superpublish {
    my ($this,%opt) = @_;
    $this->thread_parent->publish_self();
    return;
}

sub unpublish_content {
    my ($this,%opt) = @_;
    my $ml = &get_obj("ML");
    if (! exists $opt{self} || $opt{self}) {
	# remove our own files
	$this->SUPER::unpublish_content(%opt);
	if ($this->is_top_of_thread) {
	    # remove thread
	    my $file = new ExSite::Diskfile(base=>$this->basedir,
					    path=>$this->subdir,
					    filename=>$this->filename);
	    print $ml->li("removing thread ".$this->filename);
	    $file->unpublish;
	}
    }
    if (! exists $opt{parent} || $opt{parent}) {
	# update containers
	if ($share{publish_content} == $this->id) {
	    # we are only unpublishing this comment; update containers
	    if ($this->is_top_of_thread) {
		# republish parent
		$this->parent->publish_self();
	    }
	    else {
		# republish thread
		$this->my_thread->publish_self();
	    }
	}
    }
    return;
}

# archive_thread - archive this comment, and all replies

sub archive_thread {
    my $this = shift;
    if ($this->allow("moderate")) {
	if ($this->wf_status =~ /published|approved/) {
	    # archive any viewable comments
	    $this->set_status($this->wf_istatus("archived"));
	    $this->save();
	}
	foreach my $reply ($this->get_contents()) {
	    if ($reply->subtype eq "comment") {
		$reply->archive_thread();
	    }
	}
    }
}

sub delete {
    my $this = shift;
    my $id = $this->id;
    if ($id && $this->allow("delete")) {
	my ($top,$thread,$container,$published);
	$published = $this->was_published();
	if ($published) {
	    $top = $this->is_top_of_thread();
	    $thread = $this->my_thread;
	    $container = $this->thread_parent;
	    $this->unpublish(parent=>0,exec_method=>"run");
	}
	# delete ourself *after* all files have been removed
	$share{DB}->trash_r("content",$id);
	# now republish container - no need to wait for response
	if ($published) {
	    if ($top) {
		# republish index
		$container->publish(exec_method=>"spawn"); # nowait
	    }
	    else {
		# republish thread - also republishes index
		$thread->publish(exec_method=>"spawn"); # nowait
	    }
	}
	return 1;
    }
    return 0;
}

sub get_url {
    my $this = shift;
    if ($this->embedded) {
	return $this->thread_parent->get_url() . "#Comment".$this->id;
    }
    elsif ($this->is_top_of_thread()) {
	# link goes to top of thread file
	return $this->SUPER::get_url();
    }
    else {
	# link goes to thread file fragment
	return $this->my_thread()->get_url() . "#Comment".$this->id;
    }
}

1;
