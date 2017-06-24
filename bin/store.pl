#!/usr/bin/perl
#-----------------------------------------------------------------------
#
#   Copyright (C) 2008 Exware Solutions, Inc.  http://www.exware.com
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
#------------------------------------------------------------------------
#
#   store.pl - utility for command line management of the persistent
#              data store
#
#   Parameters:
#
#   --clear    delete all store entries
#   --conf     display store configuration
#   --keys     list item names
#   --list     list all items with their expiry times and sizes
#   --purge    delete expired store entries
#   --rebuild  reclaim disk space from deleted items
#   --reset    reinitialize the store
#   --restart  clear reloadable entries like config, dbmap, cache
#   other      display a particular item by name
#
#------------------------------------------------------------------------

use strict;
use Local;
use ExSite::Store;
use Devel::Size qw(size total_size);
use GDBM_File;
use Cwd;
use Storable qw(freeze);

use vars qw($conf $store %store $depth $indent $init);
$depth = 0;
$indent = "    ";

while ($_ = shift) {
    if (/^--reset$/) { 
	# reinitialize the store
	&reset();
    }
    else {
	&init;
	if (/^--clear$/) { 
	    # delete all items from the store
	    &clear();
	}
	elsif (/^--restart$/) { 
	    # delete all reloadable items from the store
	    &restart();
	}
	elsif (/^--conf$/) { 
	    # show the current store configuration
	    &showconf();
	}
	elsif (/^--purge$/) { 
	    # delete expired items from the store
	    &purge();
	}
	elsif (/^--rebuild$/) { 
	    # reclaim disk space from deleted items
	    &rebuild();
	}
	elsif (/^--keys$/) { 
	    # list all the item keys
	    &showkeys();
	}
	elsif (/^--list$/) { 
	    # list all the items with expiry times and sizes
	    &list();
	}
	else {
	    # display a specific item
	    &show($_);
	}
    }
}

sub init {
    return if ($init);
    eval { $conf = Local::store_conf(); };
    if ($@) {
	print "Persistent data store not enabled.  Reason:\n$@";
	die;
    }
    $conf->{novalidate} = 1;
    $store = tie %store, 'ExSite::Store', $conf;
    die "Persistent data store not enabled" if (!$store);
    $init = 1;
}

sub reset {
    my %st;
    eval { $conf = Local::store_conf(); };
    if ($@) {
	print "Persistent data store not enabled.  Reason:\n$@";
	die;
    }

    # create new store

    tie %st, 'GDBM_File', $conf->{name}, &GDBM_NEWDB, 0666
	or die "failed to create store ($!)";
    print "opened new store\n";

    # define the store ID

    my $id = { data => cwd, ptime=>time, etime=>0 };
    $st{_id} = freeze $id;
    print "set store id\n";

    # create new lock file

    if ($conf->{lock} && ! -e $conf->{lock}) {
	open LOCK,">$conf->{lock}" 
	    or die "cannot create lock file ($!)";
	close LOCK;
	print "created store lock file\n";
    }

    &set_permissions;
}

sub set_permissions {
    chmod 0666, $conf->{name}
    or die "cannot make store world writeable ($!)";
    if ($conf->{lock}) {
	chmod 0666, $conf->{lock}
	or die "cannot make lock file world writeable ($!)";
    }
    print "set store permissions\n";
}

sub clear {
    # internal reset is just a clear
    $store->reset();
}

sub purge {
    $store->purge();
}

sub rebuild {
    $store->rebuild();
    &set_permissions();
}

sub restart {
    my @key = sort keys %store;
    foreach my $key (@key) {
	next if ($key !~ /^(cache|config|dbmap):/);
	delete $store{$key};
    }
}

sub showconf {
    print &ShowHash(&Local::store_conf());
}

sub show {
    my $key = shift;
    my $val = $store->getraw($key);
    my $life = $val->{etime} ? $val->{etime} - time : 0;
    print "$key (${life}s) => \n";
    print &ShowList(ref $val->{data} eq "ARRAY" ?
		    @{$val->{data}} : $val->{data});
}

sub list {
    my @key = sort keys %store;
    foreach my $key (@key) {
	my $val = $store->getraw($key);
	my $life = $val->{etime} ? $val->{etime} - time : 0;
	print "$key (${life}s) => ";
	print total_size($val->{data});
	print " bytes\n";
    }
}

sub showkeys {
    print join("\n",sort keys %store);
    print "\n";
}

sub ShowHash {
    my $hash;
    if ($#_ > 0) { my %h = @_; $hash = \%h; }
    else { $hash = shift; }
    if (ref $hash !~ /HASH/) {
	return "Not a hash reference: $hash";
    }
    $depth++;
    my $out;
    foreach my $key (keys %{$hash}) {
	$out .= ($indent x $depth)."[$key] => ";
	if ($hash->{$key} =~ /HASH/) {
	    $out .= "\n";
	    $out .= &ShowHash($hash->{$key});
	} 
	elsif ($hash->{$key} =~ /ARRAY/) {
	    $out .= "\n";
	    $depth++;
	    $out .= &ShowList(@{$hash->{$key}});
	    $depth--;
	} 
	else {
	    my $val = $hash->{key};
	    if (length $val > 100) { $val = substr($val,100,0)."..."; }
	    my $data = "\"$hash->{$key}\"";
	    $out .= $data;
	    $out .= "\n";
	}
    }
    $depth--;
    return $out;
}

sub ShowList {
    my $out;
    my $i = 0;
    foreach my $item (@_) {
	my $data;
	if (ref $item eq "HASH") {
	    $data = &ShowHash($item);
	}
	elsif (ref $item eq "ARRAY") {
	    $depth++;
	    $data = &ShowList(@$item);
	    $depth--;
	}
	elsif (ref $item eq "SCALAR") {
	    $data = "[SCALAR] $$item";
	}
	else {
	    $data = $item;
	}
	$out .= ($indent x $depth)."[$i] => $data\n";
	$i++;
    }
    return $out;
}

