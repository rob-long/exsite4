package ExSite::Image;

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

### POD docs at end

use strict;
use MIME::Base64;
use IO::Handle;
use FileHandle;
use IPC::Open3;
use ExSite::Base;
use ExSite::Config;
use ExSite::Misc;

use vars qw(@ISA);
@ISA = qw(ExSite::Base);

sub new {
    my $this = shift;
    # objectify object
    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;
    return $obj->setup(@_);
}

sub setup {
    my $this = shift;
    if (@_ == 1) {
	($this->{filename},my $mimedata) = split /$config{form}{sepchar}/,shift,2;
	$this->{filedata} = &decode_base64($mimedata);
    }
    elsif (@_ == 2) {
	my @filepath = split /[:\\\/]/, shift;
	$this->{filename} = $filepath[-1];
	$this->{filedata} = shift;
    }
    else {
	$this->error("invalid image data");
	return undef;
    }
    # set our default thumbnail size
    $config{thumbnail_size} =~ /^(\d+)$/;
    $this->{thumbnail_size} = $1 || 100;
    return $this;
}

sub name {
    my $this = shift;
    return $this->{filename};
}

sub size {
    my $this = shift;
    return length $this->{filedata};
}

### FIXME: clashes with Base::info

sub info {
    my $this = shift;
    if (require Image::Info && require IO::String ) {
	my $fdata = $this->{filedata};
	my $info = &Image::Info::image_info(\$fdata);
	my @dim = &Image::Info::dim($info);
	$info->{_dim} = \@dim;
	return $info;
    }
    # no info tool, so let's kludge something up using convert
    if (&is_tainted($ENV{PATH})) { 
	$ENV{PATH} = $config{server}{securepath};
    }
    my $pid = open3(*W, *R, *E, "convert -verbose - -");
    print W $this->{filedata}; close W;
    # we have to read (and discard) stdout data before the stderr output
    # will be given to us
    while (<R>) { 1; } 
    close R;
    # now read stderr, which contains the -verbose data we want
    # expected output is something like:
    # /tmp/ABC123=>- GIF 239x239+0+0 PseudoClass 256c 8-bit 0.0u 0:01
    my $imgdata = <E>; close E; 
    waitpid $pid, 0; # perlipc recommends this to avoid zombies
    my @imgdata = split / /,$imgdata;
    $imgdata[2] =~ / ([\d]+)x([\d]+)/;
    my $ext = lc($imgdata[1]);
    return {
	file_ext => $ext,
	file_media_type => &MimeType("dummy.$ext"),
	width => $1,
	height => $2,
    }
}

sub web_ready {
    my $this = shift;
    my $mimetype = &MimeType($this->{filename});
    if ($mimetype =~ /image\/(gif|png)/) {
	# GIFs and PNGs are all good, IE PNG bugs notwithstanding
	return 1;
    }
    elsif ($mimetype =~ /image\/jpeg/) {
	# JPGs might be RGB (good) or CMYK (bad on many browsers)
	my $info = $this->info;
#	return $info->{color_type} =~ /CMYK|YCbCr/i ? 0 : 1;
	return $info->{color_type} =~ /CMYK/i ? 0 : 1;
	#
	# !!! WARNING !!!
	# Note that if Image::Info is not installed, $info will not 
	# contain a color_type entry.  In that case, the above statement
	# returns true, which is correct MOST of the time.  If you need
	# it to be true ALL of the time, make sure you install Image::Info.
	#
    }
    else {
	# unrecognized image format
	return 0;
    }
}

sub dim {
    my $this = shift;
    my ($info,$h,$w);
    $info = $this->info;
    if ($info->{_dim}) {
	return @{$info->{_dim}};
    }
    # untaint height and width
    {
	$info->{width} =~ /^(\d+)$/;
	$w = $1;
    }
    {
	$info->{height} =~ /^(\d+)$/;
	$h = $1;
    }
    return ($w,$h);
}

