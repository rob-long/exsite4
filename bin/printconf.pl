#!/usr/bin/perl
#-----------------------------------------------------------------------
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
#----------------------------------------------------------------------------
#   printconf.pl         : dumps all %config settings to stdout
#   printconf.pl MODULE  : dumps %config settings for MODULE
#   printconf.pl -a      : dumps all system and module config settings
#----------------------------------------------------------------------------

use strict;
use ExSite::Config;
use ExSite::Module qw(&module_list &read_conf);
use vars qw(@key);

&exsite_init;

my @modules = @ARGV;
if ($modules[0] eq "-a") {
    @modules = &module_list;
}
if (@modules > 0) {
    foreach my $modname (@modules) {
	&read_conf($modname);
    }
}
&scanconf(%config);

sub scanconf {
    my %c = @_;
    foreach my $k (sort keys %c) {
	if ($ARGV[0] ne "-a" && @modules > 0) {
	    my ($param,undef) = split /[\.=\s]/,$k;
	    next if (grep(/^$param$/,@modules) == 0);
	}
	push @key, $k;
	if (ref $c{$k} eq "HASH") {
	    &scanconf_r(%{$c{$k}});
	}
	elsif (ref $c{$k} eq "ARRAY") {
	    for (my $i=0; $i<=$#{$c{$k}}; $i++) { 
		print join(".",@key).".[$i]=".$c{$k}[$i]."\n";
	    }
	}
	else {
	    print join(".",@key)."=".$c{$k}."\n";
	}
	pop @key;
    }
}	

sub scanconf_r {
    my %c = @_;
    foreach my $k (sort keys %c) {
	push @key, $k;
	if (ref $c{$k} eq "HASH") {
	    &scanconf_r(%{$c{$k}});
	}
	elsif (ref $c{$k} eq "ARRAY") {
	    for (my $i=0; $i<=$#{$c{$k}}; $i++) { 
		print join(".",@key).".[$i]=".$c{$k}[$i]."\n";
	    }
	}
	else {
	    print join(".",@key)."=".$c{$k}."\n";
	}
	pop @key;
    }
}	

