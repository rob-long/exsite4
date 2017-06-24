#!/usr/bin/perl
#----------------------------------------------------------------------------
#
#   Copyright 2001-2008 Exware Solutions, Inc.  http://www.exware.com
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

package ExSite::Message;

=pod

=head1 System Message Translations

This is a system message translation tool, for displaying any text
that is hard-coded.  System messages are coded in English, and in
a default installation will simply be echoed back to the user.

If alternate languages are enabled by either changing the default
system language to something other than "English", eg.

    default_language = Deutsch

or by viewing a page whose language is set to something other than
English, then we we will try to find alternative (translated) system 
messages in the preferred language.  If found, we return those instead;
otherwise we return the English message (wrapped in "NoTranslation" CSS 
markup), and log the missing translation for the attention of 
translators.

=head2 Usage

To output a message in the preferred language, use:

    $msg{'English message'}

If the message contains data substitutions, it is best to use a template
so that the message only needs to be translated once for all values of the
data that might be substituted into it:

    &substitute($msg{'Error on page [[page]]'},{page=>"index.html"})

In both cases, the message is simply echoed if the user prefers English or
if no translation is found.

To output a message that is bilingual (English plus the alternate 
language, eg. "English / Anglais"), use:

    (tied %msg)->bilingual('English message');

If no translation exists, the bilingual function returns only the
original English message.  If a translation exists the translated part
is wrapped in "Bilingual" CSS markup.

=head2 Translation Management

Use the SysMsg plug-in to manage your message translations and build
your multilingual dictionaries.

When translating templated message with substitution fields, do not 
translate the substitution markers.  For example, the following message:

    'File not found: [[filename]]'

should leave the '[[filename]]' part the same in the translated message.
However, it can be moved to different part of the message if the grammer
rules of the alternate language require it.

=head2 Priming Translation Dictionaries

The simplest way to build a dictionary is to set the system to use the
alternate language as the default, and/or to create some alternate
language pages.

Then, exercise the system under the alternate langauge.  The system
will begin logging all messages it encounters that do not have
translations.  It may not find all such messages because many will
correspond to obscure error conditions that are not reached in normal
operations, but it should find all of the typical messages that the
system makes use of.

Then, switch your default language back to English (simply by
commenting out the default language setting in your config file).  You
can now visit the SysMsg tool to see all the messages that were logged
as requiring translations.

=cut

use strict;

sub TIEHASH {
    my ($this,$lang,$highlight,$share,$store) = @_;

    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;

    $obj->language($lang);

    $obj->{share} = $share;
    $obj->{store} = $store;
    # setup highlighting
    $obj->{hl_save} = $highlight;
    if ($highlight) { $obj->highlight; }

    return $obj;
}

sub FETCH {
    my ($this, $key) = @_;
    return $key if (! $key);
    return $key if (! $this->{language});
    $this->load_dictionary() if (! $this->{dictionary});
    if (exists $this->{dictionary}{$key}) {
	return $this->{dictionary}{$key} if ($this->{dictionary}{$key});
	return $this->{highlight} ?
	    "<span class=\"NoTranslation\">$key</span>" :
	    $key;
    }
    else {
	# translation is missing, but not logged yet
	$this->STORE($key,"");
	$this->{dictionary}{$key} = "";
	return $this->{highlight} ?
	    "<span class=\"NoTranslation\">$key</span>" :
	    $key;
    }
}

sub STORE {
    my ($this, $key, $val) = @_;
    return if (! $this->{language});

    # store local copy
    $this->{dictionary}{$key} = $val;

    # get the base message - WARNING: fetch_match is case-insensitive
    my @msg = $this->{share}{DB}->fetch_match("sysmsg",{message=>$key});
    if (@msg == 0) {
	# no base message
	my $smid = $this->{share}{DB}->insert("sysmsg",{message=>$key});
	push @msg, { sysmsg_id=>$smid, message=>$key };
    }
    # update all matching alternate messages
    my $nskip = 0;
    foreach my $m (@msg) {
	if ($m->{message} eq $key) { 
	    # case sensitive match
	    my @altmsg = $this->{share}{DB}->fetch_match("sysmsg_alt",
							 {sysmsg_id=>$m->{sysmsg_id},language=>$this->{language}});
	    if (@altmsg > 0) {
		# message exists;  update it
		$this->{share}{DB}->update("sysmsg_alt",
					   {message_alt=>$val, ctime=>undef},
					   {sysmsg_id=>$m->{sysmsg_id},language=>$this->{language}});
	    }
	    else {
		# no such message; create it
		my $asmid = $this->{share}{DB}->insert("sysmsg_alt",
						       {sysmsg_id=>$m->{sysmsg_id},
							message_alt=>$val,
							language=>$this->{language},
						    });
		$this->error("failed to create translated message")
		    if (! $asmid);
	    }
	}
	else {
	    # message was not a true case-sensitive match; skip it
	    $nskip++;
	}
    }
    if ($nskip == scalar @msg) {
	# skipped all messages; no matches - add base message
	my $smid = $this->{share}{DB}->insert("sysmsg",{message=>$key});
	if ($smid) {
	    if ($val) {
		my $asmid = $this->{share}{DB}->insert("sysmsg_alt",
						       {sysmsg_id=>$smid,
							message_alt=>$val,
							language=>$this->{language},
						    });
		$this->error("failed to create translated message")
		    if (! $asmid);
	    }
	}
	$this->error("failed to create system message")
	    if (! $smid);
    }
    return $val;
}

