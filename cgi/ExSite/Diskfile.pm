#!/usr/bin/perl
#-----------------------------------------------------------------------
#
#   Copyright 2012 Exware Solutions, Inc.  http://www.exware.com
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

package ExSite::Diskfile;

### tools for manipulating files

### fixme: linkfile - deprecated??

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Image;
use ExSite::ML;
use ExSite::Util;
use MIME::Base64;

use vars qw(@ISA);
@ISA = qw(ExSite::Base);

# Attributes:
# base = base directory - this must pre-exist
# path = subdir of file - we can make these directories
# filename = name of file
# contents = raw file contents
# linkfile = existing file that should be linked to
# file = encoded filename + contents
# mimetype = MIME type of the file (optional, will be guessed from filename)

sub new ($%) {
    my ($this,%opt) = @_;
    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;
    $obj->initialize_object;
    $obj->setup(%opt);
    return $obj;
}

sub setup {
    my ($this,%opt) = @_;
    # clear previous state, in case we get re-used
    $this->clear();
    # copy options into object
    while (my ($key,$val) = each %opt) {
	$this->{$key} = $val;
    }
    if (! $this->{base}) {
	$this->{base} = "$config{server}{HTMLroot}$config{server}{HTMLpath}";
    }
    if (! $this->{path}) {
	$this->{path} = "/";
    }
    if ($this->{file}) {
	if (! $this->{filename} || ! $this->{contents}) {
	    my ($filename,$contents) = 
		split /$config{form}{sepchar}/,$this->{file};
	    $this->{filename} or $this->{filename} = $filename;
	    $this->{contents} or $this->{contents} = &decode_base64($contents);
	}
    }
}

sub clear {
    my $this = shift;
    foreach my $opt (keys %$this) { delete $this->{$opt}; }
    $this->{diagnostics} = {};
    $this->{diagnostics}{error} = [];
    $this->{diagnostics}{warn} = [];
    $this->{diagnostics}{info} = [];
}

sub filename {
    my $this = shift;
    return $this->{filename};
}

sub path {
    my $this = shift;
    return $this->{path};
}

sub diskpath {
    my $this = shift;
    return $this->{base}.$this->{path};
}

sub location {
    my $this = shift;
    if (! exists $this->{location}) {
	$this->{location} = $this->diskpath;
	if ($this->{location} !~ /\/$/) { $this->{location} .= "/"; }
	$this->{location} .= $this->filename;
    }
    return $this->{location};
}

sub contents {
    my $this = shift;
    if (! $this->{contents}) {
	if ($this->{file}) {
	    my ($filename,$contents) = 
		split /$config{form}{sepchar}/,$this->{file};
	    $this->{filename} = $filename;
	    $this->{contents} = &decode_base64($contents);
	}
	elsif ($this->exists) {
	    # no contents, but file exists
	    $this->{contents} = &get_file($this->location);
	}
	elsif ($this->{linkfile} && -e $this->{linkfile}) {
	    # read from linkfile
	    $this->{contents} = &get_file($this->{linkfile});
	}
    }
    return $this->{contents};
}

sub mimetype {
    my $this = shift;
    if (! exists $this->{mimetype}) {
	$this->{mimetype} = &MimeType($this->{filename});
    }
    return $this->{mimetype};
}

sub get_fileinfo {
    my $this = shift;
    my $size = length $this->contents;
    my $mime = $this->mimetype;
    my %info = (
	filename => $this->{filename},
	diskpath => $this->diskpath,
	mimetype => $mime,
	size_b => $size,
	size_kb => int($size/100)/10,
	size_mb => int($size/100000)/10,
	);
    if ($info{size_mb} > 1) { $info{size} = "$info{size_mb} MB"; }
    elsif ($info{size_kb} > 1) { $info{size} = "$info{size_kb} kB"; }
    else { $info{size} = "$info{size_b} bytes"; }
    # make a description
    $info{description} = $info{size} . " " . &MimeDescr($mime);
    return wantarray ? %info : \%info;
}

sub exists {
    my $this = shift;
    return $this->{filename} ? -e $this->location : 0;
}

# is_same_as : true, if the file contents are identical
# $f can be a path or a diskfile object

