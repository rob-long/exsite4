#-----------------------------------------------------------------------
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

=pod 

=head1 ExSite::Base - ExSite Base class

The base class defines the most generic behaviours of the ExSite 
class libraries, which are inherited by all ExSite classes/objects.

=head2 C<new(%opt)>

The generic constructor method copies the contents of C<%opt> into 
the object hash attributes.  It then invokes the C<initialize_object()>
method to set up other Base class features.

=head2 C<initialize_object()>

This method sets up system handlers and diagnostic accumulators.
Classes that overload the C<new()> constructor should call this 
from their own constructors in order to get the Base class 
behaviours.

=head2 C<get($attribute)>

Returns the value of the named object attribute.

=head2 C<set($attribute,$value)>

Sets the named object attribute to the given value.

=head2 C<unset($attribute)>

Deletes the named attribute from the object, if it exists.  Returns
true if deleted, false if the attribute doesn't exist.

=head1 Handlers

Handlers exist to override or augment default system logic.  The
handler is passed sufficient data to decide if it wants to override
the logic.  Typically (but not in every case), the handler returns the
results of its special processing (in a format understood by the
caller), or C<undef> if it decided not to override the system logic.
In the latter case, ExSite will proceed with the default system logic.
Otherwise, the details of what a particular handler does is documented
elsewhere (kernel docs, or in the code).

=head2 C<handler($name,$handler_code)>

Installs a special code handler under C<$name>.  C<$handler_code> is
a reference to a subroutine that accepts the arguments required by
the handler, and returns the value expected by the handler.

=head2 C<run_handler($name,@params)>

Attempts to find and run the handler(s) installed under C<$name>.  If
no such handlers exist, returns C<undef>.  If one handler has been
installed, it executes that handler (passing it C<@params>), and
returns the handler's return value.  If more than one handler exist,
they are run in sequence (in the order in which they were installed)
until one returns a defined value.  That value is returned to the
caller, and the remaining handlers are not executed.  This allows you
to install several alternative versions of a handler, each for a
different case, and allow them all to decide if they will take action
or not.  The first to act will pre-empt the others.

=head1 Diagnostics

Diagnostics are messages about system execution, including:

=over 4

=item errors (type "error")

These are problems that prevent completion of a processing task, 
forcing the code to abort.

=item warnings (type "warn")

These are possible problems that do not prevent completion of a 
processing task, which the code can work around.

=item informational messages (type "info")

These are status messages that simply report on state or tasks being
commenced/completed.  They do not imply any problems, and are used 
mostly for logging or tracing execution flow.

=back

Diagnostic messages are logged internally in the object, and depending
on the settings of the logging configuration parameters, may also be 
written to log files.

=head2 C<error(@message)>

Logs a list of error messages.  Returns the error(s), formatted as HTML, 
so you can do something like this:

    $output_text .= $this->error("permission denied");

=head2 C<warn(@message)>

Logs a list of warning messages.  Returns the warning(s), formatted as HTML.

=head2 C<info(@message)>

Logs a list of info messages.  Returns the message(s), formatted as HTML.

=head2 C<errorcheck($type)>

