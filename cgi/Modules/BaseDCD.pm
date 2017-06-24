package Modules::BaseDCD;
#----------------------------------------------------------------------------
#
#   Copyright 2001-2004 Exware Solutions, Inc.  http://www.exware.com
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
#-----------------------------------------------------------------------

=pod

=head1 BaseDCD : a base Dynamic Content Driver

BaseDCD gives a simple framework on which all Dynamic Content Drivers
should be based.  It may be inherited by any Dynamic Content Driver that
wishes to pick up its generic methods as a starting point for
development.

The driver framework is modelled after the Unix device driver API, which
is a simple I/O framework that is easy to understand, and which will
already be familiar to many programmers.

There are 3 standard methods used by all drivers:

=over 4

=item read

acquire data from an external source (such as the URL, stdin 
[form input], a session manager, or database)

=item write

output data for insertion into a web page

=item ioctl

all operations that do not constitute either reads or writes
(eg. user authentication, updating a log file, sending email)

=back

Although DCDs may define other methods for internal use, only the above
three methods can be invoked directly by means of CMS tags.  The above
three methods may be thought of as the public driver methods.

The BaseDCD defines a set of generic DCD methods that can be
inherited by more advanced DCDs.  Generally speaking, the new()
constructor method is generic and may be reused by all DCDs.  The
read() method is fairly versatile, and should be adequate for parsing
most URLs and form input.  The write() method will almost certainly
need to be replaced with something appropriate to the DCD, as it is
the workhorse method in any CMS environment.  The ioctl() method,
while nominally useful here, serves more as an example of ioctl()
programming than as a useful piece of code.

In addition, the BaseDCD class defines a small set of utility functions 
that have proven to be generally useful for Plug-in development.

=cut

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Input;
use ExSite::Module;
use ExSite::URI;

# inherit from Base class
use ExSite::Base;
use vars qw(@ISA);
@ISA = qw(ExSite::Base);

# new : called implicitly once per page when a DCM is invoked

sub new {
    my $this = shift;
    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;

    # setup base object 
    $obj->initialize_object;

    # read the module configuration file
    $obj->read_conf;

    # automatically read the default input source
    $obj->read;

    # set ourselves as the current module
    $share{current_module} = $this->module_name;

    # call setup stub for special classes
    $obj->setup();

    return $obj;
}

# setup can be overloaded by DCDs that need special object configuration
# but don't want to overload new()
sub setup {
    return;
}

# read : called automatically by default new() to fetch input data
#        can optionally be invoked using <!--&Module.read(options)-->

sub read {
    my ($this,$opt) = @_;
    # fetch overlayed query and form input
    my $in = new ExSite::Input;
    $this->{input} = $in->combine;
}

# write : the default DCD call, invoked using <!--&BaseDCD(options)-->
#         or <!--&BaseDCD.write(options)-->  (these are synonymous).

sub write {
    my ($this,$options) = @_;

    # BaseDCD::write will almost certainly be overloaded by another
    # DCD, but we'll make it do something useful nonetheless:
    # report on the system configuration.

    my $out = "<h3>Exsite System Configuration</h3>
<ul>
<li> ExSite WebWare Version: ${ExSite::Config::VERSION}</li>
<li> Installation name: $config{site}{name}</li>
<li> Server: $config{server}{server}</li>
<li> Base HTdocs Directory: $config{server}{HTMLpath}</li>
<li> Base CGI Directory: $config{server}{CGIpath}</li>
<li> Administrator: $config{site}{administrator}</li>
<li> Configuration: ".($config{server}{auto} ? "automatic" : "manual")."</li>
</ul>

<h4>Plug-in Web Applications:</h4>

<ul>\n";
    foreach my $dcd (&ExSite::Module::module_list) {
	$out .= "<li>$dcd</li>\n";
    }
    $out .= "</ul>\n";
    return $out;
}

# ioctl : all operations that don't qualify as reads or writes
#         invoked as <!--BaseDCD.ioctl(request)-->
#
# This is typically invoked by ExSite to query the module for information
# about its capabilities.  We implement some generic queries here, as an
# example.