sub is_same_as {
    my ($this,$f) = @_;
    return ((ref $f) =~ /Diskfile/) ?
	$this->contents eq $f->contents :
	$this->contents eq &get_file($f);
}

# is_identical : true, if the two files point to the same inode
# (ie. an edit of one also changes the other)

sub is_identical {
    my ($this,$f) = @_;
    my $f1 = $this->location;
    my $f2 = ((ref $f) =~ /Diskfile/) ? $f->location : $f;
    my @stat1 = stat $f1;
    my @stat2 = stat $f2;
    return ($stat1[1] == $stat2[1]);
}

# ok is true if this is a complete file (location + contents)

sub ok {
    my $this = shift;
    return ($this->{base} &&
	    $this->{path} &&
	    $this->{filename} &&
	    ($this->{contents} || $this->exists));
}

# last_modified - set when the contents last changed, so we can skip publishing
# if it was published since then
# last_modified(date,format) - sets the last modified time
# last_modified() - returns the last modified time, in seconds ago

sub last_modified {
    my ($this,$datetime,$format) = @_;
    if ($datetime) {
	$this->{datetime} = $datetime;
	$this->{datetime_format} = $format || "sql_timestamp";
    }
    elsif ($this->{last_modified}) {
	return $this->{last_modified};
    }
    elsif ($this->{datetime}) {
	my $t = new ExSite::Time();
	$this->{last_modified} = - $t->diff($datetime,$format); # seconds ago
	return $this->{last_modified};
    }
    else {
	return undef;
    }
}

# $last_modified is a timestamp - 

sub is_published {
    my $this = shift;
    if ($this->exists) {
	my $fpath = $this->location;
	my $size = -s $fpath;
	if ($size == length $this->{contents}) {
	    # size is same, but also check dates
	    my $last_modified = $this->last_modified();
	    if ($last_modified &&
		$last_modified < int(((-M $fpath)+1) * 86400)) {
		# diskfile is older than the last modified time
		$this->info("$fpath already published");
		return 0;
	    }
	    return 1;
	}
	# different size (due to changed content OR template)
    }
    return 0;
}

# see if the path is writeable

sub can_publish {
    my $this = shift;
    if ($this->ok) {
	my $diskpath = $this->diskpath();
	if (-e $diskpath) {
	    return -w $diskpath;
	}
	else {
	    # path doesn't exist; find nearest path element that does exist
	    my @path = split /\//, $this->{path};
	    pop @path;
	    while (scalar @path) {
		my $subpath = $this->{base}.join('/',@path);
		if (-e $subpath) { return -w $subpath; }
		pop @path;
	    }
	}
	return 0;
    }
    return undef;
}

# publish: write the file contents to disk

sub publish {
    my ($this,$force) = @_;

    if ($this->ok) {
	if ($force || ! $this->is_published) {
	    my $diskpath = $this->diskpath();
	    if (! -e $diskpath) {
		if (! $this->mkdir($diskpath)) {
		    print $this->error("failed to create publication directory $diskpath: $!");
print join "\t","MEMUSAGE:", &memusage(), $this->location;
print "\n";
		    return;
		}
	    }
	    elsif (! -w $diskpath) {
		print $this->error("no permission to write to $diskpath: $!");
		return;
	    }
	    my $loc = $this->location;
	    my $dest = $this->safe_path($loc);
	    if (! $dest) {
		print $this->error("invalid filename: $loc");
	    }
	    elsif (open OUTFILE, ">$dest") {
		print OUTFILE $this->contents();
		close OUTFILE;
		my $ml = &get_obj("ML");
		my $file = $this->{path} eq "/" ? "/$this->{filename}" : "$this->{path}/$this->{filename}";
		print $ml->div($file,{class=>"publishedFile"});
		&diagnostic({level=>1,type=>"cms",message=>"Wrote $file"});
	    }
	    else {
		print $this->error("failed to publish to $loc: $!");
	    }
	}
    }
    else {
	print $this->warn("$this->{path}/$this->{filename}: no file to publish!");
    }
}


# remove the file associated with the content data

