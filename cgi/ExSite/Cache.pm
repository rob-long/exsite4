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

package ExSite::Cache;
use strict;
use ExSite::Config;
use ExSite::Base;
use ExSite::Misc;
use Storable qw(dclone);
use Devel::Size qw(size total_size);

use vars qw(@ISA);
@ISA = qw(ExSite::Base);

sub new ($) {
    my $this = shift;
    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;
    $obj->{cache_name} = "cache";
    $obj->on;
    return $obj;
}

# on/off enables/disables caching
# WARNING: disabling cache can create inconsistencies with your hard cache  
# if you make any changes the database. In that case, it is recommended to
# clear your hard cache when done.

sub on { 
    my $this = shift;
    $this->{cache} = {};
    $this->{disabled} = 0;
}

sub off {
    my $this = shift;
    $this->{disabled} = 1;
}

sub cachelog {
    my ($this,$action,$key,$value) = @_;
    # detailed logging if requested
    if ($config{cache}{log}) {
	$this->info("Cache: $action $key");
    }
    # otherwise, collect some basic stats
    return $share{cachelog}{$action}++;
}

# save some data to the cache;
# first arg is the data to save;
# remaining args are used to index the data.
#
# performs a safety check to ensure that the data isn't too large to cache.
# This test can be skipped (if you know the data is safe for the cache)
# by calling save_safe() instead.

sub save ($$@) {
    my $this = shift;
    return undef if ($this->{disabled});
    my $data = shift; # this is the value you are saving in the hash
    # escape if the data is too big
    my $size = total_size($data);
    return 0 if ($size > $config{cache}{max_size});
    return $this->save_safe($data, @_);
}

sub save_safe ($$@) {
    my ($this,$data,@keys) = @_;
    my $key = $this->key(@keys);
    $this->cachelog("save",$key,$data);

    # place the item into the soft cache
    if (exists $this->{cache}{$key}) {
	# update existing item
	$this->cachelog("update",$key,$data);
    }
    else {
	# create new cache item
	$this->cachelog("insert",$key,$data);
    }
    $this->{cache}{$key} = ref $data ? dclone $data : $data;
    my @update;
    push @update, $key;

    # save changes to the store
    $this->update(@update);

    if ($this->{disabled}) {
	# don't preserve a local copy - might be too costly in terms
	# of memory usage in some applications, such as publishing everything
	delete $this->{cache}{$key};
    }

    return 1;
}

# fetch data from the cache;
# args are used to determine the index to the data.

sub get ($@) {
    my $this = shift;
    return undef if ($this->{disabled});
    my $key = $this->key(@_);
    my $cdata;
    if (exists $this->{cache}{$key}) {
	# it's in the soft cache
	$cdata = $this->{cache}{$key};
    }
    elsif ($config{cache}{persistent}) {
	$cdata = $store{$key};
	if ($cdata) {
	    # it's in the hard cache
	    $this->{cache}{$key} = $cdata;
	}
	else {
	    # might have been expired - update key index ???
	}
    }
    if ($cdata) {
	$this->cachelog("get",$key);
	return $cdata;
    }
    else {
	return undef;
    }
}

# delete data from the cache;
# args are used to determine the index to the data.

sub delete ($@) {
    my $this = shift;
    my $key = $this->key(@_);
    $this->cachelog("delete",$key);

    # soft update (update our local memory copy of the cache)
    delete $this->{cache}{$key};

    # hard update (update the saved copy of the cache)
    $this->update($key);
}

# update: write altered cache items back to the store.

sub update {
    my ($this,@key) = @_;
    # update the hard cache
    return if (! $config{cache}{persistent});  # no hard cache
    if (@key == 0) { @key = keys %{$this->{cache}}; }   # all
    $this->cachelog("write",undef,undef);
    foreach my $key (@key) { 
	if (exists $this->{cache}{$key}) {
	    $store{$key} = $this->{cache}{$key}; 
	}
	else {
	    delete $store{$key};
	}
    }
}

# clear all cache entries under a certain primary key
# (can pass a list of primary keys as params)

sub clear ($@) {
    my ($this,@clearkey) = @_;
    my $cname = $this->{cache_name};
    my @cleared_keys;
    foreach my $pkey (@clearkey) {
	# clear from soft cache
	foreach my $key (keys %{$this->{cache}}) {
	    if ($key =~ /^${cname}[\:\w]*:$pkey:/) {
		delete $this->{cache}{$key};
	    }
	}
	# clear from hard cache
	my $st = (tied %store);
	if ($config{cache}{persistent}) {
	    my @delkey;
	    foreach my $key (keys %store) {
		if ($key =~ /^${cname}[\:\w]*:$pkey:/) {
		    push @delkey, $key;
		}
	    }
	    if ($st) {
		# clear all keys at once, so we need only a single write lock
		$st->delete(@delkey);
	    }
	    else {
		# not persistent, but update the store copy anyway
		foreach my $key (@delkey) { delete $store{$key}; }
	    }
	}
    }
}

sub clear_key ($$) {
    my $this = shift;
    my $key = shift;
    delete $this->{cache}{$key};
    $this->update($key);
}

