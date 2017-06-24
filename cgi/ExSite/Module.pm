package ExSite::Module;
#-----------------------------------------------------------------------
#
#   Copyright 2001-2009 Exware Solutions, Inc.  http://www.exware.com
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

#======================================================================

=pod

=head1 ExSite::Module

This package contains utility functions that are useful for managing 
and handling plug-in modules.

=cut

#======================================================================

use strict;
use integer;
use ExSite::Config qw(:DEFAULT &read_exsite_conf);
use ExSite::Misc;
use ExSite::Page;
use Exporter;

use vars qw(@ISA @EXPORT_OK);
@ISA = qw(Exporter);
@EXPORT_OK = qw(exists read_conf icon get_module module_list my_module_list
		site_license user_license service_page launcher_link);

sub exists {
    my ($modname) = @_;
    return (-e "$config{server}{CGIroot}/Modules/$modname.pm");
}

=pod

=head2 ExSite::Module::read_conf($module)

Looks for a config file in /cgi/conf/[MODULE].conf and if found, 
loads its parameters into $config{MODULE}{...}.

We try not to relead the config file if it has already been read.
We look for a C<_loaded> flag in the config data to tell us that the file
has already been read, and we set this flag if it is found.  This allows
us to hard-code default configurations (a la Config.pm) and then override
them with local config files.

=cut

sub read_conf {
    my $module = shift;
    return 0 if (!$module);
    my $read;
    if (! exists $config{$module} || ! exists $config{$module}{_loaded}) {
	# check persistent store
	my $conf = $store{"config:$module"};
	if ($conf) {
	    $config{$module} = $conf;
	    $read = 1;
	}
	else {
	    # load from original conf file
	    my $conffile = "./conf/${module}.conf";
	    if (-e $conffile) {
		&read_exsite_conf($conffile,$module);
		$config{$module}{_loaded} = 1;
		my $st = tied %store;
		if ($st) { $st->put("config:$module",$config{$module},0); }
		$read = 1;
	    }
	}
	if (exists $config{$module} && exists $config{$module}{"-"}) {
	    # module is attempting to override a global configuration
	    foreach my $global (keys %{$config{$module}{"-"}}) {
		&hashcopy($config{$module}{"-"}{$global}, $config{$global});
	    }
	    return $read;
	}
    }
    return 0;
}

=pod

=head2 ExSite::Module::read_dbmap($module)

If the plug-in defines its own DB map, we can read it here.

=cut

sub read_dbmap {
    my $module = shift;
    return 0 if (!$module);
    # name is something like dbmap/Module
    my $name = "$config{server}{$config{server}{db}{map}}{name}/$module";
    if ($share{DB} && -d $name) {
	my $map = new ExSite::DBmap(
				    name=>$name,
				    dbname=>$module,
				    );
	$share{DB}{map}->merge($map);
    }
}

=pod

=head2 ExSite::Module::icon($module,$iconset)

Looks for an icon graphic to represent the module.

First, we look in /_Modules/[MODULE] for a file called icon.gif or icon.png.
If none found, we look for /_Modules/icon.gif.

Icons are assumed to be 64x64 GIF or PNG graphics.

If C<$iconset> is defined, it is taken to be a suffix for the icon file,
eg. if C<$iconset = 'A'> then we look for C<iconA.png>. This allows us to
install different icon themes. We fall back on the default (null) iconset
if the theme is not supported by the plugin.

=cut

sub icon {
    my $module = shift;
    my $iconset = shift;
    my $icon = "$config{server}{HTMLpath}/_Modules/$module/icon${iconset}.png";
    if (! -e "$config{server}{HTMLroot}$icon") {
	$icon =~ s/\.png$/\.gif/;
    }
    if (! -e "$config{server}{HTMLroot}$icon") {
	# no icon; use default ExSite app icon
	if ($iconset) { 
	    # return default iconset
	    $icon = &icon($module); 
	}
	else {
	    # return generic icon
	    $icon = "$config{server}{HTMLpath}/_Modules/icon.gif";
	}
    }
    return $icon;
}