sub unpublish {
    my $this = shift;
    my $out;
    if ($this->{base} && $this->{path} && $this->{filename}) {
	if ($this->exists()) {
	    if (-w $this->diskpath) {
		my $dest = $this->safe_path($this->location);
		if (-e $dest) {
		    if (unlink $dest) {
			my $ml = &get_obj("ML");
			print $ml->div("$this->{path}/$this->{filename}",{class=>"unpublishedFile"});
			#$out .= "Removed ".$this->path."/".$this->filename;
			&diagnostic({level=>1,type=>"cms",message=>"Deleted ".$this->path."/".$this->filename});
		    }
		    else {
			print $this->error("Failed to remove $dest: $!");
		    }
		}
		else {
		    print $this->error("unpublish ".$this->path."/".$this->filename.": permission denied");
		}
	    }
	    else {
		print $this->error("no permission to write to ".$this->diskpath.": $!");
		return;
	    }
	}
	else {
	    # file is not there - not an error
	    $this->warn($this->filename.": file not found, cannot unpublish");
	}
    }
    else {
	print $this->error("incomplete file specification");
    }
    return $out;
}

# link: create an alternate instance of the same file, return its diskfile object

sub link {
    my ($this,$base,$path,$file) = @_;
    # $df is the new link
    my $df = new ExSite::Diskfile(
	base => $base,
	path => $path,
	filename => $file,
	);
    my $loc = $this->location;  # original file
    $loc =~ /(\/(\w[\w_\-\.\/]+)?)/;
    my $safeloc = $1;

    if (-e $safeloc) {
	# new link
	my $fullpath = $df->location;
	my $safepath = $this->safe_path($fullpath,"$config{server}{HTMLroot}$config{server}{HTMLpath}");
	if ($safepath) {
	    if (-e $safepath) {
		# link destination already exists!
		if ($this->is_identical($safepath)) {
		    # same file, phew!
		    return $df;
		}
		else {
		    print $this->error("failed to link $this->{path}/$this->{filename} to $path/$file: there is another file at this location");
		    print join("<br>\n",$this->{base},$this->{path},$this->{filename});
		    return undef;
		}
	    }
	    else {
		# do we need to create the directory?
		my $diskpath = $df->diskpath;
		if (! -e $diskpath) {
		    if (! $df->mkdir()) {
			print $this->error("failed to create publication directory $diskpath: $!");
			return;
		    }
		}
	    }
	    # all is good, link the file
#print "$loc -> $safepath<br>\n";	    
	    if (link($safeloc,$safepath)) {
		my $ml = &get_obj("ML");
		print $ml->div("$path/$file",{class=>"publishedFile"});
		&diagnostic({level=>1,type=>"cms",message=>"Linked $path/$file"});
		return $df;
	    }
	    else {
		print $this->error("failed to link $this->{path}/$this->{filename} to $path/$file");
		print &ShowHash($this);
	    }
	}
	else {
	    print $this->error("link $path: permission denied");
	}
    }
    else {
	print $this->error("cannot link to $loc: file not found");
    }
    return undef;
}

# unlink: remove alternate instance of file

sub unlink {
    my ($this,$base,$path,$file) = @_;
    # $df is the new link
    my $df = new ExSite::Diskfile(
	base => $base,
	path => $path,
	filename => $file,
	);
    my $fullpath = $df->location;
    my $safepath = $this->safe_path($fullpath,"$config{server}{HTMLroot}$config{server}{HTMLpath}");
    if ($safepath) {
	if (-e $safepath) {
	    # link destination already exists!
	    if ($this->is_identical($safepath)) {
		# same file, phew!
		unlink $safepath;
		my $ml = &get_obj("ML");
		print $ml->div("$path/$file",{class=>"unpublishedFile"});
		return 1;
	    }
	    else {
		print $this->error("failed to unlink $path/$file: not the same as ".$this->location);
	    }
	}
	else {
	    print $this->error("failed to unlink $path/$file: file not found");
	}
    }
    else {
	print $this->error("unlink $path/$file: permission denied");
    }
    return undef;
}

# install: installs a file in fileroot, and returns Diskfile object for it
# The file to install is this object, unless otherwise passed.
#
# options:
# file = encoded file (filename, data will be derived from this)
# tmpfile = actual file on disk
# filename, contents = raw file
# key = a unique key, to avoid filename collisions
# name = used to index the file under the fileroot
# uid = uid to run_publisher as
# auth = authorize to run as site owner
# base = install basedir ($config{server}{fileroot} by default)
# path = x/y/ by default, where x,y are first 2 chars of name
# subpath = create a subfolder under path to install the file