sub ioctl {
    my $this = shift;
    $_ = shift;   # $_ is the ioctl request
    if (/ModuleName/) {
	return $this->module_name;
    }
    elsif (/icon/i) {
	return $this->icon;
    }
    elsif (/isRestricted/) {
	return $config{$this->module_name}{isRestricted};
    }
    elsif (/isService/) {
	return $config{$this->module_name}{isService};
    }
    return 0;
}

# check for a config file, and load it if one exists and hasn't already
# been loaded.  Module name can optionally be forced;  this is useful 
# for modules that run as special cases of other modules, and share the
# other module's configuration.

sub read_conf {
    my ($this,$module) = @_;
    if (!$module) { $module = $this->module_name; }
    &ExSite::Module::read_conf($module);
}

# link - relink to DCD, with different args
#
# In simple case, modifies the query string args of the current URL
#
# For services (DCDs that are served by particular pages), it may also 
# redirect to a different page.
#
# For AJAX calls into a DCD, it may generate AJAX javascript calls 
# instead of a direct link.
#
# Whatever method is in effect, the output can be used as an anchor HREF.
#
# Some special URI features can be access using the following parameters
# with 2 leading underscores:
#
# __html         escape HTML entities in URL (default)
# __plaintext    do not escape HTML entities in URL
# __path         set PATH_INFO segments
# __secure       encrypt query parameters
# __uri          URI object for building links

sub link {
    my ($this,%opt) = @_;
    my ($uri,$url,$mode);
    if ($opt{__uri}) {
	$uri = $opt{__uri};
	delete $opt{__uri};
    }
    else {
	$uri = &get_obj("URI");
    }
    $uri->setup_output;
    $uri->update_path;
    #$uri->reset;    # don't reset, or we will reload our query string,
	             # which breaks on publishing
    # remove CMS parameters
    #$uri->parameter("_cms",undef);

    # redirect to a service page if necessary
    my $is_service = $this->ioctl("isService");
    if ($is_service) { $uri->service_page($this); }

    if ($share{ajax_target} && ! $is_service) {
	# This is an AJAX link - use Javascript to reload the module
	# and repopulate its HTML container element.
	#
	# NB: must load _ExSite/js/httprequest.js for this to work
	my $id = $share{ajax_target};
	my %oldargs = &DecodeString($share{ENV}{QUERY_STRING});
	my %ajaxopt = %opt;
	$ajaxopt{_ajax} = $id;
	$ajaxopt{_ref} = $oldargs{_ref};
	$ajaxopt{_opt} = $oldargs{_opt};
	$url = "$config{server}{CGIpath}/$config{prog}{dcd}/$id?".
	    &EncodeHash(%ajaxopt);
	return "javascript:subRequestData('$id','$url')";
    }
    else {
	# this is a normal normal hyperlink

	# optionally switch encoding modes
	if ($opt{__plaintext}) { 
	    $mode = "plaintext";
	    $uri->plaintext(); 
	    delete $opt{__plaintext};
	}
	elsif ($opt{__html}) { 
	    $mode = "html";
	    $uri->html(); 
	    delete $opt{__html};
	}

	if ($opt{__secure}) {
	    $uri->secure();
	}
	else {
	    $uri->insecure();
	}

	# change path info
	if ($opt{__path}) {
	    if (ref $opt{__path} eq "ARRAY") {
		# $opt{__path} == [$key, $path]
		$uri->path(@{$opt{__path}});
	    }
	    elsif (ref $opt{__path} eq "HASH") {
		foreach my $key (keys %{$opt{__path}}) {
		    $uri->path($key,$opt{__path}{$key});
		}
	    }
	    else {
		# scalar - overrides all path data
		$uri->path_info($opt{__path});
	    }
	    delete $opt{__path};
	}
	if ($opt{__clear}) {
	    my $query_data = $uri->get("query_data");
	    if ($query_data) {
		foreach my $key (keys %$query_data) {
		    $uri->parameter($key,undef);
		}
	    }
	    delete $opt{__clear};
	}

	# encode the URL
	$uri->query(%opt);
	$url = $uri->write($config{page}{dynamic_url_type});

	# restore mode
	if ($mode eq "plaintext") { 
	    $uri->html(); 
	}
	elsif ($mode eq "html") { 
	    $uri->plaintext(); 
	}
    }
    
    return $url;
}

