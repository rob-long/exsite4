#-----------------------------------------------------------------------
#
#   Copyright 2001-2006 Exware Solutions, Inc.  http://www.exware.com
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

# POD docs at EOF

package ExSite::Store;

use strict;
use GDBM_File;
use Storable qw(freeze thaw);
use Cwd;
use Devel::Size qw(total_size);
use Fcntl qw(:flock);

sub TIEHASH {
    my ($this,$conf) = @_;

    # abort if no store
    return undef if (ref $conf ne "HASH" || ! $conf->{name});

    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;
    $obj->{config} = $conf;

    $obj->open() or return undef;
    $obj->{callback} = {};

    return $obj;
}

sub FETCH {
    my ($this,$key) = @_;
    return $this->get($key);
}

sub STORE {
    my ($this,$key,$val) = @_;
    my $etime = $this->{config}{lifetime} ?
	$this->{config}{lifetime} + time : 0;
    $this->put($key,$val,$etime);
    return;
}

sub DELETE {
    my ($this,$key) = @_;
    $this->delete($key);
}

sub EXISTS {
    my ($this,$key) = @_;
    return $this->validate_item($key);
}

sub CLEAR {
    my $this = shift;
    $this->reset();
    return;
}

sub FIRSTKEY {
    my ($this) = @_;
    my $firstkey;
    if ($this->connect_r()) {
	my $a = keys %{$this->{store}};
	$firstkey = each %{$this->{store}};
	# Do not disconnect, because we need the same connection to
	# cycle through the keys.  This is a readonly connection, so
	# you cannot alter the store while looping through its items.
    }
    return $firstkey;
}

sub NEXTKEY {
    my ($this,$lastkey) = @_;
    my $nextkey;
    if ($this->connect_r()) {
	# that's a dummy connect_r() call, because we're probably still
	# connected from FIRSTKEY().
	$nextkey = each %{$this->{store}};
	if (! defined $nextkey) { 
	    # that's the last key, okay to disconnect now.
	    $this->disconnect_r(); 
	}
    }
    return $nextkey;
}

sub UNTIE {
    my $this = shift;
    $this->close;
    return undef;
}

#sub DESTROY {
#}

#------------------------------------------------------------------------
# Internal methods (not accessed via the tie interface).
#------------------------------------------------------------------------

# Special methods for handling store contents

# open : start up the store
# - test/validate the store connection
# - open the lock file

sub open {
    my $this = shift;
    my $stat = 0;
    if ($this->connect_r()) {
	if (! $this->{lockfile}) {
	    my $lockfile = $this->{config}{lock} || 
		"$this->{config}{name}.lock";
	    open LOCKFILE, $lockfile or return undef;
	    $this->{lockfile} = *LOCKFILE;
	}
	if ($this->validate()) {
	    $this->log("Connection established by $ENV{REQUEST_URI} at ".
		       (scalar localtime));
	    $stat = 1;
	}
	else {
	    $this->log("Bad connection; exiting store");
	}
	$this->disconnect_r();
    }
    return $stat;
}

# close : shut the store down
# - flush the logs
# - purge any expired items

sub close {
    my $this = shift;
    if ($this->{config}{log} || $this->time_until_purge <= 0) {
	# we have stuff to write to the store
	if ($this->connect_w()) {
	    if ($this->{config}{log}) {
		# save the log
		$this->put("_log",$this->{log},0);
	    }
	    if ($this->time_until_purge <= 0) {
		# looks like we're due for a good purge
		require ExSite::Util;
		if (! $this->{config}{purge_load} ||
		    &ExSite::Util::sysload() < $this->{config}{purge_load}) {
		    # only purge in slow periods
		    $this->purge();
		    # reset the purge timestamp
		    $this->{id}{ptime} = time;
		    # save
		    $this->putraw("_id",$this->{id});
		}
	    }
	    $this->disconnect_w();
	}
    }
    close $this->{lockfile};
    delete $this->{validated};
}

# connect_r : establish a readonly connection to the store

sub connect_r {
    my $this = shift;
    return $this->{store} if ($this->{mode} eq "R");
    $this->disconnect_w() if ($this->{mode} eq "W");
    my %store;
    if (tie %store, 'GDBM_File', $this->{config}{name}, 
	&GDBM_READER | &GDBM_NOLOCK, 0666) {
	$this->{store} = \%store;
	$this->{mode} = "R";
    }
    else {
	$this->{store} = undef;
    }
    return $this->{store};
}

