#!/usr/bin/perl
#-----------------------------------------------------------------------
#
#   Copyright 2013 Exware Solutions, Inc.  http://www.exware.com
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

package ExSite::Workflow;

use strict;
use ExSite::Config;
use ExSite::Base;

use vars qw(@ISA @wf_action @wf_priv @wf_matrix);
@ISA = qw(ExSite::Base);

#===========================================================================
# status management & workflows

# There are 9 workflow states:

our %status = (
    published => 0,  # active, approved for viewing
    archived => 1,   # no longer active, but still approved for viewing
    queued => 2,     # approved for viewing, to be published in a queue
    approved => 3,   # approved for viewing, to be published manually
    submitted => 4,  # pending approval/moderation
    draft => 5,      # not yet submitted for approval
    expired => 6,    # no longer approved for viewing, reinstatement likely
    canceled => 7,   # no longer approved for viewing, reinstatement unlikely
    rejected => 8,   # never approved, can be garbage-collected
    );

#my %status_old = (
#    published => 0,  # active, approved for viewing
#    archived => 1,   # no longer active, but still approved for viewing
#    queued => 2,     # approved for viewing, to be published in a queue
#    approved => 3,   # approved for viewing, to be published manually
#    draft => 4,      # not yet approved for viewing
#    expired => 5,    # no longer approved for viewing, reinstatement likely
#    canceled => 6,   # no longer approved for viewing
#    rejected => 7,   # never approved, can be garbage-collected
#    );

our @status = (
    "published",
    "archived",
    "queued",
    "approved",
    "submitted",
    "draft",
    "expired",
    "canceled",
    "rejected",
    );

@wf_action = (
    "publish",
    "archive",
    "queue",
    "approve",
    "submit",
    "draft",
    "expire",
    "cancel",
    "reject",
    );

@wf_priv = (
    "publish",
    "publish",
    "publish",
    "moderate",
    "update",
    "update",
    "publish",
    "publish",
    "moderate",
    );

# @wf_matrix describes meaningful workflow operations
# $wf_matrix[A][B] = name of operation to go from state A to state B
# if the name is undef, the operation is not meaningful (eg. archived->queued)

@wf_matrix = (
    [ undef,     "archive", undef,   undef,     undef,    "draft", "expire", "cancel", undef    ],
    [ "publish", undef,     undef,   undef,     undef,    "draft", "expire", "cancel", undef    ],
    [ "publish", "archive", undef,   undef,     undef,    "draft", "expire", "cancel", undef    ],
    [ "publish", "archive", "queue", undef,     undef,    "draft", "expire", "cancel", "reject" ],
    [ "publish", "archive", "queue", "approve", undef,    "draft", "expire", "cancel", "reject" ],
    [ "publish", "archive", "queue", "approve", "submit", undef,   "expire", "cancel", "reject" ],
    [ "publish", "archive", "queue", "approve", "submit", "draft", undef,    undef,    "reject" ],
    [ undef,     undef,     undef,   "approve", "submit", "draft", undef,    undef,    "reject" ],
    [ undef,     undef,     undef,   "approve", "submit", "draft", undef,    undef,    undef    ],
    );

# return readable status value
sub wf_status {
    my ($this,$stat) = @_;
    defined $stat or $stat = ( $this->getdata("status") || 0 );
    return $status[$stat];
}

# return numeric status value
sub wf_istatus {
    my ($this,$status) = @_;
    return $status ? $status{$status} : $this->getdata("status");
}

# Can we display this object directly? (yes if published or archived)
sub is_viewable {
    my $this = shift;
    my $stat = $this->getdata("status") || 0;
    return $stat < 2;
}

# Can we display this object in indexes? (yes if published, not if archived)
sub is_indexable {
    my $this = shift;
    return ! $this->getdata("status");
}

# Is the object "active"?
# Default rule is that if the content is viewable, it is active.
# Interactive types may need to overload this, since archived
# may imply viewable, but no longer interactive.
sub is_active {
    my $this = shift;
    return $this->is_viewable();
}

# Is this a draft?
sub is_draft {
    my $this = shift;
    return ($this->getdata("status") == 4);
}

# basic status change - no publishing
sub set_status {
    my ($this,$to) = @_;
    $this->setdata("status",$to);
    if ($this->force_save()) {
	if ($config{content}{log_workflow}) {
	    my $name = $share{cron} ? "cron" : $share{DB}->my_name;
	    $this->log("$to by $name");
	}
	if ($share{content}{tree}) {
	    # update data in cached content tree
	    my $data = $share{content}{tree}->getnode_data($this->id);
	    if (ref $data eq "HASH" && exists $data->{status}) {
		$data->{status} = $to;
	    }
	}
    }
}

# we may need to republish after status changes
sub wf_run_publisher {
    my ($this,$from,$to) = @_;
    return if ($from == $to);   # no change
    my %popt;
    if (! $this->allow("publish")) {
	# current user does not have publish perms, so we must authorize
	# the operation; find a handy administrator to make this happen
	$popt{uid} = $this->all_roles()->{administrator};
    }
    if ($from < 2) {
	if ($to < 2) {
	    # published <--> archived
	    # republish the parent to update indexes
	    my $parent = $this->parent();
	    if ($parent) { $parent->publish(%popt); }
	}
	else {
	    # published --> unpublished
	    $this->unpublish(%popt);
	}
    }
    elsif ($to < 2) {
	# unpublished --> published or archived
	$this->publish(%popt);
    }
    # else - no change in publish status
}