Returns true if any messages of C<$type> (error, warn, info) have been 
logged.  C<$type> defaults to error, so you can do the following to
see if an operation went smoothly or not:

    # some operation...
    if ($this->errorcheck()) {  # problems...

=head2 C<fetch_diagnostics($type)>

Returns an array of diagnostic messages of C<$type> (default is error).
The array is empty if no diagnostics of that type were logged.

=head2 C<show_diagnostics($type,format)>

Returns a formatted report of diagnostic messages of C<$type> (default is 
error).  C<$format> can be "HTML" to format that report as text/html; 
otherwise it is formatted as plain text.

=head2 C<log($logfile,@messages)>

Writes the messages to the given logfile, which is normally one of
"db", "cms", or "diag", depending on the class of the object logging
the message.

Logged messages include the URI, the user name, the timestamp, and the 
message.  Messages are only written out if the config file is set
to write messages of that type.  The configuration settings understand
4 logging levels:

    0 - quiet (no diagnostics)
    1 - show error messages only
    2 - show errors and warnings
    3 - show all messages

=head2 C<showlog($logfile,$n)>

Returns the last C<$n> messages in the given logfile.  If C<$n> is not
given, returns all messages in the logfile.

=cut

package ExSite::Base;
use strict;
use ExSite::Config qw(:DEFAULT &install_handlers);

# generic object constructor

sub new ($%) {
    my ($this,%opt) = @_;
    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;
    # copy options into object
    while (my ($key,$val) = each %opt) {
	$obj->{$key} = $val;
    }
    $obj->initialize_object;
    return $obj;
}

# set up attributes common to all ExSite objects
# Use a standalone method, so that overloaded new() methods in higher
# level classes can set themselves up without having to copy the code.

sub initialize_object {
    my $this = shift;

    # handlers
    $this->{handler} = {};
    &install_handlers($this);

    # error accumulators
    $this->{diagnostics} = {};
    $this->{diagnostics}->{error} = [];
    $this->{diagnostics}->{warn} = [];
    $this->{diagnostics}->{info} = [];

    # legacy
    $this->{errors} = [];

}

# generic attribute accessor functions get/set

sub get ($$) {
    my ($this,$attr) = @_;
    if (exists $this->{$attr}) {
	return $this->{$attr};
    }
    return undef;
}

sub set ($$$) {
    my ($this,$attr,$val) = @_;
    $this->{$attr} = $val;
    return $val;
}

sub unset ($$) {
    my ($this,$attr) = @_;
    if (exists $this->{$attr}) {
	delete $this->{$attr};
	return 1;
    }
    return 0;
}

# handlers

# install a handler

sub handler ($$$) {
    my ($this,$name,$handler_ptr) = @_;
    if (ref $handler_ptr eq "CODE") {
	if (! $this->{handler}->{$name}) {
	    # 1st handler
	    $this->{handler}->{$name} = $handler_ptr;
	}
	elsif (ref $this->{handler}->{$name} eq "ARRAY") {
	    # multiple handlers already; add to list
	    foreach my $h (@{$this->{handler}->{$name}}) {
		return if ($handler_ptr == $h);  # already registered
	    }
	    push @{$this->{handler}->{$name}}, $handler_ptr;
	}
	else {
	    # 2nd handler; convert to array
	    if ($handler_ptr != $this->{handler}->{$name}) {
		my $old_ptr = $this->{handler}->{$name};
		$this->{handler}->{$name} = [ $old_ptr, $handler_ptr ];
	    }
	}
    }
}

# run a handler 

sub run_handler ($$@) {
    my ($this,$name,@args) = @_;
    if (exists $this->{handler}->{$name}) {
	my @handlers;
	if (ref $this->{handler}->{$name} eq "ARRAY") {
	    @handlers = @{$this->{handler}->{$name}};
	}
	else {
	    @handlers = ( $this->{handler}->{$name} );
	}
	foreach my $handler (@handlers) {
	    my $stat = &{$handler} ($this,@args);
	    return $stat if (defined $stat);
	    # Note that we return the first non-null result.  We do not
	    # execute all handlers unconditionally.
	}
    }
    return undef;
}

# diagnostics and error handling

# diagnostics are recorded in 3 places:
# 1) in the object itself (diagnostics specific to this object)
# 2) in %share (diagnostics specific to this job)
# 3) in the logfiles (all jobs)

# All diagnostics return the message passed to it, but reformatted as HTML.

sub diag {
    my ($this,$level,@message) = @_;
    my $type = $this->general_class();
    my $severity = 
	$level == 1 ? "info" : 
	$level == 2 ? "warn" : 
	"error";
    my @msg;
    foreach my $message (@message) {
	push @{$this->{diagnostics}{$severity}}, $message;
	push @msg, {message=>$message,level=>$level,type=>$type};
    }
    # global diagnostic routine handles logging
    &diagnostic(@msg);
    my %sev = ( info=>"Info", warn=>"WARNING", error=>"ERROR" );
    return "<p class=\"$severity\">".$sev{$severity}.": ".
	join("; ",@message).
	"</p>\n";
}

# fatal errors act like regular errors, but also throw a perl exception

sub fatal ($@) {
    my $this = shift;
    $this->diag(3,@_);
    my ($package, $filename, $line) = caller;
    my $br = &get_obj("ML")->br();
    my $fatalmsg = "FATAL: " . join("; ",@_) . $br .
	"Exception raised at $filename line $line.";
    if ($package !~ /^Modules::/) {
	# we are in the base system, and our fatals are not trapped
	#my $p = $share{Page} || $share{PageBuf} || $share{ML};
	#$p->cancel() if ($p);
	# Actually, let's not abort the page, since it might contain 
	# useful information for debugging.  But prepend the fatal error 
	# to the top of the screen.
	print "Content-type: text/html\n\n<h1>Error</h1>$fatalmsg";
    }
    die $fatalmsg . $br . "Execution aborted ";
}

# errors indicate problems that stopped processing

sub error ($@) {
    my $this = shift;
    return $this->diag(3,@_);
}

# warnings indicate a possible problem, but it can be worked around

sub warn ($@) {
    my $this = shift;
    return $this->diag(2,@_);
}

# info messages simply record/log program status.

sub info ($@) {
    my $this = shift;
    return $this->diag(1,@_);
}

# audit: like info, but can log separately - useful to log operations that
# change system state

sub audit ($@) {
    my $this = shift;
    $this->diag(1,@_);
    if ($config{log}{audit}) {
	my $logfile = $config{log}{logfile}{audit} || "audit.log";
	foreach my $message (@_) {
	    &ExSite::Config::log($message,$logfile);
	}
    }
}

# errorcheck simply tests for the existence of errors; it can be used
# as a simple verification check after performing some operation.

sub errorcheck {
    my ($this, $type) = @_;
    if (! $type) { $type = "error"; }
    return (ref $this->{diagnostics}{$type} eq "ARRAY") ?
	( @{$this->{diagnostics}{$type}} > 0 ) :
	0;
}

# fetch_diagnostics returns whichever diagnostic accumulator is requested.
# It is presumed to be used by a debug report method to format the 
# messages to be viewed by the end user.

sub fetch_diagnostics ($$) {
    my ($this,$type) = @_;
    if ($type) {
	if (exists $this->{diagnostics}{$type}) {
	    return @{$this->{diagnostics}{$type}};
	}
    }
    return ();
}

sub show_diagnostics ($$$) {
    my ($this,$type,$format) = @_;
    my @diag = $this->fetch_diagnostics($type);
    if ($format =~ /HTML/i) {
	my $ml = &get_obj("ML");
	my $out;
	foreach my $d (@diag) {
	    $out .= $ml->div($d,{class=>"error"});
	}
	return $ml->div($out,{class=>"errors"});
	#return "<SPAN CLASS=\"error\">\n".join("<br>\n",@diag)."</SPAN>\n";
    }
    else {
	return join("\n",@diag);
    }
}

# determine which general class/inheritance category we belong to
# db = database handling classes
# cms = content management classes
# general = other

sub general_class { 
    my $this = shift;
    if ($this->isa("ExSite::Content")) {
	return "cms";
    }
    my $class = ref $this;
    if ($class =~ /^ExSite::(Revision|View|Diskfile)/) { 
	return "cms"; 
    }
    elsif ($class =~ /^ExSite::(DB|Form|Report|Auth)/) { 
	return "db"; 
    }
    else { 
	return "general"; 
    }
}

1;
