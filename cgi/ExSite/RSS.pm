package ExSite::RSS;

#----------------------------------------------------------------------------
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
#-----------------------------------------------------------------------

=pod

=head1 RSS.pm

All-purpose simple RSS feed generator.

=head2 Usage:

Create the feed (the channel descriptors are accepted without validation, 
so you must ensure they are correct):

    my $rss = new ExSite::RSS(title=>"My Feed",description=>"foo",link=>"http://myfeed.com/");

You can also specify channel descriptors separately.  This is slightly
better, because the parameters are validated and made XML-friendly.

    my $rss = new ExSite::RSS;
    $rss->title("My Feed");
    $rss->description("foo");
    $rss->link("http://myfeed.com/");

Add items to the feed.  The parameters are title, description, link.

    $rss->item("1st Title","1st description","http://myfeed.com/1");
    $rss->item("2nd Title","2nd description","http://myfeed.com/2");
    $rss->item("3rd Title","3rd description","http://myfeed.com/3");

Output the feed:

    print $rss->write;

Clear the feed so you can start over:

    $rss->clear;

=cut

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::ML;
use ExSite::Base;

use vars qw(@ISA);
@ISA = qw(ExSite::Base);

sub set {
    my ($this,$key,$val) = @_;
    $val =~ s/&/&amp;/g;
    $this->{$key} = $val;
    return;
}

sub title {
    my ($this,$val) = @_;
    $this->set("title",$val);
}

sub description {
    my ($this,$val) = @_;
    $this->set("description",$val);
}

sub link {
    my ($this,$val) = @_;
    if ($val !~ /^https?:/) { $val = $config{server}{server}.$val; }
    $this->set("link",$val);
}

sub item {
    my $this = shift;
    my $item;
    if (scalar @_ == 1) {
	$item = shift;
    }
    else {
	$item = {};
	$item->{title} = shift;
	$item->{description} = shift;
	$item->{link} = shift;
	$item->{pubDate} = shift;
    }
    if (! $this->{items}) { $this->{items} = []; }
    $item->{title} = $this->clean($item->{title});
    $item->{description} = $this->clean($item->{description});
    #$item->{link} =~ s/&/&amp;/g;
    if ($item->{link} !~ /^https?:/) { $item->{link} = $config{server}{server}.$item->{link}; }
    push @{$this->{items}}, { 
	title=>$item->{title}, 
	description=>$item->{description}, 
	link=>$item->{link},
	pubDate=>$item->{pubDate},
	author=>$item->{author},
    };
}

sub clear {
    my $this = shift;
    $this->{title} = undef;
    $this->{description} = undef;
    $this->{items} = undef;
}

# use ML for consistent markup
sub write {
    my $this = shift;
    my $rss = new ExSite::ML(xml=>1);
    $rss->Doctype("<?xml version=\"1.0\" encoding=\"$config{charset}\" ?>");
    $rss->_Element("title",$this->{title});
    $rss->_Element("description",$this->{description});
    $rss->_Element("link",$this->{link});
    if (ref $this->{items} eq "ARRAY" && 
	@{$this->{items}} > 0) {
	foreach my $item (@{$this->{items}}) {
	    my $rssitem =  $rss->Element("title",$item->{title});
	    $rssitem .= $rss->Element("description",$item->{description});
	    $rssitem .= $rss->Element("link",$item->{link});
	    if ($item->{pubDate}) {
		$rssitem .= $rss->Element("pubDate",$item->{pubDate});
	    }
	    if ($item->{author}) {
		$rssitem .= $rss->Element("author",$item->{author});
	    }
	    if ($item->{guid}) {
		$rssitem .= $rss->Element("guid",$item->{guid});
	    }
	    $rss->_Element("item",$rssitem);
	}
    }
    else {
	my $rssitem =  $rss->Element("title","This RSS feed is empty.");
	$rssitem .= $rss->Element("description","There are currently no items to display in this feed.");
	$rss->_Element("item",$rssitem);
	$this->warn("no items in RSS feed");
    }
    $rss->Wrap("channel");
    $rss->Wrap("rss",{version=>"2.0"});
    return $rss->Write();
}

# Clean up RSS text for display

sub clean {
    my ($this,$text) = @_;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    $text =~ s/&/&amp;/g;
#    $text =~ s/\n/<br \/>\n/g;
    $text =~ s/\s/ /g;
    return $text;
}

1;