sub crop_parameter{
    my ($this,$type,$old1,$old2,$new1,$new2) = @_;
    require POSIX;
    my $out;
    my $resize_ratio = $old1 / $new1;
    my $resize1 = $old1;
    my $resize2 = POSIX::ceil($new2 * $resize_ratio);
    my $offset = 0;
    if ($old2 >= $resize2){
	$offset = POSIX::ceil(($old2 - $resize2) / 2);
	$out = " -crop";
	if ($type =~ /x/i){
	    $out .= " ${resize1}x${resize2}";
	    $out .= "+0+${offset}";
	}else{
	    $out .= " ${resize2}x${resize1}";
	    $out .= "+${offset}+0";
	}
	
    }else{
	$resize_ratio = $old2 / $new2;
	$resize2 = $old2;
	$resize1 = POSIX::ceil($new1 * $resize_ratio);
	$offset = POSIX::ceil(($old1 - $resize1) / 2);
	$out = " -crop";
	if ($type =~ /x/i){			
	    $out .= " ${resize1}x${resize2}";
	    $out .= "+${offset}+0";
	}else{
	    $out .= " ${resize2}x${resize1}";
	    $out .= "+0+${offset}";	
	}
    }
    return $out;
}

sub scale_crop{
    my ($this,$x,$y,$optional_param) = @_;
    # Make sure $x and $y are integers
    if ($x !~ /^(\d+)$/){
	$x = 0;
    }
    else {
	$x = $1;
    }
    if ($y !~ /^(\d+)$/){
	$y = 0;
    }
    else {
	$y = $1;
    }
    # You can't create a image with 0 width or height
    return if !$x || !$y;
    
    # Original image size
    my ($width,$height) = $this->dim();	
    
    # Divide by 0 prevention
    if ($width <= 0 || $height <= 0){
	return; 
    }
	
    # Resize image	
    my $scalex = 0;
    my $scaley = 0;
    my $scale_param = " -resize";
    if ($width <= $height){
	$scalex = $x;
	$scaley = int($height * ($x / $width));
	$scale_param .= " ${x}x";
    }else{
	$scalex = int($width * ($y / $height));
	$scaley = $y;
	$scale_param .= " x${y}";
    }
    
    # Crop image
    my $crop_param;
    if ($x >= $y){
	$crop_param = $this->crop_parameter("x",$scalex,$scaley,$x,$y);
    }else{
	$crop_param = $this->crop_parameter("y",$scaley,$scalex,$y,$x);
    }
    
    my $convert_param = "${scale_param}${crop_param} +profile '*'";
    if ($optional_param){
	# taint check this before you use it!
	$convert_param .= " $optional_param";
    }
    
    return $this->convert($convert_param);
}

sub square_thumb{
	my ($this,$size) = @_;	
	my $thumb_size = $size || $this->{thumbnail_size};
	return $this->scale_crop($thumb_size,$thumb_size);
}

# Create a black and white thumbnail
sub square_thumb_bw{
	my ($this,$size) = @_;
	my $thumb_size = $size || $this->{thumbnail_size};
	return $this->scale_crop($thumb_size,$thumb_size,"-modulate 100,0,100");
}

sub scale_thumb_by_width{
	my ($this,$size,$flag) = @_;
	return if ($size == 0);
	my $x = $size || $this->{thumbnail_size};
	# make sure we have clean dimensions to work with
	my ($w,$h) = $this->dim;
	if ($w) {
	    my $y = int($h / ($w/$size));
	    return $this->scale($x,$y);
	}
	return 0;
}

sub scale_thumb_by_width_bw{
    my ($this,$size,$flag) = @_;
    return if ($size == 0);
    my $x = $size || $this->{thumbnail_size};
    # make sure we have clean dimensions to work with
    my ($w,$h) = $this->dim;
    my $y = int($h / ($w/$size));
    return $this->scale($x,$y,undef,"-modulate 100,0,100");
}

sub scale_thumb_by_height{
	my ($this,$size,$flag) = @_;
	return if ($size == 0);
	my $y = $size || $this->{thumbnail_size};
	# make sure we have clean dimensions to work with
	my ($w,$h) = $this->dim;
	my $x = int($w / ($h/$size));
	return $this->scale($x,$y);
}
sub scale_thumb_by_height_bw{
	my ($this,$size,$flag) = @_;
	return if ($size == 0);
	my $y = $size || $this->{thumbnail_size};
	# make sure we have clean dimensions to work with
	my ($w,$h) = $this->dim;
	my $x = int($w / ($h/$size));
	return $this->scale($x,$y,undef,"-modulate 100,0,100");
}