sub launcher_link {
    my ($module,$query) = @_;
    my $mod;
    if (ref $module) {
	$mod = $module;
	(ref $module) =~ /(\w+)$/;
	$module = $1;
    }
    else {
	$mod = &get_module($module);
    }
    return undef if (! $mod);
    my $href = $mod->ioctl("ControlPanel");
    if ($href) {
	# module has a control panel
	if (ref $href) {
	    # not an explicit URL
	    $href = "$config{server}{CGIpath}/$config{prog}{ctrlpanel}/$module";
	    if ($query) {
		$href .= "?$query";
	    }
	}
	if ($config{webtop}{popup_style} ne "tab") {
	    # open in popups
	    my $size = $mod->ioctl("Size") || "large";
	    $href = (ref $size eq "ARRAY") ?
		"javascript:popup_custom($size->[0],$size->[1],'$href')" :
		"javascript:popup_$size('$href')";
	}
    }
    return $href;
}

=pod

=head2 ExSite::Module::get_module($module,$auth,$site)

Instantiates a module, and returns an object.  Returns undef if the
user is not permitted to use the module.

$auth can be set to 1 to skip authorization checks (eg. if you are
pre-approving use of the module, or if you will be performing your own
authorization checks).  If allowing get_module to determine
authorization, you can pass $site (a section ID) to it to approve use
of the module on a particular site; otherwise, we look for a user
license.

If this routine returns undef, you can inspect $@ to determine the
reason.  If null, then the module instantiated but failed to
authorize; otherwise perl had a problem instantiating the module,
and $@ will contain the error message.

Once the module is instantiated, you can use standard module calls to
query the module and generate content, eg.

    $mod = &ExSite::Modules::get_module("MyMod");
    print $mod->write();

=cut

sub get_module {
    my ($module,$auth,$site) = @_;
    $module =~ s/\.pm$//;
    $module =~ s/^\w+:://;
    $module =~ /^(\w+)$/;
    my $safe_module = $1;
    my $stat = eval "require Modules::$safe_module"; 
    if ($stat) {
	# instantiate the module
	my $mod = eval "new Modules::$safe_module";
	if ($mod) {
	    # check for authorization
	    my $allow = 
		$auth ||
		(! $mod->ioctl('isRestricted')) || 
		($site ? &site_license($module,$site) : &user_license($module));
	    if ($allow) {
		$share{Module} = $mod;
		my $maploc = $mod->ioctl('ISA') || $safe_module;
		&read_dbmap($maploc);
		# also load the maps of any dependencies
		my $depend = $mod->ioctl('Dependencies');
		if ($depend) {
		    if (ref $depend ne "ARRAY") { 
			if ($depend eq "*") {
			    my @mod = &module_list();
			    $depend = \@mod;
			}
			else {
			    $depend = [$depend]; 
			}
		    }
		    foreach my $dep (@$depend) {
			&read_dbmap($dep);
		    }
		}
		return $mod;
	    }
	    else {
		&diagnostic("$module: permission denied (no license)");
	    }
	}
	else {
	    &diagnostic("$module: $@");
	}
    }
    else {
	&diagnostic("$module: $@");
    }
    return undef;
}

=pod

=head2 ExSite::Module::module_list()

Returns a list of name of modules that are installed on the system.

=cut

