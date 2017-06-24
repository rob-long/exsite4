#!/usr/bin/perl

use strict;
use ExSite::Config;
use ExSite::Crypt;
&exsite_init;        # get our default keys

use vars qw($key $text $decrypt $fast);

while (@ARGV) {
    $_ = shift @ARGV;
    if (/-k/) { $key = shift @ARGV; }
    if (/-f/) { $fast = 1; }
    elsif (/-d/) { $decrypt = 1; }
    else { $text = $_; }
}
my %opt = (key=>$key);
if ($fast) { $opt{mode} = "fast"; }
my $c = new ExSite::Crypt(%opt);
if ($decrypt) { print $c->decrypt($text); }
else { print $c->encrypt($text); }
print "\n";