sub DELETE {
    my ($this, $key) = @_;
    return if (! $this->{langauge});
    # get the base message
    my @msg = $this->{share}{DB}->fetch_match("sysmsg",{message=>$key});
    # delete all matching alternate messages
    foreach my $m (@msg) {
	if ($m->{message} eq $key) { # case sensitive match (fetch_match is not)
	    my @altmsg = $this->{share}{DB}->fetch_match("sysmsg_alt",
							 {sysmsg_id=>$m->{sysmsg_id},
							  language=>$this->{language}});
	    foreach my $am (@altmsg) {
		$this->{share}{DB}->trash_key("sysmsg_alt",$am->{sysmsg_alt_id});
	    }
	}
    }
}

sub EXISTS {
    my ($this, $key) = @_;
    return 1 if (! $this->{language});
    $this->load_dictionary() if (! $this->{dictionary});
    # message exists if it has been translated, but not if it has been logged
    return exists $this->{dictionary}{$key} && $this->{dictionary}{$key};
}

sub FIRSTKEY {
    my ($this) = @_;
    return undef if (! $this->{language});
    my $dummy = keys %{$this->{dictionary}};
    return each %{$this->{dictionary}};
}

sub NEXTKEY {
    my ($this,$lastkey) = @_;
    return undef if (! $this->{language});
    return each %{$this->{dictionary}};
}

### internal methods

sub language {
    my ($this,$lang) = @_;
    my $last_lang = $this->{language};
    $this->{language} = ($lang && $lang !~ /^English$/i) ?
	$lang :     # specific language requested
	undef;      # English

    if ($this->{language} ne $last_lang) {
	# language changed;  clear the dictionary
	delete $this->{dictionary};
    }
}

# turn on translation-needed highlights
sub highlight {
    my $this = shift;
    $this->{highlight} = 1;
}

# turn off translation-needed highlights
sub nohighlight {
    my $this = shift;
    $this->{highlight} = 0;
}

# return to default highlighting
sub restore {
    my $this = shift;
    $this->{highlight} = $this->{hl_save};
}

sub load_dictionary {
    my $this = shift;
    $this->{dictionary} = {};
    return if (! $this->{language});  # don't bother

    # ensure we have sysmsg maps loaded
    require ExSite::Module;
    &ExSite::Module::read_dbmap("SysMsg");
    if (! $this->{share}{DB} || 
	! $this->{share}{DB}{map} ||
	! $this->{share}{DB}{map}->is_mapped("sysmsg")) {
	# oops, we are missing a database, dbmap, or the sysmsg component,
	# so we should disable translation handling
	$this->{language} = undef;
	return;
    }

    if (exists $this->{share}{Cache}) {
	my $dat = $this->{share}{Cache}->get(["sysmsg","sysmsg_alt"],"sysmessages_$this->{language}");
	if ($dat) {
	    # looks like the dictionary has been cached
	    $this->{dictionary} = $dat;
	    return;
	}
    }

    # load dictionary from DB
    my @messages = $this->{share}{DB}->get_query("system messages",
						 $this->{language});
    if (@messages > 0) {
	foreach my $m (@messages) {
	    $this->{dictionary}{$m->{message}} = $m->{message_alt};
	}
    }
    # try to cache the dictionary
    if (exists $this->{share}{Cache}) {
	$this->{share}{Cache}->save($this->{dictionary},["sysmsg","sysmsg_alt"],"sysmessages_$this->{language}");
    }
}

# show a bilingual version of the message

sub bilingual {
    my ($this, $key) = @_;
    return $key if (! $this->{language});
    $this->load_dictionary() if (! $this->{dictionary});
    $this->nohighlight();
    my $val = $this->FETCH($key);
    $this->restore();
    return ($key eq $val) ?
	$key :
	"$key / <span class=\"Bilingual\">$val</span>";
}

1;