sub module_list {
    my @dcd;
    my $moddir = $config{server}{CGIroot} ?
	"$config{server}{CGIroot}/Modules" : "Modules";
    opendir MODDIR, $moddir;
    @dcd = readdir MODDIR;
    closedir MODDIR;
    @dcd = grep /\.pm$/, @dcd; # only accept Perl modules
    foreach (@dcd) { s/\.pm$//; }
    return sort @dcd;
}

=pod

=head2 ExSite::Module::my_module_list()

Returns a list of names of modules that are installed on the system, and 
which the user is authorized to use.

=cut

# my_module_list : return an array of DCD names available to the current site

sub my_module_list {
    my $section = shift;
    my $exclude = shift;
    #return undef if (!$section);
    my %hide = map { $_=>1 } @$exclude;
    my @dcd = &module_list;
    my @dcd_allow;
    foreach my $dcd (@dcd) {
	next if ($hide{$dcd});
	my $mod = &get_module($dcd,0,$section);
	if ($mod) {
	    push @dcd_allow,$dcd;
	}
    }
    return @dcd_allow;
}

=pod

=head2 ExSite::Module::site_license($module,$site)

Returns True/False (1/0) depending on whether the module is licensed
to be used on a the given site.  ($site should be a section ID.)

Modules require licenses if they respond True (1) to the "isRestricted"
ioctl query.  Otherwise, site licenses are granted automatically.

To grant a license, add a "service" record linking the module to the
website.

=cut

sub site_license {
    my ($module,$site) = @_;
    return 0 if (! $share{DB});
    my $mod = ref $module ? $module : &get_module($module,1);
    if ($mod) {
	if ($mod->ioctl("isRestricted")) {
	    # this service requires licenses
	    my $section_id = (!$site && $share{Page}) ? 
		$share{Page}->id("section") :
		&section_id($site);
	    if ($section_id) {
		my $licenses = $share{DB}->fetch_match("service",
						       {section_id => $section_id,
							name => $module }
						       );
		return (scalar @$licenses > 0);
	    }
	    # hmm, that's strange, we're not on a page
	    return 0;
	}
	# this modules is not a service - anyone can use it
	return 1;
    }
    # module does not seem to exist
    return 0;
}

=pod

=head2 ExSite::Module::user_license($module)

Returns True/False (1/0) depending on whether the module is licensed
to be used by a given user.

Modules require licenses if they respond True (1) to the
"isRestricted" ioctl query.  If so, a license must exist for this
Module on at least one of the user's web sites.

For modules that respond False (0) or do not respond to the
"IsRestricted" ioctl query, user licenses are granted automatically.

=cut

sub user_license {
    my $module = shift;
    my $db = $share{DB};
    return 0 if (! $db);
    if (! $share{licenses}) {
	$share{licenses} = {};
	if ($db->{dbtype} =~ /SQL/i) {
	    # use a join query to fetch all licensed services
	    my @services = $db->get_query("member services",$db->my_uid);
	    $share{licenses} = &keywise("name",\@services);
	}
	else {
	    # brute-force loop over all services/sites
	    my @sites = $db->my_real_sites();
	    foreach my $l ($share{DB}->fetch_all("service")) {
		foreach my $s (@sites) {
		    if ($l->{section_id} == $s->{section_id}) {
			$share{licences}{$l->{name}} = 1;
			next;
		    }
		}
	    }
	}
    }
    return (defined $share{licenses}{$module});
}

=pod

=head2 ExSite::Module::service_page($module,$site)

Returns a Page object representing the page on the site that will
be servicing the given module.  If there is no service page, returns undef.

If multiple services pages are defined for a module, it tries to select
the most appropriate one, as follows:

=over 4

=item * the service page whose version (language) matches the current page

=item * the service page in the default version/language

=item * the first service page found

=back

=cut

sub service_page {
    my ($module,$site) = @_;
    my $db = $share{DB};
    return 0 if (! $db);
    my @service = $db->fetch_match("service",{section_id=>&section_id($site),
					      name=>$module});
    # select best service page
    my $spage;
    if (@service == 0) {
	return undef;
    }
    elsif (@service == 1) {
	$spage = new ExSite::Page(id=>$service[0]{page_id});
    }
    else {
	my $default_page;
	foreach my $s (@service) {
	    my $p = new ExSite::Page(id=>$s->{page_id});
	    my $v = $p->get_my("language");
	    if ($share{Page} && $share{Page}->get_my("language") eq $v) {
		# service page of same version as current page
		$spage = $p;
		last;
	    }
	    elsif (! $v) {
		$default_page = $p; 
	    }
	}
	if (! $spage) {
	    # no service page with matching version
	    $spage = 
		$default_page ||     # use default service page
		$service[0];         # no default; use a random version
	}
    }
    return (ref $spage && $spage->id) ? $spage : undef;
}

=pod

=head2 ExSite::Module::control_panel($module)

Returns the URL to the module's control panel, if any.

=cut

sub control_panel {
    my ($module) = @_;
    my $mod = &get_module($module);
    my $panel = $mod->ioctl('ControlPanel');
    if (ref $panel eq "code") {
	return "$config{server}{CGIpath}/$config{prog}{ctrlpanel}/$module";
    }
    elsif ($panel) {
	return $panel;
    }
    return undef;
}

# convert various section refs to a section ID
sub section_id {
    my $site = shift;
    if ((ref $site) =~ /Section/) { return $site->id(); }
    elsif ((ref $site) eq "HASH") { return $site->{content_id}; }
    elsif (!$site && $share{Page}) { return $share{Page}->my_section->id; }
    else { return $site; }
}

1;