# disconnect_r : end a readonly connection to the store

sub disconnect_r {
    my ($this) = @_;
    if ($this->{store}) {
	untie %{$this->{store}};
	$this->{store} = undef;
	$this->{mode} = undef;
    }
}

# connect_w : establish a read-write connection to the store.
# This requires an exclusive lock, so it will block all other 
# users while it is active.  You can optionally pass a retry 
# count in case you cannot get a lock on the store.  
# See lock() for details.

sub connect_w {
    my $this = shift;
    return $this->{store} if ($this->{mode} eq "W");
    $this->disconnect_r() if ($this->{mode} eq "R");
    my %store; 
    if ($this->lock(shift)) {
	if (tie %store, 'GDBM_File', $this->{config}{name}, 
	    &GDBM_WRITER | &GDBM_NOLOCK, 0666) {
	    $this->{store} = \%store;
	    $this->{mode} = "W";
	}
	else {
	    $this->{store} = undef;
	}
    }
    return $this->{store};
}

# disconnect_w : end a read-write connection to the store.
# Use this ASAP so that other store users can get access.

sub disconnect_w {
    my ($this) = @_;
    $this->disconnect_r();
    $this->unlock() if ($this->{locked});
}

# time_until_purge : number of seconds remaining before garbage collection

sub time_until_purge {
    my ($this) = @_;
    return 0 if (! $this->{id}{ptime});
    return $this->{id}{ptime} + $this->{config}{purge_interval} - time;
}

# validate : verify that we are connecting to the right store

sub validate {
    my $this = shift;
    return 1 if ($this->{config}{novalidate});
    return $this->{validated} if ($this->{validated});
    $this->{id} = $this->getraw_nolock("_id");
    my $wd = $this->{id}{data};
    # check cwd to make sure we are connecting to the right store
    $this->{validated} = ($wd && $wd eq cwd);
    if (! $this->{validated}) {
	$this->log("Wrong store! ($wd)");
    }
    return $this->{validated};
}

# validate_item : verify that an item has not expired

sub validate_item {
    my $this = shift;
    my $key = shift;
    if ($key) {
	# validate a particular store item
	my $storerec = shift || $this->getraw($key);
	if (ref $storerec eq "HASH") {
	    if (! $storerec->{etime} || ($storerec->{etime} > time)) {
		return 1;
	    }
	}
    }
    return 0;
}

# get : retrieve item data from the store
# will fail if the item has expired

sub get {
    my ($this,$key) = @_;
    my $storerec = $this->getraw($key);
    if ($storerec) {
	if ($this->validate_item($key,$storerec)) {
	    return $storerec->{data};
	}
	else {
	    $this->log("expired $key");
	    $this->delete($key);
	    $this->do_callback($key);
	    $this->{expired} = $key;
	    return undef;
	}
    }
    return undef;
}

# getraw : retrieve item data and metadata (expiry time) from the store
# retrieves the item even if past expiry

sub getraw {
    my ($this,$key) = @_;
    my $raw;
    if ($this->connect_r()) {
	$raw = eval { $this->{store}{$key}; };
	if ($@) {
	    # read fail - store corrupted !?
	    $this->disconnect_r();
	    $this->hard_reset();
	    $this->log("hard reset on failed read of $key: $@");
	}
	else {
	    $this->disconnect_r();
	}
        $this->log($raw ? "fetched $key" : "$key not found");
    }
    else {
	$this->log("lookup failed for $key");
    }
    my $data;
    if ($raw) {
	$data = eval { thaw $raw; };
	if ($@) {
	    $this->log("$key: $@");
	    # stored value corrupted !?
	    $this->delete($key);
	    $data = undef;
	}
    }
    return $data;
}

# getraw_nolock : same as getraw(), but does no locking.  Use this if
# you need to do multiple gets and will manage your own locks.

sub getraw_nolock {
    my ($this,$key) = @_;
    my $data;
    my $raw = eval { $this->{store}{$key}; };
    if ($@) {
	$this->log("$key: $@");
	# read fail - store corrupted !?
	$this->hard_reset();
	$data = undef;
	$this->log("hard reset on failed read of $key: $@");
    }
    $this->log($raw ? "fetched $key" : "$key not found");
    if ($raw) {
	$data = eval { thaw $raw; };
	if ($@) {
	    $this->log("$key: $@");
	    # stored value corrupted !?
	    $this->delete($key);
	    $data = undef;
	}
    }
    return $data;
}