sub clear_all ($) {
    my $this = shift;
    my @cleared_keys;
    foreach my $key (keys %{$this->{cache}}) {
	push @cleared_keys, $key;
	delete $this->{cache}{$key};
    }
    $this->update(@cleared_keys);
}

# setup the key hash for this item

sub key {
    my $this = shift;
    my $tables = shift;
    # explicitly encode the tables to make it easier to invalidate cache items
    my $tkey = ref $tables eq "ARRAY" ? join ":", @$tables : $tables;
    # we used to use MD5 hashes, but this is faster:
    return $this->{cache_name}.":".$tkey.":".&array2text(@_);
}

# cache maintenance methods

# touch : renew expiry time for a cache item

sub touch {
    my ($this,@key) = @_;
    # WARNING: THIS FEATURE HAS BEEN DISABLED TO IMPROVE STORE PERFORMANCE
    # You can still call this, but it will have no effect.
    return;
}

# shutdown the cache

sub flush {
    my $this = shift;
    return;
}

=pod

=head1 ExSite::Cache

ExSite::Cache is a generic cache tool for saving re-useable data.

The cache is an in-memory hash of arbitrary data values.
The data can be indexed based on an arbitrary amount of
indexing data, so that the cache can store completely unrelated
data with low risk of collision.

The primary use in ExSite is to remember results of database
queries, so that we don't need to make a DB server call to
re-fetch something we've already fetched (but forgotten).

For instance, if you've fetched data record #123 from table XYZ,
you could save it in cache this way:

    my $cache = new ExSite::Cache;

    $cache->save($data,"XYZ","123");

The first value is the data to save;  the remaining values (there 
can be any number) are used to uniquely index the data.  In this case,
the table name and record number are sufficient to uniquely specify
this piece of data.

If later someone asks for the same data, eg:

    $db->fetch("XYZ",123);

then you could first check the cache for a value before querying the
the database:

    $data = $cache->get("XYZ",123);

    if (! $data) { # go to database...

In practice, all of the above is done automatically by the 
ExSite::DB class.

=head2 Cache Persistence

There are actually two caches that mirror each other, the soft cache
(which is the one that is used directly), and the hard cache (which is
where cache data is stored for persistence).  The soft cache is used
automatically; the hard cache is only effective if the persistent data
store (see ExSite::Store) is enabled.  If the persistent data store is
enabled, then the soft cache will initialize itself using the hard
cache.  Otherwise the soft cache will be empty at the start of each
request, and cached items will not be remembered by subsequent
requests.

Without the hard cache, cached items persist for the lifetime of the
current request only.

If the hard cache is enabled, cached items persist for the default
lifetime of items in the persistent data store.  This is 1 hour in the
default configuration.

If the hard cache is enabled, but you do not want your cached items to
persist, then you must set the following configuration setting:

    cache.persistent = 0

=head2 Invalidating Cached Items

Items in the cache are mirrors of original source items stored in a
slower data storage medium, such as a SQL database.  If the original
source changes, then the cached copies of those items are invalid and
should be cleared from the cache.

In practice, it is not feasible to know if any particular item has
been invalidated by any particular SQL query.  Instead we use a more
general rule, in which cached items are indexed under their table
names.  Any write operation that hits any of those tables will
invalidate cached items from those tables.  This is effected using
primary cache keys, below.

=head2 Cache Keys

You can provide any number of key values to index the data in the
cache.  These are combined together to give the aggregate hash key 
which is used to look up the data in future.

It is a good idea to append a unique ID for the database to the cache
keys, as this will keep cache entries from multiple database handles
separated in the cache.  Otherwise, you would have troubles connecting
to two ExSite databases simultaneously, since you could easily have
similar records in both (especially if one was a backup or archive of
the other).

=head3 Primary Cache Keys

The first of the key values provided is the primary key, which has a
special use.  All cache items that share a primary key are remembered,
and those cache items can be cleared at a stroke, using:

    $cache->clear("XYZ");

B<Example:> The purpose of this is to allow you to cache the results
of numerous queries, eg:

    select * from page where page_id=99
    select * from page where section_id=4 & type="template"

These 2 queries would result in at least 2 separate entries in the
cache, potentially with overlapping results.  They are both indexed
under the primary cache key "page".  At some later
time, if we updated some records in the page table, we might not know
if any of the data in the cache has now been superceded.  The safe
thing to do is expire all page entries in the cache:

    $cache->clear("page");

If you perform more complex queries involving joins of multiple tables, eg.

    select content_id,name from page,content where page.type="template" & content.page_id=page.page_id

Then you can index these under a compound primary key, by using an array
reference for your primary key, eg.

    $cache->save($data,["page","content"],...);

Then a request to clear either "page" OR "content" would clear that
cache entry.

If you do not want your cache data to be cleared based on its cache primary 
key, then use C<undef> as the primary key when saving, eg.

    $cache->save($data,undef,...);

You can also remove a single cache entry as follows:

    # remove it using original indexing data
    $cache->delete("XYZ",123);

    # remove it using cache key
    $cache->clear_key($key);

=cut

1;