sub scale {
    my ($this,$x,$y,$flag,$optional_parameter) = @_;

    # $x, $y: target size
    # $flag: -1 to scale down
    # $optional_parameter: additional arguments you would like to add to the 
    # convert shell command (do your own taint-checking!)

    # Input checks
    if ($x !~ /^\d+$/) { $x = 0; } 
    if ($y !~ /^\d+$/) { $y = 0; }
    # taint-check our sizes
    $x =~ /^(\d+)$/;
    $x = $1;
    $y =~ /^(\d+)$/;
    $y = $1;
    my $geom = "${x}x${y}";
    if ($flag > 0) { $geom .= '\<'; }
    elsif ($flag < 0) { $geom .= '\>'; }
    
    my $convert_params = "-geometry $geom +profile '*'";
    if ($optional_parameter) {
	if (&is_tainted($optional_parameter)) {
	    $this->error("insecure image conversion: $optional_parameter");
	}
	else {
	    $convert_params .= " $optional_parameter";
	}
    }
    return $this->convert($convert_params);
}

sub resize {
    my ($this,$x,$y) = @_;
    # $x, $y: target size
    # Unlike scale(), this forces the image to exactly the given size.
    # Input checks
    if ($x !~ /^\d+$/) { $x = 0; } 
    if ($y !~ /^\d+$/) { $y = 0; }
    # taint-check our sizes
    $x =~ /^(\d+)$/;
    $x = $1;
    $y =~ /^(\d+)$/;
    $y = $1;
    my $convert_params = "-resize ${x}x${y}! +profile '*'";
    return $this->convert($convert_params);
}

# shortcut for thumbnailing - $size is optional

sub thumb {
    my ($this,$size) = @_;
    my $thumbdim = $size || $this->{thumbnail_size};
    my ($x,$y) = $this->dim;
    # don't thumbnail if the image is already small
    return 0 if ($x < $thumbdim && $y < $thumbdim);
    return $this->scale($thumbdim,$thumbdim,-1);
}

# reduce image size
#
# options:
# dim => max x or y dimension  (default 500)
# height => max y dimension  (default 500)
# width => max x dimension  (default 500)
# size => max file size (K)  (default 48)

sub shrink {
    my ($this,%opt) = @_;

    my $shrunk = 0;
    my $info = $this->info;
    my $max_height = $opt{height} || $opt{dim} || 500;
    my $max_width = $opt{width} || $opt{dim} || 500;
    my $max_size = $opt{size};
    my $npass = 0;  # abort after 5 attempts to shrink

    while (! $shrunk && $npass < 5) {
	if ($info->{width} > $max_width || $info->{height} > $max_height) {
	    $this->scale(int($max_width),int($max_height),-1,"-quality 60");
	}
	my $size = $this->size;
	if ($max_size && $size > $max_size * 1024) {
	    # file size too large; scale dimensions
	    my $proportional_difference = ($max_size * 1024) / $size;
	    my $scale_proportion = $proportional_difference < 0.8 ?
		$proportional_difference : 0.8;
	    $max_width *= $scale_proportion;
	    $max_height *= $scale_proportion;
	}
	else {
	    $shrunk = 1;
	}
	$npass++;
    }
    return $shrunk;
}

# convert the image to a web-friendly JPEG format
# Even for files that are already JPEGs, this may be handy, since it
# strips out profiles, forces RGB (instead of CMYK), and sets a 
# lower quality level than most cameras use.

sub jpeg {
    my ($this) = @_;
    return $this->convert("-colorspace RGB -quality 75 +profile '*'",
			  "-","jpeg:-");
}

# run all image processing directives through the external convert program

sub convert {
    my ($this,$parameters,$infile,$outfile) = @_;

    if (!$infile) { $infile = "-"; }
    if (!$outfile) { $outfile = "-"; }

    # we DO NOT taint-check any of our parameters, so this will fail if you use
    # it carelessly.  Taint-check your own parameters before calling this.

    my $convert_command = "convert $parameters $infile $outfile";
    
    if (&is_tainted($ENV{PATH})) { 
	$ENV{PATH} = $config{server}{securepath};
    }
    my $pid = open3(*W, *R, *E, $convert_command);
    print W $this->{filedata}; close W;
    my $newdata;
    my $size = 0;
    my $continue = 1;
    while ($continue) {
	$continue = read(R,$newdata,1024,$size);
	$size += $continue;
    }
    $this->{filedata} = $newdata;
    close R;
    if (! $size) {
	# no data - check for error messages
	my @err = <E>;
	if (@err > 0) { $this->error(@err); }
    }
    close E;
    waitpid $pid, 0;  # anti-zombie magic spell
    return $size;     # non-zero result means some sort of output was received
}