# put : save an item to the store, with an optional expiry time

sub put {
    my ($this,$key,$val,$etime) = @_;
    if ($val) {
	my $storerec = { data => $val };
	$storerec->{etime} = $etime ? $etime : 0;
	$this->putraw($key,$storerec);
    }
    else {
	# can't put an empty value in the store; treat as a delete
	$this->delete($key);
    }
    return;
}

# putraw : save an item structure (with expiry time) to the store

sub putraw {
    my ($this,$key,$storerec) = @_;
    my $frozen = eval { freeze $storerec; };
    if (! $@ && $this->connect_w(-1)) {
	$this->{store}{$key} = $frozen;
	$this->disconnect_w();
	$this->log("saved $key");
    }
    else {
	$this->log("save failed for $key: $@");
    }
    return;
}

# multistore : save a hash of keys and values

sub multistore {
    my ($this,%data) = @_;
    my $etime = $this->{config}{lifetime} ?
	$this->{config}{lifetime} + time : 0;
    while (my ($key,$val) = each %data) {
	$this->put($key,$val,$etime);
    }
    return;
}

# renew : update the expiry time of an item

sub renew {
    my ($this,$key,$etime) = @_;
    my $storerec = $this->getraw($key);
    if ($storerec) {
	$this->log("renewed $key");
	$storerec->{etime} = $etime;
	$this->putraw($key,$storerec);
    }
    return;
}

# delete : remove one or more items from the store

sub delete {
    my ($this,@keys) = @_;
    if ($this->connect_w(-1)) {
	foreach my $key (@keys) {
	    delete $this->{store}{$key};
	}
	$this->disconnect_w();
    }
    $this->log("deleted ".join(", ",@keys));
}

# reset : remove all non-admin items from the store

sub reset {
    my $this = shift;
    $this->log("reset store");
    if ($this->connect_w()) {
	my @key = keys %{$this->{store}};
	foreach my $key (@key) {
	    next if ($key =~ /^_/);
	    delete $this->{store}{$key};
	}
	# clear the purge timer
	$this->{id}{ptime} = 0;
	$this->putraw("_id",$this->{id});
	$this->disconnect_w(); # redundant
    }
    return;
}

# hard reset : re-create the store DB

sub hard_reset {
    my $this = shift;
    if ($this->connect_w(-1)) { # ensure we are only ones writing at this time
	$this->create();
    }
    $this->disconnect_w();
}

# create : initialize the store DB

sub create {
    my $this = shift;
    $this->log("initializing store");
    my %st;
    tie %st, 'GDBM_File', $this->{config}{name}, &GDBM_NEWDB, 0666
	or die "failed to reset store ($!)";
    my $id = { data => cwd, ptime=>time, etime=>0 };
    $st{_id} = freeze $id;
    untie %st;
    if (! -e $this->{config}{lock}) {
	open LOCK,">$this->{config}{lock}" 
	    or die "cannot create lock file ($!)";
	close LOCK;
	$this->log("created store lock file");
    }
}

# purge : remove all expired items from the store

sub purge {
    my $this = shift;
    my $size = 0;
    if ($this->connect_r()) {
	my @key = keys %{$this->{store}};
	$this->log("purging expired data...");
	foreach my $key (@key) {
	    next if ($key =~ /^_/);
	    my $dat = $this->getraw_nolock($key);
	    if (! $this->validate_item($key,$dat)) {
		if ($this->connect_w()) {
		    $this->log("purged $key");
		    delete $this->{store}{$key};
		    $this->disconnect_w();
		    # warning: callbacks may perform their own (dis)connects
		    $this->do_callback($key);
		    $size += total_size $dat;
		    # return to read mode for next item
		    $this->connect_r();
		}
	    }
	}
	$this->disconnect_r();
    }
    return $size;
}

# clear_prefix: remove all items with a common prefix
# useful for clearing cache, and similar operations