# icon - return a URL to the icon for this DCD

sub icon {
    my $this = shift;
    my $theme = shift;
    my $name = (split /::/, ref $this)[-1];
    return &ExSite::Module::icon($name,$theme);
}

# return this module's name

sub module_name {
    my $this = shift;
    my $class = ref($this) || $this;
    my (undef,$name) = split /::/, $class;
    return $name;
}

sub whatami {
    my $this = shift;
    return $this->ioctl("ISA") || $this->module_name();
}

# return the section/site ID that we belong to

sub get_section_id {
    my $this = shift;
    if ($share{Section}) {
	return $share{Section}->id;
    }
    elsif ($share{Page}) {
	$share{Section} = $share{Page}->my_section();
	return $share{Section}->id;
    }
    else {
	# No page!  We're probably in a control panel...
	my $db = $share{DB};
	my @sites = $db->my_real_sites;
	my $in = $this->{input};
	if ($in->{section_id}) {
	    # a section ID has been explicitly passed, but we need to validate
	    foreach my $site (@sites) {
		if ($in->{section_id} == $site->{content_id}) {
		    # looks good
		    $share{Section} = new ExSite::Section(data=>$site);
		    return $in->{section_id};
		}
	    }
	}
	elsif ($in->{id}) {
	    # a content ID has been passed, but we need to validate
	    my $c = new ExSite::Content(id=>$in->{id});
	    my $s = $c->my_section();
	    my $sid = $s->id;
	    foreach my $site (@sites) {
		if ($sid == $site->{content_id}) {
		    # looks good
		    $share{Section} = new ExSite::Section(data=>$site);
		    return $sid;
		}
	    }
	}
	elsif ($in->{section_id} eq "0") {
	   return "0"; 
	}
	if (@sites == 1) {
	    $share{Section} = new ExSite::Section(data=>$sites[0]);
	    return $sites[0]{content_id};
	}
	elsif (@sites == 0) {
	    my $m = $db->my_user_record();
	    if ((ref $m) eq "HASH" && $m->{section_id}) {
		$share{Section} = new ExSite::Section(id=>$m->{section_id});
		return $m->{section_id};
	    }
	}
	# else: ambiguous - should probably ask using set_section_id()
    }
    return undef;
}

sub get_section {
    my $this = shift;
    my $section = new ExSite::Section();
    my $sid = $this->get_section_id();
    $section->setup(id=>$sid) if $sid;
    return $section;
}

# Set the section/site ID that we belong to.  This is useful in some
# control panels when it isn't obvious which site we are attached to, and
# the web application requires site-level data privacy.

sub set_section_id {
    my ($this,$name) = @_;
    $name or $name = "section_id";
    my $out;
    if (! $share{Page}) {
	my $ml = &get_obj("ML");
	# only output a site selector on control panels
	my $sid = $this->{input}{section_id} ? $this->{input}{section_id} : 0;
	my @sites = $share{DB}->my_real_sites;
	if ($sid) {
	    # already set, use a select element for economy of space
	    my $opt;
	    foreach my $s (@sites) {
		my $attr = { value=>$s->{content_id} };
		if ($s->{content_id} == $sid) { $attr->{selected} = undef; }
		$opt .= $ml->option($s->{label},$attr);
	    }
	    $out = 
		$ml->div(
		    $ml->form("Select website: ".
			      $ml->select(
				  $ml->option($msg{"== choose a site =="},{value=>"0"}).
				  $opt,
				  {name=>$name, onchange=>"document.forms[0].submit()"}
			      ),
			      {method=>"GET"}
		    ),
		    {class=>"section_selector"}
		);
	}
	else {
	    # not set; use a menu for more descriptiveness and fewer clicks
	    my $ui = &get_obj("UI");
	    my @link;
	    foreach my $s (@sites) {
		push @link, { label=>$s->{title}, size=>"l", url=>$this->link(section_id=>$s->{content_id}) };
	    }
	    $out .= $ml->h1("Select a website:").$ui->Menu(links=>\@link,size=>"l");
	}
    }
    
    return $out;
}

1;

