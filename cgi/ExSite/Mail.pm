#!/usr/bin/perl
#========================================================================
# ExSite::Mail  --  miscellaneous E-Mail functions
# Author: Alan Douglas, Exware Solutions, April 2003
#========================================================================
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
#----------------------------------------------------------------------------

package ExSite::Mail;

use strict;
use ExSite::Config;
use ExSite::Misc;
use Net::SMTP;
use Sys::Hostname;

BEGIN {
    use Exporter   ();
    use vars       qw($VERSION @ISA @EXPORT);
    $VERSION     = 1.00;
    @ISA         = qw(Exporter);
    @EXPORT = qw(   &SendMail &SendMail_Multipart
		    );
}

# ExSite::Mail::send - multi-purpose email sending tool
# Options:
# to => scalar or array of email addresses
# from => email address
# subject => subject string
# body => email message, plain text or HTML
# attach => array of files to attach

sub send {
    my (%opt) = @_;
    # fix emails that have multiple from addresses - choose first one
    $opt{from} = (split /\s*,\s*/,$opt{from})[0]; 
    if ($config{log}{audit} && $share{DB}) {
	# log emails on the DB logfile, just because we don't have an 
	# object to audit in this case
	$share{DB}->audit("Sending email to $opt{to}, subject '$opt{subject}', from $opt{from}");
    }
    if ($opt{attach}) {
	# email with attachments
	return &SendMail_Multipart(
				   $opt{to},
				   $opt{from},
				   $opt{subject},
				   $opt{body},
				   (ref $opt{attach} eq "ARRAY") ? @{$opt{attach}} : $opt{attach},
				   );
    }
    elsif ($opt{body} =~ /[^[:ascii:]]/ or $opt{subject} =~ /[^[:ascii:]]/) {
	# non-ascii email - use multipart for better encoding
	return &SendMail_Multipart(
				   $opt{to},
				   $opt{from},
				   $opt{subject},
				   $opt{body},
				   );
    }
    elsif ($opt{body} =~ /<\w+( [^>]*)?>/) {
	# html message - use multipart for mime handling
	return &SendMail_Multipart(
				   $opt{to},
				   $opt{from},
				   $opt{subject},
				   $opt{body},
				   );
    }
    else {
	# simple ascii email
	return &SendMail(
			 $opt{to},
			 $opt{from},
			 $opt{subject},
			 $opt{body},
			 );
    }
}

sub SendMail {
    if ($config{mail}{method} eq "sendmail") {
	return SendMail_2(@_);
    }
    else {
	return SendMail_1(@_);
    }
}

sub SendMail_1{
   my ($to,$from,$subject,$body) = @_;
   my @lines;
   $share{DB}->audit("allmail_sentlog: function SendMail_1");
   $from = &trim($from);
   return 2 if ($to !~ /\w/);
   $to = &firewall($to);
 
   my $server = &my_mailserver();
   my $smtp = new Net::SMTP($server);
   if (! $smtp) {
       &diagnostic("Net::SMTP: $!");
       return 1;
   }
   return 1 if (! $smtp);
   $smtp->mail($from);
   # 20040416 MB - allow for multiple recipients
   my @to = split(/,/,$to);
   if ($config{mail}{bcc}) {
       push @to, $config{mail}{bcc};
   }
   foreach (@to) {
       $_ = &trim($_);
   }
   $smtp->to(@to);
   $smtp->data;
   $smtp->datasend("To: $to\nFrom: $from\nSubject: $subject\n\n");
   @lines=split(/\n/,$body);
   foreach (@lines) {
      $_ =~ s/"/\\"/g;
      $_ =~ s/\n//g;
      $_ =~ s/\r//g;
      $smtp->datasend("$_\n");
   }
   my $status = $smtp->dataend;
   $smtp->quit;
   &log_sent($to,$from,$subject,"SendMail_1:".$status,'',$body);
   $share{sent_addresses}{$to}++;
   return 0;
}

sub SendMail_2 {
#----------------------------------------------------------------------
# SimpleSendMail: a simplified version of the SendMail function.
#                 It has also been adjusted to allow sending even from
#                 badly misconfigured mail servers
#
# Arguments:
#   to      - recipient email address
#   from    - sender email address
#   subject - email subject header
#   message - message body
#
# Returns 0 if it worked 
#         1 if not

    my ($to,$from,$subject,$message) = @_;
    $share{DB}->audit("allmail_sentlog: function SendMail_2");
    $to = &firewall($to);
    $to = &trim($to);
    $from = &trim($from);

    if (!open (SENDMAIL, "|$config{mail}{sendmailpath} -f $from $to")) {
        return 1;
    }
    else {
        my $status = print SENDMAIL "To: $to\nFrom: $from\nSubject: $subject\n\n$message";
        close SENDMAIL;
        &log_sent($to,$from,$subject,"SendMail_2:".$status,'',$message);
        return 0;
    }
}

