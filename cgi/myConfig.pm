package myConfig;
use strict;
use ExSite::Misc;
use Local;

=pod

=head1 myConfig.pm

B<myConfig.pm> - website localization.

C<myConfig.pm> contains customizations to the ExSite library for use
on a particular website.  There are four standard routines that should
be present in every instance of myConfig.pm:

=cut

# Exported Names

BEGIN {
    use Exporter;
    use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
    @ISA = qw(Exporter);
    @EXPORT_OK   = ( );
    %EXPORT_TAGS = ( );
    @EXPORT      = qw(&my_exsite_init &my_exsite_close &my_handlers);

}

use vars (@EXPORT, @EXPORT_OK);

#=====================================================================
# Non-Exported names:
#
# We cannot import %ExSite::Config::config, because it would create
# a circular reference.  Instead, we just copy it into this module
# using &my_exsite_init().  Ditto for %share.

use vars qw(%config $config $share $session $store $cookie $msg);

#=================================================================
# my_exsite_init

=pod

=head2 my_exsite_init($)

C<my_exsite_init> is called directly from the standard ExSite
initialization routine C<exsite_init>.  Site-specific setup that needs
to be performed for all or most CGI programs may be performed here.

=cut

sub my_exsite_init {
    ($config, $share, $session, $store, $cookie, $msg) = @_;
    %config = %$config;
    # custom setup here
}

sub my_exsite_close {
    # dummy routine - add custom cleanup here
}

#=================================================================
# handlers

=pod

=head2 my_handlers($$)

C<my_handlers> installs any special handler routines that are used by
this website to override default ExSite logic.  It is called
automatically during initialization.

C<my_handlers> should contains lines of the form:

C<$this-E<gt>handler("handler_name",\&handler_routine);E<GT>>

This installs a handler, C<&handler_routine>, to be invoked when the
code checks if a handler is installed under "handler_name".
C<&handler_routine> I<must be defined and installed in myConfig.pm
following the my_handlers routine.> The handler routine itself must
conform in calling arguments and output to the expectations of the
ExSite code that invokes the handler.

Handlers are installed into objects, and are invoked as methods of the
object's class.  As long as the handler names are unique, there is no
harm in installing a handler intended for one type of object into
another object.  Handlers installed as C<$this->handler(...)> will be
installed in all objects.  You can optionally restrict handlers to the
primary database objects using C<$db->handler(...)>.  This causes
non-DB objects to carry a little less baggage, but otherwise there is
no harm in doing it either way.

The ExSite Handlers documentation should be consulted for more information.

=cut

sub my_handlers {
    my $this = shift;
    my $db = $share->{DB};
    if ($db) {
	# install DB-specific handlers here
    }
    # install other handlers here
}

1;