sub clear_prefix {
    my ($this,$prefix) = @_;
    if ($this->connect_w()) {
	my @key = sort keys %{$this->{store}};
	my $in_prefix;
	foreach my $key (@key) {
	    if ($key =~ /^$prefix/) {
		$in_prefix = 1;
		delete $this->{store}{$key};
	    }
	    elsif ($in_prefix) {
		# keys are sorted, so we're done
		last;
	    }
	}
	$this->disconnect_w();
	$this->log("cleared $prefix");
    }
    else {
	$this->log("clear $prefix failed; could not acquire lock");
    }
}

# rebuild : reclaim disk space from deleted/purged items
# WARNING: Apache cannot do this, as it must rewrite the store file,
# so this must be used by 3rd-party utils only.

sub rebuild {
    my $this = shift;
    if ($this->connect_w()) {
	(tied %{$this->{store}})->reorganize();
	# reorganize() recreates the store, and resets the mode;  fix it
	chmod 0666, $this->{config}{name};
	$this->disconnect_w();
	$this->log("rebuilt store");
    }
    else {
	$this->log("store rebuild failed; could not acquire lock");
    }
}

# size : return the total size of items in the store

sub size {
    my $this = shift;
    my $size = 0;
    if ($this->connect_r()) {
	if (@_ == 0) { 
	    @_ = keys %{$this->{store}}; 
	}
	while (my $key = shift) {
	    next if ($key =~ /^_/);
	    my $dat = $this->{store}{$key};
	    $size += length $dat;
	}
	$this->disconnect_r();
    }
    return $size;
}

# summary : return a brief summary of the store state

sub summary {
    my $this = shift;
    my $id = $this->getraw("_id");
    my $purge_in = $this->time_until_purge();
    my $mm = int ($purge_in / 60);
    my $ss = $purge_in % 60;
    my $time = sprintf "%d:%02d",$mm,$ss;
    return $purge_in > 0 ?
	"Garbage collection will run in $time." :
	"Garbage collecting now...";
}

# log : record a status message about a store operation

sub log {
    my ($this,$msg) = @_;
#    return if ($this->{logging});  # infinite loop trap
    $this->{logging} = 1;
    if (! $this->{log}) {
	$this->{log} = [];
#	$this->{log} = $this->get("_log") || [];
    }
    my $log = $this->{log};
#    if (scalar @$log >= $this->{config}{loglimit}) {
#	shift @$log;
#    }
    push @$log,time."::$$: ".$msg."\n";
#    push @$log,join(" @ ",keys %{$this->{store}})."\n";

    $this->{logging} = 0;
    return;
}

# is_persistent : is the store on?

sub is_persistent {
    my $this = shift;
    return $this->validate();
}

# callbacks are used when the store unilaterally alters itself
# (usually by expiring or garbage collecting an item).  You can 
# register a store callback to notify another object of such a 
# change in the store.

sub set_callback {
    my ($this,$obj,$method,$regexp) = @_;
    # $method is a function/method that will receive the notification
    # we should call it if a deleted object key matches $regexp
    $this->{callback}{$regexp} = [$obj,$method];
}

sub do_callback {
    my ($this,$key) = @_;
    # $key is a store item that has been deleted
    # look for any matching callbacks
    foreach my $r (keys %{$this->{callback}}) {
	if ($key =~ /$r/) {
	    # match!
	    my ($obj,$method) = @{$this->{callback}{$r}};
	    eval { $obj->$method($key); };
	    $this->log($@) if $@;
	}
    }
}

# Although locking is implicit with GDBM, it is designed for readonly 
# databases (one-writer, all connections fail while the writer has
# the database open).  We have a read-write model, so we need to be
# able to lock and unlock on individual operations, not for the life
# of the file handle.

# We use a non-blocking lock on the lockfile.  If we fail to acquire
# the lock, that obviously means we have contention, so we sleep for
# 1 second to let it pass, and then retry.  We can pass the maximum
# number of retries as a parameter to lock(), eg. lock(5), but it will
# assume a default of 3 if we specify nothing.  If we pass a negative
# number, it will never stop retrying.  Use this for operations that
# MUST proceed.  Otherwise, if the number of retries is exceeded the 
# operation will fail to execute.