sub install {
    my ($this,%opt) = @_;
    my $filename = $opt{filename} || $this->{filename};
    my $data = $opt{contents} || $this->{contents};
    if (! $filename || ! $data) {
	if ($opt{file}) {
	    my ($encoded_filename, $encoded_data) = split /\#/, $opt{file};
	    $filename or $filename = $encoded_filename;
	    $data or $data = &decode_base64($encoded_data);
	}
	else {
	    my $tmpfile = $opt{tmpfile} || $this->{tmpfile};
	    my @path = split /\//, $tmpfile;
	    $filename or $filename = $path[-1];
	    $data or $data = &get_file($tmpfile);
	}
    }
    if ($filename && $data) {
	#my $clean_filename = $opt{key} . &clean_filename($filename);
	my $clean_filename = &clean_filename($filename);
	if ($opt{key}) {
	    # append the key to the filename to avoid collisions
	    if ($clean_filename =~ /\.\w{2,4}$/) {
		# filename has a suffix
		my @file = split /\./,$clean_filename;
		my $suffix = pop @file;
		push @file, $opt{key}, $suffix;
		$clean_filename = join ".",@file;
	    }
	    else {
		$clean_filename .= ".$opt{key}";
	    }
	}
	my $name = $opt{name} || $clean_filename;
	$name =~ s/\./_/g; # protect against . dirs
	my @filechars = split //, $name;
	if (scalar @filechars < 3) { push @filechars, "_", "_"; }
	my $base = $opt{base} || $config{server}{fileroot};
	my $path = $opt{path} || "/$filechars[0]/$filechars[1]";
	if ($opt{subpath}) {
	    $path .= "/$opt{subpath}";
	}
	my $f = new ExSite::Diskfile(base=>$base,
				     path=>$path,
				     filename=>$clean_filename,
				     contents=>$data);
	if ($f->exists) {
	    return $f if $this->is_same_as($f);  # not a real collision
	    # collision; might need to rename file
	    $clean_filename =~ /^(.+?)(\.(\d+))?(\.(\w{2,4}))?$/;
	    my $name = $1;
	    my $index = $3 || 1;
	    my $suffix = $5;
	    while ($f->exists) {
		return $f if $this->is_same_as($f);  # not a real collision
		# otherwise, change the filename
		$index++;
		$f->set("filename","$name.$index.$suffix");
	    }
	}
	if ($f->can_publish()) {
	    $f->publish();
	}
	elsif ($ENV{SCRIPT_NAME} =~ /publish/) {
	    # this is the publisher process, but we still don't have 
	    # permission to write
	    $this->error("Publish: publish tool does not have permission to install files.");
	    return undef;
	}
	else {
	    # write it to a tmp file, call the publisher
	    # don't re-use old tmpfile name or could grab any /tmp file
	    my $tmpfile = "$config{server}{temppath}/exsite-$clean_filename";
	    open F, ">$tmpfile" or return undef;
	    print F $data or return undef;
	    close F or return undef;
	    my $uid;
	    if ($opt{uid}) {
		$uid = $opt{uid};
	    }
	    elsif ($opt{auth}) {
		# no uid, but implicit permission granted
		if (! $share{DB}->is_executive) {
		    my $owner = $share{DB}->fetch_owner();
		    $uid = $owner->{$config{auth}{user_uid_column}};
		    $this->info("installing $clean_filename as UID $uid");
		}
		else {
		    $uid = $share{DB}->my_uid;
		}
	    }
	    else {
		$uid = $share{DB}->my_uid;
	    }
	    my $crypt = new ExSite::Crypt();
	    &run_publisher(args=>{install=>$crypt->encrypt($clean_filename)},
			   uid=>$uid);

	    ### fixme: use exec_method=>"run" so we can test for existence/success

	}
	return $f;
    }
    my $err = $! || "no file";
    &ExSite::Config::diagnostic("Diskfile::install: $err");
    return undef;
}

# utility for creating publication directories