sub wf_set_status   {
    my ($this,$to,$approve) = @_;
    my $from = $this->getdata("status");
    return if ($from == $to);   # no change
    $approve or $approve = $this->allow($wf_priv[$to]);
    if ($approve) {
	# set new status
	$this->set_status($to);
	# republish anything that needs to be republished
	$this->wf_run_publisher($from,$to);
    }
    else {
	my $action = ucfirst $wf_action[$to];
	$this->warn(&substitute("[[action]] [[type]] '[[label]]': you need [[priv]] permissions to do this.",{action=>ucfirst($wf_action[$to]),label=>$this->label,type=>$this->subtype,priv=>$wf_priv[$to]}));
    }
}

sub wf_publish {
    my ($this,$approve) = @_;
    $this->wf_set_status($status{published},$approve);
}

sub wf_archive {
    my ($this,$approve) = @_;
    $this->wf_set_status($status{archived},$approve);
}

sub wf_approve {
    my ($this,$approve) = @_;
    $this->wf_set_status($status{approved},$approve);
}

sub wf_queue {
    my ($this,$approve) = @_;
    $this->wf_set_status($status{queued},$approve);
}

sub wf_submit {
    my ($this,$approve) = @_;
    $this->wf_set_status($status{submitted},$approve);
    ### moderator notification??
}

sub wf_draft {
    my ($this,$approve) = @_;
    $this->wf_set_status($status{draft},$approve);
}

sub wf_expire {
    my ($this,$approve) = @_;
    $this->wf_set_status($status{expired},$approve);
}

sub wf_cancel {
    my ($this,$approve) = @_;
    $this->wf_set_status($status{canceled},$approve);
}

sub wf_reject {
    my ($this,$approve) = @_;
    $this->wf_set_status($status{rejected},$approve);
}

# wf_allow: returns operation name, if $to istatus is allowed, undef if not.
# If $to is not set, returns an array of allowed operations.
# This is not a strict security tool; there is no technical reason why you 
# cannot switch to any workflow status at any time. However, some of them
# just don't make much sense; wf_allow() returns sensible operations.

sub wf_allow {
    my ($this,$to) = @_;
    my $from = $this->wf_istatus();
    my $allow = $wf_matrix[$from];
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

# -- stubs (for testing) --

=pod
sub getdata { 
    my ($this,$name) = @_;
    return $this->{data}{$name};
}
sub setdata { 
    my ($this,$name,$value) = @_;
    $this->{data}{$name} = $value;
}
sub force_save { 
    my $this = shift;
    return 1;
}
sub parent { 
    my $this = shift;
    return $this;
}
sub run_publisher { 
    my $this = shift;
    return undef;
}
sub allow {
    my ($this,$action) = @_;
    return 1;
}
sub log {
    my ($this,$action) = @_;
}
=cut

=pod

=head1 Workflow

This module defines a 9-state workflow system. The states are:

=over 4

=item * published (0)

=item * archived (1)

=item * queued (2)

=item * approved (3)

=item * submitted (4)

=item * draft (5)

=item * expired (6)

=item * canceled (7)

=item * rejected (8)

=back

In general, content migrates toward lower-numbered states when being
posted to a website, and toward higher-numbered states when it is
being removed from a website. Content in the lowest-numbered state
(published) is 1st-class content suitable for general
consumption. Content in the highest-numbered state (rejected) is
considered garbage, suitable for deletion. Intermediate states have
varying levels of approval or disapproval.

Changing states is as simple as calling the appropriate workflow function:

    $c->wf_ACTION($approve);

where C<ACTION> is one of publish, archive, approve, queue, submit, draft,
expire, cancel, or reject. If the approve flag is not set, the
workflow action will only be taken if the user has an appropriate
access level and role to perform that action. An editor role is needed
to publish, but a moderator role is sufficient to approve/reject
content.

When changing to a state that permits general viewing of the content,
the workflow tools will automatically publish the content.

To find out which workflow actions are recommended in the current
state, use:

    my @allowed_actions = $c->wf_allow();
    my $is_allowed = $c->wf_allow($action);

Not all actions necessarily make sense for all types of
content. Recommended usage is:

=over 4

=item published - content is active and approved for viewing

=item archived - content is approved for viewing, but is no longer
active. Archived items may have certain tools disabled, and may not
appear in indexes or menus, but links will still work.

=approved - approved for viewing, but not yet published. Moderators
may approve content (such as comments), or editors may approve
multiple things before doing a single batch publish when they are
done. Approved content is published manually.

=item queued - approved for viewing, but not yet published. Queued
content will be published automatically by a queuing system.

=item submitted - submitted for approval. A moderator needs to approve
this content to take it live, or reject it to discard it.

= draft - not yet approved for viewing. Use this to save your edits
without risk of them accidentally going live if the site gets published.

= expired - no longer approved for viewing, reinstatement likely. Use
this for content that has a preset lifetime (such as membership
profiles), or when re-approval/reinstatement is likely.

= canceled - no longer approved for viewing. The content is no longer
valid, but you want to keep it on file.

= rejected - not approved. The content is considered junk, and it can
be deleted by garbage collectors.

=back

The revision system also uses a simplified workflow, in which the two
most important states are C<draft> and c<published>. Revisions have
implicit archived and approved states, but those are managed
automatically rather than by explicitly setting the state.

=cut

1;