sub lock {
    my $this = shift;
    if ($this->{lockfile}) {
	my $retry = shift || $this->{config}{retry} || 3;
	my $gotit = flock $this->{lockfile}, (LOCK_EX|LOCK_NB);
	while (! $gotit && $retry != 0) {
	    $retry--;
	    $this->log("no lock; $retry tries left");
	    sleep(1);
	    $gotit = flock $this->{lockfile},(LOCK_EX|LOCK_NB);
	}
	if ($gotit) {
	    $this->{locked} = 1;
#	    $this->log("$$ acquired lock");
#	    close LOCKLOG;
	    return 1;
	}
	return 1 if ($gotit);
    }
    $this->log("failed to acquire lock, aborting operation");
    return 0;
}

sub unlock {
    my $this = shift;
    $this->log("$$ released lock");
    flock $this->{lockfile}, LOCK_UN;
    $this->{locked} = 0;
    # close at store disconnect
#    close LOCK;
}

=pod

=head1 ExSite::Store

ExSite::Store is a multi-purpose data store that allows for sharing
of complex data structures among different processes.  It is used by
ExSite for the following purposes:

=over 4

=item * database cache

=item * storing system configuration

=item * session management

=back

Furthermore, any plug-in module can utilize the Store for persistent
storage of data.

The data store exposes itself to the application as a simple hash
(C<%store>) which may be used by any code in a read/write
fashion.  Values written to C<%store> will persist beyond the life of
the process, and will be available to other processes to read.

It is assumed that the store will be accessed via wrapper classes that
will handle the job of fetching data from original sources, loading
the data into the store, and checking the store for the data before
returning to the original source.  See for example, ExSite::Cache and
ExSite::Session.  Those classes are responsible for specifying any
special timeouts for stored values, otherwise the default expiry
timeout is used (typically 1 hour).

The values written to the store can be arbitrarily complex Perl data
structures.  They are serialized using C<Storable::freeze> before being 
saved, and are recovered using C<Storable::thaw>.  Freezing and thawing
of stored values is handled automatically by the store.

=head2 Storage Keys

Since the store can keep track of widely disparate data, it is
important to use unique keys when reading or writing to it, to avoid
grabbing or overwriting unrelated data accidentally.  However, the
store does not police this in any way, so you can easily clobber your
own data if not careful.  If in doubt, use a standard prefix on your
keys (eg. your plug-in name) to keep them in an identifiable group.
For example, the database cache prefixes its store keys with
"cache": by default, and the session manager prefixes its store keys
with "session:".

The store records a few internal items under plain text keys that
are prefixed with "_".  Of special importance is the "_id" key, which
records the ExSite working directory (ie. your CGI-BIN).  If this does
not match the working directory of the current process, the store
connection will be rejected.  This is to prevent one site/installation
from connecting to another's store.

=head2 Storage Lifetime

Every item is placed into the store with an expiry time (which is a
Unix timestamp).  Items past their expiry time are cleaned out in two
cases: (1) if they are fetched after their expiry time, and (2) when
garbage collection runs.

The default lifetime of an item placed into the store is defined in
the store configuration (see below), and is typically 1 hour.  The
lifetime can be change/extended by renewing the item:

    (tied %store)->renew($key,$new_expiry_time);

You can store an item and set a custom lifetime in one step, as follows:

    (tied %store)->put($key,$value,$expiry_time);

If you set the expiry time to 0 using either of these methods, the
item will persist in the store indefinitely.  Use this for system
configurations that are not expected to change during normal system
use.

=head2 Garbage Collection

Purging of expired items occurs automatically after a certain amount
of time has passed (default is every 15 minutes).  This helps to clear
out old or infrequently-used items that could use a refresh, or are
simply taking up space.

Because the store will remove expired data on a regular basis, you cannot
rely on a stored item being present when you request it.  Your code is
responsible for obtaining the desired data from alternate sources if
this is the case.  For this reason, the store is useful primarily as
a multipurpose cache to improve performance on costly data-fetch operations,
or as a place to save state for a limited term.

If you want to extend the lifetime of something in the store, to
prevent it from being expired when it is still needed, use the
following method:

    (tied %store)->renew($key,$new_expiry_time);

=head3 Notification Callbacks

The store can be configured to callback to another system component
when it automatically clears out expired items.  This is so that
higher-level components that use the store can clean themselves up
if necessary when garbage collection has been done.

If you want to be informed when an item is automatically reaped from
the store, register your callback with the store:

    (tied %store)->set_callback($my_obj, $notify_method, $regexp);