sub mkdir {
    my $this = shift;
    my $dir = $this->{path};
    if (! $dir) {
	$this->error("mkdir: undefined directory");
	return undef;
    }

    my $out = " ";  # dummy return value

    {
	# new block to limit scope of $1
	$dir =~ /(\/(\w[\w_\-\.\/]+)?)/;
	if (! $1) {
	    $this->error("mkdir: malformed directory: $dir");
	    return undef;
	}
    }

    my $path = $this->{base};
    my @path = split(/\//,$dir);
    shift @path; # first one is a dummy
    my $secure_dir;
    foreach my $dir (@path) {
	$path .= "/$dir";
	#print "ROOT=$config{server}{HTMLroot}<br>\nPATH=$config{server}{HTMLpath}<br>\n";
	#print "<br>creating $path<br>\n";
	next if (-e "$path");

	{
	    # new block to limit scope of $1
	    # new directories must be in the system docs or data path
	    $secure_dir = $this->safe_path($path,"$config{server}{HTMLroot}$config{server}{HTMLpath}");
	    if (! $secure_dir) {
		# not an HTdocs dir, maybe a data file
		$secure_dir = $this->safe_path($path,$config{server}{dataroot});
	    }
	    if (! $secure_dir) { 
		# if you get this error, you are attempting to publish
		# outside the system HTdocs or data area.  You cannot create 
		# directories outside these areas for security reasons,
		# so if you want to publish there, you must create the 
		# directories manually, or clean the directory path using
		# safe_path()
		$this->error("mkdir: permission denied: directory '$path' is insecure");
		return undef;
	    }
	}
	
	$out .= "Creating site directory $dir... ";
	if (! mkdir "$secure_dir") {
	    $this->error("mkdir $dir: failed: $!");
	    return undef;
	}
	else {
	    $this->info("created site directory $dir");
	    $out .= "succeeded.";
	}
    }
    if ($out =~ /\S/) {
	my $ml = new ExSite::ML;
	return $ml->p($out);
    }
    return $out;
}

# utility for removing publication directories - also removes contents

### $dir can be full path, or partial path below the base
### if a full path, we remove the last dir
### if a partial path, we remove all of it

sub rmdir {
    my ($this,$dir) = @_;
    $dir or $dir = $this->{base} . $this->{path};
    if (! $dir) {
	$this->error("rmdir: undefined directory");
	return undef;
    }
    my $out = " ";  # dummy return value
    my $ml = new ExSite::ML;
    my $br = $ml->br();
    # can only remove directories in the HTMLpath
    my $secure_dir = $this->safe_path($dir,"$config{server}{HTMLroot}$config{server}{HTMLpath}");
    if (! $secure_dir) { 
	$this->error("rmdir: invalid directory: $dir");
	return undef;
    }
    elsif (-e $secure_dir) {
	opendir D,$secure_dir;
	my @files = readdir D;
	closedir D;
	foreach my $f (@files) {
	    next if ($f =~ /^\.\.?$/);
	    $f =~ /^(.+)$/;
	    my $secure_file = $secure_dir."/".$1;
	    if (-d $f) {
		# subdir; better remove it, too
		$out .= $this->rmdir("$dir/$f");
	    }
	    else {
		# must move unlink to its own if statement, or it causes
		# an insecure dependency error 
		if (unlink $secure_file) {
		    $out .= $ml->div("Removed ".$ml->span($f,{class=>"unpublishedFile"}));
		}
		else {
		    $this->error("rmdir: failed to remove $f: $! (you may be trying to remove directories that are not managed by ExSite)");
		    return undef;
		}
	    }
	}
	if (rmdir $secure_dir) {
	    $out .= $ml->div("Removed ".$ml->span($secure_dir,{class=>"unpublishedFile"}));
	}
	else {
	    $this->error("rmdir: failed to remove $secure_dir: $!");
	    return undef;
	}
#	if ($out =~ /\S/) {
#	    $out = $ml->li($out);
#	}
    }
    return $out;
}

sub safe_path {
    my ($this,$path,$safe_prefix) = @_;
    if (&is_tainted($path)) {
	# path is unsafe, so let's try to clean it
	$path =~ /^($safe_prefix(\/\w[\w\-\.]*)+)$/;
	return $1;
    }
    else {
	return $path;
    }
}

1;
