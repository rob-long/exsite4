#!/usr/bin/perl

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Util;
use ExSite::Form;

&exsite_init;
my $db = new ExSite::Form();

# build a list of installed files known to ExSite

my @file = $share{DB}->custom_query("select data as file from cview where format='path'");
push @file, $share{DB}->custom_query("select answer.value as file from content,metadata,answer where content.type=21 and content.content_id=metadata.id and metadata.name='format' and metadata.value='file' and answer.question_id=content.content_id");

my @efile = map { $_->{file} } @file;

# build a list of real files in the file root

my @rfile;
my @dir = ( $config{server}{fileroot} );

while (my $dir = shift @dir) {
    opendir D, $dir;
    foreach my $file (readdir(D)) {
	next if ($file =~ /^\./);
	my $path = "$dir/$file";
	if (-d $path) {
	    push @dir, $path;
	}
	else {
	    push @rfile, $path;
	}
    }
    closedir D;
}

print scalar @efile, " files known to ExSite\n";
print scalar @rfile, " files found in the file repository\n";

my %rfile = map { $_ => 1 } @rfile;
foreach my $f (@efile) {
    if (exists $rfile{$f}) {
	delete $rfile{$f};
    }
    else {
	print "WARNING: file $f not found in the file repository\n";
    }
}

@file = sort keys %rfile;
if (scalar @file > 0) {
    print "\nUnlinked filese:\n";
    print join("\n",@file),"\n";

    print "\nPurge these files? [y/N] ";
    my $ans = <>;
    if ($ans =~ /^y$/i) {
	foreach my $f (@file) {
	    unlink $f;
	    print "removed $f\n";
	}
    }
}
else {
    print "\nNo files to purge.\n";
}