# return raw image data to user

sub get () {
    my ($this,$key) = @_;
    return $key ? $this->SUPER::get($key) : $this->{filedata};
}

# encode image data in exsite format (filename#mime_data)

sub encode {
    my $this = shift;
    my $fname = &url_escape($this->{filename});
    return $fname.$config{form}{sepchar}.&encode_base64($this->{filedata},"");
}

1;

=pod

=head1 ExSite::Image - image manager

Provides a few basic image management tools for the ExSite CMS.
This is just a simple wrapper/API to whatever underlying image processing
tools are going to do the heavy lifting, so it is easy to replace or
extend with more powerful tools if needed.

This version tries to use Image::Info for fetching image attributes,
and the convert shell command for modifying the image itself.  NB: the
convert command is part of the ImageMagick suite; so we could have
just used the ImageMagick perl module instead.  But the functions we
require are relatively simple, so the massive ImageMagick module is a
bit redundant for now.

To start working with a new image:

    my $img = new ExSite::Image($name,$rawdata);   # OR
    my $img = new ExSite::Image($encoded_data);

To get the image attributes:

    my $info = $img->info;  # $info is a hash ref

To get the image size:

    my ($x,$y) = $img->dim;

There are two ways to change the image size: C<scale()> (maintains
aspect ratio) and C<resize()> (ignores aspect ratio).

To scale the image size:

    my $stat = $img->scale(500,500,$flag);  

    # $flag > 0   scale up to that size, if smaller
    # $flag == 0  scale to that size
    # $flag < 0   scale down to that size, if larger
    # retain aspect ratio in all cases

To scale the image to exactly the passed dimensions (the edges may
get cropped to achieve the new dimensions without distorting the
original image):

    my $imgdata = $img->scale_crop($x,$y);
   
    # $x: image width
    # $y: image height

To thumbnail an image (preserve aspect ratio):

    my $stat = $img->thumb;  # equivalent to $img->scale(100,100,-1);  

To get a square thumbnail (some cropping may be involved):

    my $imgdata = $img->square_thumb($width);

To force an exact resize without regard to aspect ratio, use resize:

    my $stat = $this->resize($newwidth,$newheight);
   
To get image raw data:

    my $imgdata = $img->get();

To get image data in exsite binary file encoding format:

    my $imgdata = $img->encode;

To get the size of the image data in bytes:

    my $nbyte = $img->size;

To shrink the file size of the image:

    $img->shrink(%opt);

You can pass the following options in the hash: C<width>, C<height>
(maximum width and height of the image), C<dim> (maximum width OR
height), and C<size> (maximum file size in kilobytes).  

In all cases, the quality of the image is set to 75% (mostly
meaningful for JPGs), which will help shrink high-quality photos for
web presentation without appeciable loss in quality.  C<shrink()> also
strips any profiles out of the image.

With C<width>, C<height>, and C<dim>, the image is scaled down to reduce
its size.  With C<size>, the image is further scaled until it falls below
the given C<size>.  However, if after 5 iterations, it cannot be shrunk
to the requested size, it stops and returns what it has at that point.
A return code of 1 is returned if the size objective is met; 0 otherwise.

=head2 Preparation of Images for the Web

Only GIF, PNG, and a subset of JPG images are widely accepted by
browsers.  Some JPGs are not web-friendly (namely ones with CMYK color
encoding).

To test whether this is a web-ready image:

    if ($img->web_ready) { ...

If the image is not web ready, then you can convert it to a web-ready JPG
format:

    $img->jpeg();

This can be used as a function call, if you prefer;  it returns the number
of bytes in the new JPEG file if the conversion succeeded, 0 if not.

The other thing that is often needed to prepare web images is just to
scale them to a reasonable size.  Images from digital cameras tend to
be too large for web display, and images may also be large in terms of
file size due to high quality settings, embedded profiles, and other
factors.  

You can use the scale function to force the image dimensions down to a 
specific size, or you can use the shrink function to set upper limits on 
both image dimensions and file size:

    $img->shrink(
                 height => 500,
                 width => 300,    
                 dim => 400,      # used if height or width is not specified
                 size => 40,      # kilobytes
                );

If an image was uploaded in a non-lossy format like PNG, then the file
size might be shrinkable much farther if converted to a JPEG first.
However, for some types of line art, PNG and GIF can give excellent
compression.

=cut