# Multipart email
sub SendMail_Multipart {
    # $tolist: comma delimited email address
    # $from: from address
    # $subject: subject
    # $body: email body
    # @files: attachments(an array of hash reference)
    #	each file attachment has 2 hash keys:
    #		filename => "myfilename.txt", # string
    #		data => <attachment>, # binary data
    my ($tolist,$from,$subject,$body,@files) = @_;
    my $raw_subject = $subject;
    $from = &trim($from);
    return 2 if ($tolist !~ /\w/);
    return 2 if ($from !~ /^[\w](\.?[\w\-\+]+)*@([\w\-]+\.)+[A-Za-z]{2,6}$/);
    $tolist = &firewall($tolist);
    my @to = split /\s*,\s*/,$tolist;
    if ($config{mail}{bcc}) {
	push @to, $config{mail}{bcc};
    }
    require MIME::Entity;
    foreach my $to(@to){
	$to = &trim($to);
	if ($to !~ /^[\w](\.?[\w\-\+]+)*@([\w\-]+\.)+[A-Za-z]{2,6}$/){
	    # Invalid email address
	    next;
	}
	# Build email
	if ($subject =~ /[[:^ascii:]]/) {
	    require MIME::EncWords;
	    $subject = &MIME::EncWords::encode_mimewords($subject,Encoding=>"Q",Charset=>$config{charset});
	    # fix consecutive special chars with intervening space
	    $subject =~ s/\?=\s+=\?UTF-8\?Q\?/=20/g;
	}
	my $mime = MIME::Entity->build(
				       Type=>"multipart/mixed",
				       From=>$from,
				       To=>$to,
				       Subject=>$subject,
				       );
	my $part1 = MIME::Entity->build(
					Type=>"multipart/alternative",
					);
	my $html_message;
	my $text_message;
	# HTML tag checks
	if ($body !~ /<\w+( [^>]*)?>/gi){
	    # Send out plain text email
	    $text_message = $body;
	    $part1->attach(Type=>"text/plain; charset=\"$config{charset}\"",Data=>"$text_message");
	    # add a dummy HTML part for stupid email clients
	    if ($config{mail}{dummy_html_part}) {
		$part1->attach(Type=>"text/html; charset=\"$config{charset}\"",Data=>"<html><body><pre>$text_message</pre></body></html>");
	    }
	}
	else {
	    # Send out multipart email
	    $html_message = $body;
	    $text_message = &html_to_plaintext($html_message);
	    $part1->attach(
			   Type=>"text/plain; charset=\"$config{charset}\"",
			   Data=>$text_message,
			   );
	    $part1->attach(
			   Type=>"text/html; charset=\"$config{charset}\"",
			   Data=>$html_message,
			   );
	}
	$mime->add_part($part1);
	my $part2 = MIME::Entity->build(
					Type=>"multipart/mixed",
					);
	# Add file attachments
	my $include_attachment = 0;
	my $attach_log;
	foreach my $file(@files){
	    next if !$file;
	    next if ref($file) !~ /hash/i;
	    next if (keys(%$file) < 1);
	    $include_attachment = 1;
	    $part2->attach(
		Filename=>$file->{filename},
		Type=>&MimeType($file->{filename}),
		Data=>$file->{data}, 
		# could add Disposition => inline|attachment
		);
	    $attach_log .= $file->{filename}." ";
	}
	if ($include_attachment){
	    $mime->add_part($part2);
	}
	my $smtp = new Net::SMTP(&my_mailserver());
	if (! $smtp) {
	    &diagnostic("Net::SMTP: $!");
	    return 1;
	}
	$smtp->mail($from);
	$smtp->to($to);
	$smtp->data;
	$smtp->datasend($mime->stringify);
	my $status = $smtp->dataend;
	$smtp->quit;
	&log_sent($to,$from,$raw_subject,"SendMail_Multipart:".$status,$attach_log,$text_message,$html_message);
	$share{sent_addresses}{$to}++;
    }
    return 0;
}

# allmail_sentlog - if possible
sub log_sent {
    my ($to, $from, $subject, $status, $attachments, $body_txt, $body_html) = @_;
    # $attachments is just a list of filenames
    my $db = $share{DB} || new ExSite::DB;
    if ($db->{map}->is_mapped("allmail_sentlog")) {
	my $site = $db->this_site();
	my $sid = ref $site eq "HASH" ? $site->{section_id} : $site;

	my $depth=1;
	my $package;
	do {
	    $package = (caller($depth))[0];
	    $depth++;
	} while (($package eq "ExSite::Mail" or $package eq "myConfig") and $depth<7);
	if ($config{mail}{log_body}) {
	    $db->insert("allmail_sentlog", {to_address=>$to, from_address=>$from, subject=>$subject, module=>$package, status=>$status, attachments=>$attachments, section_id=>$sid, body_txt=>$body_txt, body_html=>$body_html});
	} else {
	    $db->insert("allmail_sentlog", {to_address=>$to, from_address=>$from, subject=>$subject, module=>$package, status=>$status, attachments=>$attachments, section_id=>$sid});
	}
    }
}

sub my_mailserver {
    my $server = $config{mail}{server} || "localhost";
    my $bulkserver = $config{mail}{bulkserver} || "localhost";
    my $bulklevel = $config{mail}{bulklevel} || 2;
    return (scalar keys %{$share{sent_addresses}} > $bulklevel) ?
	$bulkserver : $server;
}

sub firewall {
    my ($to) = @_;
    return $config{mail}{firewall} if ($config{mail}{firewall});
# the following code is a failsafe used by Exware Solutions to ensure that our interneal testing environment won't send
# emails to client addresses. Other users can comment out this code
    if (hostname eq "lucy") {
	return $config{site}{administrator} if ($config{site}{administrator} =~ /exware/);
	return "alan\@exware.com";
    } 
    return $to;
}

sub trim {
#----------------------------------------------------------------------
# trim: trims leading and trailing whitespace from a string
#
# Arguments:
#   string
	my ($string) = @_;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}

1;