C<$my_obj> is the object that should receive the notification.
C<$notify_method> is the object method that will process the
notification.  C<$regexp> is a regular expression that is used to
match store keys; only matching keys will trigger the notification.

The notification callback method will be passed the key of the
expired item.  Ie. when an item is expired, the following callback
is executed:

    $my_obj->$notify_method($key);

=head2 Implementation

This version of the ExSite store uses a GDBM database for persistent
storage of data.  This is significantly faster than a SQL database,
and also has the advantage of persisting on disk even through system
reboots, so that sessions and other state data are not lost.

The utility script C<bin/store.pl> should be used to generate
and initialize the GDBM file.  Use this command:

    ../bin/store.pl --reset

(It will not be automatically generated because the webserver process
does not normally have the necessary privileges to create the GDBM
files in the working directory.)  You can re-run this script to reset
the store, but that will clear all stored items from the GDBM file.
You should re-run this script if you ever move your CGI-BIN to a
different directory (because the store will refuse connection when it
detects this), or if you have any problems with file corruption.

Note that DBM files tend to grow as new items are added, but do not
shrink when old items are removed.  This is because the DBM file holds
on to its disk space to reuse it for future items.  If the DBM file is
taking up too much disk space, you can use this command to shrink the
file:

    ../bin/store.pl --rebuild

The C<StoreAdm> plug-in supports scheduling of this function at
regular intervals.

=head2 Store Configuration

The routine C<Local::store_conf()> contains the configuration
parameters for the store.  (These parameters cannot be stored in
%config, because %config is itself read from the store if possible.)
The important configuration settings are:

=over 4

=item name

This is the name of the store database file, which will be created
in CGI-BIN.

=item lifetime

This is the default lifetime of an item placed into the store, in seconds.

=item purge_interval

This defines how often garbage collection runs, in seconds.  If a connection
to the store is made after this many seconds have elapsed since the last 
purge, then C<purge()> is called when the job disconnects from the store
(ie. when the store is untied).

=item purge_load

This defines the maximum system load under which the store will run
garbage collection.  If the load exceeds this number, then garbage
collection will be deferred until things are quieter.

=item log

Set this to 1 to enable logging of store operations.  The store log is
written to the store itself (under the key C<_log>).

=item loglimit

This is the maximum number of lines of log that will be kept on file.
When the log exceeds this length, the oldest lines will be expired to
make room for the new lines.

=item lock

This is the name of the store lockfile.  If not provided it will
default to the store database name, above, with C<.lock> appended.

=item retry

When the store needs to write to itself, it requires an exclusive
lock.  It may not be able to acquire this lock if the system is busy.
If that is the case, it waits for a second in the hopes that the
busyness will pass, and tries again.  The C<retry> parameter defines
the maximum number of retries before it gives up and cancels the
operation.

=back

=head2 Special Methods

The following special methods can be accessed from the store object
itself:

=over 4 

=item connect()

Opens the GDBM file and validates that it is the correct store.

=item get($key)

Retrieves a specific item from the store.  (Fails if the item has expired.)

=item getraw($key)

Retrieves a specific item from the store, along with store metadata used
to manage the item (such as its expiry time).  (This returns the item,
even if the item has expired.)

=item put($key,$value,$expiry)

Places an item (C<$value>) into the store indexed under C<$key>.  An
optional C<$expiry> time can be provided (Unix timestamp), but the store
default will be used if this is not given.

=item putraw($key,$store_record)

Places an item (C<$value>) into the store indexed under C<$key>.  An
The item should be formatted as a store record, including fields for
the data and expiry time.

=item delete($key)

Removes the item indexed under C<$key>.

=item renew($key,$new_expiry_time)

Updates the expiry time of the item indexed under C<$key>.

=item purge()

Removes all expired items from the store.

=item reset()

Removes all items from the store.

=item rebuild()

Reclaims disk space from deleted items, to shrink the size of the
store database.  Because this generates a new database, Apache will
not likely have the necessary privileges to create the file.  For that
reason, the rebuild command should be issued from cron or manually.

=item size()

Returns the total size of the frozen data in the store.

=item summary()

Returns a text string describing the store contents.

=item is_persistent()

Returns TRUE if the store is connected to persistent storage, and
FALSE if not.

=back

=cut

1;
